--- GRID layout: an N×M grid of clickable item slots (positional). slotId = "r:c".
--- Clicking an empty slot selects it (the materials strip fills the selected slot);
--- clicking a filled slot clears it. The tools/result panels live in the shared
--- window frame (Crafting.lua), alchemy-window style.

local util = require('openmw.util')

local log = require('scripts.Immersive-Crafting.log')

local box = require('scripts.s3.components.box')
local column = require('scripts.s3.components.column')
local grid = require('scripts.s3.components.grid')
local Slot = require('scripts.Immersive-Crafting.ui.Slot')

local ICON_SIZE = util.vector2(44, 44)

local this = {}

---@class CraftingSlotView
---@field slotView fun(slotId: string): { resource: any?, count: integer? }? placed item for a slot, or nil
---@field onSlotClick fun(slotId: string) called when a slot is clicked
---@field onPick fun(recordId: string, iconPath: string?) place a picked material into the selected slot
---@field selectedSlot string? the slot the next picked material goes into

--- Build the grid body (input slots only).
---@param layout CContext.Layout?
---@param view CraftingSlotView
---@return table?
function this.Body(layout, view)
    if not layout or not layout.size then
        log.error('Cannot build crafting grid: layout/size is nil')
        return nil
    end

    local rows = layout.size[1] or 2
    local cols = layout.size[2] or 2
    log.trace(('Building crafting grid %dx%d'):format(rows, cols))

    local items = {}
    for r = 1, rows do
        for c = 1, cols do
            local slotId = ('%d:%d'):format(r, c)
            local placed = view.slotView(slotId)
            local state = (view.selectedSlot == slotId and not placed) and 'selected' or 'empty'
            items[#items + 1] = Slot.Slot({
                name = 'slot_' .. slotId,
                resource = placed and placed.resource or nil,
                count = placed and placed.count or nil,
                size = ICON_SIZE,
                state = state,
                onClick = function() view.onSlotClick(slotId) end,
            })
        end
    end

    return box({
        name = 'grid_box',
        children = {
            column({
                name = 'grid_body',
                children = { grid({ name = 'crafting_grid', columns = cols, items = items }) },
            }),
        },
    })
end

return this
