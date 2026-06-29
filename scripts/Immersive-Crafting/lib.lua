local core = require('openmw.core')
local nearby = require('openmw.nearby')
local self = require('openmw.self')
local interfaces = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')

local this = {}

local taggerWarned = false

---@class IngredientScanResult
---@field object any nearest object instance of this record id
---@field distance number distance to the nearest such object
---@field count integer total stack count within range (summed across stacks)

function this.len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---Find all nearby ingredient items within range, keyed by record id.
---Stacks of the same record id are merged and their counts summed.
---@param maxRange number Maximum search range
---@return table<string, IngredientScanResult> Map of record id to scan result
function this.scanNearbyIngredients(maxRange)
    maxRange = maxRange or 200

    local results = {}
    local playerPos = self.position

    -- Scan all nearby objects
    for _, obj in ipairs(nearby.items) do
        local recordId = obj.recordId
        local distance = (obj.position - playerPos):length()

        if distance <= maxRange then
            local entry = results[recordId]
            if entry then
                entry.count = entry.count + (obj.count or 1)
                if distance < entry.distance then
                    entry.object = obj
                    entry.distance = distance
                end
            else
                results[recordId] = {
                    object = obj,
                    distance = distance,
                    count = obj.count or 1,
                }
            end
        end
    end

    return results
end

--- Does a nearby object's record id satisfy a recipe ingredient id?
--- Two-tier: (1) exact record id, (2) Tagger tag (S3cret St4sh). No wildcard.
---@param recordId string nearby object's record id
---@param ingredientId Id recipe ingredient id (a record id or a Tagger tag)
---@return boolean
function this.matchesIngredient(recordId, ingredientId)
    -- 1. exact record id (case-insensitive)
    if recordId:lower() == ingredientId:lower() then
        return true
    end

    -- 2. Tagger tag. objectHasTag accepts a record id string and normalises case.
    local tagger = interfaces.TaggerL
    if tagger and tagger.objectHasTag then
        return tagger.objectHasTag(recordId, ingredientId) and true or false
    elseif not taggerWarned then
        taggerWarned = true
        log.warn('Tagger (I.TaggerL) unavailable; ingredient matching limited to exact record ids')
    end

    return false
end

--- Format a missing-ingredient list into a human-readable string (e.g. "Meat, Water x2").
---@param missing CRecipe.RecipeIngredient[]
---@return string
function this.formatMissing(missing)
    local parts = {}
    for _, ing in ipairs(missing) do
        local count = ing.count or 1
        parts[#parts + 1] = count > 1 and (ing.id .. " x" .. count) or ing.id
    end
    return table.concat(parts, ", ")
end

--- Resolve best matching recipe for the action/context, complexity wins
---@param scan table<string, IngredientScanResult>
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
    for _, recipe in pairs(GRegistries.recipes) do
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
            local needed = ingredient.count or 1
            local available = 0
            for recordId, entry in pairs(scan) do
                if this.matchesIngredient(recordId, ingredient.id) then
                    available = available + (entry.count or 1)
                end
            end

            if available < needed then
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
