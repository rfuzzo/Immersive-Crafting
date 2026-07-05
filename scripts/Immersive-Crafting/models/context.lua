local log = require('scripts.Immersive-Crafting.log')

---@class CContext
---@field id Id
---@field label string
---@field recordIds string[] Record ids OR FlexTag tags that identify this station (e.g. "bowl")
---@field recordPatterns string[]|nil Lua patterns matched against candidate record ids (lowercased) — for name-based record families that can't be tagged, e.g. SD lit campfires ("sd_wood_%d_lit")
---@field recordPatternsExclude string[]|nil patterns that veto a recordPatterns match (e.g. "firewat" vs the "fire" pattern)
---@field requires string[]|nil Extra FlexTag tags that must also be present nearby (e.g. "fire")
---@field trigger string|nil Detection: "proximity" (default), "activate" (activating the object opens it), "gaze" (crosshair raycast — for statics like trees/rocks), or "condition" (named predicate, no object)
---@field condition string|nil trigger:"condition" only — predicate name in conditions.lua (e.g. "near_water")
---@field forage CContext.Forage|nil foraging definition (see handlers/foraging.lua)
---@field layout CContext.Layout|nil UI layout for the crafting window (grid or process). Falls back to `gridSize`, then a 2x2 grid.
---@field activationRange number|nil Distance in units to detect station (default 150)
---@field actions CAction[]|Id[] List of actions available at this station
local CContext = {}

---@class CContext.Forage
---@field yield { id: string, count: integer, countMax: integer|nil } granted item (real record id); countMax makes the amount random (count..countMax)
---@field woodYield { id: string, count: integer }|nil extra wood on top, granted only while "foraging gives wood" is active (setting ON, or Sun's Dusk absent)
---@field verb string|nil action label (e.g. "Gather wood")
---@field label string|nil material name for messages (e.g. "Sticks")
---@field tools string[]|nil required tool tags/ids in inventory (NOT consumed)
---@field cooldown number|nil recovery in GAME seconds (3600 = 1 game hour); default 1800
---@field holdTime number|nil seconds the forage key must be held (default 1.2)

---@class CContext.Layout
---@field kind string "grid" | "process"
---@field size integer[]|nil grid layouts: `[cols, rows]`
---@field inputs CContext.SlotDef[]|nil process layouts: ordered named input slots

---@class CContext.SlotDef
---@field key string slot id, matched against a process recipe's `inputs` key (e.g. "fuel", "input")
---@field label string|nil label shown above the slot
---@field accepts string[]|nil only items matching one of these ids/FlexTag tags may be placed here (UX guidance only — recipe matching stays a counted multiset over ALL slots)
---@field acceptsPatterns string[]|nil like `accepts`, but Lua patterns against the lowercased record id (e.g. "^ic_mold_") — for record families without tags

--- Deserialize from table
---@param tbl any
---@return CContext?
function CContext:fromTable(tbl)
    -- validate input and return nil if invalid
    -- condition contexts have no world object, hence no recordIds — they name a
    -- predicate instead; every other trigger matches recordIds/tags.
    if
        not tbl.id
        or not tbl.label
        or not tbl.actions
        or (tbl.trigger ~= 'condition' and not tbl.recordIds)
        or (tbl.trigger == 'condition' and not tbl.condition) then
        log.error('Invalid CContext table: missing required fields')
        return nil
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

-- tostring
---@return string
function CContext:ToString()
    return string.format("%s", self.id)
end

-- tostring
---@return string
function CContext:__tostring()
    return self:ToString()
end

-- equality
---@param other CContext
---@return boolean
function CContext:__eq(other)
    return self.id == other.id
end

return CContext
