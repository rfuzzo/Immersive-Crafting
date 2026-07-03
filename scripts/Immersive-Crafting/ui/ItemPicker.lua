--[[
    Materials strip — the item picker integrated INTO the crafting window,
    modelled after the vanilla alchemy window's ingredient list (no popup).

    Renders a paged grid of the player's usable materials; clicking one calls
    `view.onPick(recordId, iconPath)` (the crafting window places it into the
    selected slot). The owner passes the pre-filtered item list; this module
    only owns presentation + paging.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local I = require('openmw.interfaces')

local column = require('scripts.s3.components.column')
local row = require('scripts.s3.components.row')
local grid = require('scripts.s3.components.grid')
local text = require('scripts.s3.components.text')
local spacer = require('scripts.s3.components.spacer')

local Slot = require('scripts.Immersive-Crafting.ui.Slot')

local v2 = util.vector2
local ICON_SIZE = v2(40, 40)
local COLUMNS = 6
local PAGE_SIZE = 12 -- 2 rows of 6

local this = {}

local page = 1
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

--- Reset paging (call when the window opens).
function this.reset() page = 1 end

---@param label string
---@param enabled boolean
---@param delta integer
---@param view { refresh: fun() }
local function pageButton(label, enabled, delta, view)
    return {
        type = ui.TYPE.Text,
        -- template = enabled and I.MWUI.templates.textNormal or I.MWUI.templates.disabled,
        template = I.MWUI.templates.textNormal,
        props = { text = label, textSize = 16 },
        events = enabled and {
            mouseClick = async:callback(function()
                page = page + delta
                view.refresh()
            end),
        } or nil,
    }
end

--- Build the embedded strip.
---@param items { recordId: string, icon: string?, count: integer }[] usable materials (pre-filtered)
---@param view { onPick: fun(recordId: string, iconPath: string?), refresh: fun() }
---@return table layout
function this.Body(items, view)
    local pages = math.max(1, math.ceil(#items / PAGE_SIZE))
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    -- header: title + pager (pager only when it matters)
    local headerChildren = { text({ text = 'Materials', template = I.MWUI.templates.textNormal }) }
    if pages > 1 then
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(14, 0) } })
        headerChildren[#headerChildren + 1] = pageButton('<', page > 1, -1, view)
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(6, 0) } })
        headerChildren[#headerChildren + 1] = text({
            text = ('%d/%d'):format(page, pages),
            template = I.MWUI.templates
                .textNormal
        })
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(6, 0) } })
        headerChildren[#headerChildren + 1] = pageButton('>', page < pages, 1, view)
    end

    -- item slots for the current page
    local slots = {}
    local first = (page - 1) * PAGE_SIZE
    for i = first + 1, math.min(first + PAGE_SIZE, #items) do
        local entry = items[i]
        slots[#slots + 1] = Slot.Slot({
            name = 'pick_' .. entry.recordId,
            resource = textureForPath(entry.icon),
            count = entry.count > 1 and entry.count or nil,
            size = ICON_SIZE,
            noborder = true,
            onClick = function() view.onPick(entry.recordId, entry.icon) end,
        })
    end

    local body
    if #slots > 0 then
        body = grid({ name = 'materials_grid', columns = COLUMNS, items = slots })
    else
        body = text({ text = '(no usable materials)', template = I.MWUI.templates.textNormal })
    end

    return column({
        children = {
            row({ name = 'materials_header', children = headerChildren }),
            spacer({ props = { size = v2(0, 4) } }),
            body,
        },
    })
end

return this
