--- PROCESS layout: labelled input slots → an output slot. slotId = input.key.
--- Clicking an input slot is handled by the owner (Crafting.lua) via `view.onSlotClick`.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local log = require('scripts.Immersive-Crafting.log')

local box = require('scripts.s3.components.box')
local row = require('scripts.s3.components.row')
local column = require('scripts.s3.components.column')
local text = require('scripts.s3.components.text')
local spacer = require('scripts.s3.components.spacer')
local itemSlot = require('scripts.s3.components.itemSlot')

local v2 = util.vector2
local whiteTexture = ui.texture { path = 'white' }
local ICON_SIZE = v2(44, 44)
local EMPTY_COLOR = util.color.rgb(0.72, 0.48, 0.18)

local this = {}

--- A labelled column: caption above a slot.
---@param label string
---@param slot table
local function labelled(label, slot)
    return column({
        props = { align = ui.ALIGNMENT.Center },
        children = {
            text({ text = label or '' }),
            spacer({ props = { size = v2(0, 3) } }),
            slot,
        },
    })
end

--- Build the process body.
---@param layout CContext.Layout?
---@param view CraftingSlotView
---@return table?
function this.Body(layout, view)
    if not layout or not layout.inputs then
        log.error('Cannot build process layout: layout/inputs is nil')
        return nil
    end

    local children = {}
    for _, inp in ipairs(layout.inputs) do
        local slotId = inp.key
        local placed = view.slotView(slotId)
        local hasIcon = placed ~= nil and placed.resource ~= nil
        local iconProps = { size = ICON_SIZE }
        if not hasIcon then iconProps.color = EMPTY_COLOR end -- tint the empty-slot square
        local slot = itemSlot({
            name = 'slot_' .. slotId,
            resource = hasIcon and placed.resource or whiteTexture,
            count = placed and placed.count or nil,
            iconProps = iconProps,
            events = { mouseClick = async:callback(function() view.onSlotClick(slotId) end) },
        })
        children[#children + 1] = labelled(inp.label or inp.key, slot)
        children[#children + 1] = spacer({ props = { size = v2(6, 0) } })
    end

    -- arrow → output (display-only)
    children[#children + 1] = column({
        props = { align = ui.ALIGNMENT.Center },
        children = { text({ text = '=>' }) },
    })
    children[#children + 1] = spacer({ props = { size = v2(6, 0) } })
    children[#children + 1] = labelled('Output', itemSlot({
        name = 'slot_output',
        resource = whiteTexture,
        iconProps = { size = ICON_SIZE, color = EMPTY_COLOR },
    }))

    return box({
        name = 'process_box',
        children = { row({ name = 'process_row', props = { align = ui.ALIGNMENT.Center }, children = children }) },
    })
end

--- Resolve the placed slots into a matched recipe. (State/craft wiring TBD.)
function this.Resolve()
end

return this
