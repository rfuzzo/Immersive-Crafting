--[[
    Sun's Dusk liquids — GLOBAL side (required by init.lua).

    Two jobs, both via SD's GLOBAL interface (I.SunsDusk.isConsumable returns
    ({ orig, q, liquid }, "drink") for its dynamic bottle records; nil-safe
    when SD isn't loaded):

    - onClassify: answer the player's ImmersiveCrafting_ClassifyLiquids query
      so the sd:<liquid> matcher (sdLiquids.lua) can tell water from sujamma.
    - emptyContainerFor: consuming an SD bottle in a craft must not eat the
      container — the executors (onCraftShaped, globalProcessing.onStart) call
      this after removing a consumed input and grant the empty container
      (`orig`) back. The water is used; the waterskin remains.
      NOTE: the whole bottle's content goes into the craft regardless of fill
      level — pick a small bottle if that bothers you (charge-level splitting
      would need SD's internal record minting; see docs/TODO.md).
]]

local I = require('openmw.interfaces')

local this = {}

--- The empty-container record id for an SD liquid bottle, or nil.
---@param recordId string
---@return string? origId
function this.emptyContainerFor(recordId)
    local sd = I.SunsDusk
    if not (sd and sd.isConsumable) then return nil end
    local ok, rev, typ = pcall(sd.isConsumable, recordId)
    if ok and typ == 'drink' and rev and rev.orig then
        return rev.orig
    end
    return nil
end

--- Event: classify candidate record ids for the player's sd:<liquid> mirror.
---@param data { actor: any, ids: string[] }
function this.onClassify(data)
    if not (data and data.actor and data.ids) then return end
    local sd = I.SunsDusk
    if not (sd and sd.isConsumable) then return end
    local map = {}
    for _, id in ipairs(data.ids) do
        local ok, rev, typ = pcall(sd.isConsumable, id)
        if ok and typ == 'drink' and rev then
            map[id] = { liquid = rev.liquid or 'water', orig = rev.orig }
        end
    end
    data.actor:sendEvent('ImmersiveCrafting_LiquidSync', { liquids = map })
end

return this
