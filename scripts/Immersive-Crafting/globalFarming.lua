--[[
    Farming — GLOBAL side (required by init.lua; shares its script environment,
    incl. the `saveData` global).

    Owns the persistent crop registry and the growth lifecycle:

    - Plant (event `ImmersiveCrafting_Plant`): consume one seed item from the
      actor, spawn the crop's plant record above the planter, scale it small,
      register it in `saveData.crops`, and schedule persisted GAME-time stage
      timers (crops grow while sleeping; timers survive save/load natively).
    - Grow: each timer fire advances the stage and scales the plant up
      (0.3 → 0.65 → 1.0 = ripe).
    - Harvest: a types.Container activation handler intercepts activation of
      registered crop objects only (O(1) registry lookup — wild flora is
      untouched). Unripe → message; ripe → grant yield, then remove (annual) or
      reset to stage 1 and reschedule (perennial, `regrow`).

    Crop definitions are read from data/Immersive-Crafting/crops/*.json (the
    player loads the same files into GRegistries for the card/seed UI).
    The player keeps a read-only mirror via `ImmersiveCrafting_CropSync`.
]]

local world = require('openmw.world')
local types = require('openmw.types')
local core = require('openmw.core')
local async = require('openmw.async')
local util = require('openmw.util')
local vfs = require('openmw.vfs')
local I = require('openmw.interfaces')

local io = require('scripts.Immersive-Crafting.io')
local constants = require('scripts.Immersive-Crafting.constants')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

local STAGES = 3
local SCALES = { 0.3, 0.65, 1.0 }
local PLANT_Z_OFFSET = 15 -- rough planter-bed height; tune per planter mesh

-- ── crop definitions (global-side copy of crops/*.json) ─────────────────────

local defs = nil ---@type table<string, CCrop-like>?

local function cropDefs()
    if defs then return defs end
    defs = {}
    for filename in vfs.pathsWithPrefix(constants.DATA_ROOT .. 'crops/') do
        if filename:match('%.json$') then
            local data = io.loadJsonFile(filename)
            for _, entry in ipairs(data or {}) do
                if entry and entry.id then defs[entry.id] = entry end
            end
        end
    end
    log.info(('farming: loaded %d crop definitions (global)'):format((function()
        local n = 0; for _ in pairs(defs) do n = n + 1 end; return n
    end)()))
    return defs
end

-- ── registry / sync ──────────────────────────────────────────────────────────

--- Persistent crop registry (lives in the global script's save data).
local function crops()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.crops = saveData.crops or {}
    return saveData.crops
end

--- Seeds SOWN into planters by dropping them (waiting for the hold-F plant).
--- planter object id -> { seedId, cropId }.
local function sown()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.sown = saveData.sown or {}
    return saveData.sown
end

--- What each planter last grew (hold-F replants it without cycling).
--- planter object id -> crop id.
local function memory()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.planterMemory = saveData.planterMemory or {}
    return saveData.planterMemory
end

local function notify(actor, text)
    if actor then actor:sendEvent('ImmersiveCrafting_Notify', { text = text }) end
end

--- Push a plain snapshot of crops, sown seeds and planter memory to the player.
local function syncPlayer()
    local player = world.players[1]
    if not player then return end
    local snapshot = {}
    for objId, e in pairs(crops()) do
        snapshot[objId] = {
            cropId = e.cropId,
            stage = e.stage,
            readyAt = e.readyAt,
            planterId = e.planterId,
        }
    end
    player:sendEvent('ImmersiveCrafting_CropSync',
        { crops = snapshot, sown = sown(), memory = memory() })
end

-- ── growth timers (persisted; game time) ────────────────────────────────────

local stageDelay -- forward decl helpers
local scheduleStage

local onCropStage = async:registerTimerCallback('IC_cropStage', function(objId)
    local e = crops()[objId]
    if not e then return end
    if not (e.object and e.object:isValid()) then
        crops()[objId] = nil
        syncPlayer()
        return
    end

    e.stage = math.min(STAGES, (e.stage or 1) + 1)
    pcall(function() e.object:setScale(SCALES[e.stage]) end)
    if e.stage < STAGES then
        scheduleStage(objId, e.stepDelay or 3600)
    end
    syncPlayer()
end)

---@param totalSeconds number full grow/regrow duration
---@return number per-stage delay
stageDelay = function(totalSeconds)
    return math.max(1, totalSeconds / (STAGES - 1))
end

scheduleStage = function(objId, delaySeconds)
    async:newGameTimer(delaySeconds, onCropStage, objId)
end

-- ── sowing by dropping (the seed goes into the ground, F does the planting) ──

local SOW_RADIUS = 100 -- units around a planter that claim a dropped seed

-- player-pushed option (shared with station loading; init.lua fans it out)
local options = { stationLoading = true }

---@param data { stationLoading: boolean? }
function this.onSetOptions(data)
    if data and data.stationLoading ~= nil then
        options.stationLoading = data.stationLoading and true or false
    end
end

--- Global-context tag match: exact record id or FlexTag (I.FlexTagG) tag.
local function matchesTagGlobal(recordId, query)
    if recordId:lower() == query:lower() then return true end
    local flexTag = I.FlexTagG
    if flexTag and flexTag.objectHasTag then
        return flexTag.objectHasTag(recordId, query) and true or false
    end
    return false
end

--- Is this record a planter? (the tag/id the planter context matches)
local function isPlanterRecord(recordId)
    return matchesTagGlobal(recordId, 'ic_station_planter')
        or matchesTagGlobal(recordId, 'planter')
end

--- Is something already growing on (or sown into) this planter?
local function planterOccupied(planterId)
    if sown()[planterId] then return true end
    for _, e in pairs(crops()) do
        if e.planterId == planterId then return true end
    end
    return false
end

--- The crop definition a seed record belongs to (nil = not a seed).
---@param recordId string
---@return table? crop
local function cropForSeed(recordId)
    for _, crop in pairs(cropDefs()) do
        if crop.seed and matchesTagGlobal(recordId, crop.seed) then return crop end
    end
    return nil
end

--- Engine handler (via init.lua's chain): a seed dropped near an empty planter
--- is SOWN into it — one seed off the stack; hold-F on the card plants it.
--- Returns true when the seed was absorbed.
---@param object any object that just became active
---@return boolean handled
function this.onObjectActive(object)
    if not options.stationLoading then return false end
    if not object.cell then return false end

    local crop = cropForSeed(object.recordId)
    if not crop then return false end

    -- nearest unoccupied planter in the cell
    local best, bestDist
    for _, misc in ipairs(object.cell:getAll(types.Miscellaneous)) do
        if misc.id ~= object.id and isPlanterRecord(misc.recordId)
            and not planterOccupied(misc.id) then
            local d = (misc.position - object.position):length()
            if d <= SOW_RADIUS and (not bestDist or d < bestDist) then
                best, bestDist = misc, d
            end
        end
    end
    if not best then return false end

    sown()[best.id] = { seedId = object.recordId, cropId = crop.id }
    object:remove(1)
    notify(world.players[1], ('You set %s into the soil'):format(crop.label or crop.id))
    log.info(('farming: sowed %s into planter %s'):format(crop.id, tostring(best.id)))
    syncPlayer()
    return true
end

--- Picking up a planter gives an unplanted sown seed back (and forgets the
--- planter's memory — the object id dies with it). Default pickup proceeds.
local function onPlanterActivate(object, actor)
    if not saveData then return end
    local entry = saveData.sown and saveData.sown[object.id]
    if entry then
        pcall(function()
            local created = world.createObject(entry.seedId, 1)
            created:moveInto(types.Actor.inventory(actor))
        end)
        saveData.sown[object.id] = nil
        syncPlayer()
    end
    if saveData.planterMemory then saveData.planterMemory[object.id] = nil end
    -- return nil: the vanilla pickup happens as normal
end

I.Activation.addHandlerForType(types.Miscellaneous, onPlanterActivate)

-- ── planting ─────────────────────────────────────────────────────────────────

--- Event: plant a seed into a planter. `fromSown` plants the seed already
--- SOWN into the planter (dropped in) instead of consuming from the inventory.
---@param data { actor: any, planter: any, cropId: string, seedId: string, fromSown: boolean? }
function this.onPlant(data)
    if not (data and data.actor and data.planter and data.cropId and data.seedId) then return end
    local crop = cropDefs()[data.cropId]
    if not crop then
        log.error('farming: unknown crop ' .. tostring(data.cropId))
        return
    end

    -- one crop per planter
    for _, e in pairs(crops()) do
        if e.planterId == data.planter.id then
            notify(data.actor, 'Something is already growing here')
            return
        end
    end

    if data.fromSown then
        -- the seed is already in the soil (dropped in); verify it — it is
        -- cleared only after the plant actually spawns
        local entry = sown()[data.planter.id]
        if not (entry and entry.cropId == data.cropId) then
            notify(data.actor, 'No seed to plant')
            return
        end
    else
        -- consume one seed item (exact record id, chosen player-side)
        local inv = types.Actor.inventory(data.actor)
        local seedItem = inv:find(data.seedId)
        if not seedItem or seedItem.count < 1 then
            notify(data.actor, 'No seed to plant')
            return
        end
        local okRemove = pcall(function() seedItem:remove(1) end)
        if not okRemove then
            log.error('farming: failed to consume seed ' .. tostring(data.seedId))
            return
        end
    end

    -- spawn the growing plant above the planter bed
    local ok, err = pcall(function()
        local obj = world.createObject(crop.plant, 1)
        obj:teleport(data.planter.cell, data.planter.position + util.vector3(0, 0, PLANT_Z_OFFSET))
        pcall(function() obj:setScale(SCALES[1]) end)

        crops()[obj.id] = {
            object = obj,
            cropId = crop.id,
            stage = 1,
            planterId = data.planter.id,
            readyAt = core.getGameTime() + crop.growTime,
            stepDelay = stageDelay(crop.growTime),
        }
        scheduleStage(obj.id, stageDelay(crop.growTime))
    end)
    if not ok then
        log.error(('farming: failed to plant "%s": %s'):format(tostring(crop.plant), tostring(err)))
        return
    end

    if data.fromSown then sown()[data.planter.id] = nil end
    memory()[data.planter.id] = crop.id -- the planter remembers its crop
    notify(data.actor, 'Planted ' .. (crop.label or crop.id))
    log.info(('farming: planted %s at planter %s'):format(crop.id, tostring(data.planter.id)))
    syncPlayer()
end

--- Event: the player (re)loaded — send the full crop snapshot.
function this.onRequestSync()
    syncPlayer()
end

-- ── harvest (activation of registered crop objects only) ────────────────────

local function onCropActivate(object, actor)
    if not saveData then return end
    local e = crops()[object.id]
    if not e then return end -- wild flora: default behaviour
    if actor.type ~= types.Player then return false end

    local crop = cropDefs()[e.cropId]
    if not crop then return false end

    if (e.stage or 1) < STAGES then
        notify(actor, (crop.label or e.cropId) .. ' is still growing')
        return false
    end

    -- ripe: grant the yield
    local ok, err = pcall(function()
        local created = world.createObject(crop.yield.id, crop.yield.count or 1)
        created:moveInto(types.Actor.inventory(actor))
    end)
    if not ok then
        log.error(('farming: harvest grant failed for "%s": %s'):format(tostring(crop.yield.id), tostring(err)))
        return false
    end

    if crop.regrow then
        -- perennial: shrink back and regrow
        e.stage = 1
        e.readyAt = core.getGameTime() + crop.regrow
        e.stepDelay = stageDelay(crop.regrow)
        pcall(function() e.object:setScale(SCALES[1]) end)
        scheduleStage(object.id, stageDelay(crop.regrow))
    else
        -- annual: the plant is gone
        crops()[object.id] = nil
        pcall(function() object:remove() end)
    end

    notify(actor, ('Harvested %d x %s'):format(crop.yield.count or 1, crop.label or e.cropId))
    syncPlayer()
    return false -- suppress the vanilla container UI
end

-- crop plants are (vanilla) flora containers; registered once at script load
I.Activation.addHandlerForType(types.Container, onCropActivate)

return this
