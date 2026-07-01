--- GRID layout: an N×M grid of clickable item slots. slotId = "r:c".
--- Clicking a slot is handled by the owner (Crafting.lua) via `view.onSlotClick`.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local log = require('scripts.Immersive-Crafting.log')

local box = require('scripts.s3.components.box')
local column = require('scripts.s3.components.column')
local grid = require('scripts.s3.components.grid')
local itemSlot = require('scripts.s3.components.itemSlot')

local v2 = util.vector2
local whiteTexture = ui.texture { path = 'white' }
local ICON_SIZE = v2(44, 44)
local EMPTY_COLOR = util.color.rgb(0.72, 0.48, 0.18)

local this = {}

---@class CraftingSlotView
---@field slotView fun(slotId: string): { resource: any?, count: integer? }? placed item for a slot, or nil
---@field onSlotClick fun(slotId: string) called when a slot is clicked

--- Build the grid body.
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
            local hasIcon = placed ~= nil and placed.resource ~= nil
            local iconProps = { size = ICON_SIZE }
            if not hasIcon then iconProps.color = EMPTY_COLOR end -- tint the empty-slot square
            items[#items + 1] = itemSlot({
                name = 'slot_' .. slotId,
                resource = hasIcon and placed.resource or whiteTexture,
                count = placed and placed.count or nil,
                iconProps = iconProps,
                events = {
                    mouseClick = async:callback(function() view.onSlotClick(slotId) end),
                },
            })
        end
    end

    return box({
        name = 'grid_box',
        children = {
            column({
                name = 'grid_body',
                children = {
                    grid({ name = 'crafting_grid', columns = cols, items = items }),
                },
            }),
        },
    })
end

--- Resolve the placed grid into a matched recipe. (State/craft wiring TBD.)
function this.Resolve()
end

return this
