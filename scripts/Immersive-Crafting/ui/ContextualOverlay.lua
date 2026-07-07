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
local ItemPicker = require('scripts.Immersive-Crafting.ui.ItemPicker')

local v2 = util.vector2

-- Configuration
local updateInterval = 0.25 -- Check for nearby context every 0.25 seconds

-- Position: lower-right, card top at ~3/4 screen height, growing downward.
local OVERLAY_POS = v2(0.99, 0.70)
local OVERLAY_ANCHOR = v2(1, 0)
local LINE_W = 196
local CARD_PAD_X = 6 -- interior padding added inside the card's border
local CARD_PAD_Y = 5

-- Hold bar (drawn while a forage key is held): a bordered track with a solid
-- gold fill, sized to the card's line width.
local HOLD_BAR_H = 10
local whiteTexture = ui.texture { path = 'white' }
local HOLD_BAR_FILL = util.color.rgb(0.95, 0.78, 0.35)  -- matches the selected-slot gold
local HOLD_BAR_TRACK = util.color.rgb(0.08, 0.07, 0.05) -- faint dark track behind the fill
local DETAIL_COLOR = util.color.rgb(0.60, 0.52, 0.38)   -- muted tan for secondary detail lines

local this = {}

-- State variables
this.timeSinceLastUpdate = 0 ---@type number

local currentContext = nil ---@type CContext?
local currentObject = nil ---@type any? matched world object (proximity/gaze), if any
local currentActions = {} ---@type CAction[]?
local overlayElement = nil

-- Hold-to-act state. `duration` (seconds) comes from the current context's
-- primary hold action (foraging); `elapsed` accrues while the key is held.
-- `fired` guards against re-triggering until the key is released.
local hold = {
    duration = 0, ---@type number 0 = current context acts on press, not hold
    enabled = false, ---@type boolean is the hold action currently allowed
    elapsed = 0, ---@type number
    fired = false, ---@type boolean
}
local prevPressed = false ---@type boolean edge tracker for instant (non-hold) actions

--- Thin separator line.
local function hLine()
    return {
        type = ui.TYPE.Image,
        template = I.MWUI.templates.horizontalLine,
        props = { size = v2(LINE_W, 2) },
    }
end

--- A keycap badge: the bound key letter in a small bordered box (reads as a
--- prompt, e.g. [F] Collect -> a boxed F followed by the label).
---@param key string
local function keycap(key)
    return c.box({
        children = {
            c.column({ children = {
                c.spacer({ props = { size = v2(0, 1) } }),
                c.row({ children = {
                    c.spacer({ props = { size = v2(5, 0) } }),
                    c.text({ text = key }),
                    c.spacer({ props = { size = v2(5, 0) } }),
                } }),
                c.spacer({ props = { size = v2(0, 1) } }),
            } }),
        },
    })
end

--- The action row: a keycap 'F' badge + the label (header template when the
--- action is enabled, normal otherwise).
---@param label string
---@param enabled boolean
local function actionRow(label, enabled)
    return c.row({
        props = { align = ui.ALIGNMENT.Center },
        children = {
            keycap('F'),
            c.spacer({ props = { size = v2(7, 0) } }),
            c.text({
                text = label,
                template = enabled and I.MWUI.templates.textHeader or I.MWUI.templates.textNormal,
            }),
        },
    })
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

    -- action hint: an [F] keycap + <label> (gold when enabled). Held actions
    -- append a "(hold)" hint until the bar is showing.
    if viewModel.action then
        local label = viewModel.action.label
        if viewModel.action.hold and viewModel.action.hold > 0 and not viewModel.progress then
            label = label .. ' (hold)'
        end
        rows[#rows + 1] = actionRow(label, viewModel.action.enabled and true or false)
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 4) } })
    end

    -- hold progress bar: shown only while the key is actively held. A solid
    -- gold fill over a dark track inside an MWUI border.
    if viewModel.progress then
        local p = math.max(0, math.min(1, viewModel.progress))
        rows[#rows + 1] = {
            template = I.MWUI.templates.box,
            content = ui.content {
                {
                    type = ui.TYPE.Widget,
                    props = { size = v2(LINE_W, HOLD_BAR_H) },
                    content = ui.content {
                        { -- track
                            type = ui.TYPE.Image,
                            props = {
                                resource = whiteTexture,
                                size = v2(LINE_W, HOLD_BAR_H),
                                color = HOLD_BAR_TRACK,
                            },
                        },
                        { -- fill
                            type = ui.TYPE.Image,
                            props = {
                                resource = whiteTexture,
                                size = v2(math.floor(LINE_W * p + 0.5), HOLD_BAR_H),
                                color = HOLD_BAR_FILL,
                            },
                        },
                    },
                },
            },
        }
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 3) } })
    end

    -- details (e.g. "Missing: Water", input roles) — dimmed as secondary text
    for _, detail in ipairs(viewModel.details or {}) do
        rows[#rows + 1] = c.text({ text = detail, props = { textColor = DETAIL_COLOR } })
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

    -- Reset the hold spec each rebuild; the first hold-capable action sets it.
    hold.duration = 0
    hold.enabled = false

    local rows = {}
    for _, action in pairs(currentActions) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            ---@type HandlerContext
            local ctx = { action = action, context = currentContext, object = currentObject }
            local viewModel = handler:present(ctx)
            if viewModel then
                -- adopt the first hold-capable action as the context's hold action,
                -- and feed live hold progress back into its card.
                if viewModel.action and viewModel.action.hold and viewModel.action.hold > 0 then
                    if hold.duration == 0 then
                        hold.duration = viewModel.action.hold
                        hold.enabled = viewModel.action.enabled and true or false
                    end
                    if hold.elapsed > 0 then
                        viewModel.progress = hold.elapsed / viewModel.action.hold
                    end
                end
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

    -- auto-sized card: transparent box + padding + interior CARD_PAD margin so
    -- the content doesn't kiss the border (matches the window pass)
    local paddedRows = { c.spacer({ props = { size = v2(0, CARD_PAD_Y) } }) }
    for _, r in ipairs(rows) do paddedRows[#paddedRows + 1] = r end
    paddedRows[#paddedRows + 1] = c.spacer({ props = { size = v2(0, CARD_PAD_Y) } })

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
                    c.row({ children = {
                        c.spacer({ props = { size = v2(CARD_PAD_X, 0) } }),
                        c.column({ name = 'overlay_rows', children = paddedRows }),
                        c.spacer({ props = { size = v2(CARD_PAD_X, 0) } }),
                    } }),
                },
            },
        },
    })
end

--#region Public API

---Register an action that should be shown in the overlay
---@param context CContext
---@param action CAction?
function this.registerAction(context, action, object)
    if not action then
        log.error('Cannot register nil action to overlay')
        return
    end

    currentContext = context
    currentObject = object
    if not currentActions then currentActions = {} end
    table.insert(currentActions, action)

    -- log.trace('Registered overlay action: ' .. action.id)

    updateOverlayUI()
end

---Clear all registered actions
function this.clearAllActions()
    currentActions = nil
    currentContext = nil
    currentObject = nil

    -- looking away / walking off cancels any in-progress hold
    hold.duration = 0
    hold.enabled = false
    hold.elapsed = 0
    hold.fired = false

    updateOverlayUI()
end

--#endregion

--#region Events

--- Dispatch OnActivate for every action on the current context.
local function fireActions()
    if not currentContext then return end
    for _, action in pairs(currentActions or {}) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler then
            ---@type HandlerContext
            local ctx = {
                action = action,
                context = currentContext,
                object = currentObject
            }
            handler:OnActivate(ctx)
        end
    end
end

--- Dispatch OnTap for every action on the current context (short press on a
--- hold-capable card, e.g. cycling the planter's seed selection).
local function fireTaps()
    if not currentContext then return end
    for _, action in pairs(currentActions or {}) do
        local handler = dataManager.resolveHandler(action.handler)
        if handler and handler.OnTap then
            ---@type HandlerContext
            local ctx = {
                action = action,
                context = currentContext,
                object = currentObject
            }
            handler:OnTap(ctx)
        end
    end
end

-- releases quicker than this (on a hold card) count as a tap, not an aborted hold
local TAP_THRESHOLD = 0.3

--- Drive the contextual action key each frame. Instant actions fire on the press
--- edge; hold actions (foraging) accrue while the key is down and fire once the
--- hold bar fills, then wait for release before they can fire again.
---@param pressed boolean current key state
---@param dt number
local function handleActionInput(pressed, dt)
    -- no card: the key does nothing. Keep the edge tracker in sync so we
    -- don't fire late.
    if not overlayElement or not currentContext or not currentActions then
        prevPressed = pressed
        return
    end
    -- activate-triggered stations are opened by activating the object, so F
    -- never fires INSTANT actions on them — but HOLD actions are allowed
    -- (holding F on a placed station's card packs it up).
    if currentContext.trigger == 'activate' and hold.duration == 0 then
        prevPressed = pressed
        return
    end

    if hold.duration > 0 then
        -- hold-to-act (foraging)
        if pressed and hold.enabled then
            hold.elapsed = hold.elapsed + dt
            if not hold.fired and hold.elapsed >= hold.duration then
                fireActions()
                hold.fired = true
            end
        else
            -- a quick press-and-release on a hold card is a TAP (cycle selection)
            if prevPressed and not pressed and not hold.fired
                and hold.elapsed > 0 and hold.elapsed < TAP_THRESHOLD then
                fireTaps()
                updateOverlayUI()
            end
            -- released, or the action is currently disabled: reset the bar
            hold.elapsed = 0
            hold.fired = false
        end
    else
        -- instant press (crafting stations)
        if pressed and not prevPressed then
            fireActions()
        end
    end

    prevPressed = pressed
end

--#endregion

--#region Parent

---Main update function called every frame
function this.onUpdate(dt)
    -- Poll the contextual action key every frame so hold timing is smooth and
    -- edge-accurate (see handleActionInput). Typing in the crafting strip's
    -- search box must never fire it (an 'f' mid-word closed the window).
    handleActionInput(
        input.getBooleanActionValue('ContextualAction') and not ItemPicker.isSearchFocused(),
        dt)

    -- Periodically update UI — but refresh every frame while a hold is in
    -- progress so the hold bar fills smoothly.
    this.timeSinceLastUpdate = this.timeSinceLastUpdate + dt
    if hold.elapsed > 0 or this.timeSinceLastUpdate >= updateInterval then
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
