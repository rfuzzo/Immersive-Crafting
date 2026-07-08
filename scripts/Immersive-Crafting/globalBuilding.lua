--[[
    Build-in-place — GLOBAL side (required by init.lua).

    The player's build card (buildScan + handlers/building.lua) found a
    complete component set on the ground and the hold completed. Here the set
    is re-validated against the CELL (something may have been picked up
    mid-hold), the loose items are consumed, and the station ACTIVATOR rises
    at their centroid. The actor gets the construction's milestone
    (progression gating + tutorial popup, player side).

    Constructions are data (data/Immersive-Crafting/constructions/*.json);
    loaded here directly — GRegistries lives in the player context.

    Tag matching: the global context has no FlexTag interface access the lib
    helper expects (I.FlexTagL is a local-script interface), so component tags
    are matched via I.FlexTagG — same pattern as init.lua's activation match.
]]

local world = require('openmw.world')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local io = require('scripts.Immersive-Crafting.io')
local log = require('scripts.Immersive-Crafting.log')

local CONSTRUCTIONS_DIR = 'data/Immersive-Crafting/constructions/constructions.json'
local BUILD_RADIUS = 250 -- re-validation range around the build position

local this = {}

local defs = nil ---@type CConstruction[]?
local function constructions()
    if defs then return defs end
    defs = {}
    for _, entry in ipairs(io.loadJsonFile(CONSTRUCTIONS_DIR) or {}) do
        if entry.id and entry.activator and entry.components then
            defs[#defs + 1] = entry
        end
    end
    log.info(('building: %d constructions loaded'):format(#defs))
    return defs
end

---@param id string
---@return CConstruction?
local function byId(id)
    for _, def in ipairs(constructions()) do
        if def.id == id then return def end
    end
    return nil
end

--- Salvage list for a built station's activator record (pack-up path in
--- globalStations). nil when the record is not a construction.
---@param activatorRecordId string
---@return { id: string, count: integer }[]?, string? salvage, label
function this.salvageFor(activatorRecordId)
    for _, def in ipairs(constructions()) do
        if def.activator:lower() == (activatorRecordId or ''):lower() then
            return def.salvage or {}, def.label or def.id
        end
    end
    return nil
end

--- Global-context tag match: exact record id or FlexTag (I.FlexTagG) tag.
---@param recordId string
---@param query string
---@return boolean
local function matchesTagGlobal(recordId, query)
    if recordId:lower() == query:lower() then return true end
    local flexTag = I.FlexTagG
    if flexTag and flexTag.objectHasTag then
        return flexTag.objectHasTag(recordId, query) and true or false
    end
    return false
end

local function notify(actor, text)
    if actor then actor:sendEvent('ImmersiveCrafting_Notify', { text = text }) end
end

--- Event: build a construction at `position` from the loose items around it.
---@param data { actor: any, constructionId: string, position: any }
function this.onBuild(data)
    if not (data and data.actor and data.constructionId and data.position) then return end
    local def = byId(data.constructionId)
    if not def then
        log.error('building: unknown construction ' .. tostring(data.constructionId))
        return
    end
    local cell = data.actor.cell
    if not cell then return end

    -- pool: loose items near the build spot (re-validated — the card's scan is stale)
    local pool = {}
    for _, obj in ipairs(cell:getAll()) do
        if obj.count and obj.count > 0 and obj.position
            and (obj.position - data.position):length() <= BUILD_RADIUS then
            pool[#pool + 1] = obj
        end
    end

    -- claim greedily; verify the FULL set before consuming anything
    local claims = {} ---@type { object: any, count: integer }[]
    local claimedUnits = {} ---@type table<any, integer>
    for _, comp in ipairs(def.components or {}) do
        local need = comp.count or 1
        for _, obj in ipairs(pool) do
            if need <= 0 then break end
            local free = (obj.count or 1) - (claimedUnits[obj] or 0)
            if free > 0 and matchesTagGlobal(obj.recordId, comp.id) then
                local take = math.min(free, need)
                claimedUnits[obj] = (claimedUnits[obj] or 0) + take
                need = need - take
            end
        end
        if need > 0 then
            notify(data.actor, 'The materials are gone')
            return
        end
    end
    for obj, units in pairs(claimedUnits) do
        claims[#claims + 1] = { object = obj, count = units }
    end

    -- raise the station first — if the record is missing (plugin not packed
    -- yet), nothing must be consumed
    local ok, err = pcall(function()
        local created = world.createObject(def.activator, 1)
        created:teleport(cell, data.position)
    end)
    if not ok then
        log.warn(('building: cannot place "%s" (%s)'):format(def.activator, tostring(err)))
        notify(data.actor, 'Nothing happens — the station cannot be placed here')
        return
    end

    for _, claim in ipairs(claims) do
        local rok = pcall(function() claim.object:remove(claim.count) end)
        if not rok then
            log.error(('building: failed to consume %dx %s'):format(
                claim.count, tostring(claim.object.recordId)))
        end
    end

    notify(data.actor, ('Built %s'):format(def.label or def.id))
    data.actor:sendEvent('ImmersiveCrafting_Milestone', { id = def.id })
    log.info(('building: built %s (%s) at %s'):format(
        def.id, def.activator, tostring(data.position)))
end

return this
