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
      the strip places it into the selected slot. Grid slots hold ONE item and the
      selection auto-advances; process slots hold a STACK (furnace-style — picking
      the same material again adds one) and the selection stays put. Clicking a
      filled slot takes one unit back off it. Process slots may declare `accepts`
      filters (e.g. the Mold slot only takes molds).
    - The RESULT slot shows the resolved recipe's output. Clicking it "takes" the
      item — that is the craft: inputs are consumed and the output is moved to the
      player's inventory (Minecraft-style). The window stays open for batches.
      When one placement matches SEVERAL recipes (carving: one wood block -> bowl,
      cup, spoon...), `< i/n >` next to Result cycles through the matches.

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
local processState = require('scripts.Immersive-Crafting.processState')
local log = require('scripts.Immersive-Crafting.log')
local components = require('scripts.Immersive-Crafting.ui.components')

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
local placed = {} ---@type table<string, {recordId:string, icon:string?, count:integer}> slotId -> placed stack (grid slots always hold 1; process slots stack)
local selectedSlot = nil ---@type string? slot the next picked material goes into
local materials = {} ---@type { recordId:string, icon:string?, count:integer }[]
local stationTools = {} ---@type string[] distinct tool ids/tags used by this station's recipes
local matchedList = {} ---@type (CShapedRecipe|CProcessRecipe)[] all recipes the placed items resolve to
local matchedIndex = 1 ---@type integer which match the Result panel shows (cycle with < >)
local matched = nil ---@type CShapedRecipe|CProcessRecipe|nil matchedList[matchedIndex]
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

--- How many of each record id are placed across all slots (stacks counted).
local function placedCounts()
    local counts = {}
    for _, cell in pairs(placed) do
        counts[cell.recordId] = (counts[cell.recordId] or 0) + (cell.count or 1)
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

-- ── slot filters (`accepts` on process slot defs) ───────────────────────────

---@param slotId string?
---@return CContext.SlotDef?
local function slotDef(slotId)
    if not slotId or not layout or layout.kind ~= 'process' then return nil end
    for _, inp in ipairs(layout.inputs or {}) do
        if inp.key == slotId then return inp end
    end
    return nil
end

--- May this item go into this slot? Slots without accepts/acceptsPatterns take
--- anything (grid slots always do). This is placement UX only — recipe matching
--- stays a forgiving multiset over all slot contents.
---@param slotId string
---@param recordId string
---@return boolean
local function slotAccepts(slotId, recordId)
    local def = slotDef(slotId)
    if not def then return true end
    local accepts, patterns = def.accepts, def.acceptsPatterns
    if not ((accepts and #accepts > 0) or (patterns and #patterns > 0)) then
        return true
    end
    for _, q in ipairs(accepts or {}) do
        if lib.matchesTag(recordId, q) then return true end
    end
    local lowered = recordId:lower()
    for _, p in ipairs(patterns or {}) do
        if lowered:find(p) then return true end
    end
    return false
end

--- Materials still pickable: inventory counts minus what is already placed in
--- the slots (placing an item visibly removes one from the strip). While an
--- EMPTY slot with an `accepts` filter is selected, the strip only shows what
--- that slot takes (e.g. molds for the Mold slot).
local function availableMaterials()
    local placedBy = placedCounts()
    local filterSlot = (selectedSlot and not placed[selectedSlot]) and selectedSlot or nil
    local list = {}
    for _, entry in ipairs(materials) do
        local remaining = entry.count - (placedBy[entry.recordId] or 0)
        if remaining > 0 and (not filterSlot or slotAccepts(filterSlot, entry.recordId)) then
            list[#list + 1] = { recordId = entry.recordId, icon = entry.icon, count = remaining }
        end
    end
    return list
end

--- Distinct tool ids/tags used by any recipe at this station (for the
--- auto-detected Tools row).
local function collectStationTools()
    local seen, list = {}, {}
    local function add(query)
        if query and not seen[query] then
            seen[query] = true
            list[#list + 1] = query
        end
    end
    for _, r in pairs(GRegistries.shapedRecipes or {}) do
        if r.context == ctx.context.id and r.action == ctx.action.id then
            for _, t in ipairs(r.tools or {}) do add(t) end
        end
    end
    for _, r in pairs(GRegistries.processRecipes or {}) do
        if r.context == ctx.context.id and r.action == ctx.action.id then
            for _, t in ipairs(r.tools or {}) do add(t) end
        end
    end
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

--- Keep a sensible selection: if none, pick the first empty slot. A selection
--- on a FILLED slot is kept — that's how process slots stack (picking the same
--- material again adds to the selected stack).
local function ensureSelection()
    if selectedSlot then return end
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

--- All placed record ids, one per unit — stacks expand (process matching is a
--- non-positional counted multiset).
local function placedList()
    local list = {}
    for _, cell in pairs(placed) do
        for _ = 1, (cell.count or 1) do
            list[#list + 1] = cell.recordId
        end
    end
    return list
end

--- Resolve the placed slots into the matched recipe(s) + craftability.
--- Both layouts can resolve to SEVERAL recipes (carving; bonemold helm vs
--- boots); the Result panel cycles through them, keeping the player's pick
--- stable while the match set allows.
local function resolve()
    local prevId = matched and matched.id
    matchedList, matched, canCraft = {}, nil, false
    if not ctx or not layout then return end

    if layout.kind == 'grid' then
        matchedList = shaped.resolveShapedRecipes(gridFromPlaced(), ctx.action, ctx.context)
    elseif layout.kind == 'process' then
        matchedList = processCrafting.resolveProcessRecipes(placedList(), ctx.action, ctx.context)
    end

    matchedIndex = 1
    for i, r in ipairs(matchedList) do
        if r.id == prevId then
            matchedIndex = i
            break
        end
    end
    matched = matchedList[matchedIndex]
    canCraft = matched ~= nil and haveEnough()
end

-- ── slot view passed to body builders ────────────────────────────────────────

---@type CraftingSlotView
local view = {
    selectedSlot = nil, -- refreshed each rebuild
    slotView = function(slotId)
        local cell = placed[slotId]
        if not cell then return nil end
        return {
            resource = textureForPath(cell.icon),
            count = (cell.count or 1) > 1 and cell.count or nil,
        }
    end,
    onSlotClick = function(slotId)
        -- Filled slot: take one unit off the stack (clears it at 1) and select
        -- it, so a new pick replaces/refills it.
        local cell = placed[slotId]
        if cell then
            if (cell.count or 1) > 1 then
                cell.count = cell.count - 1
            else
                placed[slotId] = nil
            end
        end
        selectedSlot = slotId
        this.rebuild()
    end,
    onPick = function(recordId, iconPath)
        ensureSelection()
        local isProcess = layout and layout.kind == 'process'
        local target = selectedSlot

        -- process slots stack: picking the material already in the selected
        -- slot adds one (the strip only lists items with inventory remaining)
        if isProcess and target and placed[target] and placed[target].recordId == recordId then
            placed[target].count = (placed[target].count or 1) + 1
            this.rebuild()
            return
        end

        -- place into the selected slot if it's empty and takes this item;
        -- otherwise into the first empty slot that does
        if not (target and not placed[target] and slotAccepts(target, recordId)) then
            target = nil
            for _, id in ipairs(slotOrder()) do
                if not placed[id] and slotAccepts(id, recordId) then
                    target = id
                    break
                end
            end
        end
        if not target then return end -- no slot takes this item

        placed[target] = { recordId = recordId, icon = iconPath, count = 1 }
        if isProcess then
            selectedSlot = target -- stay: the next pick of the same material stacks
        else
            selectedSlot = nil
            ensureSelection() -- grid: auto-advance to the next empty slot
        end
        this.rebuild()
    end,
}

-- ── window sections (alchemy-style) ─────────────────────────────────────────

--- Tools row — apparatus-style, AUTO-DETECTED from the inventory (like the
--- alchemy window showing the apparatus you own): every tool any recipe at
--- this station can use shows up here if the player carries a matching item.
local function toolsSection()
    local slots = {}
    for _, query in ipairs(stationTools) do
        local owned, iconPath = toolInfo(query)
        if owned then
            slots[#slots + 1] = Slot.Slot({
                name = 'tool_' .. query,
                resource = textureForPath(iconPath),
                size = TOOL_ICON,
            })
        end
    end
    -- pad to a minimum width so the section keeps its apparatus look
    while #slots < TOOL_SLOTS do
        slots[#slots + 1] = Slot.Slot({ name = 'tool_pad_' .. #slots, size = TOOL_ICON, state = 'empty' })
    end
    return {
        type = ui.TYPE.Flex,
        name = 'tools_section',
        content = ui.content({
            { type = ui.TYPE.Text,   props = { text = 'Tools' }, template = I.MWUI.templates.textNormal },
            { type = ui.TYPE.Widget, props = { size = v2(0, 3) } },
            components.grid({ name = 'tools_grid', columns = 5, items = slots }),
        }),
    }
end

--- Cycle the Result panel to another match (carving: same wood, many shapes).
---@param delta integer +1 / -1, wraps around
local function cycleMatch(delta)
    local n = #matchedList
    if n < 2 then return end
    matchedIndex = ((matchedIndex - 1 + delta) % n) + 1
    matched = matchedList[matchedIndex]
    this.rebuild()
end

--- Result panel — the resolved output. CLICKING THE RESULT SLOT IS THE CRAFT:
--- it consumes the placed inputs and moves the item into the inventory. When
--- several recipes match the same placement, `< i/n >` cycles between them.
local function resultSection()
    local resource, countLabel, caption
    if matched and matched.sdMeal then
        -- Sun's Dusk meal: SD mints the record on craft; icon comes from the meal def
        resource = textureForPath(matched.sdMeal.icon)
        local n = matched.sdMeal.count or 1
        countLabel = n > 1 and n or nil
        caption = ('%s x%d  (meal)'):format(matched.label or matched.id, n)
        if not canCraft then caption = caption .. '  (not enough materials)' end
    elseif matched then
        resource = textureForPath(recordIconPath(matched.output.id))
        local n = matched.output.count or 1
        countLabel = n > 1 and n or nil
        caption = ('%s x%d'):format(matched.label or matched.id, n)
        if matched.duration and matched.duration > 0 then
            local dur = matched.duration >= 3600
                and ('~%d h'):format(math.ceil(matched.duration / 3600))
                or ('~%d min'):format(math.max(1, math.ceil(matched.duration / 60)))
            caption = caption .. ('  (takes %s)'):format(dur)
        end
        for _, line in ipairs(matched.inputs or {}) do
            if line.returned then
                caption = caption .. '  (mold returned)'
                break
            end
        end
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

    -- header: "Result" plus the match cycler when the placement is ambiguous
    local headerParts = {
        { type = ui.TYPE.Text, props = { text = 'Result' }, template = I.MWUI.templates.textNormal },
    }
    if #matchedList > 1 then
        headerParts[#headerParts + 1] = { type = ui.TYPE.Widget, props = { size = v2(12, 0) } }
        headerParts[#headerParts + 1] = components.button({
            name = 'result_prev',
            label = '<',
            onClick = function() cycleMatch(-1) end,
        })
        headerParts[#headerParts + 1] = { type = ui.TYPE.Widget, props = { size = v2(5, 0) } }
        headerParts[#headerParts + 1] = {
            type = ui.TYPE.Text,
            props = { text = ('%d/%d'):format(matchedIndex, #matchedList) },
            template = I.MWUI.templates.textNormal,
        }
        headerParts[#headerParts + 1] = { type = ui.TYPE.Widget, props = { size = v2(5, 0) } }
        headerParts[#headerParts + 1] = components.button({
            name = 'result_next',
            label = '>',
            onClick = function() cycleMatch(1) end,
        })
    end

    return {
        type = ui.TYPE.Flex,
        name = 'result_section',
        content = ui.content({
            {
                type = ui.TYPE.Flex,
                props = { align = ui.ALIGNMENT.Center, horizontal = true },
                content = ui.content(headerParts),
            },
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
    return components.button({
        name = 'close_button',
        label = 'Close',
        onClick = function() this.close() end,
    })
end

-- ── window assembly ─────────────────────────────────────────────────────────

--- Find a direct child layout by name in a ui.content collection.
local function findChild(contentObj, name)
    for i = 1, #contentObj do
        if contentObj[i].name == name then return contentObj[i] end
    end
    return nil
end

function this.rebuild()
    if not isOpen or not ctx or not layout then return end

    local def = layouts[layout.kind]
    if not def then
        log.error('Unknown crafting layout kind: ' .. tostring(layout.kind))
        return
    end

    -- the materials strip follows the window size (alchemy-style auto layout);
    -- a resize reflows on the next rebuild (i.e. the next click)
    local winSize = WINDOW_SIZE
    if element and element.layout and element.layout.props and element.layout.props.size then
        winSize = element.layout.props.size
    end
    local inputRows = layout.kind == 'grid' and (layout.size[1] or 2)
        or math.ceil(#(layout.inputs or {}) / 4)
    local pickerDims = {
        columns = math.max(3, math.min(12, math.floor((winSize.x - 60) / 46))),
        rows = math.max(1, math.min(6, math.floor((winSize.y - 245 - inputRows * 48) / 46))),
    }

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
                    ItemPicker.Body(availableMaterials(), {
                        onPick = view.onPick,
                        refresh = function() this.rebuild() end,
                    }, pickerDims),
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

    -- Update the existing window's body in place: the window element (and its
    -- position/size, incl. user drags/resizes) is never recreated, so it cannot
    -- jump when a slot or material is clicked.
    if element then
        local foreground = findChild(element.layout.content, 'foreground')
        local body = foreground and findChild(foreground.content, 'body')
        if body then
            body.content = ui.content({ content })
            element:update()
            return
        end
        -- unexpected shape: fall back to a full recreate
        element:destroy()
        element = nil
    end

    local dlg = Window({
        title = 'Crafting Station: ' .. (ctx.context.label or 'Unknown'),
        body = ui.content({ content }),
        props = { anchor = v2(0.5, 0.5), relativePosition = v2(0.4, 0.5), size = WINDOW_SIZE },
        getElement = function() return element end,
    })

    element = ui.create(dlg)
end

-- ── events ───────────────────────────────────────────────────────────────────

--- Sun's Dusk interop: hand the craft to SD's cooking executor. SD mints the
--- meal record (with stat-bracket name + rolled buffs), consumes the listed
--- ingredients AND a bowl/plate from the inventory itself, registers freshness,
--- and grants the meal — so we consume nothing on our side.
--- NOTE: SD only consumes Ingredient-type records; sdMeal recipe inputs must be
--- ingredients. Values are on SD's raw scale (F=80 etc.) and normalised here.
local function craftSdMeal()
    local sd = matched.sdMeal
    core.sendGlobalEvent('SunsDusk_createStew', {
        self.object,
        {
            count = sd.count or 1,
            recipeName = sd.name or matched.label or matched.id,
            recipeIcon = sd.icon,
            recipeId = sd.sdRecipeId, -- optional: reuse an SD recipe's typing
            isSoup = sd.isSoup or false,
            consumeCategory = sd.category,
            foodValue = (sd.food or 0) / 200,
            foodValue2 = (sd.food2 or 0) / 200,
            drinkValue = (sd.drink or 0) / 200,
            drinkValue2 = (sd.drink2 or 0) / 200,
            wakeValue = (sd.wake or 0) / 200,
            warmthValue = sd.warmth, -- warmth is not /200-scaled in SD
            dynamicEffects = {},
            shortBuff = false,
            isToxic = sd.isToxic or false,
            virtualFoodware = sd.virtualFoodware,
            consumedIngredients = placedCounts(),
        },
    })
end

--- Consume list = everything placed minus the matched recipe's `returned`
--- lines (a reusable mold placed in the Mold slot must be there for the match
--- but stays with the player). Shaped recipes have no input lines — everything
--- placed is consumed.
local function consumeList()
    local counts = placedCounts()
    for _, line in ipairs((matched and matched.inputs) or {}) do
        if line.returned then
            local remaining = line.count or 1
            for id, n in pairs(counts) do
                if remaining <= 0 then break end
                if lib.matchesTag(id, line.id) then
                    local spare = math.min(n, remaining)
                    counts[id] = (n - spare > 0) and (n - spare) or nil
                    remaining = remaining - spare
                end
            end
        end
    end
    local consume = {}
    for id, count in pairs(counts) do consume[#consume + 1] = { id = id, count = count } end
    return consume
end

--- Craft = "take the result": consume the placed inputs, grant the output.
--- Recipes with a `duration` don't grant instantly: they START a timed run at
--- the station (globalProcessing) — inputs are consumed up front, the window
--- closes, the station card shows progress, and activating the station when
--- done collects the output.
function this.onCraft()
    if not matched or not canCraft then return end
    if matched.sdMeal then
        craftSdMeal()
    elseif matched.duration and matched.duration > 0 and ctx.object then
        local consume = consumeList()
        core.sendGlobalEvent('ImmersiveCrafting_StartProcess', {
            actor = self.object,
            station = ctx.object,
            recipeId = matched.id,
            label = matched.label or matched.id,
            consume = consume,
            output = matched.output,
            duration = matched.duration,
        })
        this.close() -- the run lives at the station now; its card shows progress
        return
    else
        core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
            actor = self.object,
            consume = consumeList(),
            output = matched.output,
        })
    end
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
    -- a station with a running/finished process doesn't open the window
    if handlerCtx.object and processState.forStation(handlerCtx.object.id) then
        ui.showMessage('This station is busy')
        return
    end
    ctx = handlerCtx
    layout = ctx.context.layout
    placed = {}
    selectedSlot = nil
    isOpen = true
    ItemPicker.reset()
    materials = collectMaterials()
    stationTools = collectStationTools()
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
    stationTools = {}
    matchedList = {}
    matchedIndex = 1
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
