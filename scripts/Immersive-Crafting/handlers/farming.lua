--[[
    Farming handler — the planter's contextual card (no window, card-only UI).

        Planter                    Kreshweed — growing        Kreshweed — ripe!
        Empty                      Ready in ~14 h             Activate the plant
        [F] Plant Saltrice (hold)                             to harvest
        tap [F]: next seed (2/3)

    Seeds are the produce itself (vegetable = seed): any inventory item matching
    a crop's `seed` id/tag is plantable. TAP the context key to cycle which seed
    is selected; HOLD it to plant (consumes one, handled by the global script).
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
---@return { seedId: string, cropId: string, label: string }[]
local function plantableSeeds()
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
    table.sort(list, function(a, b) return a.label < b.label end)
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

    -- empty planter: offer planting
    local seeds = plantableSeeds()
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

--- Tap: cycle which seed the hold action will plant.
---@param ctx HandlerContext
function CFarmingHandler:OnTap(ctx)
    if not ctx.object or farmState.forPlanter(ctx.object.id) then return end
    local seeds = plantableSeeds()
    if #seeds < 2 then return end
    selectedIndex = (selectedIndex % #seeds) + 1
end

--- Hold: plant the selected seed (global consumes it and spawns the crop).
---@param ctx HandlerContext
function CFarmingHandler:OnActivate(ctx)
    local planter = ctx.object
    if not planter then return end
    if farmState.forPlanter(planter.id) then return end -- already growing

    local seeds = plantableSeeds()
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
