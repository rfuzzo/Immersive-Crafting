local io = require('scripts.Immersive-Crafting.io')
local constants = require('scripts.Immersive-Crafting.constants')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local CContext = require('scripts.Immersive-Crafting.models.context')
local CAction = require('scripts.Immersive-Crafting.models.action')
local CRecipe = require('scripts.Immersive-Crafting.models.recipe')
local CShapedRecipe = require('scripts.Immersive-Crafting.models.shapedRecipe')
local CProcessRecipe = require('scripts.Immersive-Crafting.models.processRecipe')
local CCrop = require('scripts.Immersive-Crafting.models.crop')
local AbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')

local vfs = require('openmw.vfs')
local types = require('openmw.types')

-- item record stores probed for output existence (soft mod dependencies)
local RECORD_TYPES = {
    types.Miscellaneous, types.Weapon, types.Armor, types.Clothing,
    types.Potion, types.Ingredient, types.Book, types.Apparatus,
    types.Lockpick, types.Probe, types.Repair, types.Light,
}

--- Does an item record with this id exist in the current load order?
--- Recipes whose OUTPUT record is missing (its source mod not installed) are
--- skipped at load, so recipes for Ashlander Crafting / Hunterwind / Yurt /
--- OAAB / Tamriel Data outputs are SOFT dependencies: without the mod the
--- recipe simply doesn't exist (no consumed-inputs-for-nothing crafts).
---@param recordId string
---@return boolean
local function outputRecordExists(recordId)
    for _, t in ipairs(RECORD_TYPES) do
        local ok, rec = pcall(function() return t.records[recordId] end)
        if ok and rec then return true end
    end
    return false
end

local this = {}

---@class Registries
---@field actions table<Id, CAction>
---@field contexts table<Id, CContext>
---@field recipes table<string, CRecipe>
---@field shapedRecipes table<string, CShapedRecipe>
---@field processRecipes table<string, CProcessRecipe>
---@field crops table<string, CCrop>
---@field handlers table<string, CAbstractHandler>

---@type Registries
GRegistries = {
    handlers = {},
    actions = {},
    contexts = {},
    recipes = {},
    shapedRecipes = {},
    processRecipes = {},
    crops = {},
    processes = {},
    dressing = {}, -- creature record id (lower) -> carcass record id (field dressing)
}

local DATA_ROOT = constants.DATA_ROOT
local LUA_ROOT = constants.LUA_ROOT

local len = lib.len

---@param target table
---@param data table
local function mergeById(target, data)
    if data.id then
        target[data.id] = data
        return
    end
    for _, entry in ipairs(data) do
        if entry and entry.id then
            target[entry.id] = entry
        end
    end
end

--- Merge a plain `key -> value` object map (no `.id` field) into a registry.
--- Used for declarative maps that `mergeById` cannot handle.
---@param target table
---@param data table
local function mergeMap(target, data)
    for key, value in pairs(data) do
        target[key] = value
    end
end

local function loadActions()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "actions/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                -- data should be in the form of table[]
                for _, entry in ipairs(data) do
                    local a = CAction:fromTable(entry)
                    if a then
                        log.info(('Loading actions from %s'):format(filename))
                        mergeById(GRegistries.actions, a)
                    else
                        log.error(('Failed to load action from %s'):format(filename))
                    end
                end
            end
        end
    end

    -- logging
    log.info(('Loaded %d actions'):format(len(GRegistries.actions)))
    for a in pairs(GRegistries.actions) do
        log.info((' - %s'):format(a))
    end
end

local function loadContexts()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "contexts/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                -- data should be in the form of table[]
                for _, entry in ipairs(data) do
                    local s = CContext:fromTable(entry)
                    if s then
                        log.info(('Loading contexts from %s'):format(filename))
                        mergeById(GRegistries
                            .contexts, s)
                    else
                        log.error(('Failed to load context from %s'):format(filename))
                    end
                end
            end
        end
    end

    -- logging
    log.info(('Loaded %d contexts'):format(len(GRegistries.contexts)))
    for s in pairs(GRegistries.contexts) do
        log.info((' - %s'):format(s))
    end
end

local function loadRecipes()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "recipes/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                -- data should be in the form of table[]
                for _, entry in ipairs(data) do
                    local out = entry.output and entry.output.id
                    if out and not outputRecordExists(out) then
                        -- soft dependency: output's source mod isn't loaded
                        log.info(('Skipping recipe "%s": output record "%s" not in the load order')
                            :format(tostring(entry.id), out))
                    elseif entry.pattern then
                        -- shaped (positional) recipe
                        local r = CShapedRecipe:fromTable(entry)
                        if r then
                            log.info(('Loading shaped recipe from %s'):format(filename))
                            mergeById(GRegistries.shapedRecipes, r)
                        else
                            log.error(('Failed to load shaped recipe from %s'):format(filename))
                        end
                    elseif entry.inputs then
                        -- role-slot (process) recipe
                        local r = CProcessRecipe:fromTable(entry)
                        if r then
                            log.info(('Loading process recipe from %s'):format(filename))
                            mergeById(GRegistries.processRecipes, r)
                        else
                            log.error(('Failed to load process recipe from %s'):format(filename))
                        end
                    else
                        -- flat (world-placement) recipe
                        local r = CRecipe:fromTable(entry)
                        if r then
                            log.info(('Loading recipe from %s'):format(filename))
                            mergeById(GRegistries.recipes, r)
                        else
                            log.error(('Failed to load recipe from %s'):format(filename))
                        end
                    end
                end
            end
        end
    end

    -- logging
    log.info(('Loaded %d recipes'):format(len(GRegistries.recipes)))
    for a in pairs(GRegistries.recipes) do
        log.info((' - %s'):format(a))
    end
end

local function loadCrops()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "crops/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                for _, entry in ipairs(data) do
                    local c = CCrop:fromTable(entry)
                    if c then
                        mergeById(GRegistries.crops, c)
                    else
                        log.error(('Failed to load crop from %s'):format(filename))
                    end
                end
            end
        end
    end

    log.info(('Loaded %d crops'):format(len(GRegistries.crops)))
end

local function loadHandlers()
    -- go through all files in handlers folder and check for .lua files
    for filename in vfs.pathsWithPrefix(LUA_ROOT .. "handlers/") do
        if filename:match("%.lua$") then
            local name = filename:match("handlers/(.+)%.lua$")
            local handlerModulePath = 'scripts.Immersive-Crafting.handlers.' .. name
            local status, handlerModule = pcall(require, handlerModulePath)
            if status and handlerModule then
                log.info(('Loading handler from %s'):format(filename))
                GRegistries.handlers[name] = handlerModule
            else
                log.error(('Error loading handler module %s: %s'):format(
                    handlerModulePath, handlerModule))
            end
        end
    end

    -- logging
    log.info(('Loaded %d handlers'):format(len(GRegistries.handlers)))
    for h in pairs(GRegistries.handlers) do
        log.info((' - %s'):format(h))
    end
end

---Load all data domains.
--- Field-dressing table: dead creature -> carcass item (data/dressing/*.json).
--- Entries whose carcass record is missing (Hunterwind not installed) are
--- skipped — same soft-dependency rule as recipe outputs.
local function loadDressing()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "dressing/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            for _, entry in ipairs(data or {}) do
                if entry.creature and entry.carcass and outputRecordExists(entry.carcass) then
                    GRegistries.dressing[entry.creature:lower()] = entry.carcass
                end
            end
        end
    end
    log.info(('Loaded %d field-dressing entries'):format(len(GRegistries.dressing)))
end

function this.loadAllData()
    loadActions()
    loadContexts()
    loadRecipes()
    loadCrops()
    loadDressing()
    loadHandlers()

    log.info('All data loaded successfully.')
end

---
---@param handlerId Id
---@return CAbstractHandler?
function this.resolveHandler(handlerId)
    -- resolve from registry
    local handlerClass = GRegistries.handlers[handlerId]
    if not handlerClass then
        log.error('Handler not found: ' .. handlerId)
        return nil
    end

    -- instantiate
    local handlerInstance = handlerClass:new()
    return handlerInstance
end

return this
