local core = require('openmw.core')
local nearby = require('openmw.nearby')
local self = require('openmw.self')
local interfaces = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')
local sdLiquids = require('scripts.Immersive-Crafting.sdLiquids')

local this = {}

local flexTagWarned = false

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

--- Does a record id satisfy a query (a recipe ingredient id or a context entry)?
--- Two-tier: (1) exact record id, (2) FlexTag tag. No wildcard.
--- Special matcher: `sd:<liquid>` (e.g. `sd:water`, `sd:liquid` for any) —
--- Sun's Dusk dynamic bottle records, which can never be tagged (sdLiquids).
---@param recordId string an object's record id
---@param query Id a record id, FlexTag tag (e.g. "Meat", "bowl") or sd:<liquid>
---@return boolean
function this.matchesTag(recordId, query)
    -- 0. special matchers
    if query:sub(1, 3) == 'sd:' then
        return sdLiquids.matches(recordId, query:sub(4))
    end

    -- 1. exact record id (case-insensitive)
    if recordId:lower() == query:lower() then
        return true
    end

    -- 2. FlexTag tag. objectHasTag accepts a record id string and normalises case.
    local flexTag = interfaces.FlexTagL
    if flexTag and flexTag.objectHasTag then
        return flexTag.objectHasTag(recordId, query) and true or false
    elseif not flexTagWarned then
        flexTagWarned = true
        log.warn('FlexTag (I.FlexTagL) unavailable; matching limited to exact record ids')
    end

    return false
end

--- Does this station (context) offer this recipe? A recipe belongs to the
--- context naming it; a context's `inherits` list additionally pulls in
--- another context's recipes — entries are a context id string, or
--- `{ context = <id>, exclude = { <recipe ids> } }` to leave some out
--- (e.g. the kiln inherits the firepit's molds but not its food).
---@param context CContext
---@param recipe { context: Id, id: Id }
---@return boolean
function this.contextHasRecipe(context, recipe)
    if recipe.context == context.id then return true end
    for _, inh in ipairs(context.inherits or {}) do
        local fromId = type(inh) == 'table' and inh.context or inh
        if recipe.context == fromId then
            local excluded = false
            for _, ex in ipairs(type(inh) == 'table' and inh.exclude or {}) do
                if ex == recipe.id then
                    excluded = true
                    break
                end
            end
            if not excluded then return true end
        end
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
        if recipe.action == action.id and this.contextHasRecipe(context, recipe) then
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
                if this.matchesTag(recordId, ingredient.id) then
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

--- Select concrete nearby objects to consume for a recipe, honouring counts.
--- Each candidate stack is allocated at most once across all ingredients.
---@param range number search range
---@param recipe CRecipe
---@return { object: any, count: integer }[]? consume list, or nil if ingredients are insufficient
function this.collectConsumption(range, recipe)
    range = range or 200
    local playerPos = self.position

    -- flat list of candidate stacks within range, each with a mutable remaining count
    local candidates = {}
    for _, obj in ipairs(nearby.items) do
        if (obj.position - playerPos):length() <= range then
            candidates[#candidates + 1] = {
                object = obj,
                recordId = obj.recordId,
                remaining = obj.count or 1,
            }
        end
    end

    local consume = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        local needed = ingredient.count or 1
        for _, cand in ipairs(candidates) do
            if needed <= 0 then break end
            if cand.remaining > 0 and this.matchesTag(cand.recordId, ingredient.id) then
                local take = math.min(cand.remaining, needed)
                cand.remaining = cand.remaining - take
                needed = needed - take
                consume[#consume + 1] = { object = cand.object, count = take }
            end
        end
        if needed > 0 then
            return nil -- not enough of this ingredient nearby
        end
    end

    return consume
end

--- Craft at the given context: resolve the recipe, collect its ingredients, and
--- dispatch the mutation to the GLOBAL commit executor (D1). Player scripts cannot
--- mutate the world/inventory, so the actual consume + produce runs in init.lua.
---@param ctx HandlerContext
---@param range number?
---@return string message user-facing result
function this.commitRecipe(ctx, range)
    range = range or 200

    local scan = this.scanNearbyIngredients(range)
    local recipe = this.resolveRecipe(scan, ctx.action, ctx.context)
    if not recipe then
        return "Nothing to make here"
    end

    local consume = this.collectConsumption(range, recipe)
    if not consume then
        return "Not enough ingredients"
    end

    core.sendGlobalEvent('ImmersiveCrafting_Commit', {
        consume = consume,
        output = recipe.output,
        actor = self.object,
    })

    return "Made " .. (recipe.label or recipe.id)
end

return this
