local core = require('openmw.core')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local processState = require('scripts.Immersive-Crafting.processState')
local log = require('scripts.Immersive-Crafting.log')

--- "~N min" / "~N h" of remaining GAME time.
local function fmtRemaining(readyAt)
    local seconds = math.max(0, (readyAt or 0) - core.getGameTime())
    if seconds >= 3600 then
        return ('~%d h'):format(math.ceil(seconds / 3600))
    end
    return ('~%d min'):format(math.max(1, math.ceil(seconds / 60)))
end

---@class CProcessingHandler : CAbstractHandler
local CProcessingHandler = {

}
setmetatable(CProcessingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CProcessingHandler:evaluate(ctx)
    -- a running/finished timed process owns the card
    local run = ctx.object and processState.forStation(ctx.object.id)
    if run then
        if run.done then
            ---@type ViewModel
            return {
                status = (run.label or 'Work') .. ' — ready!',
                details = { 'Activate to collect' },
            }
        end
        ---@type ViewModel
        return {
            status = (run.label or 'Working') .. ' — in progress',
            details = { 'Ready in ' .. fmtRemaining(run.readyAt) },
        }
    end

    -- Activate-triggered stations show an info-only card (opened by activating),
    -- listing the input roles so the player knows what the station needs.
    if ctx.context.trigger == 'activate' then
        local details = nil
        local inputs = ctx.context.layout and ctx.context.layout.inputs
        if inputs and #inputs > 0 then
            -- named roles (e.g. Input, Reagent) if the layout labels them;
            -- otherwise just the generic slot count
            local roles = {}
            for _, inp in ipairs(inputs) do
                if inp.label then roles[#roles + 1] = inp.label end
            end
            if #roles > 0 then
                details = { "Inputs: " .. table.concat(roles, ", ") }
            else
                details = { ("%d input slots"):format(#inputs) }
            end
        end
        ---@type ViewModel
        return {
            status = "Activate to use",
            details = details,
            action = nil,
        }
    end

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
    -- proximity stations: [F] while a run is finished collects it; while it's
    -- still working, do nothing (the card shows the remaining time). Activate
    -- stations never reach here (init.lua intercepts their activation).
    local run = ctx.object and processState.forStation(ctx.object.id)
    if run then
        if run.done then
            local omwSelf = require('openmw.self')
            core.sendGlobalEvent('ImmersiveCrafting_CollectProcess', {
                actor = omwSelf.object,
                stationId = ctx.object.id,
            })
        end
        return
    end

    -- The window picks its layout from ctx.context.layout, so the same handler
    -- serves grid and process stations.
    log.info("Toggling crafting window for " .. (ctx.context.id or "?"))
    Crafting.toggle(ctx)
end

--#endregion


return CProcessingHandler
