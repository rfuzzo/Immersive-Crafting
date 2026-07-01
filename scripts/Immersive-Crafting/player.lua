---Player Script for Immersive Crafting

local input = require('openmw.input')
local async = require('openmw.async')

local dataManager = require('scripts.Immersive-Crafting.dataManager')
local contextManager = require('scripts.Immersive-Crafting.contextManager')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local log = require('scripts.Immersive-Crafting.log')



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

    -- Close the shaping UI if the nearby context was lost or switched.
    if Crafting.isOpen() then
        local active = contextManager.currentContext
        local activeContextId = active and active.context and active.context.id or nil
        if activeContextId ~= Crafting.getContextId() then
            Crafting.close()
        end
    end

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
