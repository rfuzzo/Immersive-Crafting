--[[
    Station drop-swap — GLOBAL side (required by init.lua).

    Craftable stations are Misc ITEMS in the inventory (so they can be carried
    and crafted), but a placed station must be an ACTIVATOR — activating a
    misc item just picks it up, an activator opens the station (init.lua's
    activation handler). The bridge, driven by
    data/Immersive-Crafting/stations/stations.json ({ item, activator } pairs):

    - onObjectActive: a station ITEM lying in a cell (just dropped, or already
      placed before this feature) is swapped in place for its ACTIVATOR record
      (same position/rotation; one item off the stack). If the activator
      record does not exist in the load order (plugin not built yet), the
      swap logs and leaves the item alone.
    - onPack (ImmersiveCrafting_PackStation): the reverse — remove the placed
      activator and give the item back. Refused while a timed run occupies
      the station. The player triggers it by holding F on the station card
      (via stationPack.lua).

    A station entry may also declare `processFx` ({ record, offset }): an
    object globalProcessing spawns at the station while a timed run burns
    (the kiln's fire in the opening) and removes when it finishes.
]]

local world = require('openmw.world')
local types = require('openmw.types')

local io = require('scripts.Immersive-Crafting.io')
local log = require('scripts.Immersive-Crafting.log')

local STATIONS_PATH = 'data/Immersive-Crafting/stations/stations.json'

local this = {}

local byItem = nil ---@type table<string, string>? item record id -> activator record id
local byActivator = nil ---@type table<string, string>? activator record id -> item record id
local fxByActivator = nil ---@type table<string, { record: string, offset: number[]? }>? activator record id -> process FX

local function maps()
    if byItem then return byItem, byActivator end
    byItem, byActivator, fxByActivator = {}, {}, {}
    for _, entry in ipairs(io.loadJsonFile(STATIONS_PATH) or {}) do
        if entry.item and entry.activator then
            byItem[entry.item:lower()] = entry.activator
            byActivator[entry.activator:lower()] = entry.item
            if entry.processFx and entry.processFx.record then
                fxByActivator[entry.activator:lower()] = entry.processFx
            end
        end
    end
    log.info(('stations: %d drop-swap pairs loaded'):format((function()
        local n = 0
        for _ in pairs(byItem) do n = n + 1 end
        return n
    end)()))
    return byItem, byActivator
end

--- The station's `processFx` declaration (spawned while a timed run burns).
---@param recordId string activator record id
---@return { record: string, offset: number[]? }?
function this.processFxFor(recordId)
    maps()
    return fxByActivator[recordId]
end

--- Engine handler: swap station items lying in the world for their activator.
---@param object any object that just became active
function this.onObjectActive(object)
    if object.type ~= types.Miscellaneous then return end
    local items = maps()
    local activatorId = items[object.recordId]
    if not activatorId then return end

    local cell, pos, rot = object.cell, object.position, object.rotation
    local ok, err = pcall(function()
        local created = world.createObject(activatorId, 1)
        created:teleport(cell, pos, { rotation = rot })
    end)
    if not ok then
        -- most likely: the activator record isn't in the load order yet
        log.warn(('stations: cannot place "%s" (%s) — item left as-is'):format(
            activatorId, tostring(err)))
        return
    end
    object:remove(1)
    log.info(('stations: placed %s'):format(activatorId))
end

--- Event: pack a placed station back into its item form.
---@param data { actor: any, station: any }
function this.onPack(data)
    if not (data and data.actor and data.station) then return end
    local station = data.station
    if not station:isValid() then return end

    local _, activators = maps()
    local itemId = activators[station.recordId]
    if not itemId then return end

    -- a running/finished timed process owns the station — collect it first
    if saveData and saveData.processes and saveData.processes[station.id] then
        data.actor:sendEvent('ImmersiveCrafting_Notify',
            { text = 'This station is busy — collect its work first' })
        return
    end

    local ok, err = pcall(function()
        local created = world.createObject(itemId, 1)
        created:moveInto(types.Actor.inventory(data.actor))
    end)
    if not ok then
        log.error(('stations: failed to grant "%s": %s'):format(itemId, tostring(err)))
        return
    end
    local name = itemId
    local okRec, rec = pcall(function() return station.type.record(station.recordId) end)
    if okRec and rec and rec.name and rec.name ~= '' then name = rec.name end
    station:remove()
    data.actor:sendEvent('ImmersiveCrafting_Notify', { text = ('Packed up %s'):format(name) })
    log.info(('stations: packed %s -> %s'):format(station.recordId, itemId))
end

return this
