local world = require('openmw.world')

local log = require('scripts.Immersive-Crafting.log')

local function onSave() return saveData end

local function onLoad(data)
    ---@diagnostic disable-next-line: lowercase-global
    saveData = data or {}
end

--- GLOBAL commit executor (D1): trusts the player request and performs the
--- world/inventory mutation that player scripts cannot do themselves.
--- Dispatched from lib.commitRecipe via core.sendGlobalEvent.
---@param data table { consume: { object: any, count: integer }[], output: { id: string, count: integer }, actor: any }
local function onCommit(data)
    if not data then return end

    -- 1. consume ingredients (remove the matched stacks from the world)
    for _, entry in ipairs(data.consume or {}) do
        local obj = entry.object
        if obj then
            local ok, err = pcall(function() obj:remove(entry.count or 1) end)
            if not ok then
                log.error(('commit: failed to remove ingredient: %s'):format(tostring(err)))
            end
        end
    end

    -- 2. produce output (create the record and grant it to the actor).
    -- NOTE: world.createObject requires an existing record id. Custom outputs
    -- (e.g. "Stew") need createRecordDraft/createRecord first — deferred (D1).
    local output = data.output
    if output and output.id and data.actor then
        local ok, err = pcall(function()
            local created = world.createObject(output.id, output.count or 1)
            ---@diagnostic disable-next-line: discard-returns
            created:moveInto(data.actor)
        end)
        if not ok then
            log.error(('commit: failed to create output "%s": %s'):format(tostring(output.id), tostring(err)))
        end
    end
end

return {
    engineHandlers = { onLoad = onLoad, onInit = onLoad, onSave = onSave },
    eventHandlers = {
        ImmersiveCrafting_Commit = onCommit,
    }
}
