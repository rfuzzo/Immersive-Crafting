--- PROCESS layout: N input slots (non-positional; chunked into rows of 4).
--- slotId = input.key. Slots may carry a label (kiln Input/Reagent/Fuel/Mold)
--- or be generic (firepit s1..sN), and hold a STACK of one item (furnace-style;
--- the count badge shows the stack size). Clicking an empty slot selects it
--- (the materials strip fills the selected slot); clicking a filled slot takes
--- one unit back. The tools/result panels live in the shared window frame
--- (Crafting.lua). Matching is a counted multiset — position never matters;
--- labels and `accepts` filters are placement guidance only.

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')

local c = require('scripts.Immersive-Crafting.ui.components')
local box, column, grid, text, spacer = c.box, c.column, c.grid, c.text, c.spacer
local Slot = require('scripts.Immersive-Crafting.ui.Slot')

local v2 = util.vector2
local ICON_SIZE = v2(44, 44)
local SLOTS_PER_ROW = 4

local this = {}

--- A column: optional caption above a slot (used when the layout labels roles).
local function labelled(label, slotWidget)
    if not label or label == '' then return slotWidget end
    return column({
        props = { align = ui.ALIGNMENT.Center },
        children = {
            text({ text = label, template = I.MWUI.templates.textNormal }),
            spacer({ props = { size = v2(0, 3) } }),
            slotWidget,
        },
    })
end

--- Build the process body (input slots only).
---@param layout CContext.Layout?
---@param view CraftingSlotView
---@return table?
function this.Body(layout, view)
    if not layout or not layout.inputs then
        log.error('Cannot build process layout: layout/inputs is nil')
        return nil
    end

    local slots = {}
    for _, inp in ipairs(layout.inputs) do
        local slotId = inp.key
        local placed = view.slotView(slotId)
        local state = (view.selectedSlot == slotId and not placed) and 'selected' or 'empty'
        local inputSlot = Slot.Slot({
            name = 'slot_' .. slotId,
            resource = placed and placed.resource or nil,
            count = placed and placed.count or nil,
            size = ICON_SIZE,
            state = state,
            -- filled: the placed item's name; empty: the slot's role, so the
            -- Input/Fuel/Mold row explains itself on hover
            tooltip = placed and placed.label or inp.label,
            onClick = function() view.onSlotClick(slotId) end,
        })
        slots[#slots + 1] = labelled(inp.label, inputSlot)
    end

    return box({
        name = 'process_box',
        children = {
            grid({
                name = 'process_inputs',
                columns = math.min(#slots, SLOTS_PER_ROW),
                items = slots,
            }),
        },
    })
end

return this
