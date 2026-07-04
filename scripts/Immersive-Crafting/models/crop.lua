local log = require('scripts.Immersive-Crafting.log')

---A farmable crop (Phase 1: planter farming). The SEED is the produce itself
---(vegetable = seed, ratified): planting consumes one item matching `seed`.
---The growing plant is a single spawned world object (`plant`, normally the
---crop's vanilla flora container record) scaled up over `growTime`; harvest is
---activating the ripe plant. `regrow` makes a crop perennial.
---@class CCrop
---@field id Id registry key
---@field label string display name (card + messages)
---@field seed string record id or FlexTag tag of the plantable item (consumed on planting)
---@field plant string record id of the spawned growing plant (vanilla flora record)
---@field growTime number game seconds from planting to ripe (3600 = 1 game hour)
---@field yield { id: string, count: integer } granted on harvest
---@field regrow number|nil perennial: game seconds to regrow after harvest; nil = annual (plant removed)
local CCrop = {}

--- Deserialize from table
---@param tbl any
---@return CCrop?
function CCrop:fromTable(tbl)
    if
        not tbl.id
        or not tbl.label
        or not tbl.seed
        or not tbl.plant
        or not tbl.growTime
        or not tbl.yield then
        log.error('Invalid CCrop table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

---@return string
function CCrop:ToString() return string.format("%s", self.id) end

---@return string
function CCrop:__tostring() return self:ToString() end

---@param other CCrop
---@return boolean
function CCrop:__eq(other) return self.id == other.id end

return CCrop
