-- Define the CAbstractHandler class
---@class CAbstractHandler
local CAbstractHandler = {}


---@class HandlerContext
---@field action CAction
---@field context CContext

-- Constructor
---@return CAbstractHandler
function CAbstractHandler:new()
    -----@type CAbstractHandler
    local newObj = {

    }
    setmetatable(newObj, self)
    self.__index = self
    return newObj
end

--- Presents the viewModel
---@param ctx HandlerContext
---@return ViewModel?
function CAbstractHandler:present(ctx)
    local result = self:evaluate(ctx)
    if result then
        ---@type ViewModel
        local viewModel = {
            header = ctx.context.label,

            status = result.status,
            details = result.details,
            action = result.action,
            progress = result.progress,
        }

        return viewModel
    end

    return nil
end

-- Method to update the state
function CAbstractHandler:onUpdate(dt)
    -- override in child classes
end

-- ---- To be implemented by concrete handlers ----

---@param ctx HandlerContext
---@return ViewModel
function CAbstractHandler:evaluate(ctx)
    error("CAbstractHandler:evaluate(ctx) must be implemented by subclass")
end

function CAbstractHandler:OnActivate()
    error("CAbstractHandler:OnActivate(ctx) must be implemented by subclass")
end

-- Return the CAbstractHandler class
return CAbstractHandler
