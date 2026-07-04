---Player Script for Immersive Crafting

local core = require('openmw.core')
local types = require('openmw.types')
local omwSelf = require('openmw.self')
local ui = require('openmw.ui')

local dataManager = require('scripts.Immersive-Crafting.dataManager')
local contextManager = require('scripts.Immersive-Crafting.contextManager')
local overlay = require('scripts.Immersive-Crafting.ui.ContextualOverlay')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local forageState = require('scripts.Immersive-Crafting.forageState')
local farmState = require('scripts.Immersive-Crafting.farmState')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

--- Push the set of "activate"-triggered contexts to the global script so it can
--- open the station window when the player activates the matching activator.
local function registerActivateContexts()
    local list = {}
    for id, context in pairs(GRegistries and GRegistries.contexts or {}) do
        if context.trigger == 'activate' then
            list[#list + 1] = {
                id = id,
                recordIds = context.recordIds,
                recordPatterns = context.recordPatterns,
                recordPatternsExclude = context.recordPatternsExclude,
            }
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
    forageState.load(data and data.forage)
    core.sendGlobalEvent('ImmersiveCrafting_RequestCropSync', {})

    log.info('Immersive Crafting player script loaded from save')
end

---Called before saving
local function onSave()
    return { forage = forageState.serialize() }
end

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

-- The contextual action key is polled every frame inside the overlay's onUpdate
-- (ContextualOverlay.handleActionInput) so it can support hold-to-forage timing;
-- no edge callback is registered here.

-- ── debug helpers (console: open `~`, enter `luap`, then e.g.
-- `I.ImmersiveCrafting.giveMaterials()` or `I.ImmersiveCrafting.giveMaterials(20)`) ──

--- Every distinct ingredient matcher (record id or tag) across all recipe kinds.
local function allMaterialMatchers()
    local seen, list = {}, {}
    local function add(v)
        if v and not seen[v] then
            seen[v] = true
            list[#list + 1] = v
        end
    end
    for _, r in pairs(GRegistries.recipes or {}) do
        for _, ing in ipairs(r.ingredients or {}) do add(ing.id) end
    end
    for _, r in pairs(GRegistries.shapedRecipes or {}) do
        for _, v in pairs(r.key or {}) do add(v) end
    end
    for _, r in pairs(GRegistries.processRecipes or {}) do
        for _, line in ipairs(r.inputs or {}) do add(line.id) end
    end
    return list
end

-- record lists to resolve tags against (order = preference)
local MATERIAL_TYPES = { types.Ingredient, types.Miscellaneous, types.Potion }

--- Debug: grant every recipe ingredient for testing. Tags resolve to the first
--- record (Ingredient/Misc/Potion) carrying the tag; exact ids resolve directly.
---@param countEach integer? items granted per matcher (default 5)
---@return integer granted, string[] unresolved
local function giveMaterials(countEach)
    countEach = countEach or 5
    local granted, unresolved = 0, {}
    for _, matcher in ipairs(allMaterialMatchers()) do
        local resolved = nil
        for _, t in ipairs(MATERIAL_TYPES) do
            local ok, rec = pcall(function() return t.records[matcher] end)
            if ok and rec then
                resolved = rec.id
                break
            end
        end
        if not resolved then
            for _, t in ipairs(MATERIAL_TYPES) do
                for _, rec in ipairs(t.records) do
                    if lib.matchesTag(rec.id, matcher) then
                        resolved = rec.id
                        break
                    end
                end
                if resolved then break end
            end
        end
        if resolved then
            core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
                actor = omwSelf.object,
                consume = {},
                output = { id = resolved, count = countEach },
            })
            granted = granted + 1
        else
            unresolved[#unresolved + 1] = matcher
        end
    end
    log.info(('giveMaterials: granted %d matchers x%d'):format(granted, countEach))
    if #unresolved > 0 then
        log.warn('giveMaterials: unresolved matchers: ' .. table.concat(unresolved, ', '))
    end
    return granted, unresolved
end

return {
    interfaceName = 'ImmersiveCrafting',
    interface = {
        version = 1,
        giveMaterials = giveMaterials,
    },
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
        onUpdate = onUpdate,
    },
    eventHandlers = {
        ImmersiveCrafting_OpenStation = onOpenStation,
        ImmersiveCrafting_CropSync = function(data)
            farmState.apply(data and data.crops)
        end,
        ImmersiveCrafting_Notify = function(data)
            if data and data.text then ui.showMessage(data.text) end
        end,
    }
}
