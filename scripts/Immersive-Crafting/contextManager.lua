local log = require('scripts.Immersive-Crafting.log')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local lib = require('scripts.Immersive-Crafting.lib')
local conditions = require('scripts.Immersive-Crafting.conditions')
local processState = require('scripts.Immersive-Crafting.processState')

local nearby = require('openmw.nearby')
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

            -- closest candidate that matches the context (id, tag, or pattern)
            local best = nil
            for _, cand in ipairs(candidates) do
                if cand.distance <= range and matchesDef(cand.recordId, def) then
                    if not best or cand.distance < best.distance then
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

---Find the gaze context, if any: a single crosshair raycast against the world,
---matched against `trigger:"gaze"` contexts (trees, rocks — statics never appear
---in the nearby.* lists, so proximity cannot find them).
---@param registries Registries
---@return ProximityResult?
local function findGazeContext(registries)
    -- longest gaze range among gaze contexts (one raycast serves all)
    local maxRange = 0
    for _, def in pairs(registries.contexts) do
        if def.trigger == 'gaze' then
            maxRange = math.max(maxRange, def.activationRange or 200)
        end
    end
    if maxRange == 0 then return nil end -- no gaze contexts defined

    local from = camera.getPosition()
    local dir = camera.viewportToWorldVector(util.vector2(0.5, 0.5))
    local ok, res = pcall(function()
        return nearby.castRay(from, from + dir * maxRange, { ignore = self })
    end)
    if not ok or not res or not res.hitObject then return nil end

    local recordId = res.hitObject.recordId
    local distance = (res.hitPos - self.position):length()

    for _, def in pairs(registries.contexts) do
        if def.trigger == 'gaze' and distance <= (def.activationRange or 200)
            and matchesDef(recordId, def) then
            return {
                context = def,
                object = res.hitObject,
                distance = distance,
            }
        end
    end
    return nil
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

    -- the gaze target wins over everything: aiming at it is the stronger signal
    local gaze = findGazeContext(GRegistries)
    if gaze then closestContext = gaze end

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
