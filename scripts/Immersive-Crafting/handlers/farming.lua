--[[
    Farming handler — the planter's contextual card (no window, card-only UI).

        Planter                    Kreshweed — growing        Kreshweed — ripe!
        Empty                      Ready in ~14 h             Activate the plant
        [F] Plant Saltrice (hold)                             to harvest
        tap [F]: next seed (2/3)

    Seeds are the produce itself (vegetable = seed): any inventory item matching
    a crop's `seed` id/tag is plantable. Three ways to choose WHAT the hold-F
    plants, most immersive first:
    - SOWN seed: DROP a seed onto the planter — it goes into the soil
      (globalFarming absorbs it); hold F to plant exactly that.
    - MEMORY: a planter remembers its last crop; it sorts first in the seed
      list, so hold-F replants it without any cycling.
    - TAP-cycle: tap the context key to pick a different seed by hand.
    HOLD plants (consumes the sown seed, or one from the inventory).
    Harvesting is activating the ripe plant itself (globalFarming intercepts).
]]

local core = require('openmw.core')
-- NOT named `self`: the method receiver in `Handler:Method()` would shadow it.
local omwSelf = require('openmw.self')
local types = require('openmw.types')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local farmState = require('scripts.Immersive-Crafting.farmState')
local log = require('scripts.Immersive-Crafting.log')

local STAGES = 3
local PLANT_HOLD = 1.2

---@class CFarmingHandler : CAbstractHandler
local CFarmingHandler = {

}
setmetatable(CFarmingHandler, { __index = CAbstractHandler })

local selectedIndex = 1

--- Distinct plantable stacks in the inventory: items matching any crop's seed.
--- The planter's REMEMBERED crop sorts first, so the default hold-F replants
--- it and tap-cycling is only needed to switch crops.
---@param planterId string?
---@return { seedId: string, cropId: string, label: string }[]
local function plantableSeeds(planterId)
    local list, seen = {}, {}
    for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
        local recordId = item.recordId
        if not seen[recordId] then
            seen[recordId] = true
            for cropId, crop in pairs(GRegistries.crops or {}) do
                if lib.matchesTag(recordId, crop.seed) then
                    list[#list + 1] = { seedId = recordId, cropId = cropId, label = crop.label or cropId }
                    break
                end
            end
        end
    end
    local remembered = planterId and farmState.memoryFor(planterId)
    table.sort(list, function(a, b)
        local ra, rb = a.cropId == remembered, b.cropId == remembered
        if ra ~= rb then return ra end
        return a.label < b.label
    end)
    return list
end

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CFarmingHandler:evaluate(ctx)
    local planter = ctx.object
    if not planter then
        return { status = 'Planter' }
    end

    -- something growing here?
    local state = farmState.forPlanter(planter.id)
    if state then
        local crop = (GRegistries.crops or {})[state.cropId]
        local name = crop and crop.label or state.cropId
        if (state.stage or 1) >= STAGES then
            return {
                status = name .. ' — ripe!',
                details = { 'Activate the plant to harvest' },
            }
        end
        local remaining = math.max(0, (state.readyAt or 0) - core.getGameTime())
        return {
            status = name .. ' — growing',
            details = { ('Ready in ~%d h'):format(math.max(1, math.ceil(remaining / 3600))) },
        }
    end

    -- a seed dropped into the soil owns the card: hold-F plants exactly it
    local sownSeed = farmState.sownFor(planter.id)
    if sownSeed then
        local crop = (GRegistries.crops or {})[sownSeed.cropId]
        local name = crop and crop.label or sownSeed.cropId
        ---@type ViewModel
        return {
            status = ('%s in the soil'):format(name),
            action = {
                id = 'farming',
                label = 'Plant ' .. name,
                enabled = true,
                hold = PLANT_HOLD,
            },
        }
    end

    -- empty planter: offer planting (the remembered crop sorts first)
    local seeds = plantableSeeds(planter.id)
    if #seeds == 0 then
        return {
            status = 'Empty',
            details = { 'Nothing plantable in your pack' },
        }
    end
    if selectedIndex > #seeds then selectedIndex = 1 end
    local selected = seeds[selectedIndex]

    local details = nil
    if #seeds > 1 then
        details = { ('tap [F]: next seed (%d/%d)'):format(selectedIndex, #seeds) }
    end

    ---@type ViewModel
    return {
        status = 'Empty',
        details = details,
        action = {
            id = 'farming',
            label = 'Plant ' .. selected.label,
            enabled = true,
            hold = PLANT_HOLD,
        },
    }
end

--- Tap: cycle which seed the hold action will plant (not while a dropped
--- seed sits in the soil — that one IS the choice).
---@param ctx HandlerContext
function CFarmingHandler:OnTap(ctx)
    if not ctx.object or farmState.forPlanter(ctx.object.id) then return end
    if farmState.sownFor(ctx.object.id) then return end
    local seeds = plantableSeeds(ctx.object.id)
    if #seeds < 2 then return end
    selectedIndex = (selectedIndex % #seeds) + 1
end

--- Hold: plant — the sown (dropped-in) seed if there is one, else the
--- selected inventory seed (global consumes it and spawns the crop).
---@param ctx HandlerContext
function CFarmingHandler:OnActivate(ctx)
    local planter = ctx.object
    if not planter then return end
    if farmState.forPlanter(planter.id) then return end -- already growing

    local sownSeed = farmState.sownFor(planter.id)
    if sownSeed then
        log.info(('farming: planting sown %s (%s)'):format(sownSeed.cropId, sownSeed.seedId))
        core.sendGlobalEvent('ImmersiveCrafting_Plant', {
            actor = omwSelf.object,
            planter = planter,
            cropId = sownSeed.cropId,
            seedId = sownSeed.seedId,
            fromSown = true,
        })
        return
    end

    local seeds = plantableSeeds(planter.id)
    if #seeds == 0 then return end
    if selectedIndex > #seeds then selectedIndex = 1 end
    local selected = seeds[selectedIndex]

    log.info(('farming: planting %s (%s)'):format(selected.cropId, selected.seedId))
    core.sendGlobalEvent('ImmersiveCrafting_Plant', {
        actor = omwSelf.object,
        planter = planter,
        cropId = selected.cropId,
        seedId = selected.seedId,
    })
end

--#endregion


return CFarmingHandler
