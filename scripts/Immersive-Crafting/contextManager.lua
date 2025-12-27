local log = require('scripts.Immersive-Crafting.log')
local lib = require('scripts.Immersive-Crafting.lib')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')

local this = {}

local updateInterval = 0.25 -- Check for nearby stations every 0.25 seconds

---@type ProximityResult|nil
this.nearbyStation = nil
---@type number
this.timeSinceLastUpdate = 0


--- Resolve an action definition, whether by ID or direct reference
---@param actionDef CAction|string
---@return CAction
local function resolveAction(actionDef)
    -- if actionDef is a string, look up the action definition
    if type(actionDef) == 'string' then
        return GRegistries.actions[actionDef]
    else
        return actionDef
    end
end

---Update overlay actions based on nearby stations
local function updateOverlay()
    log.trace('Updating overlay actions for nearby stations')

    -- Clear existing actions
    overlay.clearAllActions()

    local result = this.nearbyStation
    if not result then return end

    local station = result.station
    local stationId = station.id

    for _, action in ipairs(station.actions or {}) do
        overlay.registerAction(stationId, resolveAction(action))
    end
end

---Update nearby stations and overlay actions
local function updateNearbyStations()
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return
    end

    -- Find all nearby shaped crafting stations
    local previousStation = this.nearbyStation
    local nearbyStations = lib.findNearbyStations(GRegistries, 200)

    -- get the closest station
    local closestStation = nil
    local closestDistance = math.huge
    for stationId, result in pairs(nearbyStations) do
        if result.distance < closestDistance then
            closestDistance = result.distance
            closestStation = result
        end
    end

    if not closestStation then
        this.nearbyStation = nil
        if previousStation ~= nil then updateOverlay() end
        return
    end

    this.nearbyStation = closestStation
    if previousStation ~= this.nearbyStation then updateOverlay() end
end

---Main update function called every frame
function this.onUpdate(dt)
    this.timeSinceLastUpdate = this.timeSinceLastUpdate + dt

    -- Periodically update nearby stations
    if this.timeSinceLastUpdate >= updateInterval then
        updateNearbyStations()
        this.timeSinceLastUpdate = 0
    end
end

return this
