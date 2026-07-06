--[[
    Sun's Dusk interop: gate SD's cooking menu at placed IC stations.

    SD offers its campfire cooking UI on any activator whose record id contains
    'fire' (or 'stove', 'oven', ...) — which includes our placed fire stations
    (drop-swapped activators like ic_station_firepit_a). That is a nice
    integration, so it is ON by default; the "Sun's Dusk cooking at fire
    stations" setting turns it off.

    SD exposes its player-script environment via I.SunsDusk.getGlobals(); its
    detection (G_isCookingActivator) consults G_module_cooking_blacklist —
    substring matches against the record id — on every look-at, so adding or
    removing our 'ic_station' prefix there takes effect immediately.
]]

local I = require('openmw.interfaces')
local async = require('openmw.async')
local storage = require('openmw.storage')

local log = require('scripts.Immersive-Crafting.log')

local BLACKLIST_ENTRY = 'ic_station'
local SETTING = 'SDCookingAtStations'

local settingsSection = storage.playerSection('SettingsImmersiveCrafting')

local this = {}

---@return table? SD's player-script globals, nil when SD is not installed
local function sdGlobals()
    local sd = I.SunsDusk
    if not (sd and sd.getGlobals) then return nil end
    local ok, G = pcall(sd.getGlobals)
    return ok and G or nil
end

--- Sync SD's cooking blacklist with the setting.
function this.apply()
    local G = sdGlobals()
    local blacklist = G and G.G_module_cooking_blacklist
    if type(blacklist) ~= 'table' then return end
    for i = #blacklist, 1, -1 do
        if blacklist[i] == BLACKLIST_ENTRY then table.remove(blacklist, i) end
    end
    if settingsSection:get(SETTING) == false then
        blacklist[#blacklist + 1] = BLACKLIST_ENTRY
        log.info('SD cooking at IC stations: off (blacklisted in Sun\'s Dusk)')
    end
end

local initialized = false

--- Apply once and follow setting changes. Safe to call from both onInit and
--- onLoad; a no-op without Sun's Dusk.
function this.init()
    if initialized then return end
    initialized = true
    if not sdGlobals() then return end
    settingsSection:subscribe(async:callback(function(_, key)
        if key == nil or key == SETTING then this.apply() end
    end))
    this.apply()
end

return this
