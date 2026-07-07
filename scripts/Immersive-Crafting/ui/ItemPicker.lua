--[[
    Materials strip — the item picker integrated INTO the crafting window,
    modelled after the vanilla alchemy window's ingredient list (no popup).

    Renders a paged grid of entries; clicking one calls
    `view.onPick(recordId, iconPath)` (the crafting window places it into the
    selected slot — or applies a recipe when the strip shows recipes). The
    owner passes the pre-filtered entry list; this module only owns
    presentation, paging and hover tooltips.

    Entries: { recordId, icon?, count, label?, tooltip? } — the hover tooltip
    shows `tooltip` (multi-line, e.g. recipe ingredients), falling back to
    `label` (item/recipe name), then the record id. Search filters on `label`.

    The header is configurable: `header = { title = 'Recipes', button =
    { label = 'Materials', onClick = fn } }` renders a right-side toggle
    button (the crafting window flips the strip between materials and the
    recipe guide with it).
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local I = require('openmw.interfaces')

local c = require('scripts.Immersive-Crafting.ui.components')
local column, row, grid, text, spacer = c.column, c.row, c.grid, c.text, c.spacer

local Slot = require('scripts.Immersive-Crafting.ui.Slot')
local Tooltip = require('scripts.Immersive-Crafting.ui.Tooltip')

local v2 = util.vector2
local ICON_SIZE = v2(40, 40)
-- layout pitch: borderless 40px slot + 4px grid gap; used to derive how many
-- rows/columns fit the space the owner hands us (must match GRID_GAP)
local ICON_PITCH = 44
local GRID_GAP = 4 -- gap between strip slots so items read as distinct tiles
-- the strip's own vertical chrome around the item grid: header row + divider +
-- spacers + the bottom-anchored search row (+ its divider)
local CHROME_H = 76
-- fallback layout when the owner passes no space
local DEFAULT_COLUMNS = 6
local DEFAULT_ROWS = 2

local this = {}

local page = 1
local searchQuery = '' ---@type string live filter over the entries (label/record id substring)
local searchFocused = false ---@type boolean the search TextEdit has keyboard focus (game action keys must not fire while typing)
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

-- ── hover tooltip (shared ui/Tooltip element) ───────────────────────────────

function this.hideTooltip()
    Tooltip.hide()
end

-- ── search box ───────────────────────────────────────────────────────────────

local searchBox = nil ---@type table? cached layout so rebuilds REUSE the widget

--- The strip's search box: a bordered MWUI box around a TextEdit. The
--- template's `autoSize` must be overridden — an empty auto-sized TextEdit
--- collapses to nothing (the invisible-search-bar bug). The layout table is
--- cached so element updates keep the SAME widget (and its keyboard focus)
--- across the rebuild every keystroke triggers; `props.text` is re-synced to
--- the query each build — updates re-apply props, so a stale creation-time
--- text would wipe what was just typed (the one-letter-at-a-time bug).
---@param view { refresh: fun() }
local function searchBoxLayout(view)
    if searchBox then
        searchBox.userData.view = view
        searchBox.userData.input.props.text = searchQuery
        return searchBox
    end
    local input = {
        name = 'strip_search_input',
        type = ui.TYPE.TextEdit,
        template = I.MWUI.templates.textEditLine,
        -- grow so the field fills the row; a non-zero base width keeps it
        -- visible even if grow doesn't apply (guards the collapse bug below)
        external = { grow = 1, stretch = 1 },
        props = {
            size = v2(120, 18),
            autoSize = false,
            text = searchQuery,
        },
        events = {
            textChanged = async:callback(function(newText)
                searchQuery = newText or ''
                page = 1
                local v = searchBox and searchBox.userData.view
                if v then v.refresh() end
            end),
            -- while typing here, the owner suppresses game action keys (the
            -- contextual 'F' would close the window mid-word otherwise)
            focusGain = async:callback(function() searchFocused = true end),
            focusLoss = async:callback(function() searchFocused = false end),
        },
    }
    -- full-width field: a GROWING bordered Flex (not the box Container, which
    -- would shrink-wrap the input) fills the search row; padding + TextEdit fill
    -- it through the border/padding relativeSize slots
    searchBox = {
        name = 'strip_search',
        type = ui.TYPE.Flex,
        template = I.MWUI.templates.borders,
        external = { grow = 1, stretch = 1 },
        userData = { view = view, input = input },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content { input },
            },
        },
    }
    return searchBox
end

--- Reset paging, search and hide the tooltip (call when the window opens /
--- mode flips).
function this.reset()
    page = 1
    searchQuery = ''
    searchFocused = false -- the widget is going away; never leave this stuck on
    searchBox = nil       -- next Body() builds a fresh, empty box
    this.hideTooltip()
end

--- Is the search box focused? The owner gates game action keys on this
--- (typing must never fire them).
---@return boolean
function this.isSearchFocused()
    return searchFocused
end

-- ── header ───────────────────────────────────────────────────────────────────

---@param label string
---@param enabled boolean
---@param delta integer
---@param view { refresh: fun() }
local function pageButton(label, enabled, delta, view)
    return {
        type = ui.TYPE.Text,
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

--- Build the embedded strip. The owner passes the pixel `space` the strip may
--- fill (alchemy-style auto layout) — rows and columns are derived from it
--- (rows from the height left over after the strip's own chrome, columns from
--- the width). Without space a 6x2 fallback is used.
---@param items { recordId: string, icon: string?, count: integer, label: string?, tooltip: string? }[] entries (pre-filtered)
---@param view { onPick: fun(recordId: string, iconPath: string?), refresh: fun() }
---@param space any? util.vector2 — available pixel space for the whole strip
---@param header { title: string?, button: { label: string, onClick: fun() }? }?
---@return table layout
function this.Body(items, view, space, header)
    -- the strip is rebuilt in place — any tooltip now points at a dead widget
    this.hideTooltip()

    -- search filter: case-insensitive substring over label and record id
    if searchQuery ~= '' then
        local q = searchQuery:lower()
        local filtered = {}
        for _, e in ipairs(items) do
            if (e.label or ''):lower():find(q, 1, true)
                or e.recordId:lower():find(q, 1, true) then
                filtered[#filtered + 1] = e
            end
        end
        items = filtered
    end

    -- rows first: as many rows as the leftover height fits, then columns
    -- from the width — together the page grid fills the strip's space
    local columns, rows
    if space then
        columns = math.max(1, math.floor(space.x / ICON_PITCH))
        rows = math.max(1, math.floor((space.y - CHROME_H) / ICON_PITCH))
    else
        columns, rows = DEFAULT_COLUMNS, DEFAULT_ROWS
    end
    local pageSize = columns * rows
    local pages = math.max(1, math.ceil(#items / pageSize))
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    -- header: title + pager (pager only when it matters) + optional toggle
    local headerChildren = {
        text({ text = (header and header.title) or 'Materials', template = I.MWUI.templates.textNormal }),
    }
    if pages > 1 then
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(14, 0) } })
        headerChildren[#headerChildren + 1] = pageButton('<', page > 1, -1, view)
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(6, 0) } })
        headerChildren[#headerChildren + 1] = text({
            text = ('%d/%d'):format(page, pages),
            template = I.MWUI.templates.textNormal,
        })
        headerChildren[#headerChildren + 1] = spacer({ props = { size = v2(6, 0) } })
        headerChildren[#headerChildren + 1] = pageButton('>', page < pages, 1, view)
    end
    if header and header.button then
        -- grow spacer pushes the toggle to the header's right edge (the header
        -- row is given `stretch` below so this fills)
        headerChildren[#headerChildren + 1] = { type = ui.TYPE.Widget, external = { grow = 1 }, props = { size = v2(0, 0) } }
        headerChildren[#headerChildren + 1] = c.button({
            name = 'strip_toggle',
            label = header.button.label,
            onClick = header.button.onClick,
        })
    end

    -- item slots for the current page
    local slots = {}
    local first = (page - 1) * pageSize
    for i = first + 1, math.min(first + pageSize, #items) do
        local entry = items[i]
        slots[#slots + 1] = Slot.Slot({
            name = 'pick_' .. entry.recordId,
            resource = textureForPath(entry.icon),
            count = entry.count > 1 and entry.count or nil,
            size = ICON_SIZE,
            noborder = true,
            tooltip = entry.tooltip or entry.label or entry.recordId,
            onClick = function()
                view.onPick(entry.recordId, entry.icon)
            end,
        })
    end

    local body
    if #slots > 0 then
        body = grid({ name = 'materials_grid', columns = columns, items = slots, gap = GRID_GAP })
    else
        body = text({ text = '(nothing here)', template = I.MWUI.templates.textNormal })
    end

    return column({
        -- fill the (growing) strip box, so the search row can anchor to its
        -- bottom edge — the same grow mechanism that pins Close to the window's
        external = { grow = 1, stretch = 1 },
        children = {
            -- header: title + pager on the left, toggle pushed to the right
            row({ name = 'materials_header', external = { stretch = 1 }, children = headerChildren }),
            spacer({ props = { size = v2(0, 6) } }),
            c.hline(),
            spacer({ props = { size = v2(0, 8) } }),
            body,
            -- grows: takes all leftover height, pushing search to the bottom
            { type = ui.TYPE.Widget, external = { grow = 1 }, props = { size = v2(0, 4) } },
            -- divider, then the full-width search at the strip's bottom
            c.hline(),
            spacer({ props = { size = v2(0, 8) } }),
            row({
                name = 'strip_search_row',
                props = { align = ui.ALIGNMENT.Center },
                external = { stretch = 1 },
                children = {
                    text({ text = 'Search', template = I.MWUI.templates.textNormal }),
                    spacer({ props = { size = v2(8, 0) } }),
                    searchBoxLayout(view),
                },
            }),
            spacer({ props = { size = v2(0, 8) } }),
        },
    })
end

return this
