---Player Script for Immersive Crafting

local input = require('openmw.input')
local async = require('openmw.async')
local core = require('openmw.core')

local dataManager = require('scripts.Immersive-Crafting.dataManager')
local contextManager = require('scripts.Immersive-Crafting.contextManager')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local log = require('scripts.Immersive-Crafting.log')

--- Push the set of "activate"-triggered contexts to the global script so it can
--- open the station window when the player activates the matching activator.
local function registerActivateContexts()
    local list = {}
    for id, context in pairs(GRegistries and GRegistries.contexts or {}) do
        if context.trigger == 'activate' then
            list[#list + 1] = { id = id, recordIds = context.recordIds }
        end
    end
    core.sendGlobalEvent('ImmersiveCrafting_RegisterActivateContexts', { contexts = list })
    log.info(('Sent %d activate contexts to global'):format(#list))
end

--- Resolve a context's action reference (id or CAction) to a CAction.
local function resolveAction(actionRef)
    if type(actionRef) == 'string' then return GRegistries.actions[actionRef] end
    return actionRef
end

--- Global asks us to open a station's crafting window (from an activation).
local function onOpenStation(data)
    if not (data and data.contextId) then return end
    local context = GRegistries and GRegistries.contexts[data.contextId]
    if not context then
        log.error('OpenStation: unknown context ' .. tostring(data.contextId))
        return
    end
    local action = resolveAction((context.actions or {})[1])
    if not action then
        log.error('OpenStation: no action for context ' .. tostring(data.contextId))
        return
    end
    Crafting.toggle({ action = action, context = context })
end



---Called when the script is first loaded
local function onInit() log.info('Immersive Crafting player script initialized') end

---Called after loading a save
local function onLoad(data)
    dataManager.loadAllData()
    registerActivateContexts()

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
    },
    eventHandlers = {
        ImmersiveCrafting_OpenStation = onOpenStation,
    }
}
