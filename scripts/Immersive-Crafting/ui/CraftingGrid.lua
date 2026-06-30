--[[
    Crafting Grid UI (shaped crafting)

    An interactive shaped-crafting window opened at a station, styled after the
    Morrowind alchemy window: a bordered box with a title, an N×M grid of item
    slots (like the alchemy ingredient slots), a result area, and Craft/Close
    buttons. Items are dropped from the inventory into grid cells.

    Layout is built from MWUI templates (boxSolid / box / padding / horizontalLine /
    textHeader / textButtonNormal) and Flex containers — NOT absolute positions —
    so the window auto-sizes and looks consistent with the vanilla UI.

    OpenMW notes (verified against the UI reference):
    - util.color.rgb(r, g, b) components are 0..1 (not 0..255).
    - Custom interactive UI = element on the interactive 'Windows' layer +
      I.UI.setMode('Interface') to show the cursor; setMode() to exit.
    - Click handling: events = { mouseClick = async:callback(fn) }.
    - Inventory: types.Actor.inventory(self):getAll(); icon from item.type.record(item).icon.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local shaped = require('scripts.Immersive-Crafting.shapedCrafting')
local log = require('scripts.Immersive-Crafting.log')

local this = {}
local iconTextureCache = {} ---@type table<string, any>

-- Slot/icon sizing — Morrowind item slots are small (~44px icons).
local ICON = 44
local SLOT_GAP = 6
local RESULT_W = 132

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local cols, rows = 2, 2
local cells = {} ---@type table<integer, table<integer, {recordId:string, icon:string?}>>
local ctx = nil ---@type HandlerContext?
local element = nil
local matched = nil ---@type CShapedRecipe?

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

---@param iconPath string?
---@return any
local function textureForIcon(iconPath)
    if not iconPath or iconPath == '' then return nil end
    local cached = iconTextureCache[iconPath]
    if cached then return cached end

    local ok, tex = pcall(function()
        return ui.texture({ path = iconPath })
    end)
    if ok and tex then
        iconTextureCache[iconPath] = tex
        return tex
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

--- How many of each record id are placed in the grid.
local function placedCounts()
    local counts = {}
    for r = 1, rows do
        for c = 1, cols do
            local cell = cells[r] and cells[r][c]
            if cell then counts[cell.recordId] = (counts[cell.recordId] or 0) + 1 end
        end
    end
    return counts
end

--- Build the recordId|nil grid the matcher expects.
local function asGrid()
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            local cell = cells[r] and cells[r][c]
            grid[r][c] = cell and cell.recordId or nil
        end
    end
    return grid
end

--- Do we actually own enough of everything placed?
local function haveEnough()
    local need = placedCounts()
    for id, n in pairs(need) do
        if inventoryCount(id) < n then return false end
    end
    return true
end

local function refreshMatch()
    if not ctx then return end
    matched = shaped.resolveShapedRecipe(asGrid(), ctx.action, ctx.context)
end

-- ── widget builders (MWUI templates + Flex) ─────────────────────────────────

--- Invisible fixed-size spacer for gaps between flex children.
local function spacer(w, h)
    return { type = ui.TYPE.Widget, props = { size = util.vector2(w or 0, h or 0) } }
end

local function headerText(text)
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textHeader,
        props = { text = text, textSize = 20 },
    }
end

local function normalText(text)
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = { text = text },
    }
end

local function hLine(width)
    return {
        type = ui.TYPE.Image,
        template = I.MWUI.templates.horizontalLine,
        props = { size = util.vector2(width, 2) },
    }
end

local function button(label, enabled, cb)
    return {
        type = ui.TYPE.Text,
        template = enabled and I.MWUI.templates.textButtonNormal or I.MWUI.templates.disabled,
        props = { text = label, textSize = 18 },
        events = enabled and { mouseClick = async:callback(cb) } or nil,
    }
end

--- A single grid slot: a bordered box (boxSolid) sized to the icon, with the
--- item icon centred inside when the cell is filled. Drop/click events attach here.
local function slotWidget(r, c)
    local cell = cells[r] and cells[r][c]
    local inner = ui.content {}

    if cell and cell.icon then
        local iconTex = textureForIcon(cell.icon)
        if iconTex then
            inner:add({
                type = ui.TYPE.Image,
                props = {
                    resource = iconTex,
                    size = util.vector2(ICON, ICON),
                    relativePosition = util.vector2(0.5, 0.5),
                    anchor = util.vector2(0.5, 0.5),
                },
            })
        end
    end

    -- fixed-size inner area so the boxSolid border wraps a consistent square
    local slotInner = {
        type = ui.TYPE.Widget,
        props = { size = util.vector2(ICON, ICON) },
        content = inner,
    }

    return {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.boxSolid,
        events = {
            mouseClick = async:callback(function(e) this.onCellClick(r, c, e) end),
            mouseRelease = async:callback(function(e) this.onCellDrop(r, c, e) end),
            dragDrop = async:callback(function(e) this.onCellDrop(r, c, e) end),
        },
        content = ui.content { slotInner },
    }
end

--- The N×M slot grid as a vertical Flex of horizontal row Flexes.
local function gridWidget()
    local rowsContent = ui.content {}
    for r = 1, rows do
        if r > 1 then rowsContent:add(spacer(0, SLOT_GAP)) end
        local rowContent = ui.content {}
        for c = 1, cols do
            if c > 1 then rowContent:add(spacer(SLOT_GAP, 0)) end
            rowContent:add(slotWidget(r, c))
        end
        rowsContent:add({ type = ui.TYPE.Flex, props = { horizontal = true }, content = rowContent })
    end
    return { type = ui.TYPE.Flex, props = { horizontal = false }, content = rowsContent }
end

--- The result column: "Result" header + recipe/tools status (or "no recipe").
---@return table widget, boolean canCraft
local function resultWidget()
    refreshMatch()

    local lines = ui.content {}
    lines:add(headerText('Result'))
    lines:add(spacer(0, 6))

    local canCraft = false
    if matched then
        local toolsOk = shaped.hasTools(matched.tools)
        local enough = haveEnough()
        lines:add(normalText(('%s x%d'):format(matched.label, matched.output.count or 1)))
        if matched.tools and #matched.tools > 0 then
            lines:add(spacer(0, 4))
            lines:add(normalText(('Tools: %s %s')
                :format(table.concat(matched.tools, ', '), toolsOk and '[ok]' or '[missing]')))
        end
        if not enough then
            lines:add(spacer(0, 4))
            lines:add(normalText('Not enough items'))
        end
        canCraft = toolsOk and enough
    else
        lines:add(normalText('(no recipe)'))
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, autoSize = false, size = util.vector2(RESULT_W, ICON * rows + SLOT_GAP * (rows - 1)) },
        content = lines,
    }, canCraft
end

--- (Re)build and show the whole window from current state.
local function rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx then return end

    local result, canCraft = resultWidget()

    -- approximate content width for separators (grid + gap + result column)
    local gridW = cols * (ICON + 12) + (cols - 1) * SLOT_GAP
    local lineW = math.max(240, gridW + 16 + RESULT_W)

    -- grid + result, side by side
    local body = {
        type = ui.TYPE.Flex,
        props = { horizontal = true },
        content = ui.content {
            gridWidget(),
            spacer(16, 0),
            result,
        },
    }

    -- buttons
    local buttons = {
        type = ui.TYPE.Flex,
        props = { horizontal = true },
        content = ui.content {
            button('Craft', canCraft, function() this.onCraft() end),
            spacer(16, 0),
            button('Close', true, function() this.close() end),
        },
    }

    -- vertical stack: title / line / body / line / buttons
    local column = {
        type = ui.TYPE.Flex,
        props = { horizontal = false },
        content = ui.content {
            headerText(ctx.context.label or 'Crafting'),
            spacer(0, 8),
            hLine(lineW),
            spacer(0, 10),
            body,
            spacer(0, 10),
            hLine(lineW),
            spacer(0, 8),
            buttons,
        },
    }

    -- padded bordered window on the interactive Windows layer
    element = ui.create({
        type = ui.TYPE.Container,
        layer = 'Windows',
        template = I.MWUI.templates.boxSolid,
        props = {
            anchor = util.vector2(0.5, 0.5),
            relativePosition = util.vector2(0.4, 0.5),
        },
        content = ui.content {
            {
                type = ui.TYPE.Container,
                template = I.MWUI.templates.padding,
                content = ui.content { column },
            },
        },
    })
end

-- ── public API / event handlers ─────────────────────────────────────────────

---@param handlerCtx HandlerContext
function this.open(handlerCtx)
    ctx = handlerCtx
    local gs = ctx.context.gridSize or { 2, 2 }
    cols, rows = gs[1] or 2, gs[2] or 2
    cells, matched = {}, nil
    isOpen = true
    -- Enter interface mode (inventory remains available in default Interface mode).
    I.UI.setMode('Interface')
    rebuild()
end

---@return boolean
function this.isOpen()
    return isOpen
end

---@return string?
function this.getContextId()
    if not ctx or not ctx.context then return nil end
    return ctx.context.id
end

---@param handlerCtx HandlerContext
function this.toggle(handlerCtx)
    if isOpen then
        this.close()
        return
    end
    this.open(handlerCtx)
end

function this.close()
    isOpen = false
    if element then element:destroy() end
    element = nil
    matched, ctx = nil, nil
    I.UI.setMode() -- back to gameplay
end

---@param ev any
---@return string?
local function extractRecordIdFromDrop(ev)
    if type(ev) ~= 'table' then return nil end

    local invSet = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        invSet[item.recordId] = true
    end

    local visited = {}
    local function probe(value, depth)
        if depth > 4 then return nil end
        if type(value) == 'string' then
            return invSet[value] and value or nil
        end
        if type(value) ~= 'table' then return nil end
        if visited[value] then return nil end
        visited[value] = true

        if type(value.recordId) == 'string' and invSet[value.recordId] then return value.recordId end
        if type(value.id) == 'string' and invSet[value.id] then return value.id end
        if type(value.itemId) == 'string' and invSet[value.itemId] then return value.itemId end
        if type(value.baseId) == 'string' and invSet[value.baseId] then return value.baseId end

        for _, nested in pairs(value) do
            local found = probe(nested, depth + 1)
            if found then return found end
        end
        return nil
    end

    return probe(ev, 0)
end

function this.onCellClick(r, c, ev)
    cells[r] = cells[r] or {}
    -- Right click clears a filled slot.
    if ev and ev.button == 3 and cells[r][c] then
        cells[r][c] = nil
        rebuild()
    end
end

function this.onCellDrop(r, c, ev)
    local recordId = extractRecordIdFromDrop(ev)
    if not recordId then
        if type(ev) == 'table' then
            local keys = {}
            for k, v in pairs(ev) do
                keys[#keys + 1] = tostring(k) .. ':' .. type(v)
            end
            log.trace('Drop unresolved at slot (' .. r .. ',' .. c .. ') keys=[' .. table.concat(keys, ', ') .. ']')
        end
        return
    end
    if inventoryCount(recordId) <= 0 then return end

    cells[r] = cells[r] or {}
    cells[r][c] = {
        recordId = recordId,
        icon = iconForRecordId(recordId),
    }
    rebuild()
end

function this.onCraft()
    if not matched then return end
    local consume = {}
    for id, count in pairs(placedCounts()) do consume[#consume + 1] = { id = id, count = count } end
    core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
        actor = self.object,
        consume = consume,
        output = matched.output,
    })
    log.info('Crafted ' .. (matched.label or matched.id))
    this.close()
end

return this
