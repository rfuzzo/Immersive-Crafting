--[[
    Timed processes — PLAYER-side read-only mirror of the global run registry.

    Populated by `ImmersiveCrafting_ProcessSync` snapshots. Used by the
    processing handler to render the station card ("working / ready") and by
    the crafting window to refuse opening a busy station.
]]

local this = {}

local byStation = {} ---@type table<string, { recipeId: string, label: string, startedAt: number?, readyAt: number?, done: boolean }>
local chargeByStation = {} ---@type table<string, { id: string, count: integer, name: string? }[]> dropped-in charges awaiting ignition

--- Apply a full snapshot from the global script.
---@param snapshot table<string, table>?
---@param charges table<string, table>?
function this.apply(snapshot, charges)
    byStation = snapshot or {}
    chargeByStation = charges or {}
end

--- The charge loaded into a station (nil/empty = nothing dropped in yet).
---@param stationId string
---@return { id: string, count: integer, name: string? }[]?
function this.chargeFor(stationId)
    return chargeByStation[stationId]
end

--- Active run at a station (nil = idle).
---@param stationId string
---@return table? state
function this.forStation(stationId)
    return byStation[stationId]
end

return this
