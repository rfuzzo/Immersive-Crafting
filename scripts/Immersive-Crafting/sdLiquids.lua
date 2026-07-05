--[[
    Sun's Dusk liquids — PLAYER-side matcher for `sd:<liquid>` ingredient
    queries (e.g. `sd:water` in a recipe input/tool cell).

    SD water/drink bottles are DYNAMIC Potion records (minted per fill level),
    so they can never be FlexTag-tagged. Two facts make matching possible:
    - every SD bottle record is created with `mwscript = "sd_liquid_tracker"`
      (readable from the record in any context) — that answers "is this an SD
      liquid at all" instantly;
    - WHICH liquid it is (water vs sujamma vs tea...) lives only in SD's
      global registry, so unknown ids are classified through a tiny
      global round-trip (ImmersiveCrafting_ClassifyLiquids ->
      ImmersiveCrafting_LiquidSync) and cached in a mirror, farmState-style.
      The first match attempt for a fresh bottle can miss; the reply lands
      next frame and every later rebuild/scan sees it.

    `sd:liquid` matches ANY SD bottle; `sd:water` etc. match the liquid key
    (SD keys: water, saltWater, susWater, sujamma, flin, tea_*, ...).
    The consume side (return the empty container) is globalLiquids.lua.
]]

local core = require('openmw.core')
local types = require('openmw.types')
local omwSelf = require('openmw.self')

local TRACKER_SCRIPT = 'sd_liquid_tracker'

local this = {}

local mirror = {} ---@type table<string, { liquid: string, orig: string }> classified SD bottle records
local requested = {} ---@type table<string, boolean> ids already sent for classification

---@param recordId string
---@return boolean is this record an SD dynamic liquid bottle?
local function isSdLiquidRecord(recordId)
    local ok, rec = pcall(function() return types.Potion.record(recordId) end)
    return (ok and rec and rec.mwscript == TRACKER_SCRIPT) or false
end

--- Does this record satisfy an `sd:<liquid>` query?
---@param recordId string
---@param liquidKey string SD liquid key ("water", ...) or "liquid" (any SD bottle)
---@return boolean
function this.matches(recordId, liquidKey)
    if not isSdLiquidRecord(recordId) then return false end
    if liquidKey == 'liquid' then return true end
    local info = mirror[recordId]
    if info then return info.liquid == liquidKey end
    if not requested[recordId] then
        requested[recordId] = true
        core.sendGlobalEvent('ImmersiveCrafting_ClassifyLiquids', {
            actor = omwSelf.object,
            ids = { recordId },
        })
    end
    return false -- unknown yet; the sync reply covers the next resolve
end

--- ImmersiveCrafting_LiquidSync payload -> mirror.
---@param data { liquids: table<string, { liquid: string, orig: string }> }?
function this.apply(data)
    for id, info in pairs((data and data.liquids) or {}) do
        mirror[id] = info
    end
end

return this
