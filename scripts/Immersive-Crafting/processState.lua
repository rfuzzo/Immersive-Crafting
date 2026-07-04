--[[
    Timed processes — PLAYER-side read-only mirror of the global run registry.

    Populated by `ImmersiveCrafting_ProcessSync` snapshots. Used by the
    processing handler to render the station card ("working / ready") and by
    the crafting window to refuse opening a busy station.
]]

local this = {}

local byStation = {} ---@type table<string, { recipeId: string, label: string, readyAt: number?, done: boolean }>

--- Apply a full snapshot from the global script.
---@param snapshot table<string, table>?
function this.apply(snapshot)
    byStation = snapshot or {}
end

--- Active run at a station (nil = idle).
---@param stationId string
---@return table? state
function this.forStation(stationId)
    return byStation[stationId]
end

return this
