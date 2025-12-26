local log = require('scripts.Immersive-Crafting.log')
local lib = require('scripts.Immersive-Crafting.lib')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')

local input = require('openmw.input')
local ui = require('openmw.ui')

local this = {}

local updateInterval = 0.25 -- Check for nearby stations every 0.25 seconds

---@type ProximityResult|nil
this.nearbyStation = nil
---@type number
this.timeSinceLastUpdate = 0

-- #region Shaped Crafting Handling

---Open the crafting interface for a station
---@param station StationDef
---@param stationObject GameObject
local function openCraftingInterface(station, stationObject)
    -- TODO: Create and show the actual crafting grid UI
    -- For now, just show a message
    ui.showMessage('Opening ' .. station.gridSize .. ' crafting interface')

    -- This will eventually create a modal UI with the crafting grid
    -- based on station.uiTemplate
end

--- Update overlay actions for shaped crafting stations
---@param result ProximityResult
local function updateOverlayShapedCrafting(result)

    local station = result.station
    local stationId = station.id

    -- Register a "Craft" action for shaped crafting stations
    overlay.registerAction(stationId, {
        id = "craft_" .. stationId,
        label = "Craft",
        key = input.KEY.F,
        onKeyRelease = function()
            log.info('Opening crafting UI for ' .. stationId)
            openCraftingInterface(station, result.object)
        end
    })

end

-- #endregion

---Update overlay actions based on nearby stations
local function updateOverlay()
    log.trace('Updating overlay actions for nearby stations')

    -- Clear existing actions
    overlay.clearAllActions()

    local result = this.nearbyStation
    if not result then return end

    local station = result.station

    -- shaped crafting stations
    if station.mode == "shaped" then
        log.trace('Updating overlay for shaped crafting station: ' .. station.id)
        updateOverlayShapedCrafting(result)
    end

    -- TODO : Handle other station modes (contextual, process)
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
