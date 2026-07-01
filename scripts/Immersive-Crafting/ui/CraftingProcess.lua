--- PROCESS layout: [input slots] → [output slot]. slotId = input.key.

local this = {}

---@param layout CContext.Layout?
function this.Body(layout)
    -- local row = ui.content {}
    -- for i, inp in ipairs(layout.inputs) do
    --     if i > 1 then row:add(spacer(SLOT_GAP, 0)) end
    --     row:add(labelledSlot(inp.key, inp.label or inp.key))
    -- end
    -- row:add(spacer(10, 0))
    -- row:add(text('→', 24))
    -- row:add(spacer(10, 0))
    -- row:add(outputSlot('Output'))
    -- return { type = ui.TYPE.Flex, props = { horizontal = true, align = ui.ALIGNMENT.Center }, content = row }
end

function this.Resolve()
    -- local slots = {}
    -- for _, inp in ipairs(layout.inputs) do
    --     local cell = placed[inp.key]
    --     slots[inp.key] = cell and cell.recordId or nil
    -- end
    -- matched = process.resolveProcessRecipe(slots, ctx.action, ctx.context)
    -- canCraft = matched ~= nil and haveEnough()
end

return this
