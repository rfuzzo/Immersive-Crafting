local log = require('scripts.Immersive-Crafting.log')

---@class CContext
---@field id Id
---@field recordIds string[] List of game object record IDs that act as this station
---@field activationRange number|nil Distance in units to detect station (default 150)
---@field actions CAction|Id[] List of actions available at this station
local CContext = {}

---@return CContext
---@param id Id
---@param recordIds string[]
---@param activationRange number|nil
---@param actions CAction|Id[]
function CContext:new(id, recordIds, activationRange, actions)
    local o = {
        id = id,
        recordIds = recordIds,
        activationRange = activationRange,
        actions = actions
    } -- create object if user does not provide one

    setmetatable(o, self)
    self.__index = self
    return o
end

--- Deserialize from table
---@param tbl any
---@return CContext?
function CContext:fromTable(tbl)
    -- validate input and return nil if invalid
    if not tbl.id or not tbl.recordIds or not tbl.activationRange or not tbl.actions then
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
