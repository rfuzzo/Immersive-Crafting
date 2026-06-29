local log = require('scripts.Immersive-Crafting.log')

---@class CRecipe
---@field id Id
---@field label string
---@field context Id
---@field action Id
---@field ingredients CRecipe.RecipeIngredient[]
---@field cookTime number? cooking-only; seconds for the simmer/cook process. Omitted for instant crafting.
---@field output table
local CRecipe = {}

---@class CRecipe.RecipeIngredient
---@field id Id
---@field count integer

--- Deserialize from table
---@param tbl any
---@return CRecipe?
function CRecipe:fromTable(tbl)
    -- validate input and return nil if invalid
    -- cookTime is intentionally optional: it is a cooking-only field, so
    -- crafting/mixing recipes legitimately omit it.
    if
        not tbl.id
        or not tbl.context
        or not tbl.label
        or not tbl.action
        or not tbl.ingredients
        or not tbl.output then
        log.error('Invalid CRecipe table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

-- tostring
---@return string
function CRecipe:ToString()
    return string.format("%s", self.id)
end

-- tostring
---@return string
function CRecipe:__tostring()
    return self:ToString()
end

-- equality
---@param other CRecipe
---@return boolean
function CRecipe:__eq(other)
    return self.id == other.id
end

return CRecipe
