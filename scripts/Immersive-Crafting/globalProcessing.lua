--[[
    Timed processes — GLOBAL side (required by init.lua; shares its script
    environment, incl. the `saveData` global).

    The station-side twin of globalFarming: a process recipe with a `duration`
    is not crafted instantly — starting it consumes the inputs up front,
    registers the run in `saveData.processes` (one per station object), and a
    persisted GAME-time timer marks it done (`3600` = one game hour; time
    passes while waiting/sleeping and timers survive save/load natively).

    Flow:
    - `ImmersiveCrafting_StartProcess` (from the crafting window): verify +
      consume the inputs from the actor's inventory, register, schedule.
    - Timer fires → entry.done; the player is notified and the station card
      (processState mirror) flips to "ready".
    - Activating the station while it runs → remaining-time message; while
      done → collect: grant the output, clear the entry. init.lua calls
      `onStationActivated` before its normal open-station handling, and
      `ImmersiveCrafting_CollectProcess` covers proximity stations.
]]

local world = require('openmw.world')
local types = require('openmw.types')
local core = require('openmw.core')
local async = require('openmw.async')
local util = require('openmw.util')

local log = require('scripts.Immersive-Crafting.log')
local globalLiquids = require('scripts.Immersive-Crafting.globalLiquids')
local globalStations = require('scripts.Immersive-Crafting.globalStations')

local this = {}

-- ── registry / helpers ───────────────────────────────────────────────────────

--- Persistent process registry (one active run per station object).
local function processes()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.processes = saveData.processes or {}
    return saveData.processes
end

local function notify(actor, text)
    if actor then actor:sendEvent('ImmersiveCrafting_Notify', { text = text }) end
end

--- "~N min" / "~N h" of remaining GAME time.
---@param seconds number
---@return string
local function fmtDuration(seconds)
    if seconds >= 3600 then
        return ('~%d h'):format(math.ceil(seconds / 3600))
    end
    return ('~%d min'):format(math.max(1, math.ceil(seconds / 60)))
end

--- Push a plain snapshot of all runs to the player (for the station card).
local function syncPlayer()
    local player = world.players[1]
    if not player then return end
    local snapshot = {}
    for stationId, e in pairs(processes()) do
        snapshot[stationId] = {
            recipeId = e.recipeId,
            label = e.label,
            startedAt = e.startedAt,
            readyAt = e.readyAt,
            done = e.done or false,
        }
    end
    player:sendEvent('ImmersiveCrafting_ProcessSync', { processes = snapshot })
end

-- ── process FX (the kiln's fire while it burns) ─────────────────────────────

--- Spawn the station's `processFx` object (stations.json), offset in the
--- station's LOCAL space (rotates with it). Returns nil when the station
--- declares none or the record is missing from the load order.
---@param station any
---@return any? spawned object
local function igniteFx(station)
    local fx = globalStations.processFxFor(station.recordId)
    if not fx then return nil end
    local off = fx.offset or {}
    local offset = util.vector3(off[1] or 0, off[2] or 0, off[3] or 0)
    local ok, created = pcall(function()
        local obj = world.createObject(fx.record, 1)
        obj:teleport(station.cell, station.position + station.rotation:apply(offset),
            { rotation = station.rotation })
        return obj
    end)
    if not ok then
        log.warn(('process: cannot light fx "%s": %s'):format(tostring(fx.record), tostring(created)))
        return nil
    end
    log.info(('process: lit %s at %s'):format(fx.record, tostring(station.recordId)))
    return created
end

--- Remove a run's FX object (fire goes out when the work is done).
---@param e table process entry
local function extinguishFx(e)
    if not (e and e.fx) then return end
    pcall(function()
        if e.fx:isValid() then e.fx:remove() end
    end)
    e.fx = nil
end

-- ── completion timer (persisted; game time) ─────────────────────────────────

local onProcessDone = async:registerTimerCallback('IC_processDone', function(stationId)
    local e = processes()[stationId]
    if not e then return end
    e.done = true
    extinguishFx(e) -- the fire has burnt down: visually signals "ready"
    log.info(('process: "%s" finished at station %s'):format(tostring(e.label), tostring(stationId)))
    notify(world.players[1], (e.label or 'A process') .. ' is ready')
    syncPlayer()
end)

-- ── start ────────────────────────────────────────────────────────────────────

--- Event: start a timed process at a station. Inputs are consumed UP FRONT —
--- including `returned` items (the mold sits in the kiln for the duration);
--- those are granted back to the collector along with the output.
---@param data { actor: any, station: any, recipeId: string, label: string, consume: { id: string, count: integer }[], returned: { id: string, count: integer }[]?, output: { id: string, count: integer }, duration: number }
function this.onStart(data)
    if not (data and data.actor and data.station and data.output and data.duration) then return end
    local stationId = data.station.id

    if processes()[stationId] then
        notify(data.actor, 'This station is already working')
        return
    end

    -- verify availability first so we never partially consume
    local inv = types.Actor.inventory(data.actor)
    for _, entry in ipairs(data.consume or {}) do
        local have = 0
        for _, item in ipairs(inv:getAll()) do
            if item.recordId == entry.id then have = have + (item.count or 1) end
        end
        if have < (entry.count or 1) then
            notify(data.actor, 'Not enough materials')
            return
        end
    end
    for _, entry in ipairs(data.consume or {}) do
        local needed = entry.count or 1
        local removed = 0
        for _, item in ipairs(inv:getAll()) do
            if needed <= 0 then break end
            if item.recordId == entry.id then
                local take = math.min(needed, item.count or 1)
                local ok = pcall(function() item:remove(take) end)
                if ok then
                    needed = needed - take
                    removed = removed + take
                end
            end
        end
        -- SD water interop: the water is poured in NOW, so the empty container
        -- comes back immediately (it does not sit in the station like a mold)
        local orig = removed > 0 and globalLiquids.emptyContainerFor(entry.id)
        if orig then
            local ok, err = pcall(function()
                local created = world.createObject(orig, removed)
                created:moveInto(inv)
            end)
            if not ok then
                log.error(('process: failed to return container "%s": %s'):format(tostring(orig), tostring(err)))
            end
        end
    end

    processes()[stationId] = {
        stationId = stationId,
        recipeId = data.recipeId,
        label = data.label or data.recipeId,
        output = data.output,
        returned = data.returned, -- items held by the station, given back on collect
        startedAt = core.getGameTime(), -- for the station card's progress bar
        readyAt = core.getGameTime() + data.duration,
        done = false,
        fx = igniteFx(data.station), -- e.g. the kiln's fire (removed when done)
    }
    async:newGameTimer(data.duration, onProcessDone, stationId)

    log.info(('process: started "%s" at station %s (%ds)'):format(
        tostring(data.label), tostring(stationId), data.duration))
    notify(data.actor, ('%s — ready in %s'):format(data.label or 'Process', fmtDuration(data.duration)))
    syncPlayer()
end

-- ── collect / activation hook ────────────────────────────────────────────────

--- Grant a finished run's output (plus anything the station held, e.g. the
--- mold) and clear it.
local function collect(actor, stationId)
    local e = processes()[stationId]
    if not e then return end
    local ok, err = pcall(function()
        local created = world.createObject(e.output.id, e.output.count or 1)
        created:moveInto(types.Actor.inventory(actor))
    end)
    if not ok then
        log.error(('process: collect failed for "%s": %s'):format(tostring(e.output.id), tostring(err)))
        return
    end
    for _, entry in ipairs(e.returned or {}) do
        local rok, rerr = pcall(function()
            local created = world.createObject(entry.id, entry.count or 1)
            created:moveInto(types.Actor.inventory(actor))
        end)
        if not rok then
            log.error(('process: failed to return "%s": %s'):format(tostring(entry.id), tostring(rerr)))
        end
    end
    extinguishFx(e) -- safety net; normally already out since onProcessDone
    processes()[stationId] = nil
    notify(actor, ('Collected %d x %s'):format(e.output.count or 1, e.label or e.output.id))
    syncPlayer()
end

--- Called by init.lua's activation handler BEFORE normal station handling.
--- Returns true when the activation was consumed by a process (busy or collect).
---@param object any the activated object
---@param actor any
---@return boolean handled
function this.onStationActivated(object, actor)
    if not saveData then return false end
    local e = processes()[object.id]
    if not e then return false end
    if actor.type ~= types.Player then return true end

    if not e.done then
        local remaining = math.max(0, (e.readyAt or 0) - core.getGameTime())
        notify(actor, ('%s — ready in %s'):format(e.label or 'Working', fmtDuration(remaining)))
        return true
    end

    collect(actor, object.id)
    return true
end

--- Event: collect from a proximity station (no activation path).
---@param data { actor: any, stationId: string }
function this.onCollect(data)
    if not (data and data.actor and data.stationId) then return end
    local e = processes()[data.stationId]
    if e and e.done then collect(data.actor, data.stationId) end
end

--- Event: the player (re)loaded — send the full snapshot.
function this.onRequestSync()
    syncPlayer()
end

return this
