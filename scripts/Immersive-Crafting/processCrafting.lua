local self = require('openmw.self')
local types = require('openmw.types')

local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

--- Are all required tools present in the player's inventory?
---@param tools string[]|nil
---@return boolean
function this.hasTools(tools)
    if not tools or #tools == 0 then return true end
    local items = types.Actor.inventory(self):getAll()
    for _, tool in ipairs(tools) do
        local found = false
        for _, item in ipairs(items) do
            if lib.matchesTag(item.recordId, tool) then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

--- Count how many of a recipe's input slots are satisfied by the placed slots.
---@param recipe CProcessRecipe
---@param slots table<string, string|nil> slot key -> placed record id
---@return boolean ok, integer filled
local function recipeSatisfied(recipe, slots)
    local filled = 0
    for key, need in pairs(recipe.inputs) do
        local placedId = slots[key]
        if not placedId or not lib.matchesTag(placedId, need) then
            return false, 0
        end
        filled = filled + 1
    end
    return true, filled
end

--- Resolve the process recipe matching the placed role-slots for this
--- action/context. When several recipes match, the one using the most input
--- slots (most specific) wins.
---@param slots table<string, string|nil> slot key -> placed record id (or nil)
---@param action CAction
---@param context CContext
---@return CProcessRecipe?
function this.resolveProcessRecipe(slots, action, context)
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return nil
    end

    local best, bestScore = nil, -1
    for _, recipe in pairs(GRegistries.processRecipes or {}) do
        if recipe.action == action.id and recipe.context == context.id then
            local ok, filled = recipeSatisfied(recipe, slots)
            if ok and this.hasTools(recipe.tools) and filled > bestScore then
                best, bestScore = recipe, filled
            end
        end
    end

    return best
end

return this
