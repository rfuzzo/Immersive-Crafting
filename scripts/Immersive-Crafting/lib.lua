local nearby = require('openmw.nearby')
local core = require('openmw.core')
local self = require('openmw.self')


local this = {}

function this.len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---@class ProximityResult
---@field station CStation The station definition
---@field object GameObject The actual game object
---@field distance number Distance to the object

---Find all nearby stations within range
---@param registries Registries The data registries
---@param maxRange number Maximum search range
---@return table<string, ProximityResult> Map of station ID to proximity result
function this.findNearbyStations(registries, maxRange)
    maxRange = maxRange or 200

    local results = {}
    local playerPos = self.position

    -- Scan all nearby objects
    for _, obj in ipairs(nearby.activators) do
        local recordId = obj.recordId
        local distance = (obj.position - playerPos):length()

        if distance <= maxRange then
            -- Check if this object is a registered station
            for stationId, stationDef in pairs(registries.stations) do
                if stationDef.recordIds then
                    for _, id in ipairs(stationDef.recordIds) do
                        -- Case-insensitive comparison
                        if id:lower() == recordId:lower() then
                            local stationRange = stationDef.activationRange or 150

                            if distance <= stationRange then
                                -- -- Found a matching station
                                -- log.info('Found nearby station: ' ..
                                --     stationId .. ' (' .. recordId .. ') at distance ' .. tostring(distance))

                                results[stationId] = {
                                    station = stationDef,
                                    object = obj,
                                    distance = distance,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Also check containers and other object types if needed
    -- This is extensible for different station types

    return results
end

return this
