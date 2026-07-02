--- Shared bordered item slot (MWUI box + icon, or a tinted placeholder square).
--- Used by the crafting grid, process slots, tools/result panels, and the
--- materials strip so every slot in the mod renders identically.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')

local itemSlot = require('scripts.s3.components.itemSlot')

local whiteTexture = ui.texture { path = 'white' }
local DEFAULT_SIZE = util.vector2(44, 44)

--- Placeholder tints for empty slots.
local COLORS = {
    empty = util.color.rgb(0.72, 0.48, 0.18),    -- vacant slot
    selected = util.color.rgb(0.95, 0.78, 0.35), -- vacant slot awaiting a pick
    missing = util.color.rgb(0.62, 0.20, 0.16),  -- required but not owned
}

---@param opts { name: string, resource: any?, count: integer|string?, size: any?, state: string?, onClick: fun()? }
---@return table layout
local function Slot(opts)
    local iconProps = { size = opts.size or DEFAULT_SIZE }
    local resource = opts.resource
    if not resource then
        resource = whiteTexture
        iconProps.color = COLORS[opts.state or 'empty'] or COLORS.empty
    end
    return itemSlot({
        name = opts.name,
        resource = resource,
        count = opts.count,
        iconProps = iconProps,
        events = opts.onClick and { mouseClick = async:callback(opts.onClick) } or nil,
    })
end

return Slot
