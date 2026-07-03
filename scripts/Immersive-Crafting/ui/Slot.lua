--- Shared bordered item slot (MWUI box + icon, or a tinted placeholder square).
--- Used by the crafting grid, process slots, tools/result panels, and the
--- materials strip so every slot in the mod renders identically.

local ui = require('openmw.ui')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local async = require('openmw.async')

local this = {}

local whiteTexture = ui.texture { path = 'white' }
local DEFAULT_SIZE = util.vector2(44, 44)

--- Placeholder tints for empty slots.
local COLORS = {
    -- empty = util.color.rgb(0.72, 0.48, 0.18),    -- vacant slot
    empty = util.color.rgb(0, 0, 0),             -- vacant slot
    selected = util.color.rgb(0.95, 0.78, 0.35), -- vacant slot awaiting a pick
    missing = util.color.rgb(0.62, 0.20, 0.16),  -- required but not owned
}

---@param opts { name: string, resource: any?, count: integer|string?, size: any?, state: string?, onClick: fun()?, noborder: boolean? }
---@return table layout
function this.Slot(opts)
    local iconProps = { size = opts.size or DEFAULT_SIZE }
    local resource = opts.resource
    if not resource then
        resource = whiteTexture
        iconProps.color = COLORS[opts.state or 'empty'] or COLORS.empty
    end

    iconProps.resource = resource

    local content = {
        {
            type = ui.TYPE.Image,
            props = iconProps,
        },
    }
    if opts.count ~= nil then
        content[#content + 1] = {
            template = I.MWUI.templates.textNormal,
            props = {
                text = tostring(opts.count),
                position = util.vector2(iconProps.size.x - 12, iconProps.size.y - 16),
            },
        }
    end

    if opts.noborder == true then
        return {
            type = ui.TYPE.Container,
            name = opts.name,
            content = ui.content(content),
            events = opts.onClick and { mouseClick = async:callback(opts.onClick) } or nil,
        }
    else
        return {
            template = I.MWUI.templates.box,
            name = opts.name,
            content = ui.content(content),
            events = opts.onClick and { mouseClick = async:callback(opts.onClick) } or nil,
        }
    end
end

return this
