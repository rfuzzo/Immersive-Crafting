local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local stationPack = require('scripts.Immersive-Crafting.stationPack')
local log = require('scripts.Immersive-Crafting.log')

---@class CShapingHandler : CAbstractHandler
local CShapingHandler = {

}
setmetatable(CShapingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CShapingHandler:evaluate(ctx)
    local grid = ctx.context.layout and ctx.context.layout.size or { 2, 2 }

    -- Activate-triggered stations show an info-only card (opened by activating).
    if ctx.context.trigger == 'activate' then
        ---@type ViewModel
        return {
            status = "Activate to use",
            details = { ("Crafting grid %dx%d"):format(grid[1] or 2, grid[2] or 2) },
            -- placed IC stations offer hold-F pack-up under the info card
            action = stationPack.action(ctx.object),
        }
    end

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
    -- activate-triggered stations never open the window from here (activating
    -- the object does that) — completing the hold on their card PACKS them up
    if ctx.context.trigger == 'activate' then
        if stationPack.isPackable(ctx.object) then
            stationPack.pack(ctx.object)
        end
        return
    end

    -- Toggle the interactive crafting grid with the contextual action key.
    log.info("Toggling crafting grid for " .. (ctx.context.id or "?"))
    Crafting.toggle(ctx)
end

--#endregion


return CShapingHandler
