--[[
    Field dressing — GLOBAL side (required by init.lua).

    Grants the carcass for a dressed corpse. Take-from-loot-else-mint:
    UNPATCHED Hunterwind already injects the carcass into the creature's
    inventory — pull that one out (no doubles); with the creature-edit-free
    patched plugin (tools/patch_hunterwind.py) the loot is clean and the
    carcass is created instead. Both configurations behave identically.
]]

local world = require('openmw.world')
local types = require('openmw.types')

local log = require('scripts.Immersive-Crafting.log')

local this = {}

local function notify(actor, text)
    if actor then actor:sendEvent('ImmersiveCrafting_Notify', { text = text }) end
end

---@param data { actor: any, corpse: any, carcass: string }
function this.onFieldDress(data)
    if not (data and data.actor and data.corpse and data.carcass) then return end
    local corpse = data.corpse
    if not corpse:isValid() then return end

    -- 1. unpatched Hunterwind: the carcass is already in the corpse's loot
    local granted = false
    pcall(function()
        local item = types.Actor.inventory(corpse):find(data.carcass)
        if item then
            item:moveInto(types.Actor.inventory(data.actor))
            granted = true
        end
    end)

    -- 2. patched plugin: mint the carcass
    if not granted then
        local ok, err = pcall(function()
            local created = world.createObject(data.carcass, 1)
            created:moveInto(types.Actor.inventory(data.actor))
        end)
        if not ok then
            log.error(('dressing: failed to grant "%s": %s'):format(tostring(data.carcass), tostring(err)))
            notify(data.actor, 'You cannot make use of this carcass')
            return
        end
    end

    notify(data.actor, 'You field dress the carcass')
    log.info(('dressing: granted %s (%s)'):format(data.carcass, granted and 'from loot' or 'minted'))
end

return this
