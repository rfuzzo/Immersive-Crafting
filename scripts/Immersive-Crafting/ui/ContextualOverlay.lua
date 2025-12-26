---Contextual Overlay UI
---Always-present UI that shows available actions based on player context
---Displays buttons that can be held to trigger actions or open interfaces
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local async = require('openmw.async')

local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local this = {}

---@class ContextualAction
---@field id string Unique identifier for this action
---@field label string Display text (e.g. "Craft", "Forage")
---@field key KEY Key bining
---@field onKeyRelease function? Called on simple press (if no hold)
---@field onHoldStart function? Called when hold begins
---@field onHoldProgress function? Called during hold (receives progress 0-1)
---@field onHoldComplete function? Called when hold completes
---@field onHoldCancel function? Called if hold is cancelled
---@field holdDuration number? Seconds to hold (default 0.5 for opening interfaces)

local currentStationId = nil ---@type Id?
local currentActions = {} ---@type ContextualAction[]?
local overlayElement = nil

---Create or update the overlay UI element
local function updateOverlayUI()

    log.trace('Updating contextual overlay UI')

    -- Destroy existing overlay if present
    if overlayElement then
        overlayElement:destroy()
        overlayElement = nil
    end

    if not currentActions then return end

    log.trace(('Creating overlay with %s actions'):format(
                  lib.len(currentActions)))

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
        props = {size = util.vector2(220, 100)},
        content = ui.content {}
    }
    overlay.content:add(mainSizer)

    -- display the station name
    local headerSizer = {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.padding,
        props = {
            -- size = util.vector2(200, 50),
            -- center horizontally
            anchor = util.vector2(0.5, 0),
            relativePosition = util.vector2(0.5, 0)
        },
        content = ui.content {}
    }
    local stationNameWidget = {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textHeader,
        props = {
            text = ('Station: %s'):format(currentStationId or "Unknown"),
            textAlignH = ui.ALIGNMENT.Center
        }
    }
    headerSizer.content:add(stationNameWidget)
    mainSizer.content:add(headerSizer)

    -- line break
    local lineBreak = {
        type = ui.TYPE.Image,
        template = I.MWUI.templates.horizontalLine,
        props = {size = util.vector2(200, 2)}
    }
    mainSizer.content:add(lineBreak)

    -- -- Actions
    -- local stationLabel = ui.create({
    --     type = ui.TYPE.Text,
    --     template = I.MWUI.templates.textHeader,
    --     props = {text = "Available Actions"}
    -- })
    -- mainSizer.content:add(stationLabel)

    -- action button
    for actionId, action in pairs(currentActions) do
        log.trace(('Adding overlay button for action: %s at %s'):format(
                      action.label, actionId))

        local buttonSizer = {
            type = ui.TYPE.Container,
            template = I.MWUI.templates.boxSolid,
            props = {autoSize = true, horizontal = true},
            content = ui.content {}
        }
        buttonSizer.events = {
            keyRelease = async:callback(function(_, elem)
                log.info(('Overlay action button pressed: %s'):format(
                             action.label))
                if action.onKeyRelease then action.onKeyRelease() end
            end)
        }

        local button = {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = '[F] ' .. action.label,
                textSize = 20,
                relativePosition = util.vector2(0, 0)
            }

        }
        buttonSizer.content:add(button)

        mainSizer.content:add(buttonSizer)
    end

    -- Create and store the overlay element
    overlayElement = ui.create(overlay)
    overlayElement:update()
end

---Register an action that should be shown in the overlay
---@param id Id StationId this action is associated with
---@param action ContextualAction
function this.registerAction(id, action)
    currentStationId = id
    if not currentActions then currentActions = {} end
    table.insert(currentActions, action)

    log.trace('Registered overlay action: ' .. action.id)

    updateOverlayUI()
end

---Clear all registered actions
function this.clearAllActions()
    currentActions = nil
    currentStationId = nil

    updateOverlayUI()
end

---Main update function called every frame
function this.onUpdate(dt)

    -- For now, nothing to update per-frame
end

---@param key KeyboardEvent 
function this.onKeyRelease(key)
    -- early outs
    if not overlayElement then return end
    if not currentStationId then return end
    if not currentActions then return end

    -- for all actions
    for _, action in pairs(currentActions or {}) do
        -- if the key matches the action (for now, we assume 'F' key)
        if key.code == action.key then
            log.info(('Overlay action key %s released: %s'):format(action.key,
                                                                   action.label))
            if action.onKeyRelease then action.onKeyRelease() end
        end
    end
end

return this
