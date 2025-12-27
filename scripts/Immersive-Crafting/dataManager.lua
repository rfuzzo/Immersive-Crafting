local io = require('scripts.Immersive-Crafting.io')
local constants = require('scripts.Immersive-Crafting.constants')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local CContext = require('scripts.Immersive-Crafting.models.station')
local CAction = require('scripts.Immersive-Crafting.models.action')

local vfs = require('openmw.vfs')

local this = {}

---@class Registries
---@field tags table<Id, string[]>
---@field uiTemplates table<Id, table>
---@field actions table<Id, CAction>
---@field contexts table<Id, CContext>
---@field recipes table<string, table<Id, RecipeDef>>

---@type Registries
GRegistries = {
    tags = {},
    uiTemplates = {},
    actions = {},
    contexts = {},
    recipes = {
        shaped = {},
        contextual = {},
    },
    processes = {},
}

local DATA_ROOT = constants.DATA_ROOT

-- === Data Registries ===

local len = lib.len

-- === Data domain loaders ===

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

local function loadTags()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "tags/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                log.info(('Loading tags from %s'):format(filename))
                mergeById(GRegistries.tags, data)
            end
        end
    end

    -- logging
    log.info(('Loaded %d tags'):format(len(GRegistries.tags)))
    for a in pairs(GRegistries.tags) do
        log.info((' - %s'):format(a))
    end
end

local function loadUiTemplates()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "uiTemplates/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                log.info(('Loading uiTemplates from %s'):format(filename))
                mergeById(GRegistries.uiTemplates, data)
            end
        end
    end

    -- logging
    log.info(('Loaded %d uiTemplates'):format(len(GRegistries.uiTemplates)))
    for a in pairs(GRegistries.uiTemplates) do
        log.info((' - %s'):format(a))
    end
end

local function loadActions()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "actions/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                local a = CAction:fromTable(data)
                if a then
                    log.info(('Loading actions from %s'):format(filename))
                    mergeById(GRegistries.actions, a)
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
                local s = CContext:fromTable(data)
                if s then
                    log.info(('Loading contexts from %s'):format(filename))
                    mergeById(GRegistries.contexts, s)
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
    -- Shaped recipes
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "recipes/shaped/") do
        local data = io.loadJsonFile(filename)
        if data then
            log.info(('Loading shaped recipes from %s'):format(filename))
            mergeById(GRegistries.recipes.shaped, data)
        end
    end

    -- logging
    log.info(('Loaded %d shaped recipes'):format(len(GRegistries.recipes.shaped)))
    for r in pairs(GRegistries.recipes.shaped) do
        log.info((' - %s'):format(r))
    end

    -- Contextual recipes
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "recipes/contextual/") do
        local data = io.loadJsonFile(filename)
        if data then
            log.info(('Loading contextual recipes from %s'):format(filename))
            mergeById(GRegistries.recipes.contextual, data)
        end
    end

    -- logging
    log.info(('Loaded %d contextual recipes'):format(len(GRegistries.recipes.contextual)))
    for r in pairs(GRegistries.recipes.contextual) do
        log.info((' - %s'):format(r))
    end
end

---Load all data domains.
function this.loadAllData()
    loadTags()
    loadUiTemplates()
    loadActions()
    loadContexts()
    loadRecipes()

    log.info('All data loaded successfully.')
end

return this
