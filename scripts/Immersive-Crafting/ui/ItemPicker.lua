--[[
    Item Picker widget — pick an inventory item by clicking it (no drag-and-drop).

    Opens a small bordered window listing the player's inventory items as a grid of
    clickable icon slots. Clicking an item calls `onPick(recordId, iconPath)` and
    closes the picker. Used by the crafting window when an empty slot is clicked.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local dialog = require('scripts.s3.components.dialog')
local grid = require('scripts.s3.components.grid')
local itemSlot = require('scripts.s3.components.itemSlot')
local log = require('scripts.Immersive-Crafting.log')

local v2 = util.vector2
local ICON_SIZE = v2(40, 40)
local COLUMNS = 6

local this = {}

local element = nil
local iconTextureCache = {} ---@type table<string, any>

---@param path string?
---@return any
local function textureForPath(path)
    if not path or path == '' then return nil end
    local cached = iconTextureCache[path]
    if cached then return cached end
    local ok, tex = pcall(function() return ui.texture({ path = path }) end)
    if ok and tex then
        iconTextureCache[path] = tex
        return tex
    end
    return nil
end

---@return boolean
function this.isOpen() return element ~= nil end

function this.close()
    if element then element:destroy() end
    element = nil
end

--- Open the picker.
---@param opts { onPick: fun(recordId: string, iconPath: string?), title?: string }
function this.open(opts)
    this.close()

    -- Collapse the inventory into one clickable slot per record id (summed count).
    local order, byId = {}, {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local rid = item.recordId
        local entry = byId[rid]
        if not entry then
            local icon
            local ok, rec = pcall(function() return item.type.record(item) end)
            if ok and rec and rec.icon and rec.icon ~= '' then icon = rec.icon end
            entry = { recordId = rid, icon = icon, count = 0 }
            byId[rid] = entry
            order[#order + 1] = entry
        end
        entry.count = entry.count + (item.count or 1)
    end

    local items = {}
    for _, entry in ipairs(order) do
        items[#items + 1] = itemSlot({
            name = 'pick_' .. entry.recordId,
            resource = textureForPath(entry.icon),
            count = entry.count > 1 and entry.count or nil,
            iconProps = { size = ICON_SIZE },
            events = {
                mouseClick = async:callback(function()
                    local pick = entry
                    this.close()
                    opts.onPick(pick.recordId, pick.icon)
                end),
            },
        })
    end

    if #items == 0 then
        items[1] = { template = I.MWUI.templates.textNormal, props = { text = '(inventory empty)' } }
    end

    log.trace(('ItemPicker: %d distinct items'):format(#order))

    element = ui.create({
        layer = 'Windows',
        template = I.MWUI.templates.boxSolid,
        props = {
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.62, 0.5),
        },
        content = ui.content({
            dialog({
                name = 'item_picker_dialog',
                title = opts.title or 'Select item',
                children = { grid({ name = 'item_picker_grid', columns = COLUMNS, items = items }) },
            }),
        }),
    })
end

return this
