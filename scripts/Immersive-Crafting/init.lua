local world = require('openmw.world')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')
local globalFarming = require('scripts.Immersive-Crafting.globalFarming')
local globalProcessing = require('scripts.Immersive-Crafting.globalProcessing')
local globalLiquids = require('scripts.Immersive-Crafting.globalLiquids')
local globalStations = require('scripts.Immersive-Crafting.globalStations')
local globalDressing = require('scripts.Immersive-Crafting.globalDressing')
local globalBuilding = require('scripts.Immersive-Crafting.globalBuilding')
local craftedBonus = require('scripts.Immersive-Crafting.craftedBonus')

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
---@param crafted boolean? true for real player crafts: equipment outputs are
--- granted as their boosted "Wrought" clone (craftedBonus)
local function grantOutput(actor, output, crafted)
    if not (output and output.id) then
        log.error('grant: no output in commit payload')
        return
    end
    if not actor then
        log.error(('grant: no actor in commit payload (output "%s")'):format(tostring(output.id)))
        return
    end
    local grantId = crafted and craftedBonus.boostedOutput(output.id) or output.id
    local ok, err = pcall(function()
        local created = world.createObject(grantId, output.count or 1)
        -- move into the actor's inventory (moveInto wants an Inventory, not the actor)
        created:moveInto(types.Actor.inventory(actor))
    end)
    if ok then
        log.info(('grant: %d x "%s" -> %s'):format(output.count or 1, output.id, tostring(actor.recordId)))
    else
        log.error(('grant: failed to create output "%s": %s'):format(tostring(output.id), tostring(err)))
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
--- (by record id), then grant the output. Consumed Sun's Dusk liquid bottles
--- give the empty container back (the water is used; the waterskin remains).
--- `crafted` marks REAL player crafts: their equipment outputs are granted
--- as boosted "Wrought" clones (debug grants leave it unset).
---@param data table { actor: any, consume: { id: string, count: integer }[], output: { id: string, count: integer }, crafted: boolean? }
local function onCraftShaped(data)
    if not (data and data.actor) then
        log.error('craft: event without actor')
        return
    end
    log.info(('craft: %d inputs -> "%s"'):format(
        #(data.consume or {}), tostring(data.output and data.output.id)))
    local inv = types.Actor.inventory(data.actor)

    for _, entry in ipairs(data.consume or {}) do
        local needed = entry.count or 1
        local removed = 0
        for _, item in ipairs(inv:getAll()) do
            if needed <= 0 then break end
            if item.recordId == entry.id then
                local take = math.min(needed, item.count or 1)
                local ok, err = pcall(function() item:remove(take) end)
                if ok then
                    needed = needed - take
                    removed = removed + take
                else
                    log.error(('craft: failed to remove "%s": %s'):format(tostring(entry.id), tostring(err)))
                end
            end
        end
        if needed > 0 then
            log.warn(('craft: not enough "%s" in inventory'):format(tostring(entry.id)))
        end
        -- SD water interop: an emptied bottle leaves its container behind
        local orig = removed > 0 and globalLiquids.emptyContainerFor(entry.id)
        if orig then
            grantOutput(data.actor, { id = orig, count = removed })
        end
    end

    grantOutput(data.actor, data.output, data.crafted)
end

-- ── activation ───────────────────────────────────────────────────────────────
-- Activate-triggered stations are Activator objects. The player pushes the set of
-- "activate" contexts on load; on activating a matching activator we tell the player
-- to open the station window (and suppress the default activation).

local activateContexts = {} ---@type { id: string, recordIds: string[], recordPatterns: string[]?, recordPatternsExclude: string[]? }[]
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

--- id/tag match, or Lua-pattern match with vetoes (SD lit campfires etc.).
---@param recordId string
---@param c table pushed activate-context entry
---@return boolean
local function matchesActivateContext(recordId, c)
    for _, rid in ipairs(c.recordIds or {}) do
        if matchesTagGlobal(recordId, rid) then return true end
    end
    if c.recordPatterns then
        local lowered = recordId:lower()
        for _, pattern in ipairs(c.recordPatterns) do
            if lowered:find(pattern) then
                for _, veto in ipairs(c.recordPatternsExclude or {}) do
                    if lowered:find(veto) then return false end
                end
                return true
            end
        end
    end
    return false
end

--- Activation handler for Activator objects. Returns false to suppress the default
--- activation when we open one of our stations.
---@param object any
---@param actor any
local function onActivateStation(object, actor)
    if actor.type ~= types.Player then return end

    -- a running/finished timed process owns the station's activation
    -- (busy -> remaining-time message; done -> collect the output)
    if globalProcessing.onStationActivated(object, actor) then
        return false
    end

    local recordId = object.recordId
    for _, c in ipairs(activateContexts) do
        if matchesActivateContext(recordId, c) then
            actor:sendEvent('ImmersiveCrafting_OpenStation', { contextId = c.id, object = object })
            return false -- we handled it; skip default activation
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
    engineHandlers = {
        onLoad = onLoad,
        onInit = onLoad,
        onSave = onSave,
        onObjectActive = function(object)
            -- station items swap into activators; seeds dropped near a planter
            -- are sown into it; anything else dropped near a loadable station
            -- joins its charge (UI-less kiln/charcoal pit)
            if not globalStations.onObjectActive(object)
                and not globalFarming.onObjectActive(object) then
                globalProcessing.onObjectActive(object)
            end
        end,
    },
    eventHandlers = {
        ImmersiveCrafting_Commit = onCommit,
        ImmersiveCrafting_CraftShaped = onCraftShaped,
        ImmersiveCrafting_RegisterActivateContexts = onRegisterActivateContexts,
        ImmersiveCrafting_Plant = globalFarming.onPlant,
        ImmersiveCrafting_RequestCropSync = function(data)
            globalFarming.onRequestSync(data)
            globalProcessing.onRequestSync(data)
        end,
        ImmersiveCrafting_StartProcess = globalProcessing.onStart,
        ImmersiveCrafting_CollectProcess = globalProcessing.onCollect,
        ImmersiveCrafting_ClassifyLiquids = globalLiquids.onClassify,
        ImmersiveCrafting_PackStation = function(data)
            -- a cold loaded station gives its charge back before folding up
            globalProcessing.returnCharge(data)
            globalStations.onPack(data)
        end,
        ImmersiveCrafting_IgniteStation = globalProcessing.onIgnite,
        ImmersiveCrafting_GroundProbe = globalStations.onGroundProbe,
        ImmersiveCrafting_FieldDress = globalDressing.onFieldDress,
        ImmersiveCrafting_Build = globalBuilding.onBuild,
        ImmersiveCrafting_SetOptions = function(data)
            globalProcessing.onSetOptions(data)
            globalFarming.onSetOptions(data)
            craftedBonus.onSetOptions(data)
        end,
    }
}
