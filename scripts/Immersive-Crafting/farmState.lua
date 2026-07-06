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
local sownByPlanter = {} ---@type table<string, { seedId: string, cropId: string }> seeds dropped into planters, awaiting the hold-F plant
local memoryByPlanter = {} ---@type table<string, string> planter object id -> crop id it last grew

--- Apply a full snapshot from the global script.
---@param snapshot table<string, table>?
---@param sown table<string, table>?
---@param memory table<string, string>?
function this.apply(snapshot, sown, memory)
    byObject = snapshot or {}
    sownByPlanter = sown or {}
    memoryByPlanter = memory or {}
    byPlanter = {}
    for objId, e in pairs(byObject) do
        if e.planterId then byPlanter[e.planterId] = objId end
    end
end

--- The seed sown (dropped) into a planter, waiting to be planted.
---@param planterId string
---@return { seedId: string, cropId: string }?
function this.sownFor(planterId)
    return sownByPlanter[planterId]
end

--- The crop this planter last grew (for hold-F replanting).
---@param planterId string
---@return string? cropId
function this.memoryFor(planterId)
    return memoryByPlanter[planterId]
end

--- Crop state growing on a given planter (nil = planter is empty).
---@param planterId string
---@return table? state
function this.forPlanter(planterId)
    local objId = byPlanter[planterId]
    return objId and byObject[objId] or nil
end

return this
