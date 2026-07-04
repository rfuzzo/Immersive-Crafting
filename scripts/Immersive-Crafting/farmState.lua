--[[
    Farming — PLAYER-side read-only mirror of the global crop registry.

    Populated by `ImmersiveCrafting_CropSync` events (full snapshots sent by the
    global script on every change and on request after load). Used by the
    farming handler to render the planter's contextual card ("growing / ripe /
    empty") without any global round-trips.
]]

local this = {}

local byObject = {} ---@type table<string, { cropId: string, stage: integer, readyAt: number?, planterId: string? }>
local byPlanter = {} ---@type table<string, string> planter object id -> crop object id

--- Apply a full snapshot from the global script.
---@param snapshot table<string, table>?
function this.apply(snapshot)
    byObject = snapshot or {}
    byPlanter = {}
    for objId, e in pairs(byObject) do
        if e.planterId then byPlanter[e.planterId] = objId end
    end
end

--- Crop state growing on a given planter (nil = planter is empty).
---@param planterId string
---@return table? state
function this.forPlanter(planterId)
    local objId = byPlanter[planterId]
    return objId and byObject[objId] or nil
end

return this
