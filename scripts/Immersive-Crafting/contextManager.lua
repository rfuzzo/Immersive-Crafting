local log = require('scripts.Immersive-Crafting.log')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local lib = require('scripts.Immersive-Crafting.lib')
local conditions = require('scripts.Immersive-Crafting.conditions')
local processState = require('scripts.Immersive-Crafting.processState')

local nearby = require('openmw.nearby')
local types = require('openmw.types')
local self = require('openmw.self')
local util = require('openmw.util')
local camera = require('openmw.camera')

local updateInterval = 0.25 -- Check for nearby context every 0.25 seconds

-- Nominal "distance" for condition contexts (no world object): closer stations
-- still win, but the condition card shows when nothing else is around.
local CONDITION_DISTANCE = 100

local this = {}

---@class ProximityResult
---@field context CContext? The context definition
---@field object GameObject The actual game object
---@field distance number Distance to the object

this.currentContext = nil ---@type ProximityResult|nil
this.timeSinceLastUpdate = 0 ---@type number

--- Resolve an action definition, whether by ID or direct reference
---@param actionDef CAction|string
---@return CAction?
local function resolveAction(actionDef)
    -- if actionDef is a string, look up the action definition
    if type(actionDef) == 'string' then
        local a = GRegistries.actions[actionDef]

        if not a then
            log.error('Action not found: ' .. actionDef)
            return nil
        end

        return a
    else
        return actionDef
    end
end

---Update overlay actions based on nearby context
local function updateOverlay()
    -- log.trace('Updating overlay actions for nearby context')

    -- Clear existing actions
    overlay.clearAllActions()

    local result = this.currentContext
    if not result then return end

    local context = result.context
    if not context then return end

    for _, action in ipairs(context.actions or {}) do
        overlay.registerAction(context, resolveAction(action), result.object)
    end
end

--- Gather candidate station objects (items + activators) within range.
---@param maxRange number
---@return { object: any, recordId: string, distance: number }[]
local function gatherNearby(maxRange)
    local playerPos = self.position
    local list = {}
    local function collect(objs)
        for _, obj in ipairs(objs) do
            local distance = (obj.position - playerPos):length()
            if distance <= maxRange then
                list[#list + 1] = { object = obj, recordId = obj.recordId, distance = distance }
            end
        end
    end
    -- stations/fires may be misc items (bowl, pot) or activators (furniture, fire pits)
    collect(nearby.items)
    collect(nearby.activators)
    -- DEAD creatures are candidates too, but only for `targets:"corpse"` contexts
    -- (field dressing); living actors never card
    for _, actor in ipairs(nearby.actors) do
        if actor ~= self.object then
            local okDead, dead = pcall(function() return types.Actor.isDead(actor) end)
            if okDead and dead then
                local distance = (actor.position - playerPos):length()
                if distance <= maxRange then
                    list[#list + 1] = { object = actor, recordId = actor.recordId,
                        distance = distance, corpse = true }
                end
            end
        end
    end
    return list
end

--- Does a candidate record id match a context definition? recordIds match as
--- exact id or FlexTag tag; recordPatterns match as Lua patterns on the
--- lowercased id (with recordPatternsExclude vetoes) — used for name-based
--- families like Sun's Dusk lit campfires.
---@param recordId string
---@param def CContext
---@return boolean
local function matchesDef(recordId, def)
    for _, rid in ipairs(def.recordIds or {}) do
        if lib.matchesTag(recordId, rid) then return true end
    end
    if def.recordPatterns then
        local lowered = recordId:lower()
        for _, pattern in ipairs(def.recordPatterns) do
            if lowered:find(pattern) then
                for _, veto in ipairs(def.recordPatternsExclude or {}) do
                    if lowered:find(veto) then return false end
                end
                return true
            end
        end
    end
    return false
end

--- Are all required tags present among the candidates?
---@param candidates { recordId: string }[]
---@param requires string[]
---@return boolean
local function hasRequired(candidates, requires)
    for _, tag in ipairs(requires) do
        local found = false
        for _, cand in ipairs(candidates) do
            if lib.matchesTag(cand.recordId, tag) then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

---Find all nearby contexts within range, matching record ids OR FlexTag tags.
---@param registries Registries The data registries
---@param maxRange number Maximum search range
---@return table<string, ProximityResult> Map of ID to proximity result
local function findcurrentContexts(registries, maxRange)
    maxRange = maxRange or 200

    local candidates = gatherNearby(maxRange)
    local results = {}

    for id, def in pairs(registries.contexts) do
        if def.trigger == 'gaze' then
            -- handled by findGazeContext (crosshair raycast, not proximity)
        elseif def.trigger == 'condition' then
            -- predicate contexts have no world object (e.g. shovel near water)
            if def.condition and conditions.check(def.condition) then
                results[id] = {
                    context = def,
                    object = nil,
                    distance = CONDITION_DISTANCE,
                }
            end
        else
            -- Both proximity and activate contexts show a nearby card. For "activate"
            -- contexts the card is info-only (no [F] action; the station is opened by
            -- activating the object — see the global activation handler).
            local range = def.activationRange or 150

            -- closest candidate that matches the context (id, tag, or pattern).
            -- `targets:"corpse"` contexts match only DEAD-actor candidates, via
            -- the field-dressing registry (or explicit recordIds); everything
            -- else matches only non-corpse candidates.
            local wantCorpse = def.targets == 'corpse'
            local best = nil
            for _, cand in ipairs(candidates) do
                if (cand.corpse or false) == wantCorpse and cand.distance <= range then
                    local matches
                    if wantCorpse then
                        matches = (GRegistries.dressing and GRegistries.dressing[cand.recordId:lower()] ~= nil)
                            or matchesDef(cand.recordId, def)
                    else
                        matches = matchesDef(cand.recordId, def)
                    end
                    if matches and (not best or cand.distance < best.distance) then
                        best = cand
                    end
                end
            end

            -- gate on any extra required tags nearby (e.g. cooking_pot requires "fire")
            if best and (not def.requires or hasRequired(candidates, def.requires)) then
                results[id] = {
                    context = def,
                    object = best.object,
                    distance = best.distance,
                }
            end
        end
    end

    return results
end

---One crosshair raycast per poll, serving BOTH gaze contexts (trees, rocks —
---statics never appear in nearby.*) and stacked-station disambiguation
---(looking at the crafting cloth on the crafting table picks the cloth).
---@param registries Registries
---@return { object: any, recordId: string, distance: number }? what the crosshair rests on
local function crosshairTarget(registries)
    -- longest range any context cares about (one raycast serves all)
    local maxRange = 200
    for _, def in pairs(registries.contexts) do
        maxRange = math.max(maxRange, def.activationRange or 0)
    end

    local from = camera.getPosition()
    local dir = camera.viewportToWorldVector(util.vector2(0.5, 0.5))
    local ok, res = pcall(function()
        return nearby.castRay(from, from + dir * maxRange, { ignore = self })
    end)
    if not ok or not res or not res.hitObject then return nil end

    return {
        object = res.hitObject,
        recordId = res.hitObject.recordId,
        distance = (res.hitPos - self.position):length(),
    }
end

---Match the crosshair hit against `trigger:"gaze"` contexts.
---@param registries Registries
---@param hit { object: any, recordId: string, distance: number }?
---@return ProximityResult?
local function findGazeContext(registries, hit)
    if not hit then return nil end
    for _, def in pairs(registries.contexts) do
        if def.trigger == 'gaze' and hit.distance <= (def.activationRange or 200)
            and matchesDef(hit.recordId, def) then
            return {
                context = def,
                object = hit.object,
                distance = hit.distance,
            }
        end
    end
    return nil
end

---When two stations sit next to each other (crafting cloth ON the crafting
---table), the crosshair chooses between them: if the looked-at object matches
---one of the proximity/activate contexts that already qualified this poll
---(range + `requires` gating), that context wins over plain closest-distance.
---Deterministic on overlap: exact-object matches beat def-only matches, then
---context id order.
---@param currentContexts table<string, ProximityResult>
---@param hit { object: any, recordId: string, distance: number }?
---@return ProximityResult?
local function lookedAtContext(currentContexts, hit)
    if not hit then return nil end
    local best, bestExact, bestId = nil, false, nil
    for id, result in pairs(currentContexts) do
        local def = result.context
        if def.trigger ~= 'condition'
            and hit.distance <= (def.activationRange or 150)
            and matchesDef(hit.recordId, def) then
            local exact = result.object and result.object.id == hit.object.id
            if not best or (exact and not bestExact)
                or (exact == bestExact and id < bestId) then
                best, bestExact, bestId = result, exact, id
            end
        end
    end
    if not best then return nil end
    -- card the OBJECT under the crosshair (it may not be the context's closest
    -- candidate — e.g. the farther of two crafting tables)
    return { context = best.context, object = hit.object, distance = hit.distance }
end

--- Same logical target? Each poll builds fresh result tables, so identity
--- comparison would see a "change" every tick (rebuilding the overlay and
--- resetting hold-to-forage progress). Compare the context definition and the
--- matched world object instead.
---@param a ProximityResult|nil
---@param b ProximityResult|nil
---@return boolean
local function isSameResult(a, b)
    if a == nil or b == nil then return a == b end
    if a.context ~= b.context then return false end
    local aId = a.object and a.object.id or nil
    local bId = b.object and b.object.id or nil
    return aId == bId
end

---Update nearby contexts and overlay actions
local function updatecurrentContexts()
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return
    end

    -- Find all nearby shaped crafting contexts
    local previousContext = this.currentContext
    local currentContexts = findcurrentContexts(GRegistries, 200)

    -- get the closest context
    local closestContext = nil
    local closestDistance = math.huge
    for _, result in pairs(currentContexts) do
        if result.distance < closestDistance then
            closestDistance = result.distance
            closestContext = result
        end
    end

    -- the crosshair is the stronger signal than distance: a gaze context
    -- (tree, rock) wins over everything; failing that, LOOKING at one of the
    -- qualified nearby stations picks it (stacked stations: cloth on table).
    -- Looking at neither keeps the closest-wins fallback, so the card doesn't
    -- vanish while glancing around between two stations.
    local hit = crosshairTarget(GRegistries)
    local gaze = findGazeContext(GRegistries, hit)
    if gaze then
        closestContext = gaze
    else
        local looked = lookedAtContext(currentContexts, hit)
        if looked then closestContext = looked end
    end

    if not closestContext then
        this.currentContext = nil
        if previousContext ~= nil then updateOverlay() end
        return
    end

    this.currentContext = closestContext
    -- stations with a running/finished process show a LIVE card (progress bar,
    -- remaining time) — refresh it every poll, not only on target change.
    -- Safe: busy/done cards carry no hold action, so no hold progress resets.
    local live = closestContext.object
        and processState.forStation(closestContext.object.id) ~= nil
    if live or not isSameResult(previousContext, closestContext) then updateOverlay() end
end

---Main update function called every frame
function this.onUpdate(dt)
    -- Periodically update nearby contexts
    this.timeSinceLastUpdate = this.timeSinceLastUpdate + dt
    if this.timeSinceLastUpdate >= updateInterval then
        updatecurrentContexts()
        this.timeSinceLastUpdate = 0
    end
end

return this
