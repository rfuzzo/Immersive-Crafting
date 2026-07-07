local log = require('scripts.Immersive-Crafting.log')

---A non-positional (process) recipe for stations that transform inputs —
---kiln/firepit/furnace (input + fuel), charcoal pit, tanning rack, etc.
---Unlike shaped recipes there is no grid shape: `inputs` is a counted multiset
---(e.g. 3 Ore + 2 Charcoal) matched against whatever is placed in the station's
---generic slots, regardless of position. `tools` are required from the player's
---inventory and are NEVER consumed; all placed inputs ARE consumed on craft —
---except lines marked `returned` (a reusable mold placed in the Mold slot must
---be present for the match but comes back to the player). `duration` is the
---process time in GAME seconds.
---@class CProcessRecipe
---@field id Id registry key
---@field label string display name of the result
---@field context Id must match a context id (the station)
---@field action Id must match an action id (e.g. "processing")
---@field inputs CProcessRecipe.Input[] counted, non-positional ingredients
---@field duration number|nil process time in seconds (timing deferred)
---@field tools string[]|nil tool tags/ids required in inventory (NOT consumed)
---@field output { id: string, count: integer }|nil produced item (real record). Omitted for sdMeal recipes.
---@field sdMeal CRecipe.SdMeal|nil Sun's Dusk meal output — crafted via the SunsDusk_createStew event instead of a static record (see docs; requires SD; inputs must be Ingredient-type records)
local CProcessRecipe = {}

---@class CProcessRecipe.Input
---@field id string|nil record id or FlexTag tag (absent on fuel lines)
---@field count integer|nil how many are required
---@field returned boolean|nil must be placed for the match but is NOT consumed (reusable molds); NOT scaled by the batch count — one mold serves the whole batch
---@field soul string|nil "filled": only soul gems with a trapped soul satisfy this line — an INSTANCE gate, checked at consume time (filled and empty gems share a record id, so id/tag matching cannot tell them apart)
---@field fuel number|nil burn units required per batch instead of an id/count: ANY fuel-valued items feed it (data/fuels/*.json — wood 1, charcoal 3...); the minimal covering subset burns, excess fuel is allowed and never consumed

--- Deserialize from table
---@param tbl any
---@return CProcessRecipe?
function CProcessRecipe:fromTable(tbl)
    if
        not tbl.id
        or not tbl.label
        or not tbl.context
        or not tbl.action
        or not tbl.inputs
        or not (tbl.output or tbl.sdMeal) then
        log.error('Invalid CProcessRecipe table: missing required fields')
        return nil
    end

    -- inputs must be a counted array: [{ id, count }]
    if type(tbl.inputs) ~= 'table' or #tbl.inputs == 0 then
        log.error(('Invalid CProcessRecipe "%s": inputs must be a non-empty array'):format(tbl.id))
        return nil
    end
    for _, entry in ipairs(tbl.inputs) do
        if type(entry) ~= 'table' or not (entry.id or entry.fuel) then
            log.error(('Invalid CProcessRecipe "%s": each input needs an id (or fuel units)'):format(tbl.id))
            return nil
        end
    end

    local o = tbl
    setmetatable(o, self)
    self.__index = self
    return o
end

---@return string
function CProcessRecipe:ToString() return string.format("%s", self.id) end

---@return string
function CProcessRecipe:__tostring() return self:ToString() end

---@param other CProcessRecipe
---@return boolean
function CProcessRecipe:__eq(other) return self.id == other.id end

return CProcessRecipe
