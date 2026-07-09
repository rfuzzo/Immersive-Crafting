--[[
    Crafted-gear bonus — GLOBAL side.

    Gear you FORGE is finer than gear you buy: equipment outputs of a craft
    are granted as a "Wrought" record clone with better numbers (weapons hit
    harder, armor rates higher, both last longer and are worth more). This is
    the incentive for walking the whole chain: mine -> smelt -> mold -> cast
    beats a shop shelf.

    Implementation: one boosted clone per base record, minted lazily via
    types.<T>.createRecordDraft + world.createRecord and cached in the save
    (saveData.bonusRecords, baseId -> mintedId — dynamic records persist in
    saves on 0.51, as the SD meal interop established). Non-equipment outputs
    (ingots, molds, ceramics) pass through untouched. Everything is
    pcall-guarded: if record drafting is unavailable, the base item is
    granted instead — the bonus is a bonus, never a break.

    The boosted clone keeps the base MESH, so the equip gate's mesh-based
    material lookup classifies it correctly (crafted daedric still gates at
    80). Known caveat: dynamic records carry no tags, so melt-down recipes
    matching by material tag skip Wrought gear (TODO if it ever matters).
]]

local world = require('openmw.world')
local types = require('openmw.types')

local log = require('scripts.Immersive-Crafting.log')

local PREFIX = 'Wrought '
local DAMAGE_FACTOR = 1.15 -- weapon min/max damage
local ARMOR_FACTOR = 1.15  -- armor rating (min +2)
local HEALTH_FACTOR = 1.25 -- condition/durability
local VALUE_FACTOR = 1.25

-- player-pushed option (ImmersiveCrafting_SetOptions)
local options = { craftedBonus = true }

local this = {}

function this.onSetOptions(data)
    if data and data.craftedBonus ~= nil then
        options.craftedBonus = data.craftedBonus and true or false
    end
end

local function cache()
    ---@diagnostic disable-next-line: lowercase-global
    if not saveData then saveData = {} end
    saveData.bonusRecords = saveData.bonusRecords or {}
    return saveData.bonusRecords
end

local function boost(v, factor, minGain)
    v = v or 0
    return math.max(math.floor(v * factor + 0.5), v + (minGain or 0))
end

local function mintWeapon(rec)
    local draft = types.Weapon.createRecordDraft {
        name = PREFIX .. (rec.name or ''),
        model = rec.model,
        icon = rec.icon,
        enchant = rec.enchant,
        isMagical = rec.isMagical,
        isSilver = rec.isSilver,
        weight = rec.weight,
        value = boost(rec.value, VALUE_FACTOR),
        type = rec.type,
        health = boost(rec.health, HEALTH_FACTOR),
        speed = rec.speed,
        reach = rec.reach,
        enchantCapacity = rec.enchantCapacity,
        chopMinDamage = boost(rec.chopMinDamage, DAMAGE_FACTOR),
        chopMaxDamage = boost(rec.chopMaxDamage, DAMAGE_FACTOR, 1),
        slashMinDamage = boost(rec.slashMinDamage, DAMAGE_FACTOR),
        slashMaxDamage = boost(rec.slashMaxDamage, DAMAGE_FACTOR, 1),
        thrustMinDamage = boost(rec.thrustMinDamage, DAMAGE_FACTOR),
        thrustMaxDamage = boost(rec.thrustMaxDamage, DAMAGE_FACTOR, 1),
    }
    return world.createRecord(draft).id
end

local function mintArmor(rec)
    local draft = types.Armor.createRecordDraft {
        name = PREFIX .. (rec.name or ''),
        model = rec.model,
        icon = rec.icon,
        enchant = rec.enchant,
        weight = rec.weight,
        value = boost(rec.value, VALUE_FACTOR),
        type = rec.type,
        health = boost(rec.health, HEALTH_FACTOR),
        enchantCapacity = rec.enchantCapacity,
        baseArmor = boost(rec.baseArmor, ARMOR_FACTOR, 2),
    }
    return world.createRecord(draft).id
end

--- The record id to GRANT for a crafted output: the cached/minted "Wrought"
--- clone for weapons and armor, the base id for everything else (or when the
--- bonus is off / minting fails).
---@param baseId string
---@return string
function this.boostedOutput(baseId)
    if not options.craftedBonus or not baseId then return baseId end
    local key = baseId:lower()
    local cached = cache()[key]
    if cached then return cached end

    local okW, wrec = pcall(function() return types.Weapon.record(baseId) end)
    local okA, arec = pcall(function() return types.Armor.record(baseId) end)
    local mintOk, minted
    if okW and wrec then
        mintOk, minted = pcall(mintWeapon, wrec)
    elseif okA and arec then
        mintOk, minted = pcall(mintArmor, arec)
    else
        return baseId -- not equipment: ingots, molds, ceramics, food...
    end

    if mintOk and minted then
        cache()[key] = minted
        log.info(('bonus: minted "%s" for %s'):format(minted, baseId))
        return minted
    end
    log.warn(('bonus: could not mint a Wrought clone for %s (%s) — granting the base item')
        :format(baseId, tostring(minted)))
    return baseId
end

return this
