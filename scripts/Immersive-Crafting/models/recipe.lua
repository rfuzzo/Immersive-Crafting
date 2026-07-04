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

---Sun's Dusk meal output (lane-B interop). The craft dispatches SD's global
---`SunsDusk_createStew` event: SD mints the meal Potion record (stat-bracket
---name, rolled buffs), consumes the recipe's ingredients AND a bowl/plate from
---the inventory, registers freshness, and grants the meal. Requires Sun's Dusk
---(recipes carrying this are hidden when I.SunsDusk is absent). Inputs must be
---Ingredient-type records — SD only consumes types.Ingredient.
---@class CRecipe.SdMeal
---@field name string meal display name (SD appends the stat bracket)
---@field icon string|nil icon path for the result slot / meal record
---@field count integer|nil meals produced (default 1)
---@field isSoup boolean|nil soup prefers bowls; solid food prefers plates
---@field category string|nil SD consume category (e.g. "Hearty Meal")
---@field food number|nil food value on SD's raw scale (e.g. 160); normalised /200 on send
---@field drink number|nil drink value (raw scale)
---@field wake number|nil wake value (raw scale)
---@field warmth number|nil warmth value (NOT /200-scaled)
---@field sdRecipeId string|nil optional SD cooking recipe id to reuse its typing
---@field virtualFoodware boolean|nil true = no bowl/plate consumed
---@field isToxic boolean|nil

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
