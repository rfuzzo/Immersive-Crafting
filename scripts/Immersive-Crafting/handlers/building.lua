--[[
    Build-in-place handler: the "Construction" card. buildScan found a complete
    component set lying on the ground; the card names the station, lists what
    the build consumes, and hold-F sends the build to the global side.
]]

local core = require('openmw.core')
local omwSelf = require('openmw.self')
local types = require('openmw.types')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local buildScan = require('scripts.Immersive-Crafting.buildScan')
local lib = require('scripts.Immersive-Crafting.lib')

local BUILD_HOLD_DEFAULT = 3

---@param tools string[]|nil
---@return string[] missing tool tags (empty = all in inventory)
local function missingTools(tools)
    local missing = {}
    for _, tool in ipairs(tools or {}) do
        local found = false
        for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
            if lib.matchesTag(item.recordId, tool) then
                found = true
                break
            end
        end
        if not found then missing[#missing + 1] = tool end
    end
    return missing
end

---@class CBuildingHandler : CAbstractHandler
local CBuildingHandler = {}
setmetatable(CBuildingHandler, { __index = CAbstractHandler })

---@param ctx HandlerContext
---@return ViewModel?
function CBuildingHandler:evaluate(ctx)
    local candidate = buildScan.current
    if not candidate then return nil end
    local def = candidate.def

    -- what the build consumes (from the recipe, not the pile — the pile holds it)
    local parts = {}
    for _, comp in ipairs(def.components or {}) do
        parts[#parts + 1] = ('%dx %s'):format(comp.count or 1, comp.id)
    end
    local details = { 'Uses: ' .. table.concat(parts, ', ') }

    local missing = missingTools(def.tools)
    if #missing > 0 then
        details[#details + 1] = 'Requires: ' .. table.concat(missing, ', ')
        ---@type ViewModel
        return {
            header = 'Construction',
            status = ('%s — materials ready'):format(def.label or def.id),
            details = details,
        }
    end

    ---@type ViewModel
    return {
        header = 'Construction',
        status = ('%s — materials ready'):format(def.label or def.id),
        action = {
            id = 'build',
            label = 'Build ' .. (def.label or def.id),
            enabled = true,
            hold = def.holdTime or BUILD_HOLD_DEFAULT,
        },
        details = details,
    }
end

---@param ctx HandlerContext
function CBuildingHandler:OnActivate(ctx)
    local candidate = buildScan.current
    if not candidate then return end
    if #missingTools(candidate.def.tools) > 0 then return end

    core.sendGlobalEvent('ImmersiveCrafting_Build', {
        actor = omwSelf.object,
        constructionId = candidate.def.id,
        position = candidate.position,
    })
    buildScan.current = nil -- consumed; the next poll rescans
end

return CBuildingHandler
