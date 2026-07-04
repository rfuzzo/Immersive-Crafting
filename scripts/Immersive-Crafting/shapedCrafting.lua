local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

--- Trim a 2D grid to its minimal bounding box of non-empty cells.
--- Cells are a record-id string (filled) or nil/false (empty).
---@param grid table 2D array grid[row][col]
---@return table? rows minimal sub-grid, or nil if entirely empty
local function trim(grid)
    local minR, maxR, minC, maxC = math.huge, -math.huge, math.huge, -math.huge
    for r, row in ipairs(grid) do
        for c, cell in pairs(row) do
            if cell then
                if r < minR then minR = r end
                if r > maxR then maxR = r end
                if c < minC then minC = c end
                if c > maxC then maxC = c end
            end
        end
    end
    if minR == math.huge then return nil end -- empty grid

    local out = {}
    for r = minR, maxR do
        local newRow = {}
        for c = minC, maxC do
            newRow[c - minC + 1] = (grid[r] and grid[r][c]) or nil
        end
        out[r - minR + 1] = newRow
    end
    return out
end

--- Convert a shaped recipe's pattern + key into a 2D grid of tags/ids (or nil).
---@param pattern string[]
---@param key table<string, string>
---@return table grid[row][col] = tag/id or nil
local function patternToGrid(pattern, key)
    local grid = {}
    for r, rowStr in ipairs(pattern) do
        local row = {}
        for c = 1, #rowStr do
            local ch = rowStr:sub(c, c)
            if ch ~= ' ' and ch ~= '.' then
                row[c] = key[ch] -- nil if symbol not mapped
            end
        end
        grid[r] = row
    end
    return grid
end

--- Same dimensions?
local function sameDims(a, b)
    if #a ~= #b then return false end
    for r = 1, #a do
        local aw, bw = 0, 0
        for c in pairs(a[r]) do if c > aw then aw = c end end
        for c in pairs(b[r]) do if c > bw then bw = c end end
        -- compare against the trimmed width (max column index)
        if aw ~= bw then return false end
    end
    return true
end

--- Do the trimmed item-grid and trimmed pattern-grid match cell-for-cell?
--- A filled item cell must match the pattern tag/id via lib.matchesTag; empties align.
---@param items table trimmed item grid (recordId|nil)
---@param pat table trimmed pattern grid (tag/id|nil)
---@return boolean
local function cellsMatch(items, pat)
    local rows = math.max(#items, #pat)
    for r = 1, rows do
        local irow, prow = items[r] or {}, pat[r] or {}
        local width = 0
        for c in pairs(irow) do if c > width then width = c end end
        for c in pairs(prow) do if c > width then width = c end end
        for c = 1, width do
            local item, tag = irow[c], prow[c]
            if (item and not tag) or (tag and not item) then
                return false
            elseif item and tag and not lib.matchesTag(item, tag) then
                return false
            end
        end
    end
    return true
end

--- Are all required tools present in the player's inventory?
---@param tools string[]|nil
---@return boolean
function this.hasTools(tools)
    if not tools or #tools == 0 then return true end
    local inv = types.Actor.inventory(self)
    local items = inv:getAll()
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

--- Resolve the shaped recipe matching a placed grid for this action/context.
---@param grid table 2D array grid[row][col] = recordId|nil (from the crafting UI)
---@param action CAction
---@param context CContext
---@return CShapedRecipe?
function this.resolveShapedRecipe(grid, action, context)
    if not GRegistries then
        log.error('GRegistries not initialized yet')
        return nil
    end

    local items = trim(grid)
    if not items then return nil end -- empty grid

    for _, recipe in pairs(GRegistries.shapedRecipes or {}) do
        -- Sun's Dusk meal recipes only exist when SD is loaded (soft dependency)
        local available = not recipe.sdMeal or I.SunsDusk ~= nil
        if available and recipe.action == action.id and recipe.context == context.id then
            local pat = trim(patternToGrid(recipe.pattern, recipe.key))
            if pat and sameDims(items, pat) and cellsMatch(items, pat)
                and this.hasTools(recipe.tools) then
                return recipe
            end
        end
    end

    return nil
end

return this
