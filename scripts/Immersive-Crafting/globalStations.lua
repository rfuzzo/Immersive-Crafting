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

    Charge styles: `loadable` stations ABSORB a dropped item into a stored
    charge (charcoal pit — the mound swallows it); `openCharge` stations
    (kiln) never absorb — items are placed VISIBLY in the mesh and the ignite
    path consumes them from the world (handlers/processing.lua +
    globalProcessing.onIgnite `consume`).
]]

local world = require('openmw.world')
local types = require('openmw.types')
local util = require('openmw.util')

local io = require('scripts.Immersive-Crafting.io')
local log = require('scripts.Immersive-Crafting.log')

local STATIONS_PATH = 'data/Immersive-Crafting/stations/stations.json'

local this = {}

local byItem = nil ---@type table<string, string>? item record id -> activator record id
local byActivator = nil ---@type table<string, string>? activator record id -> item record id
local fxByActivator = nil ---@type table<string, { record: string, offset: number[]? }>? activator record id -> process FX
local loadable = nil ---@type table<string, boolean>? activator record id -> accepts a dropped-in charge (UI-less kiln/charcoal pit)
local alignToGround = nil ---@type table<string, boolean>? item record id -> tilt the placed activator to the terrain normal (mound-like meshes)

local function maps()
    if byItem then return byItem, byActivator end
    byItem, byActivator, fxByActivator, loadable, alignToGround = {}, {}, {}, {}, {}
    for _, entry in ipairs(io.loadJsonFile(STATIONS_PATH) or {}) do
        if entry.item and entry.activator then
            byItem[entry.item:lower()] = entry.activator
            byActivator[entry.activator:lower()] = entry.item
            if entry.processFx and entry.processFx.record then
                fxByActivator[entry.activator:lower()] = entry.processFx
            end
            if entry.loadable then
                loadable[entry.activator:lower()] = true
            end
            if entry.alignToGround then
                alignToGround[entry.item:lower()] = true
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

--- Does this placed station accept a dropped-in charge (UI-less loading)?
---@param recordId string activator record id
---@return boolean
function this.isLoadable(recordId)
    maps()
    return loadable[recordId] or false
end

--- Swap one unit of a station item for its activator at position/rotation.
---@param object any the station item
---@param activatorId string
---@param pos any placement position
---@param rot any placement rotation (util.transform)
local function placeActivator(object, activatorId, pos, rot)
    local cell = object.cell
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

-- align-to-ground swaps wait for the player to raycast the terrain (raycasts
-- are local-script-only); keyed by the item object's id
local pendingAlign = {} ---@type table<string, any>

--- Engine handler: swap station items lying in the world for their activator.
--- Returns true when the object IS a station item (handled here — even if the
--- swap failed, it must not be treated as station-charge input).
--- `alignToGround` stations don't swap immediately: the player probes the
--- terrain under the drop point first (ImmersiveCrafting_ProbeGround) and the
--- swap completes in onGroundProbe, tilted to the surface normal.
---@param object any object that just became active
---@return boolean handled
function this.onObjectActive(object)
    if object.type ~= types.Miscellaneous then return false end
    local items = maps()
    local activatorId = items[object.recordId]
    if not activatorId then return false end

    if alignToGround[object.recordId] and world.players[1] then
        pendingAlign[object.id] = object
        world.players[1]:sendEvent('ImmersiveCrafting_ProbeGround', {
            token = object.id,
            object = object,
            position = object.position,
        })
        return true
    end

    placeActivator(object, activatorId, object.position, object.rotation)
    return true
end

--- Event (from the player): terrain probe result — finish an align-to-ground
--- swap. Tilts the activator's up-axis onto the surface normal (keeping the
--- item's yaw) and drops it onto the hit point; no hit -> plain swap.
---@param data { token: string, normal: any?, position: any? }
function this.onGroundProbe(data)
    if not (data and data.token) then return end
    local object = pendingAlign[data.token]
    pendingAlign[data.token] = nil
    if not (object and object:isValid() and object.count and object.count > 0) then return end
    local items = maps()
    local activatorId = items[object.recordId]
    if not activatorId then return end

    local pos = data.position or object.position
    local rot = object.rotation
    if data.normal then
        local up = util.vector3(0, 0, 1)
        local n = data.normal:normalize()
        local axis = up:cross(n)
        local angle = math.acos(util.clamp(up:dot(n), -1, 1))
        if axis:length() > 1e-4 and angle > 1e-3 then
            rot = util.transform.rotate(angle, axis:normalize()) * rot
        end
    end
    placeActivator(object, activatorId, pos, rot)
end

--- Event: pack a placed station up. BUILT stations (constructions) dismantle
--- into their salvage components — you don't fold a kiln into a backpack;
--- item-swap stations return their item form.
---@param data { actor: any, station: any }
function this.onPack(data)
    if not (data and data.actor and data.station) then return end
    local station = data.station
    if not station:isValid() then return end

    local globalBuilding = require('scripts.Immersive-Crafting.globalBuilding')
    local salvage, buildLabel = globalBuilding.salvageFor(station.recordId)

    local _, activators = maps()
    local itemId = activators[station.recordId]
    if not salvage and not itemId then return end

    -- a running/finished timed process owns the station — collect it first
    if saveData and saveData.processes and saveData.processes[station.id] then
        data.actor:sendEvent('ImmersiveCrafting_Notify',
            { text = 'This station is busy — collect its work first' })
        return
    end

    if salvage then
        -- dismantle: grant the salvage components (partial — mortar doesn't
        -- come off bricks cleanly), remove the structure
        local parts = {}
        for _, entry in ipairs(salvage) do
            local ok, err = pcall(function()
                local created = world.createObject(entry.id, entry.count or 1)
                created:moveInto(types.Actor.inventory(data.actor))
            end)
            if ok then
                parts[#parts + 1] = ('%dx %s'):format(entry.count or 1, entry.id)
            else
                log.error(('stations: failed to salvage "%s": %s'):format(entry.id, tostring(err)))
            end
        end
        station:remove()
        data.actor:sendEvent('ImmersiveCrafting_Notify', {
            text = ('Dismantled %s%s'):format(buildLabel or station.recordId,
                #parts > 0 and (' — salvaged ' .. table.concat(parts, ', ')) or ''),
        })
        log.info(('stations: dismantled %s'):format(station.recordId))
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
