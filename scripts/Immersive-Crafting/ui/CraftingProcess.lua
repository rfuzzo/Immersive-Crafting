--- PROCESS layout: labelled input slots → a result output slot. slotId = input.key.
--- Input clicks go through `view.onSlotClick`; clicking the output slot crafts via `view.onCraft`.

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

--- An item slot showing `data` ({resource,count} or nil); empty slots are tinted.
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

--- A labelled column: caption above a slot.
local function labelled(label, slotWidget)
    return column({
        props = { align = ui.ALIGNMENT.Center },
        children = {
            text({ text = label or '' }),
            spacer({ props = { size = v2(0, 3) } }),
            slotWidget,
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
        local inputSlot = slot('slot_' .. slotId, view.slotView(slotId),
            function() view.onSlotClick(slotId) end)
        children[#children + 1] = labelled(inp.label or inp.key, inputSlot)
        children[#children + 1] = spacer({ props = { size = v2(6, 0) } })
    end

    children[#children + 1] = column({ props = { align = ui.ALIGNMENT.Center }, children = { text({ text = '=>' }) } })
    children[#children + 1] = spacer({ props = { size = v2(6, 0) } })

    local outputSlot = slot('slot_output', view.output, view.output and view.onCraft or nil)
    children[#children + 1] = labelled('Output', outputSlot)

    return box({
        name = 'process_box',
        children = { row({ name = 'process_row', props = { align = ui.ALIGNMENT.Center }, children = children }) },
    })
end

return this
