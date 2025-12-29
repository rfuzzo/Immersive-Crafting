---Player Script for Immersive Crafting

local input = require('openmw.input')
local async = require('openmw.async')

local dataManager = require('scripts.Immersive-Crafting.dataManager')
local contextManager = require('scripts.Immersive-Crafting.contextManager')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local log = require('scripts.Immersive-Crafting.log')


input.registerAction {
    key = 'ContextualAction',
    type = input.ACTION_TYPE.Boolean,
    l10n = 'none',
    name = 'ContextualAction',
    description = 'Button to trigger overlay action',
    defaultValue = false
}

---Called when the script is first loaded
local function onInit() log.info('Immersive Crafting player script initialized') end

---Called after loading a save
local function onLoad(data)
    dataManager.loadAllData()

    log.info('Immersive Crafting player script loaded from save')
end

---Called before saving
local function onSave() return {} end

---Main update loop
local function onUpdate(dt)
    contextManager.onUpdate(dt)
    overlay.onUpdate(dt)
end

-- callbacks
input.registerActionHandler('ContextualAction', async:callback(function(pressed)
    if not pressed then return end
    overlay.onContextualAction()
end))

return {
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
        onUpdate = onUpdate,
    }
}
