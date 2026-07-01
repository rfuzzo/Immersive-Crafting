local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local log = require('scripts.Immersive-Crafting.log')

local box = require 'scripts.s3.components.box'
local column = require 'scripts.s3.components.column'
local spacer = require 'scripts.s3.components.spacer'
local text = require 'scripts.s3.components.text'
local grid = require 'scripts.s3.components.grid'
local itemSlot = require 'scripts.s3.components.itemSlot'

local v2 = util.vector2
local whiteTexture = ui.texture { path = 'white' }

local ICON_SIZE = v2(44, 44)
local ICON_COLOR = util.color.rgb(0.72, 0.48, 0.18)

local this = {}


-- ── layout: bodies + resolution ─────────────────────────────────────────────

--- GRID layout: vertical Flex of horizontal slot rows. slotId = "r:c".
---@param layout CContext.Layout?
---@return openmw.ui.Layout?
function this.Body(layout)
    if not layout then
        log.error('Cannot build crafting grid layout: layout is nil')
        return nil
    end

    local rows = layout.size[1] or 2
    local cols = layout.size[2] or 2
    log.trace('Building crafting grid layout with ' .. rows .. ' rows and ' .. cols .. ' cols')

    return box({
        props = {
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.5, 0.5),
        },
        name = 'grid_box',
        children = {
            column({
                name = 'grid_body',
                children = {
                    -- text({ name = 'header', text = "title" }),
                    -- spacer({ name = 'spacer', props = { size = v2(0, 4) } }),
                    grid({
                        name = 'crafting_grid',
                        columns = cols,
                        items = {
                            itemSlot({ name = 'ct_item_slot_one', resource = whiteTexture, count = 1, iconProps = { size = ICON_SIZE } }),
                            itemSlot({ name = 'ct_item_slot_two', resource = whiteTexture, count = 2, iconProps = { size = ICON_SIZE, color = ICON_COLOR } }),
                            itemSlot({ name = 'ct_item_slot_three', resource = whiteTexture, count = 3, iconProps = { size = ICON_SIZE } }),
                        },
                    }),
                },
            }),
        },
    })
end

function this.Resolve()
    -- local grid = {}
    -- for r = 1, layout.rows do
    --     grid[r] = {}
    --     for c = 1, layout.cols do
    --         local cell = placed[('%d:%d'):format(r, c)]
    --         grid[r][c] = cell and cell.recordId or nil
    --     end
    -- end
    -- matched = shaped.resolveShapedRecipe(grid, ctx.action, ctx.context)
    -- canCraft = matched ~= nil and haveEnough()
end

-- ── state ───────────────────────────────────────────────────────────────────


local layout = nil ---@type table? resolved layout (see resolveLayout)
local placed = {} ---@type table<string, {recordId:string, icon:string?}> slotId -> placed item
local matched = nil ---@type CShapedRecipe|CProcessRecipe|nil

local currentProgress = 0 ---@type number 0..1, driven by the (future) timed process


-- ── helpers (inventory / icons) ─────────────────────────────────────────────

---@param recordId string
---@return string?
local function iconForRecordId(recordId)
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if item.recordId == recordId then
            local ok, rec = pcall(function() return item.type.record(item) end)
            if ok and rec and rec.icon and rec.icon ~= '' then
                return rec.icon
            end
            break
        end
    end
    return nil
end

---@param recordId string
---@return integer
local function inventoryCount(recordId)
    local total = 0
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if item.recordId == recordId then
            total = total + (item.count or 1)
        end
    end
    return total
end

--- How many of each record id are placed across all slots.
local function placedCounts()
    local counts = {}
    for _, cell in pairs(placed) do
        counts[cell.recordId] = (counts[cell.recordId] or 0) + 1
    end
    return counts
end

--- Do we actually own enough of everything placed?
local function haveEnough()
    for id, n in pairs(placedCounts()) do
        if inventoryCount(id) < n then return false end
    end
    return true
end










-- ── public API ──────────────────────────────────────────────────────────────


-- ── event handlers ──────────────────────────────────────────────────────────

-- ---@param ev any
-- ---@return string?
-- local function extractRecordIdFromDrop(ev)
--     if type(ev) ~= 'table' then return nil end

--     local invSet = {}
--     for _, item in ipairs(types.Actor.inventory(self):getAll()) do
--         invSet[item.recordId] = true
--     end

--     local visited = {}
--     local function probe(value, depth)
--         if depth > 4 then return nil end
--         if type(value) == 'string' then
--             return invSet[value] and value or nil
--         end
--         if type(value) ~= 'table' then return nil end
--         if visited[value] then return nil end
--         visited[value] = true

--         if type(value.recordId) == 'string' and invSet[value.recordId] then return value.recordId end
--         if type(value.id) == 'string' and invSet[value.id] then return value.id end
--         if type(value.itemId) == 'string' and invSet[value.itemId] then return value.itemId end
--         if type(value.baseId) == 'string' and invSet[value.baseId] then return value.baseId end

--         for _, nested in pairs(value) do
--             local found = probe(nested, depth + 1)
--             if found then return found end
--         end
--         return nil
--     end

--     return probe(ev, 0)
-- end

-- ---@param slotId string
-- function this.onSlotClick(slotId, ev)
--     -- Right click clears a filled slot.
--     if ev and ev.button == 3 and placed[slotId] then
--         placed[slotId] = nil
--         rebuild()
--     end
-- end

-- ---@param slotId string
-- function this.onSlotDrop(slotId, ev)
--     local recordId = extractRecordIdFromDrop(ev)
--     if not recordId then
--         if type(ev) == 'table' then
--             local keys = {}
--             for k, v in pairs(ev) do keys[#keys + 1] = tostring(k) .. ':' .. type(v) end
--             log.trace('Drop unresolved at slot ' .. slotId .. ' keys=[' .. table.concat(keys, ', ') .. ']')
--         end
--         return
--     end
--     if inventoryCount(recordId) <= 0 then return end

--     placed[slotId] = { recordId = recordId, icon = iconForRecordId(recordId) }
--     rebuild()
-- end


return this
