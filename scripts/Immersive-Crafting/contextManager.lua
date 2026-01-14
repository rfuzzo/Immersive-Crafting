local log = require('scripts.Immersive-Crafting.log')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')

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
    log.trace('Updating overlay actions for nearby context')

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

---Find all nearby contexts or containers within range
---@param registries Registries The data registries
---@param maxRange number Maximum search range
---@return table<string, ProximityResult> Map of ID to proximity result
local function findcurrentContexts(registries, maxRange)
    maxRange = maxRange or 200

    local results = {}
    local playerPos = self.position

    -- Scan all nearby objects
    for _, obj in ipairs(nearby.activators) do
        local recordId = obj.recordId
        local distance = (obj.position - playerPos):length()

        if distance <= maxRange then
            -- Check if this object is a registered context
            for id, def in pairs(registries.contexts) do
                for _, rid in ipairs(def.recordIds) do
                    -- Case-insensitive comparison
                    if rid:lower() == recordId:lower() then
                        local range = def.activationRange or 150

                        if distance <= range then
                            -- -- Found a match
                            results[id] = {
                                context = def,
                                object = obj,
                                distance = distance,
                            }
                        end
                    end
                end
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
