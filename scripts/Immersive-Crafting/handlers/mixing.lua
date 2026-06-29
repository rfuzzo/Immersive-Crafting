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
            local parts = {}
            for _, ing in ipairs(missing) do
                local count = ing.count or 1
                parts[#parts + 1] = count > 1 and (ing.id .. " x" .. count) or ing.id
            end
            details = {
                "Missing: " .. table.concat(parts, ", ")
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

function CMixingHandler:OnActivate()
    --[[ TODO Implement mixing cooking
    * Check for ingredients and possibility should happen before
    * This just produces the output
    * Remove ingredients from world
    * Add output item to inventory
    ]]

    log.info("Mixing action activated")

    -- placeholder message
    ui.showMessage("Mixing action activated - to be implemented")
end

--#endregion


return CMixingHandler
