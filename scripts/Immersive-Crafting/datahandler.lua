local io = require('scripts.Immersive-Crafting.io')
local constants = require('scripts.Immersive-Crafting.constants')
local lib = require('scripts.Immersive-Crafting.lib')
local log = require('scripts.Immersive-Crafting.log')

local CStation = require('scripts.Immersive-Crafting.models.station')
local CAction = require('scripts.Immersive-Crafting.models.action')

local vfs = require('openmw.vfs')

local this = {}

---@class Registries
---@field tags table<Id, string[]>
---@field uiTemplates table<Id, table>
---@field actions table<Id, CAction>
---@field stations table<Id, CStation>
---@field containers table<Id, ContainerDef>
---@field recipes table<string, table<Id, RecipeDef>>

---@type Registries
GRegistries = {
    tags = {},
    uiTemplates = {},
    actions = {},
    stations = {},
    containers = {},
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

local function loadStations()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "stations/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                local s = CStation:fromTable(data)
                if s then
                    log.info(('Loading stations from %s'):format(filename))
                    mergeById(GRegistries.stations, s)
                end
            end
        end
    end

    -- logging
    log.info(('Loaded %d stations'):format(len(GRegistries.stations)))
    for s in pairs(GRegistries.stations) do
        log.info((' - %s'):format(s))
    end
end

local function loadContainers()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "containers/") do
        if filename:match("%.json$") then
            local data = io.loadJsonFile(filename)
            if data then
                log.info(('Loading containers from %s'):format(filename))
                mergeById(GRegistries.containers, data)
            end
        end
    end

    -- logging
    log.info(('Loaded %d containers'):format(len(GRegistries.containers)))
    for c in pairs(GRegistries.containers) do
        log.info((' - %s'):format(c))
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
    loadStations()
    loadContainers()
    loadRecipes()

    log.info('All data loaded successfully.')
end

return this
