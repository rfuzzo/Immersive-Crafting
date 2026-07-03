--[[
    Contextual Overlay UI Module

    This module manages the contextual overlay UI that appears when the player is near
    an interactive crafting station. It displays available actions and their statuses.

    It provides functions to register actions, clear actions, and update the overlay UI.

    Example Overlay Layout:

    ┌─────────────────────────────┐
    │ Mixing Bowl                 │   ← header
    │                             │
    │ Ready                       │   ← status
    │                             │
    │ [F] Mix Dough               │   ← action (if enabled)
    │                             │
    │ Missing: Water              │   ← details (optional)
    └─────────────────────────────┘
]]

-- Module imports
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local async = require('openmw.async')
local input = require('openmw.input')

local dataManager = require('scripts.Immersive-Crafting.dataManager')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')
local c = require('scripts.Immersive-Crafting.ui.components')

local v2 = util.vector2

-- Configuration
local updateInterval = 0.25 -- Check for nearby context every 0.25 seconds

-- Position: lower-right, card top at ~3/4 screen height, growing downward.
local OVERLAY_POS = v2(0.99, 0.75)
local OVERLAY_ANCHOR = v2(1, 0)
local LINE_W = 190

local this = {}

-- State variables
this.timeSinceLastUpdate = 0 ---@type number

local currentContext = nil ---@type CContext?
local currentActions = {} ---@type CAction[]?
local overlayElement = nil

--- Thin separator line.
local function hLine()
    return {
        type = ui.TYPE.Image,
        template = I.MWUI.templates.horizontalLine,
        props = { size = v2(LINE_W, 2) },
    }
end

--- Build one action card's rows from its ViewModel.
---@param viewModel ViewModel
---@param rows table[] target list
local function renderViewModel(viewModel, rows)
    -- header: station name
    if viewModel.header then
        rows[#rows + 1] = c.text({ text = viewModel.header, template = I.MWUI.templates.textHeader })
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 3) } })
        rows[#rows + 1] = hLine()
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 4) } })
    end

    -- status
    if viewModel.status then
        rows[#rows + 1] = c.text({ text = viewModel.status })
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 3) } })
    end

    -- action hint: "[F] <label>" (gold when enabled)
    if viewModel.action then
        local template = viewModel.action.enabled
            and I.MWUI.templates.textHeader
            or I.MWUI.templates.textNormal
        rows[#rows + 1] = c.text({ text = ('[F] %s'):format(viewModel.action.label), template = template })
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 3) } })
    end

    -- details (e.g. "Missing: Water", input roles)
    for _, detail in ipairs(viewModel.details or {}) do
        rows[#rows + 1] = c.text({ text = detail })
    end
end

---Create or update the overlay UI element
local function updateOverlayUI()
    -- Destroy existing overlay if present
    if overlayElement then
        overlayElement:destroy()
        overlayElement = nil
    end

    if not currentActions then return end
    if not currentContext then return end

    local rows = {}
    for _, action in pairs(currentActions) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            ---@type HandlerContext
            local ctx = { action = action, context = currentContext }
            local viewModel = handler:present(ctx)
            if viewModel then
                if #rows > 0 then -- separate stacked actions
                    rows[#rows + 1] = c.spacer({ props = { size = v2(0, 8) } })
                    rows[#rows + 1] = hLine()
                    rows[#rows + 1] = c.spacer({ props = { size = v2(0, 8) } })
                end
                renderViewModel(viewModel, rows)
            end
        else
            log.error('No handler found for action: ' .. action.id)
        end
    end
    if #rows == 0 then return end

    -- auto-sized card: transparent box + padding + vertical flex
    overlayElement = ui.create({
        layer = 'HUD',
        name = 'contextualOverlay',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = OVERLAY_POS,
            anchor = OVERLAY_ANCHOR,
        },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    c.column({ name = 'overlay_rows', children = rows }),
                },
            },
        },
    })
end

--#region Public API

---Register an action that should be shown in the overlay
---@param context CContext
---@param action CAction?
function this.registerAction(context, action)
    if not action then
        log.error('Cannot register nil action to overlay')
        return
    end

    currentContext = context
    if not currentActions then currentActions = {} end
    table.insert(currentActions, action)

    -- log.trace('Registered overlay action: ' .. action.id)

    updateOverlayUI()
end

---Clear all registered actions
function this.clearAllActions()
    currentActions = nil
    currentContext = nil

    updateOverlayUI()
end

--#endregion

--#region Events

function this.onContextualAction()
    -- early outs
    if not overlayElement then return end
    if not currentContext then return end
    if not currentActions then return end

    -- Activate-triggered stations are opened by activating the object, not [F];
    -- their overlay card is info-only.
    if currentContext.trigger == 'activate' then return end

    -- for all actions
    for _, action in pairs(currentActions or {}) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            ---@type HandlerContext
            local ctx = {
                action = action,
                context = currentContext
            }
            handler:OnActivate(ctx)
        end
    end
end

--#endregion

--#region Parent

---Main update function called every frame
function this.onUpdate(dt)
    -- Periodically update UI
    this.timeSinceLastUpdate = this.timeSinceLastUpdate + dt
    if this.timeSinceLastUpdate >= updateInterval then
        updateOverlayUI()
        this.timeSinceLastUpdate = 0
    end


    -- delegate to handlers
    for _, action in pairs(currentActions or {}) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            handler:onUpdate(dt)
        end
    end
end

--#endregion

return this
