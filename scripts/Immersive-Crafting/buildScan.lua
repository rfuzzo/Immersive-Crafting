--[[
    Build-in-place detection — PLAYER side.

    Scans the loose items around the player for a COMPLETE construction
    component set (GRegistries.constructions). The result is cached for the
    frame's card: the `construction_ready` condition (registered here into
    conditions.lua) makes the "Construction" context appear exactly when
    something can be built, and handlers/building.lua reads `this.current`
    for the card and the build itself.

    The card only appears on a full set (no partial-progress noise): dropped
    wood near a charcoal pit stays a charge, two stones on a beach stay
    stones. Milestone-gated it is not — building the first firepit IS the
    entry point.
]]

local nearby = require('openmw.nearby')
local self = require('openmw.self')

local conditions = require('scripts.Immersive-Crafting.conditions')
local lib = require('scripts.Immersive-Crafting.lib')
local progressState = require('scripts.Immersive-Crafting.progressState')

local SCAN_RADIUS = 200 -- components must lie within this range of the player

local this = {}

---@class BuildCandidate
---@field def CConstruction
---@field position any util.vector3 — centroid of the claimed components (spawn point)
---@field claims { object: any, count: integer }[] the loose items the build consumes

this.current = nil ---@type BuildCandidate?

--- Greedy claim of a construction's components from the nearby loose items.
---@param def CConstruction
---@param items { object: any, recordId: string, count: integer }[]
---@return BuildCandidate?
local function tryConstruction(def, items)
    local claimedUnits = {} ---@type table<integer, integer> item index -> units claimed
    for _, comp in ipairs(def.components or {}) do
        local need = comp.count or 1
        for i, it in ipairs(items) do
            if need <= 0 then break end
            local free = it.count - (claimedUnits[i] or 0)
            if free > 0 and lib.matchesTag(it.recordId, comp.id) then
                local take = math.min(free, need)
                claimedUnits[i] = (claimedUnits[i] or 0) + take
                need = need - take
            end
        end
        if need > 0 then return nil end
    end

    -- centroid of the claimed items = where the station rises
    local claims, sum, n = {}, nil, 0
    for i, units in pairs(claimedUnits) do
        local it = items[i]
        claims[#claims + 1] = { object = it.object, count = units }
        sum = sum and (sum + it.object.position) or it.object.position
        n = n + 1
    end
    if n == 0 then return nil end

    return { def = def, position = sum / n, claims = claims }
end

--- Rescan the surroundings; sets `this.current` (first complete construction
--- in data order — the bootstrap tiers come first in the json).
---@return boolean anything buildable
function this.rescan()
    this.current = nil
    local defs = GRegistries and GRegistries.constructions
    if not defs or #defs == 0 then return false end

    -- collect loose items once
    local items = {}
    local playerPos = self.position
    for _, item in ipairs(nearby.items) do
        if item.count and (item.position - playerPos):length() <= SCAN_RADIUS then
            items[#items + 1] = { object = item, recordId = item.recordId, count = item.count or 1 }
        end
    end
    if #items == 0 then return false end

    for _, def in ipairs(defs) do
        -- sequential reveal: a tier's construction only becomes buildable once
        -- its prerequisite milestone is unlocked (firepit -> kiln -> furnace)
        if not def.requires or progressState.has(def.requires) then
            local candidate = tryConstruction(def, items)
            if candidate then
                this.current = candidate
                return true
            end
        end
    end
    return false
end

-- The condition the "building" context is gated on (contexts/building.json).
-- contextManager polls conditions every 0.25s; the rescan doubles as the
-- cache fill for the handler's card.
conditions.register('construction_ready', function()
    return this.rescan()
end)

return this
