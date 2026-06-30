local log = require('scripts.Immersive-Crafting.log')

---A role-slot (process) recipe for stations that transform inputs over time —
---kiln/furnace/oven (fuel + input), tanning rack (ingredients + input), etc.
---Unlike shaped recipes there is no grid: each named slot (`inputs` key) must be
---filled with a matching item. `duration` is the process time in seconds (the
---timed process itself is wired separately; see docs). All placed items are
---consumed on completion.
---@class CProcessRecipe
---@field id Id registry key
---@field label string display name of the result
---@field context Id must match a context id (the station)
---@field action Id must match an action id (e.g. "processing")
---@field inputs table<string, string> slot key -> record id or Tagger tag (e.g. { fuel = "Fuel", input = "GreenWare" })
---@field duration number|nil process time in seconds (timing deferred)
---@field tools string[]|nil tool tags/ids required in inventory (outside the slots)
---@field output { id: string, count: integer } produced item (must be a real record)
local CProcessRecipe = {}

--- Deserialize from table
---@param tbl any
---@return CProcessRecipe?
function CProcessRecipe:fromTable(tbl)
    if
        not tbl.id
        or not tbl.label
        or not tbl.context
        or not tbl.action
        or not tbl.inputs
        or not tbl.output then
        log.error('Invalid CProcessRecipe table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

---@return string
function CProcessRecipe:ToString() return string.format("%s", self.id) end

---@return string
function CProcessRecipe:__tostring() return self:ToString() end

---@param other CProcessRecipe
---@return boolean
function CProcessRecipe:__eq(other) return self.id == other.id end

return CProcessRecipe
