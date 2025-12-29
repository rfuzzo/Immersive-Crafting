local core = require('openmw.core')
local nearby = require('openmw.nearby')
local self = require('openmw.self')

local log = require('scripts.Immersive-Crafting.log')

local this = {}

function this.len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---Find all nearby contexts or containers within range
---@param maxRange number Maximum search range
---@return table<string, ProximityResult> Map of ID to proximity result
function this.scanNearbyIngredients(maxRange)
    maxRange = maxRange or 200

    local results = {}
    local playerPos = self.position

    -- Scan all nearby objects
    for _, obj in ipairs(nearby.items) do
        local recordId = obj.recordId
        local distance = (obj.position - playerPos):length()

        if distance <= maxRange then
            -- Found a match
            results[recordId] = {
                object = obj,
                distance = distance,
            }
        end
    end

    return results
end

--- Resolve best matching mixing recipe, complexity wins
---@param scan table<string, ProximityResult>
---@param action CAction
---@param context CContext
---@return CRecipe?, CRecipe.RecipeIngredient[]?
function this.resolveRecipe(scan, action, context)
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return nil, nil
    end

    -- first get all recipes for this action and context
    local allRecipes = {} ---@type CRecipe[]
    for key, recipe in pairs(GRegistries.recipes) do
        if recipe.action == action.id and recipe.context == context.id then
            table.insert(allRecipes, recipe)
        end
    end

    -- sort by complexity (number of ingredients)
    table.sort(allRecipes, function(a, b)
        return #a.ingredients > #b.ingredients
    end)

    -- then resolve best matching recipe
    local result = nil ---@type CRecipe?
    local missing = nil ---@type CRecipe.RecipeIngredient[]?
    for _, recipe in pairs(allRecipes) do
        local hasAllIngredients = true
        local missingIngredients = {} ---@type CRecipe.RecipeIngredient[]

        for _, ingredient in pairs(recipe.ingredients) do
            local found = false
            for recordId, entry in pairs(scan) do
                if recordId:lower() == ingredient.id:lower() then
                    found = true
                    break
                end
            end

            if not found then
                hasAllIngredients = false
                table.insert(missingIngredients, ingredient)
            end
        end

        if hasAllIngredients then
            -- perfect match
            return recipe, nil
        else
            -- keep track of best partial match
            if not result or #missingIngredients < #missing then
                result = recipe
                missing = missingIngredients
            end
        end
    end


    return result, missing
end

return this
