local world = require('openmw.world')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')
local globalFarming = require('scripts.Immersive-Crafting.globalFarming')
local globalProcessing = require('scripts.Immersive-Crafting.globalProcessing')
local globalLiquids = require('scripts.Immersive-Crafting.globalLiquids')
local globalStations = require('scripts.Immersive-Crafting.globalStations')
local globalDressing = require('scripts.Immersive-Crafting.globalDressing')

local function onSave() return saveData end

local function onLoad(data)
    ---@diagnostic disable-next-line: lowercase-global
    saveData = data or {}
end

--- Normalize a count received through a player event.
---@param value any
---@return integer?
local function normalizeCount(value)
    local count = tonumber(value or 1)
    if not count or count < 1 or count % 1 ~= 0 then return nil end
    return count
end

--- Create the output record and grant it to the actor.
--- NOTE: world.createObject requires an existing record id. Custom outputs need
--- createRecordDraft/createRecord first — deferred (D1).
---@param actor any
---@param output { id: string, count: integer }
---@return boolean
local function grantOutput(actor, output)
    if not (output and output.id) then
        log.error('grant: no output in commit payload')
        return false
    end
    if not actor then
        log.error(('grant: no actor in commit payload (output "%s")'):format(tostring(output.id)))
        return false
    end

    local count = normalizeCount(output.count)
    if not count then
        log.error(('grant: invalid output count for "%s"'):format(tostring(output.id)))
        return false
    end

    local ok, err = pcall(function()
        local created = world.createObject(output.id, count)
        -- move into the actor's inventory (moveInto wants an Inventory, not the actor)
        created:moveInto(types.Actor.inventory(actor))
    end)
    if ok then
        log.info(('grant: %d x "%s" -> %s'):format(count, output.id, tostring(actor.recordId)))
        return true
    end

    log.error(('grant: failed to create output "%s": %s'):format(tostring(output.id), tostring(err)))
    return false
end

--- Validate world-object removals before mutating anything.
---@param consume { object: any, count: integer }[]
---@return { object: any, count: integer }[]?
local function buildWorldRemovalPlan(consume)
    local plan = {}
    for _, entry in ipairs(consume or {}) do
        local obj = entry and entry.object
        local count = entry and normalizeCount(entry.count)
        if not obj or not count then
            return nil
        end

        local ok, available = pcall(function() return obj.count or 1 end)
        if not ok or available < count then
            return nil
        end

        plan[#plan + 1] = { object = obj, count = count }
    end
    return plan
end

--- Execute an already validated removal plan.
---@param plan { object: any, count: integer }[]
---@param operation string
---@return boolean
local function executeRemovalPlan(plan, operation)
    for _, entry in ipairs(plan) do
        local ok, err = pcall(function()
            entry.object:remove(entry.count)
        end)
        if not ok then
            log.error(('%s: failed to remove ingredient: %s'):format(operation, tostring(err)))
            return false
        end
    end
    return true
end

--- GLOBAL commit executor (D1): performs the world/inventory mutation that
--- player scripts cannot do themselves.
--- Dispatched from lib.commitRecipe via core.sendGlobalEvent.
---@param data table { consume: { object: any, count: integer }[], output: { id: string, count: integer }, actor: any }
local function onCommit(data)
    if not (data and data.actor and data.output and data.output.id) then
        log.error('commit: malformed payload')
        return
    end

    local plan = buildWorldRemovalPlan(data.consume)
    if not plan then
        log.warn('commit: ingredients changed before the craft could be committed')
        return
    end

    if not executeRemovalPlan(plan, 'commit') then
        log.error('commit: aborted output because ingredient removal failed')
        return
    end

    grantOutput(data.actor, data.output)
end

--- Shaped-crafting executor: consume placed items from the actor's INVENTORY
--- (by record id), then grant the output. Consumed Sun's Dusk liquid bottles
--- give the empty container back (the water is used; the waterskin remains).
---@param data table { actor: any, consume: { id: string, count: integer }[], output: { id: string, count: integer } }
local function onCraftShaped(data)
    if not (data and data.actor and data.output and data.output.id) then
        log.error('craft: malformed payload')
        return
    end
    if not normalizeCount(data.output.count) then
        log.error('craft: invalid output count')
        return
    end

    log.info(('craft: %d inputs -> "%s"'):format(
        #(data.consume or {}), tostring(data.output.id)))
    local inv = types.Actor.inventory(data.actor)

    -- Aggregate duplicate input lines first, then build one complete removal plan.
    -- Nothing is removed until every requirement is satisfied.
    local requirements = {}
    for _, entry in ipairs(data.consume or {}) do
        local id = entry and type(entry.id) == 'string' and entry.id or nil
        local count = entry and normalizeCount(entry.count)
        if not id or not count then
            log.error('craft: invalid consume entry')
            return
        end

        local key = id:lower()
        local req = requirements[key]
        if req then
            req.count = req.count + count
        else
            requirements[key] = { id = id, count = count }
        end
    end

    local plan = {}
    for key, req in pairs(requirements) do
        local needed = req.count
        for _, item in ipairs(inv:getAll()) do
            if needed <= 0 then break end
            if item.recordId:lower() == key then
                local take = math.min(needed, item.count or 1)
                plan[#plan + 1] = { object = item, count = take }
                needed = needed - take
            end
        end

        if needed > 0 then
            log.warn(('craft: not enough "%s" in inventory (missing %d)'):format(
                tostring(req.id), needed))
            return
        end
    end

    if not executeRemovalPlan(plan, 'craft') then
        log.error('craft: aborted output because ingredient removal failed')
        return
    end

    -- SD water interop: an emptied bottle leaves its container behind.
    for _, req in pairs(requirements) do
        local orig = globalLiquids.emptyContainerFor(req.id)
        if orig then
            grantOutput(data.actor, { id = orig, count = req.count })
        end
    end

    grantOutput(data.actor, data.output)
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
        ImmersiveCrafting_SetOptions = function(data)
            globalProcessing.onSetOptions(data)
            globalFarming.onSetOptions(data)
        end,
    }
}
