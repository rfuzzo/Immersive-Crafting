local io = require('scripts.Immersive-Crafting.io')
local constants = require('scripts.Immersive-Crafting.constants')
local lib = require('scripts.Immersive-Crafting.lib')

local vfs = require('openmw.vfs')

local this = {}

local DATA_ROOT = constants.DATA_ROOT

-- === Data Registries ===

---@type Registries
this.registries = {
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

local registries = this.registries

---@return Registries
function this.getRegistries()
    return this.registries
end

local function len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

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
    registries.tags = io.loadJsonFile('tags.json') or {}
    lib.info(('Loaded %d tags'):format(len(registries.tags)))
end

local function loadUiTemplates()
    registries.uiTemplates = io.loadJsonFile('ui_templates.json') or {}
    lib.info(('Loaded %d UI templates'):format(len(registries.uiTemplates)))
end

local function loadActions()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "actions/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading actions from %s'):format(filename))
            mergeById(registries.actions, data)
        end
    end

    -- logging
    lib.info(('Loaded %d actions'):format(len(registries.actions)))
    for a in pairs(registries.actions) do
        lib.info((' - %s'):format(a))
    end
end

local function loadStations()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "stations/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading stations from %s'):format(filename))
            mergeById(registries.stations, data)
        end
    end

    -- logging
    lib.info(('Loaded %d stations'):format(len(registries.stations)))
    for s in pairs(registries.stations) do
        lib.info((' - %s'):format(s))
    end
end

local function loadContainers()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "containers/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading containers from %s'):format(filename))
            mergeById(registries.containers, data)
        end
    end

    -- logging
    lib.info(('Loaded %d containers'):format(len(registries.containers)))
    for c in pairs(registries.containers) do
        lib.info((' - %s'):format(c))
    end
end

local function loadProcesses()
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "processes/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading processes from %s'):format(filename))
            mergeById(registries.processes, data)
        end
    end

    -- logging
    lib.info(('Loaded %d processes'):format(len(registries.processes)))
    for p in pairs(registries.processes) do
        lib.info((' - %s'):format(p))
    end
end

local function loadRecipes()
    -- Shaped recipes
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "recipes/shaped/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading shaped recipes from %s'):format(filename))
            mergeById(registries.recipes.shaped, data)
        end
    end

    -- logging
    lib.info(('Loaded %d shaped recipes'):format(len(registries.recipes.shaped)))
    for r in pairs(registries.recipes.shaped) do
        lib.info((' - %s'):format(r))
    end

    -- Contextual recipes
    for filename in vfs.pathsWithPrefix(DATA_ROOT .. "recipes/contextual/") do
        local data = io.loadJsonFile(filename)
        if data then
            lib.info(('Loading contextual recipes from %s'):format(filename))
            mergeById(registries.recipes.contextual, data)
        end
    end

    -- logging
    lib.info(('Loaded %d contextual recipes'):format(len(registries.recipes.contextual)))
    for r in pairs(registries.recipes.contextual) do
        lib.info((' - %s'):format(r))
    end
end

---Load all data domains.
function this.loadAllData()
    loadTags()
    loadUiTemplates()
    loadActions()
    loadStations()
    loadContainers()
    loadProcesses()
    loadRecipes()

    lib.info('All data loaded successfully.')
end

return this
