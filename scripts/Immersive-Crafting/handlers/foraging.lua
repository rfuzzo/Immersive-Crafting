--[[
    Foraging handler — gather raw materials from the world.

    Works with `trigger:"gaze"` contexts (look at a tagged static: tree, rock)
    and `trigger:"condition"` contexts (predicate, e.g. shovel near water).
    The context carries the forage definition:

        "forage": {
          "verb": "Gather wood",            -- action label
          "label": "Sticks",                -- material name for messages
          "yield": { "id": "ic_stick", "count": 1, "countMax": 3 },
                                            -- countMax -> random count..countMax
          "woodYield": { "id": "ic_wood", "count": 1 },
                                            -- extra wood, only while "foraging
                                            -- gives wood" is active (setting ON,
                                            -- or Sun's Dusk absent — SD's own
                                            -- wood-chopping covers firewood)
          "tools": ["shovel"],              -- required in inventory, NOT consumed
          "cooldown": 3600                  -- game seconds until this source recovers
        }

    Nothing is consumed; the yield is granted via the existing global executor
    (ImmersiveCrafting_CraftShaped with an empty consume list). Cooldowns are
    per object (gaze) / per context (condition), persisted in the player save.
]]

local core = require('openmw.core')
-- NOT named `self`: inside `function CForagingHandler:Method()` the implicit
-- method receiver would shadow it (self.object -> nil actor in events).
local omwSelf = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')
local I = require('openmw.interfaces')
local storage = require('openmw.storage')

local settingsSection = storage.playerSection('SettingsImmersiveCrafting')

--- Should tree foraging also yield wood? Explicit setting wins; without
--- Sun's Dusk it is always on (no other firewood source exists then).
---@return boolean
local function foragingGivesWood()
    if settingsSection and settingsSection:get('ForagingGivesWood') then return true end
    return I.SunsDusk == nil
end

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local forageState = require('scripts.Immersive-Crafting.forageState')
local log = require('scripts.Immersive-Crafting.log')

-- Seconds the forage key must be held before the yield is granted. A gather is a
-- deliberate act (chopping, digging), not a tap — the overlay shows a hold bar.
local DEFAULT_HOLD = 1.2

---@class CForagingHandler : CAbstractHandler
local CForagingHandler = {

}
setmetatable(CForagingHandler, { __index = CAbstractHandler })

--- Tools (tags/ids) from the forage definition that are NOT in the inventory.
---@param forage table
---@return string[]
local function missingTools(forage)
    local missing = {}
    for _, tool in ipairs(forage.tools or {}) do
        local found = false
        for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
            if lib.matchesTag(item.recordId, tool) then
                found = true
                break
            end
        end
        if not found then missing[#missing + 1] = tool end
    end
    return missing
end

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CForagingHandler:evaluate(ctx)
    local forage = ctx.context.forage
    if not forage or not forage.yield then
        return { status = 'Nothing to gather' }
    end

    local missing = missingTools(forage)
    local remaining = forageState.remaining(forageState.key(ctx))

    local status, enabled
    if remaining > 0 then
        status = ('Recovering (%d min)'):format(math.ceil(remaining / 60))
        enabled = false
    elseif #missing > 0 then
        status = 'Missing tool'
        enabled = false
    else
        status = 'Ready'
        enabled = true
    end

    local details = nil
    if #missing > 0 then
        details = { 'Requires: ' .. table.concat(missing, ', ') }
    end

    ---@type ViewModel
    return {
        status = status,
        details = details,
        action = {
            id = 'foraging',
            label = forage.verb or ('Gather ' .. (forage.label or forage.yield.id)),
            enabled = enabled,
            hold = forage.holdTime or DEFAULT_HOLD,
        },
    }
end

---@param ctx HandlerContext
function CForagingHandler:OnActivate(ctx)
    local forage = ctx.context.forage
    if not forage or not forage.yield then return end

    -- re-check gating (the overlay activates all current actions regardless of enabled)
    local key = forageState.key(ctx)
    if forageState.remaining(key) > 0 then return end
    if #missingTools(forage) > 0 then return end

    -- grant the yield (nothing consumed) via the existing global executor;
    -- countMax makes the amount random (count..countMax)
    local count = forage.yield.count or 1
    if forage.yield.countMax and forage.yield.countMax > count then
        count = math.random(count, forage.yield.countMax)
    end
    core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
        actor = omwSelf.object,
        consume = {},
        output = { id = forage.yield.id, count = count },
    })

    -- wood on top (trees), when the foraging-gives-wood rule is active
    local wood = forage.woodYield
    if wood and not foragingGivesWood() then wood = nil end
    if wood then
        core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
            actor = omwSelf.object,
            consume = {},
            output = wood,
        })
    end
    forageState.setCooldown(key, forage.cooldown)

    local label = forage.label or forage.yield.id
    local message = ('You gather %d x %s'):format(count, label)
    if wood then
        message = message .. (' (+%d Wood)'):format(wood.count or 1)
    end
    log.info('Foraged ' .. label)
    ui.showMessage(message)
end

--#endregion


return CForagingHandler
