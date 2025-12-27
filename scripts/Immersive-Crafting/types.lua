-- Central registry tables (populated by loaders)
---@alias Id string

---@class ActionResult
---@field id Id
---@field min integer
---@field max integer
---@field chance number

---@class ContainerDef
---@field id Id
---@field requiresStation Id|nil
---@field process Id|nil

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

---@class ProcessDef
---@field id Id
---@field initial string
---@field states table<string, table>
