--[[
    Progression milestones — PLAYER-side persisted set (milestone id -> true),
    dressState-style. Milestones gate the recipe GUIDE's visibility (never the
    matching itself) and fire the tutorial popups.

    A milestone is granted when the player BUILDS the matching station
    (globalBuilding -> ImmersiveCrafting_Milestone event) or the first time
    they USE one found in the world (Crafting.toggle) — either way you have
    kiln access because you stood at a kiln.
]]

local this = {}

local unlocked = {} ---@type table<string, boolean>

---@param id string
---@return boolean
function this.has(id)
    return unlocked[id] == true
end

--- Grant a milestone. Returns true when it was NEW (caller shows the popup).
---@param id string
---@return boolean new
function this.grant(id)
    if not id or unlocked[id] then return false end
    unlocked[id] = true
    return true
end

function this.serialize() return unlocked end

function this.load(data) unlocked = data or {} end

return this
