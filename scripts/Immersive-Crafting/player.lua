---Player Script for Immersive Crafting
---Handles contextual UI overlay and proximity-based crafting interaction
local dataHandler = require('scripts.Immersive-Crafting.datahandler')
local contextManager = require('scripts.Immersive-Crafting.contextManager')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local log = require('scripts.Immersive-Crafting.log')

local input = require('openmw.input')
local async = require('openmw.async')
local core = require('openmw.core')

---Called when the script is first loaded
local function onInit() log.info('Immersive Crafting player script initialized') end

---Called after loading a save
local function onLoad(data)
    dataHandler.loadAllData()

    log.info('Immersive Crafting player script loaded from save')
end

---Called before saving
local function onSave() return {} end

---Main update loop
local function onUpdate(dt)
    contextManager.onUpdate(dt)
    overlay.onUpdate(dt)
end

-- TODO input bindings
-- input.registerAction {
--     key = 'OverlayAction',
--     type = input.ACTION_TYPE.Boolean,
--     l10n = 'MyLocalizationContext',
--     name = 'OverlayAction',
--     description = 'Button to trigger overlay action',
--     defaultValue = false
-- }

-- local function onFrame(dt)
--     local myAction = input.getBooleanActionValue('OverlayAction')
--     if (myAction) then print('My action is active!') end
-- end

---Handle key presses for crafting actions
---@param key KeyboardEvent
local function onKeyRelease(key)
    -- Delegate to overlay handler
    overlay.onKeyRelease(key)
end

---Handle input actions (for gamepads, etc)
local function onInputAction(action)
    -- TODO: Handle gamepad input for crafting actions
end

return {
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
        onUpdate = onUpdate,
        onKeyRelease = onKeyRelease
        -- onFrame = onFrame
    }
}
