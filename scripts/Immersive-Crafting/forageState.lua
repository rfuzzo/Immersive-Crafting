--[[
    Foraging cooldown store (player context).

    Tracks when a forage source recovers, keyed per world object (gaze targets,
    e.g. one specific tree) or per context (condition contexts, e.g. clay
    digging). Times are GAME time seconds (core.getGameTime), so cooldowns pass
    while waiting/sleeping — a 3600s cooldown is one game hour.

    Persisted via the player script's onSave/onLoad.
]]

local core = require('openmw.core')

local this = {}

local cooldowns = {} ---@type table<string, number> key -> expiry (game time seconds)

--- Cooldown key for a handler context: per object when we have one, else per context.
---@param ctx HandlerContext
---@return string
function this.key(ctx)
    if ctx.object then
        return 'obj:' .. tostring(ctx.object.id)
    end
    return 'ctx:' .. tostring(ctx.context.id)
end

--- Seconds of game time until this source recovers (0 = ready).
---@param key string
---@return number
function this.remaining(key)
    local expiry = cooldowns[key]
    if not expiry then return 0 end
    return math.max(0, expiry - core.getGameTime())
end

---@param key string
---@param seconds number game seconds (3600 = 1 game hour)
function this.setCooldown(key, seconds)
    cooldowns[key] = core.getGameTime() + (seconds or 1800)
end

--- For the player script's onSave.
function this.serialize()
    return cooldowns
end

--- For the player script's onLoad.
function this.load(data)
    cooldowns = data or {}
end

return this
