-- Central registry tables (populated by loaders)
---@alias Id string

---@class ActionResult
---@field id Id
---@field min integer
---@field max integer
---@field chance number

---@class ActionDef
---@field id Id
---@field label string
---@field contexts string[]
---@field holdSeconds number
---@field timeCostHours number
---@field results table<string, ActionResult[]>

---@class StationDef
---@field id Id
---@field mode string "shaped", "contextual", or "process"
---@field recordIds string[]|nil List of game object record IDs that act as this station
---@field gridSize string|nil For shaped: "2x2", "3x3", etc
---@field proximityRange number|nil Distance in units to detect station (default 150)
---@field scan table|nil
---@field uiTemplate Id
---@field process Id|nil

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
