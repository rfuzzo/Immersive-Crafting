--[[
    Shared hover tooltip — ONE floating label element for the whole mod
    (Notification layer: above Windows), following the mouse. Owners wire it
    via Slot's `tooltip` option or ItemPicker entries; whoever shows it last
    wins, so a single element never stacks or fights.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local c = require('scripts.Immersive-Crafting.ui.components')

local TOOLTIP_OFFSET = util.vector2(18, 22)

local this = {}

local element = nil
local currentLabel = nil ---@type string? label the tooltip currently shows

function this.hide()
    if element then
        element:destroy()
        element = nil
    end
    currentLabel = nil
end

--- Show/move the tooltip next to the mouse.
--- Same label -> just follow the mouse; new label -> recreate.
---@param label string
---@param mousePos any
function this.show(label, mousePos)
    if element and currentLabel == label then
        element.layout.props.position = mousePos + TOOLTIP_OFFSET
        element:update()
        return
    end
    this.hide()
    currentLabel = label
    element = ui.create({
        layer = 'Notification',
        name = 'ic_tooltip',
        template = I.MWUI.templates.boxTransparent,
        props = { position = mousePos + TOOLTIP_OFFSET },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    c.text({ text = label, template = I.MWUI.templates.textNormal }),
                },
            },
        },
    })
end

return this
