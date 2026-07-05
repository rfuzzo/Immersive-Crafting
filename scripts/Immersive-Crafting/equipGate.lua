--[[
    Equipment skill gating (player-side, ALL armor — looted, bought or crafted).

    Natural progression: armor above the player's skill cannot be worn. A
    throttled watcher compares the worn equipment against the governing armor
    skill and strips anything the player is not skilled enough for, with a
    message saying what is needed. (Vanilla already scales armor RATING by
    skill — this adds the hard gate on top.)

    The required skill is derived from the item itself, so it covers every
    armor mod without authored data: in Morrowind every piece of a set shares
    the set's base armor value (iron 10 ... glass 50, ebony 60, daedric 80),
    which maps directly onto a 0-100 skill requirement.

    The governing skill (Light/Medium/Heavy Armor) is computed the same way
    the engine does it: item weight vs the slot's reference-weight GMST
    (iHelmWeight etc.) times fLightMaxMod / fMedMaxMod.
]]

local core = require('openmw.core')
local types = require('openmw.types')
local omwSelf = require('openmw.self')
local ui = require('openmw.ui')

local log = require('scripts.Immersive-Crafting.log')

local CHECK_INTERVAL = 0.5 -- seconds between equipment checks
local SKILL_FACTOR = 1.0   -- requiredSkill = baseArmor * factor
local MIN_REQUIREMENT = 15 -- anything at/below is always wearable (iron, chitin, hide)

-- slot type -> reference-weight GMST (the engine's light/medium/heavy formula)
local REF_WEIGHT_GMST = {
    [types.Armor.TYPE.Helmet]    = 'iHelmWeight',
    [types.Armor.TYPE.Cuirass]   = 'iCuirassWeight',
    [types.Armor.TYPE.LPauldron] = 'iPauldronWeight',
    [types.Armor.TYPE.RPauldron] = 'iPauldronWeight',
    [types.Armor.TYPE.Greaves]   = 'iGreavesWeight',
    [types.Armor.TYPE.Boots]     = 'iBootsWeight',
    [types.Armor.TYPE.LGauntlet] = 'iGauntletWeight',
    [types.Armor.TYPE.RGauntlet] = 'iGauntletWeight',
    [types.Armor.TYPE.LBracer]   = 'iGauntletWeight',
    [types.Armor.TYPE.RBracer]   = 'iGauntletWeight',
    [types.Armor.TYPE.Shield]    = 'iShieldWeight',
}

local this = {}

local timer = 0
local gateCache = {} ---@type table<string, { req: integer, skillId: string, skillName: string }|false> recordId -> gate info (false = ungated)

---@param rec any armor record
---@return string? skillId, string? skillName
local function governingSkill(rec)
    local gmst = REF_WEIGHT_GMST[rec.type]
    if not gmst then return nil, nil end
    local ref = core.getGMST(gmst)
    if not ref or ref <= 0 then return nil, nil end
    local lightMax = ref * (core.getGMST('fLightMaxMod') or 0.6)
    local medMax = ref * (core.getGMST('fMedMaxMod') or 0.9)
    if rec.weight <= lightMax then
        return 'lightarmor', 'Light Armor'
    elseif rec.weight <= medMax then
        return 'mediumarmor', 'Medium Armor'
    end
    return 'heavyarmor', 'Heavy Armor'
end

--- Gate info for an armor record id, or false when the piece is ungated
--- (requirement at/below MIN_REQUIREMENT, or no classifiable slot).
---@param item any equipped armor item
---@return { req: integer, skillId: string, skillName: string }|false
local function gateFor(item)
    local cached = gateCache[item.recordId]
    if cached ~= nil then return cached end

    local gate = false
    local ok, rec = pcall(function() return item.type.record(item) end)
    if ok and rec then
        local req = math.min(100, math.floor((rec.baseArmor or 0) * SKILL_FACTOR + 0.5))
        if req > MIN_REQUIREMENT then
            local skillId, skillName = governingSkill(rec)
            if skillId then
                gate = { req = req, skillId = skillId, skillName = skillName, name = rec.name }
            end
        end
    end
    gateCache[item.recordId] = gate
    return gate
end

--- Throttled equipment check: strip any worn armor above the player's skill.
---@param dt number
function this.onUpdate(dt)
    timer = timer + dt
    if timer < CHECK_INTERVAL then return end
    timer = 0

    local equipment = types.Actor.getEquipment(omwSelf)
    local changed = false
    for slot, item in pairs(equipment) do
        if item and item.type == types.Armor then
            local gate = gateFor(item)
            if gate then
                local stat = types.NPC.stats.skills[gate.skillId](omwSelf)
                local level = stat and stat.base or 0
                if level < gate.req then
                    equipment[slot] = nil
                    changed = true
                    ui.showMessage(('%s is beyond your skill (%s %d needed)')
                        :format(gate.name or item.recordId, gate.skillName, gate.req))
                    log.info(('gate: stripped "%s" (%s %d > %d)')
                        :format(item.recordId, gate.skillId, gate.req, level))
                end
            end
        end
    end
    if changed then
        types.Actor.setEquipment(omwSelf, equipment)
    end
end

return this
