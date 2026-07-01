local log = require('scripts.Immersive-Crafting.log')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local lib = require('scripts.Immersive-Crafting.lib')

local nearby = require('openmw.nearby')
local self = require('openmw.self')

local updateInterval = 0.25 -- Check for nearby context every 0.25 seconds

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
        overlay.registerAction(context, resolveAction(action))
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

---Find all nearby contexts within range, matching record ids OR Tagger tags.
---@param registries Registries The data registries
---@param maxRange number Maximum search range
---@return table<string, ProximityResult> Map of ID to proximity result
local function findcurrentContexts(registries, maxRange)
    maxRange = maxRange or 200

    local candidates = gatherNearby(maxRange)
    local results = {}

    for id, def in pairs(registries.contexts) do
        -- Only proximity-triggered contexts appear in the nearby overlay.
        -- "activate" contexts are opened by activating the object (handled elsewhere).
        if def.trigger ~= 'activate' then
            local range = def.activationRange or 150

            -- closest candidate that matches any of the context's recordIds (id or tag)
            local best = nil
            for _, cand in ipairs(candidates) do
                if cand.distance <= range then
                    for _, rid in ipairs(def.recordIds or {}) do
                        if lib.matchesTag(cand.recordId, rid) then
                            if not best or cand.distance < best.distance then
                                best = cand
                            end
                            break
                        end
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

    if not closestContext then
        this.currentContext = nil
        if previousContext ~= nil then updateOverlay() end
        return
    end

    this.currentContext = closestContext
    if previousContext ~= this.currentContext then updateOverlay() end
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
