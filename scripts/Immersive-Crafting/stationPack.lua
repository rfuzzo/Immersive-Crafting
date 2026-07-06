--[[
    Pack-up for placed IC stations (drop-swapped activators) — PLAYER side.

    Any station from data/Immersive-Crafting/stations/stations.json can be
    packed back into its item form by holding F on its card. Shared by the
    handlers whose contexts sit on placed stations (processing, shaping);
    globalStations.onPack does the actual swap (and refuses busy stations).
]]

local core = require('openmw.core')
local omwSelf = require('openmw.self')

local io = require('scripts.Immersive-Crafting.io')

local this = {}

this.HOLD = 1.5 -- seconds of holding F on the card

local packable = nil ---@type table<string, boolean>? activator record id -> packable

---@param object any
---@return boolean
function this.isPackable(object)
    if not object then return false end
    if not packable then
        packable = {}
        local list = io.loadJsonFile('data/Immersive-Crafting/stations/stations.json') or {}
        for _, entry in ipairs(list) do
            if entry.activator then packable[entry.activator:lower()] = true end
        end
    end
    return packable[object.recordId] or false
end

--- Hold-F card action for a placed station (nil when not packable).
---@param object any
---@return table? action ViewModel action
function this.action(object)
    if not this.isPackable(object) then return nil end
    return { id = 'pack', label = 'Pack up', enabled = true, hold = this.HOLD }
end

--- Ask the global side to swap the placed activator back into its item.
---@param object any
function this.pack(object)
    core.sendGlobalEvent('ImmersiveCrafting_PackStation', {
        actor = omwSelf.object,
        station = object,
    })
end

return this
