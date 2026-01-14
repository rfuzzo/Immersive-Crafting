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

-- Configuration
local updateInterval = 0.25 -- Check for nearby context every 0.25 seconds

local this = {}

-- State variables
this.timeSinceLastUpdate = 0 ---@type number

local currentContext = nil ---@type CContext?
local currentActions = {} ---@type CAction[]?
local overlayElement = nil

---Create or update the overlay UI element
local function updateOverlayUI()
    -- Destroy existing overlay if present
    if overlayElement then
        overlayElement:destroy()
        overlayElement = nil
    end

    if not currentActions then return end
    if not currentContext then return end

    log.trace('Updating contextual overlay UI')

    -- Create the overlay container
    local overlay = {
        type = ui.TYPE.Container,
        layer = 'HUD',
        name = "contextualOverlay",
        template = I.MWUI.templates.boxTransparent,
        props = {
            -- position: upper right corner
            relativePosition = util.vector2(1, 0),
            anchor = util.vector2(1, 0)
        },
        content = ui.content {}
    }

    local mainSizer = {
        type = ui.TYPE.Flex,
        name = 'mainLayout',
        props = { size = util.vector2(220, 100) },
        content = ui.content {}
    }
    overlay.content:add(mainSizer)

    for _, action in pairs(currentActions) do
        -- render the viewmodel
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            ---@type HandlerContext
            local ctx =
            {
                action = action,
                context = currentContext
            }
            local viewModel = handler:present(ctx)

            if viewModel then
                -- render the viewmodel

                log.trace('Rendering overlay for action: ' .. action.id)

                -- first the header
                local headerSizer = {
                    type = ui.TYPE.Container,
                    template = I.MWUI.templates.padding,
                    props = {
                        anchor = util.vector2(0.5, 0),
                        relativePosition = util.vector2(0.5, 0)
                    },
                    content = ui.content {}
                }
                local stationNameWidget = {
                    type = ui.TYPE.Text,
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = viewModel.header,
                        textAlignH = ui.ALIGNMENT.Center
                    }
                }
                headerSizer.content:add(stationNameWidget)
                mainSizer.content:add(headerSizer)

                -- line break
                mainSizer.content:add({
                    type = ui.TYPE.Image,
                    template = I.MWUI.templates.horizontalLine,
                    props = { size = util.vector2(200, 2) }
                })

                -- then the status
                if viewModel.status then
                    local statusWidget = {
                        type = ui.TYPE.Text,
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "Status: " .. viewModel.status,
                            textAlignH = ui.ALIGNMENT.Start
                        }
                    }
                    mainSizer.content:add(statusWidget)

                    -- line break
                    mainSizer.content:add({
                        type = ui.TYPE.Image,
                        template = I.MWUI.templates.horizontalLine,
                        props = { size = util.vector2(200, 2) }
                    })
                end

                -- the action
                if viewModel.action then
                    local buttonSizer = {
                        type = ui.TYPE.Container,
                        template = I.MWUI.templates.boxSolid,
                        props = { autoSize = true, horizontal = true },
                        content = ui.content {}
                    }

                    local template = I.MWUI.templates.textButtonNormal
                    if not viewModel.action.enabled then
                        template = I.MWUI.templates.disabled
                    end
                    local button = {
                        type = ui.TYPE.Text,
                        template = template,
                        props = {
                            text = 'Press [F] to ' .. viewModel.action.label,
                            textSize = 20,
                            relativePosition = util.vector2(0, 0)
                        }
                    }

                    buttonSizer.content:add(button)
                    mainSizer.content:add(buttonSizer)
                end


                -- then details if any
                if viewModel.details then
                    for _, detail in pairs(viewModel.details) do
                        local detailWidget = {
                            type = ui.TYPE.Text,
                            template = I.MWUI.templates.textNormal,
                            props = {
                                text = detail,
                                textAlignH = ui.ALIGNMENT.Start
                            }
                        }
                        mainSizer.content:add(detailWidget)
                    end
                end
            end
        else
            log.error('No handler found for action: ' .. action.id)
        end
    end

    -- Create and store the overlay element
    overlayElement = ui.create(overlay)
    overlayElement:update()
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

    log.trace('Registered overlay action: ' .. action.id)

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

    -- for all actions
    for _, action in pairs(currentActions or {}) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            handler:OnActivate()
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
