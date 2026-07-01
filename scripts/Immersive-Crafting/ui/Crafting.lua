--[[
    Crafting Window UI (extensible, layout-driven)

    An interactive crafting window opened at a station. The window shell (bordered,
    draggable/resizable, titled) is the reusable `ui/Window.lua` widget; this module
    supplies the body for the active layout, owns the placed-item state, resolves the
    matching recipe, and commits the craft.

    LAYOUT-DRIVEN (CContext.layout):
      - "grid"    : N×M grid of item slots (cloth 2x2, table 3x3).  body: CraftingGrid
      - "process" : named role slots → output slot.                 body: CraftingProcess
    Add a new entry to `layouts` to support another shape.

    Slots are filled by CLICKING (no drag-and-drop): clicking an empty slot opens the
    `ui/ItemPicker.lua` widget; picking an item places it in the slot. Clicking a
    filled slot clears it. The placed slots are resolved to a recipe every rebuild; the
    result is shown in a Minecraft-style output slot. Clicking the output slot crafts.
]]

local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')

local Window = require('scripts.Immersive-Crafting.ui.Window')
local ItemPicker = require('scripts.Immersive-Crafting.ui.ItemPicker')
local grid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local process = require('scripts.Immersive-Crafting.ui.CraftingProcess')
local shaped = require('scripts.Immersive-Crafting.shapedCrafting')
local processCrafting = require('scripts.Immersive-Crafting.processCrafting')
local log = require('scripts.Immersive-Crafting.log')

local v2 = util.vector2

local this = {}

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local ctx = nil ---@type HandlerContext?
local layout = nil ---@type CContext.Layout?
local element = nil
local placed = {} ---@type table<string, {recordId:string, icon:string?}> slotId -> placed item
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

-- Item types whose records carry an inventory `icon` (for the output slot).
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

-- ── resolution ───────────────────────────────────────────────────────────────

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

local function slotsFromPlaced()
    local s = {}
    for _, inp in ipairs(layout.inputs or {}) do
        local cell = placed[inp.key]
        s[inp.key] = cell and cell.recordId or nil
    end
    return s
end

--- Resolve the placed slots into a matched recipe + craftability for the layout.
local function resolve()
    matched, canCraft = nil, false
    if not ctx or not layout then return end

    if layout.kind == 'grid' then
        matched = shaped.resolveShapedRecipe(gridFromPlaced(), ctx.action, ctx.context)
    elseif layout.kind == 'process' then
        matched = processCrafting.resolveProcessRecipe(slotsFromPlaced(), ctx.action, ctx.context)
    end

    canCraft = matched ~= nil and haveEnough()
end

-- ── slot view passed to body builders ────────────────────────────────────────

---@type CraftingSlotView
local view = {
    slotView = function(slotId)
        local cell = placed[slotId]
        if not cell then return nil end
        return { resource = textureForPath(cell.icon) }
    end,
    onSlotClick = function(slotId)
        -- Clicking a filled slot clears it; an empty slot opens the item picker.
        if placed[slotId] then
            placed[slotId] = nil
            this.rebuild()
            return
        end
        ItemPicker.open({
            title = 'Select item',
            onPick = function(recordId, iconPath)
                placed[slotId] = { recordId = recordId, icon = iconPath }
                this.rebuild()
            end,
        })
    end,
    onCraft = function() this.onCraft() end,
    output = nil,  -- { resource, count } — refreshed each rebuild
}

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
    if matched then
        view.output = { resource = textureForPath(recordIconPath(matched.output.id)), count = matched.output.count }
    else
        view.output = nil
    end

    local body = def.body(layout, view)
    if not body then
        log.error('Failed to build crafting window body for layout kind: ' .. tostring(layout.kind))
        return
    end

    local dlg = Window({
        title = 'Crafting Station: ' .. (ctx.context.label or 'Unknown'),
        body = body,
        props = { anchor = v2(0.5, 0.5), relativePosition = v2(0.4, 0.5), size = v2(300, 300) },
        getElement = function() return element end,
    })

    element = ui.create(dlg)
end

-- ── events ───────────────────────────────────────────────────────────────────

function this.onCraft()
    if not matched or not canCraft then return end
    -- All placed items are consumed; the global executor removes them from the
    -- inventory by record id and grants the output.
    local consume = {}
    for id, count in pairs(placedCounts()) do consume[#consume + 1] = { id = id, count = count } end
    core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
        actor = self.object,
        consume = consume,
        output = matched.output,
    })
    log.info('Crafted ' .. (matched.label or matched.id))

    -- clear the grid and refresh (inventory updates next frame)
    placed = {}
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
    isOpen = true
    I.UI.setMode('Interface') -- show cursor; inventory remains available
    this.rebuild()
end

function this.close()
    isOpen = false
    ItemPicker.close()
    if element then element:destroy() end
    element = nil
    ctx = nil
    layout = nil
    placed = {}
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
