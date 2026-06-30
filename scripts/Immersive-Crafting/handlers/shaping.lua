local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local CraftingGrid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local log = require('scripts.Immersive-Crafting.log')

---@class CShapingHandler : CAbstractHandler
local CShapingHandler = {

}
setmetatable(CShapingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CShapingHandler:evaluate(ctx)
    local grid = ctx.context.gridSize or { 2, 2 }

    ---@type ViewModel
    local vm = {
        status = ("Crafting grid %dx%d"):format(grid[1] or 2, grid[2] or 2),
        action = {
            id = "shaping",
            label = "Toggle crafting grid",
            enabled = true,
        }
    }
    return vm
end

---@param ctx HandlerContext
function CShapingHandler:OnActivate(ctx)
    -- Toggle the interactive crafting grid with the contextual action key.
    log.info("Toggling crafting grid for " .. (ctx.context.id or "?"))
    CraftingGrid.toggle(ctx)
end

--#endregion


return CShapingHandler
