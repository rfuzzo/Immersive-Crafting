local log = require('scripts.Immersive-Crafting.log')

---A positional (shaped) crafting recipe. The `pattern` rows are matched against
---the crafting grid; each non-space character is looked up in `key` to a record
---id or FlexTag tag. `tools` are required (from inventory) but sit outside the grid.
---@class CShapedRecipe
---@field id Id registry key
---@field label string display name of the result
---@field context Id must match a context id (a crafting station)
---@field action Id must match an action id (e.g. "shaping")
---@field pattern string[] grid rows; each char is a key symbol, space = empty cell
---@field key table<string, string> symbol -> record id or FlexTag tag
---@field tools string[]|nil tool tags/ids required in inventory (outside the grid)
---@field returned { id: string, count: integer }[]|nil placed cells that are NOT consumed — given back on craft (reusable molds); ids also appear in pattern/key
---@field output { id: string, count: integer }|nil produced item (real record). Omitted for sdMeal recipes.
---@field sdMeal CRecipe.SdMeal|nil Sun's Dusk meal output (SunsDusk_createStew; requires SD)
local CShapedRecipe = {}

--- Deserialize from table
---@param tbl any
---@return CShapedRecipe?
function CShapedRecipe:fromTable(tbl)
    if
        not tbl.id
        or not tbl.label
        or not tbl.context
        or not tbl.action
        or not tbl.pattern
        or not tbl.key
        or not (tbl.output or tbl.sdMeal) then
        log.error('Invalid CShapedRecipe table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

---@return string
function CShapedRecipe:ToString() return string.format("%s", self.id) end

---@return string
function CShapedRecipe:__tostring() return self:ToString() end

---@param other CShapedRecipe
---@return boolean
function CShapedRecipe:__eq(other) return self.id == other.id end

return CShapedRecipe
