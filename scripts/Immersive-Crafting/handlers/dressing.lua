--[[
    Field dressing handler — turn a dead creature into its Hunterwind carcass.

        Guar — dead
        [F] Field dress (hold)          <- requires the Hunter Knife
        Requires: Hunter Knife          <- when you don't carry it

    Replaces Hunterwind's creature-record loot edits with IC's contextual
    grammar: stand at a dead creature listed in GRegistries.dressing (built
    from HW's own creature->carcass data), hold F with the HUNTER KNIFE in
    your pack, and the carcass is granted — taken from the corpse's loot when
    unpatched Hunterwind already put it there, minted otherwise (see
    globalDressing). Once per corpse (dressState); the corpse itself stays
    for vanilla looting/disposal. HW's own butchering then processes the
    carcass item as normal.
]]

local core = require('openmw.core')
-- NOT named `self`: the method receiver in `Handler:Method()` would shadow it.
local omwSelf = require('openmw.self')
local types = require('openmw.types')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local lib = require('scripts.Immersive-Crafting.lib')
local dressState = require('scripts.Immersive-Crafting.dressState')
local log = require('scripts.Immersive-Crafting.log')

local DRESS_HOLD = 1.5
local KNIFE = 'hb_hunters_knife' -- ratified: the Hunter Knife specifically

---@class CDressingHandler : CAbstractHandler
local CDressingHandler = {}
setmetatable(CDressingHandler, { __index = CAbstractHandler })

local function hasHunterKnife()
    for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
        if lib.matchesTag(item.recordId, KNIFE) then return true end
    end
    return false
end

---@param corpse any
---@return string display name
local function creatureName(corpse)
    local ok, rec = pcall(function() return types.Creature.record(corpse.recordId) end)
    if ok and rec and rec.name and rec.name ~= '' then return rec.name end
    return corpse.recordId
end

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CDressingHandler:evaluate(ctx)
    local corpse = ctx.object
    local carcass = corpse and GRegistries.dressing
        and GRegistries.dressing[corpse.recordId:lower()]
    if not carcass then
        return { status = 'Nothing to dress' }
    end

    local name = creatureName(corpse)
    if dressState.isDressed(corpse.id) then
        return { status = name .. ' — dressed', details = { 'Nothing more to take' } }
    end
    if not hasHunterKnife() then
        return { status = name .. ' — dead', details = { 'Requires: Hunter Knife' } }
    end

    ---@type ViewModel
    return {
        status = name .. ' — dead',
        action = {
            id = 'dressing',
            label = 'Field dress',
            enabled = true,
            hold = DRESS_HOLD,
        },
    }
end

---@param ctx HandlerContext
function CDressingHandler:OnActivate(ctx)
    local corpse = ctx.object
    local carcass = corpse and GRegistries.dressing
        and GRegistries.dressing[corpse.recordId:lower()]
    if not carcass then return end
    if dressState.isDressed(corpse.id) then return end
    if not hasHunterKnife() then return end

    dressState.mark(corpse.id)
    log.info(('dressing: %s -> %s'):format(corpse.recordId, carcass))
    core.sendGlobalEvent('ImmersiveCrafting_FieldDress', {
        actor = omwSelf.object,
        corpse = corpse,
        carcass = carcass,
    })
end

--#endregion

return CDressingHandler
