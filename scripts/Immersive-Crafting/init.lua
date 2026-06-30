local world = require('openmw.world')
local types = require('openmw.types')

local log = require('scripts.Immersive-Crafting.log')

local function onSave() return saveData end

local function onLoad(data)
    ---@diagnostic disable-next-line: lowercase-global
    saveData = data or {}
end

--- Create the output record and grant it to the actor.
--- NOTE: world.createObject requires an existing record id. Custom outputs need
--- createRecordDraft/createRecord first — deferred (D1).
---@param actor any
---@param output { id: string, count: integer }
local function grantOutput(actor, output)
    if not (output and output.id and actor) then return end
    local ok, err = pcall(function()
        local created = world.createObject(output.id, output.count or 1)
        ---@diagnostic disable-next-line: discard-returns
        created:moveInto(actor)
    end)
    if not ok then
        log.error(('commit: failed to create output "%s": %s'):format(tostring(output.id), tostring(err)))
    end
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

    -- 2. produce output and grant it to the actor
    grantOutput(data.actor, data.output)
end

--- Shaped-crafting executor: consume placed items from the actor's INVENTORY
--- (by record id), then grant the output.
---@param data table { actor: any, consume: { id: string, count: integer }[], output: { id: string, count: integer } }
local function onCraftShaped(data)
    if not (data and data.actor) then return end
    local inv = types.Actor.inventory(data.actor)

    for _, entry in ipairs(data.consume or {}) do
        local needed = entry.count or 1
        for _, item in ipairs(inv:getAll()) do
            if needed <= 0 then break end
            if item.recordId == entry.id then
                local take = math.min(needed, item.count or 1)
                local ok, err = pcall(function() item:remove(take) end)
                if ok then
                    needed = needed - take
                else
                    log.error(('craft: failed to remove "%s": %s'):format(tostring(entry.id), tostring(err)))
                end
            end
        end
        if needed > 0 then
            log.warn(('craft: not enough "%s" in inventory'):format(tostring(entry.id)))
        end
    end

    grantOutput(data.actor, data.output)
end

return {
    engineHandlers = { onLoad = onLoad, onInit = onLoad, onSave = onSave },
    eventHandlers = {
        ImmersiveCrafting_Commit = onCommit,
        ImmersiveCrafting_CraftShaped = onCraftShaped,
    }
}
