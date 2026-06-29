local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local ui = require('openmw.ui')

---@class CCookingHandler : CAbstractHandler
local CCookingHandler = {

}
setmetatable(CCookingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CCookingHandler:evaluate(ctx)
    -- 1. Scan nearby ingredients
    local scan = lib.scanNearbyIngredients(200)

    -- 2. Resolve best matching cooking recipe
    local recipe, missing = lib.resolveRecipe(scan, ctx.action, ctx.context)

    -- 3. No valid recipe
    if not recipe then
        local details = nil
        if missing and #missing > 0 then
            details = {
                "Missing: " .. lib.formatMissing(missing)
            }
        end

        ---@type ViewModel
        local vm = {
            status = "Nothing to cook",
            details = details,
            action = nil,
        }

        return vm
    end

    -- 4. Valid recipe found
    ---@type ViewModel
    local vm = {
        status = "Ready",
        action = {
            id = "cooking",
            label = "Cook " .. recipe.label,
            enabled = true,
        }
    }
    return vm
end

function CCookingHandler:OnActivate()
    --[[ TODO (Cooking phase): consume ingredients + start the cook process
    * cookTime / "requires" heat -> surface progress via ViewModel.progress
    * produce output via the global commit executor
    ]]

    log.info("Cooking action activated")

    -- placeholder message
    ui.showMessage("Cooking action activated - to be implemented")
end

--#endregion


return CCookingHandler
