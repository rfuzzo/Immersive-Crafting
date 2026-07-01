local log = require('scripts.Immersive-Crafting.log')

---@class CContext
---@field id Id
---@field label string
---@field recordIds string[] Record ids OR Tagger tags that identify this station (e.g. "bowl")
---@field requires string[]|nil Extra Tagger tags that must also be present nearby (e.g. "fire")
---@field layout CContext.Layout|nil UI layout for the crafting window (grid or process). Falls back to `gridSize`, then a 2x2 grid.
---@field activationRange number|nil Distance in units to detect station (default 150)
---@field actions CAction[]|Id[] List of actions available at this station
local CContext = {}

---@class CContext.Layout
---@field kind string "grid" | "process"
---@field size integer[]|nil grid layouts: `[cols, rows]`
---@field inputs CContext.SlotDef[]|nil process layouts: ordered named input slots

---@class CContext.SlotDef
---@field key string slot id, matched against a process recipe's `inputs` key (e.g. "fuel", "input")
---@field label string|nil label shown above the slot

--- Deserialize from table
---@param tbl any
---@return CContext?
function CContext:fromTable(tbl)
    -- validate input and return nil if invalid
    if
        not tbl.id
        or not tbl.label
        or not tbl.recordIds
        or not tbl.actions then
        log.error('Invalid CContext table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

-- tostring
---@return string
function CContext:ToString()
    return string.format("%s", self.id)
end

-- tostring
---@return string
function CContext:__tostring()
    return self:ToString()
end

-- equality
---@param other CContext
---@return boolean
function CContext:__eq(other)
    return self.id == other.id
end

return CContext
