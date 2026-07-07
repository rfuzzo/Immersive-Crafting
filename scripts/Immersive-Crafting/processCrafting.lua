local I = require('openmw.interfaces')

local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

-- batching: a placement holding k exact input sets matches as ONE run of k
-- batches (output xk). Each extra batch adds a fraction of the base duration —
-- firing four pots together beats four firings, that's the point of a kiln.
local MAX_BATCH = 64
local BATCH_TIME_FACTOR = 0.5

--- The recipe's fuel requirement in burn units per batch (0 = no fuel line).
--- Fuel lines are `{ "fuel": N }` inputs: no record/tag — ANY fuel-valued item
--- (lib.fuelValue > 0) feeds them, wood and charcoal alike.
---@param inputs CProcessRecipe.Input[]
---@return number
local function fuelNeedOf(inputs)
    for _, line in ipairs(inputs or {}) do
        if line.fuel then return line.fuel end
    end
    return 0
end

--- Try to match the placed items against k batches of the recipe's inputs.
--- Normal lines claim count*k items (greedy tag claiming, as before);
--- `returned` lines claim count ONCE (a reusable mold serves the whole batch);
--- the fuel requirement claims fuel-valued items LARGEST-VALUE-FIRST until
--- fuel*k units are covered — only the claimed subset burns. Leftover placed
--- items fail the match UNLESS the recipe has a fuel line and the leftovers
--- are fuel (excess fuel is allowed and never consumed: overfilling the fire
--- is how fires work, not an error).
--- NOTE: greedy line-order claiming; with heavily overlapping tags a
--- pathological assignment could fail where a perfect matching exists —
--- acceptable for now (same caveat as the old exact matcher).
---@param placedIds string[] record ids, one per placed unit (stacks expanded)
---@param inputs CProcessRecipe.Input[]
---@param k integer batch count to try
---@return table<string, integer>? claimedCounts record id -> units consumed (nil = no match)
local function tryMatch(placedIds, inputs, k)
    local claimed = {}

    -- 1. normal + returned lines (exact, scaled by k; returned lines once)
    for _, line in ipairs(inputs) do
        if not line.fuel then
            local need = (line.count or 1) * (line.returned and 1 or k)
            for i, recordId in ipairs(placedIds) do
                if need <= 0 then break end
                if not claimed[i] and lib.matchesTag(recordId, line.id) then
                    claimed[i] = true
                    need = need - 1
                end
            end
            if need > 0 then return nil end
        end
    end

    -- 2. fuel: claim the minimal covering subset, largest value first
    local fuelNeed = fuelNeedOf(inputs) * k
    if fuelNeed > 0 then
        local candidates = {}
        for i, recordId in ipairs(placedIds) do
            if not claimed[i] then
                local v = lib.fuelValue(recordId)
                if v > 0 then candidates[#candidates + 1] = { i = i, value = v } end
            end
        end
        table.sort(candidates, function(a, b) return a.value > b.value end)
        for _, cand in ipairs(candidates) do
            if fuelNeed <= 0 then break end
            claimed[cand.i] = true
            fuelNeed = fuelNeed - cand.value
        end
        if fuelNeed > 0 then return nil end
    end

    -- 3. leftovers: fuel recipes tolerate unclaimed FUEL (refunded); anything
    --    else unclaimed fails — consumed-but-unused items must never vanish
    local fuelRecipe = fuelNeedOf(inputs) > 0
    for i, recordId in ipairs(placedIds) do
        if not claimed[i] then
            if not (fuelRecipe and lib.fuelValue(recordId) > 0) then return nil end
        end
    end

    local counts = {}
    for i in pairs(claimed) do
        local id = placedIds[i]
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

--- Upper bound for the batch count: the scarcest normal line caps k (fuel is
--- bounded by total placed burn value). Bounds only — tryMatch verifies.
---@param placedIds string[]
---@param inputs CProcessRecipe.Input[]
---@return integer
local function batchBound(placedIds, inputs)
    local kMax = MAX_BATCH
    for _, line in ipairs(inputs or {}) do
        if not line.fuel and not line.returned then
            local have = 0
            for _, recordId in ipairs(placedIds) do
                if lib.matchesTag(recordId, line.id) then have = have + 1 end
            end
            kMax = math.min(kMax, math.floor(have / (line.count or 1)))
        elseif line.fuel then
            local total = 0
            for _, recordId in ipairs(placedIds) do
                total = total + lib.fuelValue(recordId)
            end
            kMax = math.min(kMax, math.floor(total / line.fuel))
        end
    end
    return math.max(kMax, 0)
end

--- Wrap a matched recipe as a BATCH MATCH: reads fall through to the recipe
--- (id, label, tools, inputs, ...), while `output`/`duration` are the k-scaled
--- values and `claimedCounts` is exactly what a craft consumes (excess fuel is
--- simply never claimed, so it is never consumed — the refund is implicit).
---@param recipe CProcessRecipe
---@param k integer
---@param claimedCounts table<string, integer>
---@return table match
local function makeMatch(recipe, k, claimedCounts)
    local match = {
        batch = k,
        claimedCounts = claimedCounts,
        output = recipe.output and {
            id = recipe.output.id,
            count = (recipe.output.count or 1) * k,
        } or nil,
        duration = (recipe.duration and recipe.duration > 0)
            and math.floor(recipe.duration * (1 + BATCH_TIME_FACTOR * (k - 1)))
            or recipe.duration,
    }
    return setmetatable(match, { __index = recipe })
end

--- Resolve ALL process recipes matching the placed items for this action/context.
--- Non-positional: only the multiset of placed items matters. Each recipe
--- matches at its LARGEST possible batch count (k input sets placed = one run
--- of k batches); several recipes may still claim the same multiset (bonemold
--- helm vs boots) — the UI cycles through the matches. Sorted by id for a
--- stable order.
--- NOTE: matching is by INPUTS only — whether the recipe's `tools` are
--- satisfied is the UI's job (tools ⊆ the window's slotted tools).
---@param placedIds string[] record ids of the placed items (one per filled slot unit)
---@param action CAction
---@param context CContext
---@return table[] all matches (empty if none) — batch-match proxies over CProcessRecipe
function this.resolveProcessRecipes(placedIds, action, context)
    local matches = {}
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return matches
    end
    if #placedIds == 0 then return matches end

    for _, recipe in pairs(GRegistries.processRecipes or {}) do
        -- Sun's Dusk meal recipes only exist when SD is loaded (soft dependency)
        local available = not recipe.sdMeal or I.SunsDusk ~= nil
        if available and recipe.action == action.id and lib.contextHasRecipe(context, recipe) then
            -- SD meals are minted one at a time by SD itself — never batched
            local kMax = recipe.sdMeal and 1 or batchBound(placedIds, recipe.inputs)
            for k = math.max(kMax, 1), 1, -1 do
                local claims = tryMatch(placedIds, recipe.inputs, k)
                if claims then
                    matches[#matches + 1] = makeMatch(recipe, k, claims)
                    break
                end
            end
        end
    end

    table.sort(matches, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return matches
end

return this
