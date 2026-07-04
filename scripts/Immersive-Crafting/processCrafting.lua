local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

--- Are all required tools present in the player's inventory? (Tools are NEVER consumed.)
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

--- Exact multiset match: every counted input line must be satisfied by distinct
--- placed items, and no placed item may be left over (everything placed is
--- consumed on craft, so extras would silently vanish).
--- NOTE: greedy line-order claiming; with heavily overlapping tags a pathological
--- assignment could fail where a perfect matching exists — acceptable for now.
---@param placedIds string[] record ids of the placed items (one per filled slot)
---@param inputs CProcessRecipe.Input[]
---@return boolean
local function multisetMatch(placedIds, inputs)
    local claimed = {}
    local total = 0
    for _, line in ipairs(inputs) do
        local need = line.count or 1
        total = total + need
        for i, recordId in ipairs(placedIds) do
            if need <= 0 then break end
            if not claimed[i] and lib.matchesTag(recordId, line.id) then
                claimed[i] = true
                need = need - 1
            end
        end
        if need > 0 then return false end
    end
    return total == #placedIds
end

--- Resolve the process recipe matching the placed items for this action/context.
--- Non-positional: only the multiset of placed items matters. When several
--- recipes match, the one requiring the most items (most specific) wins.
---@param placedIds string[] record ids of the placed items (one per filled slot)
---@param action CAction
---@param context CContext
---@return CProcessRecipe?
function this.resolveProcessRecipe(placedIds, action, context)
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return nil
    end
    if #placedIds == 0 then return nil end

    local best, bestScore = nil, -1
    for _, recipe in pairs(GRegistries.processRecipes or {}) do
        -- Sun's Dusk meal recipes only exist when SD is loaded (soft dependency)
        local available = not recipe.sdMeal or I.SunsDusk ~= nil
        if available and recipe.action == action.id and recipe.context == context.id then
            if multisetMatch(placedIds, recipe.inputs) and this.hasTools(recipe.tools) then
                local score = 0
                for _, line in ipairs(recipe.inputs) do score = score + (line.count or 1) end
                if score > bestScore then
                    best, bestScore = recipe, score
                end
            end
        end
    end

    return best
end

return this
