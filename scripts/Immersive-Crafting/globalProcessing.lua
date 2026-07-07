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

--- Persistent charge registry: items dropped INTO a loadable station (UI-less
--- kiln/charcoal pit) waiting to be lit. stationId -> { {id, count} }.
local function charges()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.charges = saveData.charges or {}
    return saveData.charges
end

-- player-pushed options (ImmersiveCrafting_SetOptions; defaults apply until pushed)
local options = { stationLoading = true }

local function notify(actor, text)
    if actor then actor:sendEvent('ImmersiveCrafting_Notify', { text = text }) end
end

-- item types that may be dropped into a loadable station (no Light — a
-- dropped torch is a light source, not kiln feed; actors/statics never qualify)
local ITEM_TYPES = {
    types.Miscellaneous, types.Ingredient, types.Potion, types.Weapon,
    types.Armor, types.Book, types.Clothing, types.Apparatus,
    types.Repair, types.Lockpick, types.Probe,
}

local function isLoadableItem(object)
    for _, t in ipairs(ITEM_TYPES) do
        if object.type == t then return true end
    end
    return false
end

--- Display name for a record id (charge messages/snapshots).
---@param recordId string
---@return string
local function recordName(recordId)
    for _, t in ipairs(ITEM_TYPES) do
        local ok, rec = pcall(function() return t.record(recordId) end)
        if ok and rec and rec.name and rec.name ~= '' then return rec.name end
    end
    return recordId
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

--- Push a plain snapshot of all runs AND station charges to the player
--- (for the station card).
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
    local chargeSnapshot = {}
    for stationId, list in pairs(charges()) do
        local copy = {}
        for i, e in ipairs(list) do
            copy[i] = { id = e.id, count = e.count, name = recordName(e.id) }
        end
        chargeSnapshot[stationId] = copy
    end
    player:sendEvent('ImmersiveCrafting_ProcessSync',
        { processes = snapshot, charges = chargeSnapshot })
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

--- Register a run at a station and schedule its completion (shared by the
--- crafting-window start and UI-less ignition).
---@param station any
---@param data { recipeId: string, label: string?, output: table, returned: table[]?, duration: number }
local function registerRun(station, data)
    processes()[station.id] = {
        stationId = station.id,
        recipeId = data.recipeId,
        label = data.label or data.recipeId,
        output = data.output,
        returned = data.returned,       -- items held by the station, given back on collect
        startedAt = core.getGameTime(), -- for the station card's progress bar
        readyAt = core.getGameTime() + data.duration,
        done = false,
        fx = igniteFx(station), -- e.g. the kiln's fire (removed when done)
    }
    async:newGameTimer(data.duration, onProcessDone, station.id)
    log.info(('process: started "%s" at station %s (%ds)'):format(
        tostring(data.label), tostring(station.id), data.duration))
end

-- ── start ────────────────────────────────────────────────────────────────────

--- Event: start a timed process at a station. Inputs are consumed UP FRONT —
--- including `returned` items (the mold sits in the kiln for the duration);
--- those are granted back to the collector along with the output.
---@param data { actor: any, station: any, recipeId: string, label: string, consume: { id: string, count: integer, soul: string? }[], returned: { id: string, count: integer }[]?, output: { id: string, count: integer }, duration: number }
function this.onStart(data)
    if not (data and data.actor and data.station and data.output and data.duration) then return end
    local stationId = data.station.id

    if processes()[stationId] then
        notify(data.actor, 'This station is already working')
        return
    end

    -- Instance gate (soul:"filled"): filled and empty soul gems share a record
    -- id, so the gate is checked per ITEM here — only gems with a trapped soul
    -- count toward (and are removed for) such an entry.
    local function satisfiesGate(item, entry)
        if entry.soul ~= 'filled' then return true end
        local ok, soul = pcall(function() return types.Miscellaneous.getSoul(item) end)
        return ok and soul ~= nil and soul ~= ''
    end

    -- verify availability first so we never partially consume
    local inv = types.Actor.inventory(data.actor)
    for _, entry in ipairs(data.consume or {}) do
        local have = 0
        for _, item in ipairs(inv:getAll()) do
            if item.recordId == entry.id and satisfiesGate(item, entry) then
                have = have + (item.count or 1)
            end
        end
        if have < (entry.count or 1) then
            notify(data.actor, entry.soul == 'filled'
                and 'Requires a filled soul gem' or 'Not enough materials')
            return
        end
    end
    for _, entry in ipairs(data.consume or {}) do
        local needed = entry.count or 1
        local removed = 0
        for _, item in ipairs(inv:getAll()) do
            if needed <= 0 then break end
            if item.recordId == entry.id and satisfiesGate(item, entry) then
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

    registerRun(data.station, data)
    notify(data.actor, ('%s — ready in %s'):format(data.label or 'Process', fmtDuration(data.duration)))
    syncPlayer()
end

-- ── UI-less loading + ignition (kiln, charcoal pit) ─────────────────────────

local LOAD_RADIUS = 150 -- units around a loadable station that claim a dropped item

--- Engine handler (via init.lua, after the drop-swap check): an item dropped
--- near an idle LOADABLE station joins its charge (the item is absorbed;
--- packing the station returns it). Gated by the "load stations by dropping
--- items" setting (player-pushed option).
---@param object any object that just became active
function this.onObjectActive(object)
    if not options.stationLoading then return end
    if not object.cell or not isLoadableItem(object) then return end

    -- nearest idle loadable station in the cell
    local best, bestDist
    for _, act in ipairs(object.cell:getAll(types.Activator)) do
        if globalStations.isLoadable(act.recordId) and not processes()[act.id] then
            local d = (act.position - object.position):length()
            if d <= LOAD_RADIUS and (not bestDist or d < bestDist) then
                best, bestDist = act, d
            end
        end
    end
    if not best then return end

    local list = charges()[best.id]
    if not list then
        list = {}
        charges()[best.id] = list
    end
    local id, n = object.recordId, object.count or 1
    local merged = false
    for _, e in ipairs(list) do
        if e.id == id then
            e.count = (e.count or 1) + n
            merged = true
            break
        end
    end
    if not merged then list[#list + 1] = { id = id, count = n } end
    object:remove()

    local stationName = recordName(best.recordId)
    local okRec, rec = pcall(function() return types.Activator.record(best.recordId) end)
    if okRec and rec and rec.name and rec.name ~= '' then stationName = rec.name end
    notify(world.players[1], ('Loaded %d x %s into the %s'):format(n, recordName(id), stationName))
    log.info(('process: loaded %d x %s into %s'):format(n, id, best.recordId))
    syncPlayer()
end

--- Event: light a loaded station (the player resolved the charge against the
--- station's recipes and holds a fire source). The WHOLE charge burns —
--- process matching is exact, so a resolvable charge has no leftovers.
---@param data { actor: any, station: any, recipeId: string, label: string, output: table, duration: number, returned: { id: string, count: integer }[]? }
function this.onIgnite(data)
    if not (data and data.actor and data.station and data.output and data.duration) then return end
    local stationId = data.station.id
    if processes()[stationId] then
        notify(data.actor, 'This station is already working')
        return
    end
    local charge = charges()[stationId]
    if not charge or #charge == 0 then
        notify(data.actor, 'Nothing is loaded')
        return
    end

    charges()[stationId] = nil
    registerRun(data.station, data)
    notify(data.actor, ('%s — ready in %s'):format(data.label or 'Process', fmtDuration(data.duration)))
    syncPlayer()
end

--- Give a cold station's charge back (called before packing it up; a busy
--- station has no charge — igniting consumed it).
---@param data { actor: any, station: any }
function this.returnCharge(data)
    if not (data and data.actor and data.station) then return end
    local stationId = data.station.id
    local list = charges()[stationId]
    if not list then return end
    for _, e in ipairs(list) do
        local ok, err = pcall(function()
            local created = world.createObject(e.id, e.count or 1)
            created:moveInto(types.Actor.inventory(data.actor))
        end)
        if not ok then
            log.error(('process: failed to return charge "%s": %s'):format(tostring(e.id), tostring(err)))
        end
    end
    charges()[stationId] = nil
    syncPlayer()
end

--- Event: player-pushed options (settings live player-side).
---@param data { stationLoading: boolean? }
function this.onSetOptions(data)
    if data and data.stationLoading ~= nil then
        options.stationLoading = data.stationLoading and true or false
    end
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
    if not e then
        -- a cold LOADED station doesn't open the window: activating it takes
        -- the LAST loaded stack back out (the drop-in undo — a wrong fuel is
        -- one activation away from the inventory). Light it with a fire
        -- source in hand instead (hold F on its card). Empty again -> the
        -- next activation falls through to normal station handling.
        local charge = saveData.charges and saveData.charges[object.id]
        if charge and #charge > 0 then
            if actor.type ~= types.Player then return true end
            local entry = charge[#charge]
            local ok, err = pcall(function()
                local created = world.createObject(entry.id, entry.count or 1)
                created:moveInto(types.Actor.inventory(actor))
            end)
            if not ok then
                log.error(('process: failed to unload "%s": %s'):format(tostring(entry.id), tostring(err)))
                return true
            end
            charge[#charge] = nil
            if #charge == 0 then saveData.charges[object.id] = nil end
            local parts = {}
            for _, rest in ipairs(charge) do
                parts[#parts + 1] = ('%d x %s'):format(rest.count or 1, recordName(rest.id))
            end
            notify(actor, ('Took back %d x %s%s'):format(
                entry.count or 1, recordName(entry.id),
                #parts > 0 and (' — still loaded: ' .. table.concat(parts, ', ')) or ''))
            syncPlayer()
            return true
        end
        return false
    end
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
---@param data table {  }
function this.onRequestSync(data)
    syncPlayer()
end

return this
