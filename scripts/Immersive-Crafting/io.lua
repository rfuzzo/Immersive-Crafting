local jsonLib = require('scripts.Immersive-Crafting.ext.dkjson')
local log = require('scripts.Immersive-Crafting.log')

local core = require('openmw.core')
local vfs = require('openmw.vfs')

local this = {}

---@param relPath string
---@return string|nil, string|nil
function this.readFile(relPath)
    local file, errorMsg = vfs.open(relPath)
    if not file then
        log.warn(('Failed to open file %s: %s'):format(relPath, errorMsg or 'unknown'))
        return nil, errorMsg
    end

    local content = file:read("*all")
    file:close()

    return content, nil
end

---@param relPath string
---@return table|nil
function this.loadJsonFile(relPath)
    local text, err = this.readFile(relPath)
    if not text then
        log.warn(('%s'):format(err or 'Unknown read error'))
        return nil
    end

    local data, pos, err = jsonLib.decode(text, 1, nil)
    if err then
        log.warn(('Error parsing JSON file %s at position %d: %s'):format(relPath, pos, err))
        return {}
    end

    if not data then
        log.warn(('No data found in JSON file %s'):format(relPath))
        return {}
    end

    ---@cast data table
    return data
end

return this
