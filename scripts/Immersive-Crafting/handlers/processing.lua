local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local CraftingGrid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local log = require('scripts.Immersive-Crafting.log')

---@class CProcessingHandler : CAbstractHandler
local CProcessingHandler = {

}
setmetatable(CProcessingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CProcessingHandler:evaluate(ctx)
    ---@type ViewModel
    local vm = {
        status = "Processing station",
        action = {
            id = "processing",
            label = "Use " .. (ctx.context.label or "station"),
            enabled = true,
        }
    }
    return vm
end

---@param ctx HandlerContext
function CProcessingHandler:OnActivate(ctx)
    -- The window picks its layout from ctx.context.layout, so the same handler
    -- serves grid and process stations.
    log.info("Toggling crafting window for " .. (ctx.context.id or "?"))
    CraftingGrid.toggle(ctx)
end

--#endregion


return CProcessingHandler
