--[[
    Foraging handler — gather raw materials from the world.

    Works with `trigger:"gaze"` contexts (look at a tagged static: tree, rock)
    and `trigger:"condition"` contexts (predicate, e.g. shovel near water).
    The context carries the forage definition:

        "forage": {
          "verb": "Chop wood",              -- action label
          "label": "Wood",                  -- material name for messages
          "yield": { "id": "ic_wood", "count": 1 },
          "tools": ["axe"],                 -- required in inventory, NOT consumed
          "cooldown": 3600                  -- game seconds until this source recovers
        }

    Nothing is consumed; the yield is granted via the existing global executor
    (ImmersiveCrafting_CraftShaped with an empty consume list). Cooldowns are
    per object (gaze) / per context (condition), persisted in the player save.
]]

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local forageState = require('scripts.Immersive-Crafting.forageState')
local log = require('scripts.Immersive-Crafting.log')

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
        for _, item in ipairs(types.Actor.inventory(self):getAll()) do
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

    -- grant the yield (nothing consumed) via the existing global executor
    core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
        actor = self.object,
        consume = {},
        output = forage.yield,
    })
    forageState.setCooldown(key, forage.cooldown)

    local label = forage.label or forage.yield.id
    log.info('Foraged ' .. label)
    ui.showMessage(('You gather %d x %s'):format(forage.yield.count or 1, label))
end

--#endregion


return CForagingHandler
