--[[
    Crafting Window UI (extensible, layout-driven, alchemy-window style)

    An interactive crafting window opened at a station, modelled after the vanilla
    alchemy window:

        Crafting Station: <name>                 (Window widget title bar)
        Tools:  [🔪][ ][ ]      Result:  [▣]  Stick x1     ← Apparatus | Created Effects
        <input slots — grid or process layout>
        ───────────────────────────────────────
        Materials   < 1/3 >                                 ← integrated item picker
        [icon][icon][icon][icon][icon][icon]
        [icon][icon][icon][icon][icon][icon]
                                        [Close]

    Interaction (no drag-and-drop, no Create button):
    - Clicking an empty input slot SELECTS it (highlighted); clicking a material in
      the strip places it into the selected slot and auto-advances the selection to
      the next empty slot. Clicking a filled slot clears it (and selects it).
    - The RESULT slot shows the resolved recipe's output. Clicking it "takes" the
      item — that is the craft: inputs are consumed and the output is moved to the
      player's inventory (Minecraft-style). The window stays open for batches.

    The window shell (borders, drag/resize, title) is `ui/Window.lua`; the input
    area comes from the layout registry (grid → CraftingGrid, process →
    CraftingProcess); the materials strip is `ui/ItemPicker.lua`; slots are the
    shared `ui/Slot.lua`. Add a `layouts` entry to support a new station shape.

    The materials strip lists only inventory items usable at this station (matching
    any recipe ingredient by id or FlexTag tag); if nothing matches (e.g. tags not
    authored yet) it falls back to the full inventory.
]]

local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')

local Window = require('scripts.Immersive-Crafting.ui.Window')
local ItemPicker = require('scripts.Immersive-Crafting.ui.ItemPicker')
local Slot = require('scripts.Immersive-Crafting.ui.Slot')
local grid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local process = require('scripts.Immersive-Crafting.ui.CraftingProcess')
local shaped = require('scripts.Immersive-Crafting.shapedCrafting')
local processCrafting = require('scripts.Immersive-Crafting.processCrafting')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local v2 = util.vector2

local WINDOW_SIZE = v2(480, 470)
local LINE_W = 430
local TOOL_SLOTS = 3
local TOOL_ICON = v2(40, 40)

local this = {}

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local ctx = nil ---@type HandlerContext?
local layout = nil ---@type CContext.Layout?
local element = nil
local placed = {} ---@type table<string, {recordId:string, icon:string?}> slotId -> placed item
local selectedSlot = nil ---@type string? slot the next picked material goes into
local materials = {} ---@type { recordId:string, icon:string?, count:integer }[]
local matched = nil ---@type CShapedRecipe|CProcessRecipe|nil
local canCraft = false
local iconTextureCache = {} ---@type table<string, any>

-- ── layout registry ─────────────────────────────────────────────────────────

---@class CraftingLayout
---@field body fun(layout: CContext.Layout, view: CraftingSlotView): table?

--- Add an entry here to support a new station shape.
local layouts = {
    grid = { body = grid.Body },
    process = { body = process.Body },
} ---@type table<string, CraftingLayout>

-- ── helpers: textures / icons / inventory ────────────────────────────────────

-- Item types whose records carry an inventory `icon` (for the result slot).
local ICON_TYPES = {
    types.Miscellaneous, types.Weapon, types.Armor, types.Clothing, types.Potion,
    types.Ingredient, types.Book, types.Apparatus, types.Lockpick, types.Probe,
    types.Repair, types.Light,
}

---@param path string?
---@return any
local function textureForPath(path)
    if not path or path == '' then return nil end
    local cached = iconTextureCache[path]
    if cached then return cached end
    local ok, tex = pcall(function() return ui.texture({ path = path }) end)
    if ok and tex then
        iconTextureCache[path] = tex
        return tex
    end
    return nil
end

--- Best-effort icon path for a record id by probing the item types.
---@param recordId string
---@return string?
local function recordIconPath(recordId)
    for _, t in ipairs(ICON_TYPES) do
        local ok, rec = pcall(function() return t.record(recordId) end)
        if ok and rec and rec.icon and rec.icon ~= '' then
            return rec.icon
        end
    end
    return nil
end

---@param item any inventory item
---@return string?
local function itemIconPath(item)
    local ok, rec = pcall(function() return item.type.record(item) end)
    if ok and rec and rec.icon and rec.icon ~= '' then return rec.icon end
    return nil
end

---@param recordId string
---@return integer
local function inventoryCount(recordId)
    local total = 0
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if item.recordId == recordId then total = total + (item.count or 1) end
    end
    return total
end

--- How many of each record id are placed across all slots.
local function placedCounts()
    local counts = {}
    for _, cell in pairs(placed) do
        counts[cell.recordId] = (counts[cell.recordId] or 0) + 1
    end
    return counts
end

--- Do we own enough of everything placed (in inventory)?
local function haveEnough()
    for id, n in pairs(placedCounts()) do
        if inventoryCount(id) < n then return false end
    end
    return true
end

--- Is `query` (tool tag/id) in the player's inventory? Returns its icon path too.
---@param query string
---@return boolean owned, string? iconPath
local function toolInfo(query)
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if lib.matchesTag(item.recordId, query) then
            return true, itemIconPath(item)
        end
    end
    return false, nil
end

-- ── materials (integrated picker data) ───────────────────────────────────────

--- Inventory items usable at this station: anything matching an ingredient
--- id/tag of any recipe for this context+action. Falls back to the full
--- inventory when nothing matches (e.g. tags not authored yet).
local function collectMaterials()
    local matchers = {}
    for _, r in pairs(GRegistries.shapedRecipes or {}) do
        if r.context == ctx.context.id and r.action == ctx.action.id then
            for _, v in pairs(r.key or {}) do matchers[#matchers + 1] = v end
        end
    end
    for _, r in pairs(GRegistries.processRecipes or {}) do
        if r.context == ctx.context.id and r.action == ctx.action.id then
            for _, line in ipairs(r.inputs or {}) do matchers[#matchers + 1] = line.id end
        end
    end

    local function gather(filtered)
        local order, byId = {}, {}
        for _, item in ipairs(types.Actor.inventory(self):getAll()) do
            local rid = item.recordId
            if byId[rid] == nil then
                local usable = not filtered
                if filtered then
                    for _, q in ipairs(matchers) do
                        if lib.matchesTag(rid, q) then
                            usable = true
                            break
                        end
                    end
                end
                if usable then
                    local entry = { recordId = rid, icon = itemIconPath(item), count = 0 }
                    order[#order + 1] = entry
                    byId[rid] = entry
                else
                    byId[rid] = false
                end
            end
            if byId[rid] then
                byId[rid].count = byId[rid].count + (item.count or 1)
            end
        end
        return order
    end

    local list = gather(#matchers > 0)
    if #list == 0 then list = gather(false) end
    return list
end

-- ── selection / resolution ───────────────────────────────────────────────────

--- Slot ids in visual order (grid row-major / process input order).
local function slotOrder()
    local order = {}
    if layout.kind == 'grid' then
        local rows, cols = layout.size[1] or 2, layout.size[2] or 2
        for r = 1, rows do
            for c = 1, cols do order[#order + 1] = ('%d:%d'):format(r, c) end
        end
    else
        for _, inp in ipairs(layout.inputs or {}) do order[#order + 1] = inp.key end
    end
    return order
end

--- Keep a sensible selection: if none (or it got filled), pick the first empty slot.
local function ensureSelection()
    if selectedSlot and not placed[selectedSlot] then return end
    selectedSlot = nil
    for _, id in ipairs(slotOrder()) do
        if not placed[id] then
            selectedSlot = id
            return
        end
    end
end

local function gridFromPlaced()
    local g = {}
    local rows, cols = layout.size[1] or 2, layout.size[2] or 2
    for r = 1, rows do
        g[r] = {}
        for c = 1, cols do
            local cell = placed[('%d:%d'):format(r, c)]
            g[r][c] = cell and cell.recordId or nil
        end
    end
    return g
end

--- All placed record ids, one per filled slot (process matching is non-positional).
local function placedList()
    local list = {}
    for _, cell in pairs(placed) do
        list[#list + 1] = cell.recordId
    end
    return list
end

--- Resolve the placed slots into a matched recipe + craftability for the layout.
local function resolve()
    matched, canCraft = nil, false
    if not ctx or not layout then return end

    if layout.kind == 'grid' then
        matched = shaped.resolveShapedRecipe(gridFromPlaced(), ctx.action, ctx.context)
    elseif layout.kind == 'process' then
        matched = processCrafting.resolveProcessRecipe(placedList(), ctx.action, ctx.context)
    end

    canCraft = matched ~= nil and haveEnough()
end

-- ── slot view passed to body builders ────────────────────────────────────────

---@type CraftingSlotView
local view = {
    selectedSlot = nil, -- refreshed each rebuild
    slotView = function(slotId)
        local cell = placed[slotId]
        if not cell then return nil end
        return { resource = textureForPath(cell.icon) }
    end,
    onSlotClick = function(slotId)
        -- Filled slot: clear it (and select it, so a new pick replaces it).
        if placed[slotId] then
            placed[slotId] = nil
        end
        selectedSlot = slotId
        this.rebuild()
    end,
    onPick = function(recordId, iconPath)
        ensureSelection()
        if not selectedSlot then return end -- no empty slot left
        placed[selectedSlot] = { recordId = recordId, icon = iconPath }
        ensureSelection()                   -- auto-advance to the next empty slot
        this.rebuild()
    end,
}

-- ── window sections (alchemy-style) ─────────────────────────────────────────

--- Tools row — apparatus-style: the matched recipe's tools as slots (icon when
--- owned; matching already guarantees ownership, so these read as "in use").
local function toolsSection()
    local slots = {}
    local tools = (matched and matched.tools) or {}
    for i = 1, TOOL_SLOTS do
        local query = tools[i]
        if query then
            local owned, iconPath = toolInfo(query)
            slots[#slots + 1] = Slot.Slot({
                name = 'tool_' .. i,
                resource = textureForPath(iconPath),
                size = TOOL_ICON,
                state = owned and 'selected' or 'missing',
            })
        else
            slots[#slots + 1] = Slot.Slot({ name = 'tool_' .. i, size = TOOL_ICON, state = 'empty' })
        end
        if i < TOOL_SLOTS then
            slots[#slots + 1] = { type = ui.TYPE.Widget, props = { size = v2(4, 0) } }
        end
    end
    return {
        type = ui.TYPE.Flex,
        name = 'tools_section',
        content = ui.content({
            { type = ui.TYPE.Text,   props = { text = 'Tools' },    template = I.MWUI.templates.textNormal },
            { type = ui.TYPE.Widget, props = { size = v2(0, 3) } },
            { type = ui.TYPE.Flex,   props = { horizontal = true }, content = ui.content(slots) },
        }),
    }
end

--- Result panel — the resolved output. CLICKING THE RESULT SLOT IS THE CRAFT:
--- it consumes the placed inputs and moves the item into the inventory.
local function resultSection()
    local resource, countLabel, caption
    if matched then
        resource = textureForPath(recordIconPath(matched.output.id))
        local n = matched.output.count or 1
        countLabel = n > 1 and n or nil
        caption = ('%s x%d'):format(matched.label or matched.id, n)
        if not canCraft then caption = caption .. '  (not enough materials)' end
    else
        caption = '(no match)'
    end

    local resultSlot = Slot.Slot({
        name = 'slot_output',
        resource = resource,
        count = countLabel,
        state = 'empty',
        onClick = canCraft and function() this.onCraft() end or nil,
    })

    return {
        type = ui.TYPE.Flex,
        name = 'result_section',
        content = ui.content({
            { type = ui.TYPE.Text,   props = { text = 'Result' }, template = I.MWUI.templates.textNormal },
            { type = ui.TYPE.Widget, props = { size = v2(0, 3) } },
            {
                type = ui.TYPE.Flex,
                props = { align = ui.ALIGNMENT.Center, horizontal = true },
                content = ui.content({
                    resultSlot,
                    { type = ui.TYPE.Widget, props = { size = v2(8, 0) } },
                    { type = ui.TYPE.Text,   props = { text = caption }, template = I.MWUI.templates.textNormal },
                })
            },
        }),
    }
end

local function hLine(width)
    return {
        type = ui.TYPE.Image,
        template = I.MWUI.templates.horizontalLine,
        props = { size = v2(width, 2) },
    }
end

local function closeButton()
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = { text = 'Close' },
        events = { mouseClick = async:callback(function() this.close() end) },
    }
end

-- ── window assembly ─────────────────────────────────────────────────────────

function this.rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx or not layout then return end

    local def = layouts[layout.kind]
    if not def then
        log.error('Unknown crafting layout kind: ' .. tostring(layout.kind))
        return
    end

    resolve()
    view.selectedSlot = selectedSlot

    local inputs = def.body(layout, view)
    if not inputs then
        log.error('Failed to build crafting window body for layout kind: ' .. tostring(layout.kind))
        return
    end

    local content = {
        type = ui.TYPE.Flex,
        name = 'crafting_content',
        props = { position = v2(20, 20) },
        external = {
            grow = 1,
            stretch = 1
        },
        content = ui.content({
            {
                type = ui.TYPE.Flex,
                name = 'tools_result_row',
                props = { horizontal = true },
                content = ui.content({
                    toolsSection(),
                    { type = ui.TYPE.Widget, props = { size = v2(26, 0) } },
                    resultSection(),
                }),
            },

            { type = ui.TYPE.Widget, props = { size = v2(0, 10) } },

            -- grid
            inputs,

            { type = ui.TYPE.Widget, props = { size = v2(0, 6) } },

            {
                name = 'itempicker',
                type = ui.TYPE.Flex,
                template = I.MWUI.templates.bordersThick,
                external = {
                    grow = 1,
                    stretch = 1
                },
                content = ui.content({
                    ItemPicker.Body(materials, {
                        onPick = view.onPick,
                        refresh = function() this.rebuild() end,
                    }),
                })
            },

            { type = ui.TYPE.Widget, props = { size = v2(0, 8) } },
            -- footer: close button
            {
                name = 'footer',
                type = ui.TYPE.Flex,
                external = { stretch = 1 },
                props = {
                    align = ui.ALIGNMENT.End,
                },
                content = ui.content({ closeButton() })
            },
            {
                type = ui.TYPE.Widget,
                props = {
                    size = v2(0, 8)
                }
            },
        }),
    }

    local dlg = Window({
        title = 'Crafting Station: ' .. (ctx.context.label or 'Unknown'),
        -- body = ui.content(contentList),
        body = ui.content({ content }),
        props = { anchor = v2(0.5, 0.5), relativePosition = v2(0.4, 0.5), size = WINDOW_SIZE },
        getElement = function() return element end,
    })

    element = ui.create(dlg)
end

-- ── events ───────────────────────────────────────────────────────────────────

--- Craft = "take the result": consume the placed inputs, grant the output.
function this.onCraft()
    if not matched or not canCraft then return end
    local consume = {}
    for id, count in pairs(placedCounts()) do consume[#consume + 1] = { id = id, count = count } end
    core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
        actor = self.object,
        consume = consume,
        output = matched.output,
    })
    local label = matched.label or matched.id
    log.info('Crafted ' .. label)
    ui.showMessage('Crafted ' .. label)

    -- clear the inputs and stay open for batch crafting (the global consume lands
    -- next frame, so material counts refresh on the next interaction)
    placed = {}
    ensureSelection()
    materials = collectMaterials()
    this.rebuild()
end

-- ── public API ──────────────────────────────────────────────────────────────

---@return boolean
function this.isOpen() return isOpen end

---@return string?
function this.getContextId()
    if not ctx or not ctx.context then return nil end
    return ctx.context.id
end

---@param handlerCtx HandlerContext
function this.open(handlerCtx)
    ctx = handlerCtx
    layout = ctx.context.layout
    placed = {}
    selectedSlot = nil
    isOpen = true
    ItemPicker.reset()
    materials = collectMaterials()
    ensureSelection()
    I.UI.setMode('Interface') -- show cursor; inventory remains available
    this.rebuild()
end

function this.close()
    isOpen = false
    if element then element:destroy() end
    element = nil
    ctx = nil
    layout = nil
    placed = {}
    selectedSlot = nil
    materials = {}
    matched = nil
    canCraft = false
    I.UI.setMode() -- back to gameplay
end

---@param handlerCtx HandlerContext
function this.toggle(handlerCtx)
    if isOpen then
        this.close()
        return
    end
    this.open(handlerCtx)
end

return this
