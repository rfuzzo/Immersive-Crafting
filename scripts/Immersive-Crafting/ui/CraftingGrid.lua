--- GRID layout: an N×M grid of clickable item slots + a result output slot (Minecraft-style).
--- slotId = "r:c". Clicks are handled by the owner (Crafting.lua) via `view.onSlotClick`;
--- clicking the output slot crafts via `view.onCraft`.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local log = require('scripts.Immersive-Crafting.log')

local box = require('scripts.s3.components.box')
local row = require('scripts.s3.components.row')
local column = require('scripts.s3.components.column')
local grid = require('scripts.s3.components.grid')
local text = require('scripts.s3.components.text')
local spacer = require('scripts.s3.components.spacer')
local itemSlot = require('scripts.s3.components.itemSlot')

local v2 = util.vector2
local whiteTexture = ui.texture { path = 'white' }
local ICON_SIZE = v2(44, 44)
local EMPTY_COLOR = util.color.rgb(0.72, 0.48, 0.18)

local this = {}

---@class CraftingSlotView
---@field slotView fun(slotId: string): { resource: any?, count: integer? }? placed item for a slot, or nil
---@field onSlotClick fun(slotId: string) called when a slot is clicked
---@field onCraft fun() called when the output slot is clicked
---@field output { resource: any?, count: integer? }? the resolved result, or nil for no recipe

--- An item slot showing `data` ({resource,count} or nil); empty slots are tinted.
--- `onClick` (optional) wires a mouseClick handler.
---@param name string
---@param data { resource: any?, count: integer? }?
---@param onClick fun()?
local function slot(name, data, onClick)
    local hasIcon = data ~= nil and data.resource ~= nil
    local iconProps = { size = ICON_SIZE }
    if not hasIcon then iconProps.color = EMPTY_COLOR end
    return itemSlot({
        name = name,
        resource = hasIcon and data.resource or whiteTexture,
        count = data and data.count or nil,
        iconProps = iconProps,
        events = onClick and { mouseClick = async:callback(onClick) } or nil,
    })
end

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
            items[#items + 1] = slot('slot_' .. slotId, view.slotView(slotId),
                function() view.onSlotClick(slotId) end)
        end
    end

    -- output slot is clickable only when there's a craftable result
    local outputSlot = slot('slot_output', view.output, view.output and view.onCraft or nil)

    return box({
        name = 'grid_box',
        children = {
            row({
                name = 'grid_row',
                props = { align = ui.ALIGNMENT.Center },
                children = {
                    column({ name = 'grid_body', children = { grid({ name = 'crafting_grid', columns = cols, items = items }) } }),
                    spacer({ props = { size = v2(12, 0) } }),
                    column({
                        name = 'grid_output',
                        props = { align = ui.ALIGNMENT.Center },
                        children = {
                            text({ text = '=>' }),
                            spacer({ props = { size = v2(0, 4) } }),
                            outputSlot,
                        },
                    }),
                },
            }),
        },
    })
end

return this
