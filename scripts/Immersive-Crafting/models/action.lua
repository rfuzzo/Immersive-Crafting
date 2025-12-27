local log = require('scripts.Immersive-Crafting.log')

---@class CAction
---@field id Id
---@field label string
---@field handler Id
local CAction = {}

---@return CAction
---@param id Id
---@param label string
---@param handler Id
function CAction:new(id, label, handler)
    local o = {
        id = id,
        label = label,
        handler = handler,
    }

    setmetatable(o, self)
    self.__index = self
    return o
end

--- Deserialize from table
---@param tbl any
---@return CAction?
function CAction:fromTable(tbl)
    -- validate input and return nil if invalid
    if not tbl.id or not tbl.label or not tbl.handler then
        log.error('Invalid CAction table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

-- tostring
---@return string
function CAction:ToString()
    return string.format("%s", self.id)
end

-- tostring
---@return string
function CAction:__tostring()
    return self:ToString()
end

-- equality
---@param other CAction
---@return boolean
function CAction:__eq(other)
    return self.id == other.id
end

return CAction
