local world = require('openmw.world')
local types = require('openmw.types')
local I = require('openmw.interfaces')

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

-- ── activation ───────────────────────────────────────────────────────────────
-- Activate-triggered stations are Activator objects. The player pushes the set of
-- "activate" contexts on load; on activating a matching activator we tell the player
-- to open the station window (and suppress the default activation).

local activateContexts = {} ---@type { id: string, recordIds: string[] }[]
local activationHandlerRegistered = false

--- Global-context tag match: exact record id or FlexTag (I.FlexTagG) tag.
---@param recordId string
---@param query string
---@return boolean
local function matchesTagGlobal(recordId, query)
    if recordId:lower() == query:lower() then return true end
    local flexTag = I.FlexTagG
    if flexTag and flexTag.objectHasTag then
        return flexTag.objectHasTag(recordId, query) and true or false
    end
    return false
end

--- Activation handler for Activator objects. Returns false to suppress the default
--- activation when we open one of our stations.
---@param object any
---@param actor any
local function onActivateStation(object, actor)
    if actor.type ~= types.Player then return end
    local recordId = object.recordId
    for _, c in ipairs(activateContexts) do
        for _, rid in ipairs(c.recordIds or {}) do
            if matchesTagGlobal(recordId, rid) then
                actor:sendEvent('ImmersiveCrafting_OpenStation', { contextId = c.id })
                return false -- we handled it; skip default activation
            end
        end
    end
end

--- Player pushes its "activate" contexts here after loading data.
---@param data table { contexts: { id: string, recordIds: string[] }[] }
local function onRegisterActivateContexts(data)
    activateContexts = (data and data.contexts) or {}
    if not activationHandlerRegistered then
        I.Activation.addHandlerForType(types.Activator, onActivateStation)
        activationHandlerRegistered = true
    end
    log.info(('Registered %d activate-triggered contexts'):format(#activateContexts))
end

return {
    engineHandlers = { onLoad = onLoad, onInit = onLoad, onSave = onSave },
    eventHandlers = {
        ImmersiveCrafting_Commit = onCommit,
        ImmersiveCrafting_CraftShaped = onCraftShaped,
        ImmersiveCrafting_RegisterActivateContexts = onRegisterActivateContexts,
    }
}
