local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local ui = require('openmw.ui')

---@class CMixingHandler : CAbstractHandler
local CMixingHandler = {

}
setmetatable(CMixingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CMixingHandler:evaluate(ctx)
    -- 1. Scan nearby ingredients
    -- TODO range param?
    local scan = lib.scanNearbyIngredients(200)

    -- 2. Resolve best matching mixing recipe
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
            status = "No valid mixture",
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
            id = "mixing",
            label = "Mix " .. recipe.label,
            enabled = true,
        }
    }
    return vm
end

---@param ctx HandlerContext
function CMixingHandler:OnActivate(ctx)
    -- Re-resolve + dispatch the consume/produce to the global commit executor.
    local message = lib.commitRecipe(ctx)
    log.info(message)
    ui.showMessage(message)
end

--#endregion


return CMixingHandler
