--[[
    Crafting Grid UI (shaped crafting, Phase 2 — FIRST PASS / untested in-game)

    An interactive shaped-crafting grid opened at a station.
    The window renders icon-only slots and supports dropping inventory items into
    grid cells when the UI drop event payload includes the dragged item.

    OpenMW notes (verify in-game):
    - Custom interactive UI = element on the interactive 'Windows' layer +
      I.UI.setMode('Interface', {windows = {}}) to show the cursor; setMode() to exit.
      (OpenMW cannot create new named windows; this is the supported custom-UI path.)
    - Click handling: events = { mouseClick = async:callback(fn) }; mouseClick arg is nil.
    - Inventory: types.Actor.inventory(self):getAll(); item icon from item.type.record(item).icon.
    - Esc handling not wired yet: use the Close button (see TODO).
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local mwuiConstants = require('scripts.omw.mwui.constants')

local shaped = require('scripts.Immersive-Crafting.shapedCrafting')
local log = require('scripts.Immersive-Crafting.log')

local this = {}
local iconTextureCache = {} ---@type table<string, any>
local whiteTexture = mwuiConstants.whiteTexture
local CELL_SIZE = 128
local CELL_GAP = 8
local CELL_ICON_SIZE = 112

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local cols, rows = 2, 2
local cells = {} ---@type table<integer, table<integer, {recordId:string, icon:string?}>>
local ctx = nil ---@type HandlerContext?
local element = nil
local matched = nil ---@type CShapedRecipe?

-- ── helpers ─────────────────────────────────────────────────────────────────

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

-- ── widget builders ─────────────────────────────────────────────────────────

local function button(label, enabled, cb)
    return {
        type = ui.TYPE.Text,
        template = enabled and I.MWUI.templates.textButtonNormal or I.MWUI.templates.textNormal,
        props = { text = label, textSize = 20 },
        events = enabled and { mouseClick = async:callback(cb) } or nil,
    }
end

local function cellWidget(r, c, x, y)
    local cell = cells[r] and cells[r][c]
    local content = ui.content {}

    content:add({
        type = ui.TYPE.Image,
        props = {
            resource = whiteTexture,
            color = util.color.rgb(108, 84, 34),
            alpha = 0.9,
            size = util.vector2(CELL_SIZE, CELL_SIZE),
            position = util.vector2(0, 0),
        },
    })

    if cell and cell.icon then
        local iconTex = textureForIcon(cell.icon)
        if iconTex then
            content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = iconTex,
                    size = util.vector2(CELL_ICON_SIZE, CELL_ICON_SIZE),
                    position = util.vector2((CELL_SIZE - CELL_ICON_SIZE) / 2, (CELL_SIZE - CELL_ICON_SIZE) / 2),
                },
            })
        end
    end

    return {
        type = ui.TYPE.Container,
        props = {
            autoSize = false,
            size = util.vector2(CELL_SIZE, CELL_SIZE),
            position = util.vector2(x, y),
        },
        events = {
            mouseClick = async:callback(function(e) this.onCellClick(r, c, e) end),
            mouseRelease = async:callback(function(e) this.onCellDrop(r, c, e) end),
            dragDrop = async:callback(function(e) this.onCellDrop(r, c, e) end),
        },
        content = content,
    }
end

--- (Re)build and show the whole window from current state.
local function rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx then return end

    local cellSize = CELL_SIZE
    local cellGap = CELL_GAP
    local gridW = cols * cellSize + (cols - 1) * cellGap
    local gridH = rows * cellSize + (rows - 1) * cellGap

    local gridContainer = {
        type = ui.TYPE.Container,
        props = {
            autoSize = false,
            position = util.vector2(20, 54),
            size = util.vector2(gridW, gridH),
        },
        content = ui.content {},
    }

    for r = 1, rows do
        for c = 1, cols do
            local x = (c - 1) * (cellSize + cellGap)
            local y = (r - 1) * (cellSize + cellGap)
            gridContainer.content:add(cellWidget(r, c, x, y))
        end
    end

    -- result line
    refreshMatch()
    local resultText, canCraft
    if matched then
        local toolsOk = shaped.hasTools(matched.tools)
        local enough = haveEnough()
        local toolStr = (matched.tools and #matched.tools > 0)
            and ('  Tools: ' .. table.concat(matched.tools, ', ') .. (toolsOk and ' ✓' or ' ✗')) or ''
        resultText = ('→ %s x%d%s'):format(matched.label, (matched.output.count or 1), toolStr)
        canCraft = toolsOk and enough
    else
        resultText = '→ (no recipe)'
        canCraft = false
    end
    local panelHeight = 48 + gridH + 92
    local panelWidth = math.max(350, gridW + 32)

    -- buttons
    local btnRow = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            position = util.vector2(20, panelHeight - 42),
            size = util.vector2(260, 28),
        },
        content = ui.content {},
    }
    btnRow.content:add(button('Craft', canCraft, function() this.onCraft() end))
    btnRow.content:add(button('  Close', true, function() this.close() end))

    local gridPanelContent = ui.content {
        {
            type = ui.TYPE.Image,
            props = {
                resource = whiteTexture,
                color = util.color.rgb(122, 96, 40),
                alpha = 0.86,
                size = util.vector2(panelWidth - 8, panelHeight - 8),
                position = util.vector2(4, 4),
            },
        },
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textHeader,
            props = {
                position = util.vector2(16, 12),
                text = ('%s (%dx%d)'):format(ctx.context.label or 'Crafting', cols, rows),
                textSize = 20,
            },
        },
        gridContainer,
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                position = util.vector2(20, panelHeight - 72),
                text = resultText,
                textSize = 17,
            },
        },
        btnRow,
    }

    local gridPanel = {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.boxSolid,
        props = {
            autoSize = false,
            size = util.vector2(panelWidth, panelHeight),
        },
        content = gridPanelContent,
    }

    element = ui.create({
        type = ui.TYPE.Container,
        layer = 'Windows',
        props = {
            autoSize = false,
            relativePosition = util.vector2(0.34, 0.5),
            anchor = util.vector2(0.5, 0.5),
            size = util.vector2(panelWidth, panelHeight),
        },
        content = ui.content { gridPanel },
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
