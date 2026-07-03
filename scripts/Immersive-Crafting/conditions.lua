--[[
    Named condition predicates for `trigger:"condition"` contexts.

    JSON data can't express arbitrary predicates, so a condition context names
    one of these by id (`condition` field), e.g. digging clay:

        { "id": "forage_clay", "trigger": "condition", "condition": "near_water", ... }

    Runs in the PLAYER context (uses openmw.self).
]]

local self = require('openmw.self')

local log = require('scripts.Immersive-Crafting.log')

local this = {}

local registry = {} ---@type table<string, fun(): boolean>

--- In/near water: the player's z is within a band around the cell's water
--- level (standing in the shallows or on the waterline). Cells without water
--- have no water level. Margins are a first guess — tune in-game.
registry.near_water = function()
    local cell = self.cell
    if not cell then return false end
    local waterLevel = cell.waterLevel
    if waterLevel == nil then return false end
    local dz = self.position.z - waterLevel
    return dz > -64 and dz < 128
end

--- Evaluate a named condition (false on unknown names or predicate errors).
---@param name string
---@return boolean
function this.check(name)
    local predicate = registry[name]
    if not predicate then
        log.error('Unknown condition: ' .. tostring(name))
        return false
    end
    local ok, result = pcall(predicate)
    return ok and result == true
end

--- Register a custom condition (extension point for more predicates).
---@param name string
---@param fn fun(): boolean
function this.register(name, fn)
    registry[name] = fn
end

return this
