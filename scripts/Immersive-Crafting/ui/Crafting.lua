--[[
    Crafting Window UI (extensible, layout-driven)

    An interactive crafting window opened at a station. The window shell (bordered,
    draggable/resizable, titled) is the reusable `ui/Window.lua` widget; this module
    supplies the body for the active layout and owns the placed-item state.

    LAYOUT-DRIVEN (CContext.layout):
      - "grid"    : N×M grid of item slots (cloth 2x2, table 3x3).  body: CraftingGrid
      - "process" : named role slots → output slot.                 body: CraftingProcess
    Add a new entry to `layouts` to support another shape.

    Slots are filled by CLICKING (no drag-and-drop): clicking an empty slot opens the
    `ui/ItemPicker.lua` widget; picking an item places it in the slot. Clicking a
    filled slot clears it.

    NOTE: recipe resolution / craft commit is not wired yet (Resolve/onCraft are stubs).
]]

local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')

local Window = require('scripts.Immersive-Crafting.ui.Window')
local ItemPicker = require('scripts.Immersive-Crafting.ui.ItemPicker')
local grid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local process = require('scripts.Immersive-Crafting.ui.CraftingProcess')
local log = require('scripts.Immersive-Crafting.log')

local v2 = util.vector2

local this = {}

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local ctx = nil ---@type HandlerContext?
local layout = nil ---@type CContext.Layout?
local element = nil
local placed = {} ---@type table<string, {recordId:string, icon:string?}> slotId -> placed item
local iconTextureCache = {} ---@type table<string, any>

-- ── layout registry ─────────────────────────────────────────────────────────

---@class CraftingLayout
---@field body fun(layout: CContext.Layout, view: CraftingSlotView): table?
---@field resolve fun()

--- Add an entry here to support a new station shape.
local layouts = {
    grid = { body = grid.Body, resolve = grid.Resolve },
    process = { body = process.Body, resolve = process.Resolve },
} ---@type table<string, CraftingLayout>

-- ── slot state / view ────────────────────────────────────────────────────────

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

--- The view passed to body builders: how to render and click each slot.
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
    -- TODO: resolve placed items → recipe, dispatch consume/produce to the global
    -- executor (ImmersiveCrafting_CraftShaped). Not wired yet.
    this.close()
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
