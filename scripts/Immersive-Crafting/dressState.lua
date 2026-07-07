--[[
    Field dressing — PLAYER-side persisted set of already-dressed corpses
    (corpse object id -> true). A corpse yields its carcass once; the entry
    outlives the corpse harmlessly (corpses despawn; the set stays small and
    is player save data, forageState-style).
]]

local this = {}

local dressed = {} ---@type table<string, boolean>

---@param corpseId string
---@return boolean
function this.isDressed(corpseId)
    return dressed[corpseId] == true
end

---@param corpseId string
function this.mark(corpseId)
    dressed[corpseId] = true
end

function this.serialize() return dressed end

function this.load(data) dressed = data or {} end

return this
