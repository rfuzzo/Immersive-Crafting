local log = require('scripts.Immersive-Crafting.log')

---@class CAction
---@field id Id
---@field mode Id
---@field uiTemplate Id
---@field inputAction Id?
local CAction = {}

---@return CAction
---@param id Id
---@param mode string
---@param uiTemplate Id
---@param inputAction string
function CAction:new(id, mode, uiTemplate, inputAction)
    local o = {
        id = id,
        mode = mode,
        uiTemplate = uiTemplate,
        inputAction = inputAction
    } -- create object if user does not provide one

    setmetatable(o, self)
    self.__index = self
    return o
end

--- Deserialize from table
---@param tbl any
---@return CAction?
function CAction:fromTable(tbl)
    -- validate input and return nil if invalid
    if not tbl.id or not tbl.mode or not tbl.uiTemplate or not tbl.inputAction then
        log.error('Invalid CAction table: missing required fields')
        return nil
    end

    return CAction:new(
        tbl.id,
        tbl.mode,
        tbl.uiTemplate,
        tbl.inputAction
    )
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
