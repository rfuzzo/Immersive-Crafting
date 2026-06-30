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
            label = "Open crafting grid",
            enabled = true,
        }
    }
    return vm
end

---@param ctx HandlerContext
function CShapingHandler:OnActivate(ctx)
    -- Open the interactive crafting grid sized to the station (ctx.context.gridSize).
    -- The grid UI handles placement, matching, and dispatching the craft.
    log.info("Opening crafting grid for " .. (ctx.context.id or "?"))
    CraftingGrid.open(ctx)
end

--#endregion


return CShapingHandler
