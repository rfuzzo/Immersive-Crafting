-- Central registry tables (populated by loaders)
---@alias Id string

---@class RecipeIngredient
---@field id Id
---@field count integer

---@class RecipeDef
---@field id Id
---@field station Id|nil
---@field container Id|nil
---@field ingredients RecipeIngredient[]
---@field cookTime number|nil
---@field output table
