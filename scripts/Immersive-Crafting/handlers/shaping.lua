local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local log = require('scripts.Immersive-Crafting.log')

local ui = require('openmw.ui')

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
    --[[ TODO (Phase 2): open the interactive crafting grid UI for ctx.context.gridSize.
    On "Craft":
      * read the placed cells into a grid (recordId|nil)
      * shapedCrafting.resolveShapedRecipe(grid, ctx.action, ctx.context)
      * consume the placed items from inventory + grant output via the global commit
    ]]
    log.info("Shaping activated (crafting grid UI pending - Phase 2)")
    ui.showMessage("Crafting grid UI coming soon")
end

--#endregion


return CShapingHandler
