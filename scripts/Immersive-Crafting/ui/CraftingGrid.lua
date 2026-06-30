--[[
    Crafting Window UI (extensible, MWUI-styled)

    An interactive crafting window opened at a station, styled after the Morrowind
    alchemy window: a bordered box with a title, a central slot area, a result /
    progress footer, and Craft/Close buttons. Items are dropped from the inventory
    into slots.

    The window is LAYOUT-DRIVEN so new station shapes are data-driven (CContext.layout):
      - "grid"    : N×M shaped-crafting grid (cloth 2x2, table 3x3). Engine: shapedCrafting.
      - "process" : named role slots (kiln fuel+input, tanning ingredients+input) with an
                    output slot and a progress bar. Engine: processCrafting.
    Add a new entry to `layouts` below to support another shape.

    Layout is built from MWUI templates (boxSolid / box / padding / horizontalLine /
    textHeader / textButtonNormal) and Flex containers — never absolute positions —
    so the window auto-sizes and matches the vanilla UI.

    OpenMW notes (verified against the UI reference):
    - util.color.rgb(r, g, b) components are 0..1 (not 0..255).
    - Custom interactive UI = element on the 'Windows' layer + I.UI.setMode('Interface')
      to show the cursor; setMode() to exit.
    - Inventory: types.Actor.inventory(self):getAll(); icon from item.type.record(item).icon.

    NOTE: the process layout's progress bar is driven by `currentProgress` (0..1). The
    timed process that advances it (start -> consume -> wait duration -> grant output,
    persisted across saves) is deferred; today Craft commits instantly like the grid.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local shaped = require('scripts.Immersive-Crafting.shapedCrafting')
local process = require('scripts.Immersive-Crafting.processCrafting')
local log = require('scripts.Immersive-Crafting.log')

local this = {}
local iconTextureCache = {} ---@type table<string, any>

-- Slot/icon sizing — Morrowind item slots are small (~44px icons).
local ICON = 44
local SLOT_GAP = 6

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local ctx = nil ---@type HandlerContext?
local element = nil
local layout = nil ---@type table? resolved layout (see resolveLayout)
local placed = {} ---@type table<string, {recordId:string, icon:string?}> slotId -> placed item
local matched = nil ---@type CShapedRecipe|CProcessRecipe|nil
local canCraft = false
local currentProgress = 0 ---@type number 0..1, driven by the (future) timed process

-- ── layout resolution ───────────────────────────────────────────────────────

--- Resolve a context's UI layout. Falls back: layout -> gridSize -> 2x2 grid.
---@param context CContext
local function resolveLayout(context)
    local L = context.layout
    if L and L.kind == 'process' then
        return { kind = 'process', inputs = L.inputs or {} }
    end
    local size = (L and L.kind == 'grid' and L.size) or context.gridSize or { 2, 2 }
    return { kind = 'grid', cols = size[1] or 2, rows = size[2] or 2 }
end

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

    local ok, tex = pcall(function() return ui.texture({ path = iconPath }) end)
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

-- ── widget builders (MWUI templates + Flex) ─────────────────────────────────

--- Invisible fixed-size spacer for gaps between flex children.
local function spacer(w, h)
    return { type = ui.TYPE.Widget, props = { size = util.vector2(w or 0, h or 0) } }
end

local function headerText(text, size)
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textHeader,
        props = { text = text, textSize = size or 20 },
    }
end

local function normalText(text)
    return { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal, props = { text = text } }
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

--- A bordered square box (boxSolid) sized to the icon, holding `iconTex` centred.
--- `events` (optional) wires drop/click handling.
local function boxSlot(iconTex, events)
    local inner = ui.content {}
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
    return {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.boxSolid,
        events = events,
        content = ui.content { { type = ui.TYPE.Widget, props = { size = util.vector2(ICON, ICON) }, content = inner } },
    }
end

--- An interactive slot bound to `slotId`: shows the placed item's icon and accepts drops.
local function slotWidget(slotId)
    local cell = placed[slotId]
    local iconTex = cell and cell.icon and textureForIcon(cell.icon) or nil
    return boxSlot(iconTex, {
        mouseClick = async:callback(function(e) this.onSlotClick(slotId, e) end),
        mouseRelease = async:callback(function(e) this.onSlotDrop(slotId, e) end),
        dragDrop = async:callback(function(e) this.onSlotDrop(slotId, e) end),
    })
end

--- A labelled slot: small caption above an interactive slot.
local function labelledSlot(slotId, label)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, align = ui.ALIGNMENT.Center },
        content = ui.content {
            normalText(label or ''),
            spacer(0, 3),
            slotWidget(slotId),
        },
    }
end

--- A display-only output slot (no events) with a caption.
local function outputSlot(label)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, align = ui.ALIGNMENT.Center },
        content = ui.content {
            normalText(label or 'Output'),
            spacer(0, 3),
            boxSlot(nil, nil),
        },
    }
end

--- A simple progress bar: bordered track with a filled boxSolid segment (0..1).
local function progressBar(value, width)
    value = math.max(0, math.min(1, value or 0))
    local fillContent = ui.content {}
    if value > 0 then
        fillContent:add({
            type = ui.TYPE.Container,
            template = I.MWUI.templates.boxSolid,
            content = ui.content {
                { type = ui.TYPE.Widget, props = { size = util.vector2(math.max(1, (width - 6) * value), 10) } },
            },
        })
    end
    return {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.box,
        content = ui.content {
            { type = ui.TYPE.Widget, props = { size = util.vector2(width - 4, 12) }, content = fillContent },
        },
    }
end

-- ── layout: bodies + resolution ─────────────────────────────────────────────

--- GRID layout: vertical Flex of horizontal slot rows. slotId = "r:c".
local function gridBody()
    local rowsContent = ui.content {}
    for r = 1, layout.rows do
        if r > 1 then rowsContent:add(spacer(0, SLOT_GAP)) end
        local rowContent = ui.content {}
        for c = 1, layout.cols do
            if c > 1 then rowContent:add(spacer(SLOT_GAP, 0)) end
            rowContent:add(slotWidget(('%d:%d'):format(r, c)))
        end
        rowsContent:add({ type = ui.TYPE.Flex, props = { horizontal = true }, content = rowContent })
    end
    return { type = ui.TYPE.Flex, props = { horizontal = false, align = ui.ALIGNMENT.Center }, content = rowsContent }
end

local function gridResolve()
    local grid = {}
    for r = 1, layout.rows do
        grid[r] = {}
        for c = 1, layout.cols do
            local cell = placed[('%d:%d'):format(r, c)]
            grid[r][c] = cell and cell.recordId or nil
        end
    end
    matched = shaped.resolveShapedRecipe(grid, ctx.action, ctx.context)
    canCraft = matched ~= nil and haveEnough()
end

--- PROCESS layout: [input slots] → [output slot]. slotId = input.key.
local function processBody()
    local row = ui.content {}
    for i, inp in ipairs(layout.inputs) do
        if i > 1 then row:add(spacer(SLOT_GAP, 0)) end
        row:add(labelledSlot(inp.key, inp.label or inp.key))
    end
    row:add(spacer(10, 0))
    row:add(headerText('→', 24))
    row:add(spacer(10, 0))
    row:add(outputSlot('Output'))
    return { type = ui.TYPE.Flex, props = { horizontal = true, align = ui.ALIGNMENT.Center }, content = row }
end

local function processResolve()
    local slots = {}
    for _, inp in ipairs(layout.inputs) do
        local cell = placed[inp.key]
        slots[inp.key] = cell and cell.recordId or nil
    end
    matched = process.resolveProcessRecipe(slots, ctx.action, ctx.context)
    canCraft = matched ~= nil and haveEnough()
end

--- Layout registry: add an entry here to support a new station shape.
local layouts = {
    grid = { body = gridBody, resolve = gridResolve, hasProgress = false },
    process = { body = processBody, resolve = processResolve, hasProgress = true },
}

-- ── footer (result + optional progress) ─────────────────────────────────────

local function footer(width)
    local lines = ui.content {}
    if matched then
        lines:add(normalText(('%s x%d'):format(matched.label, matched.output.count or 1)))
        if matched.tools and #matched.tools > 0 then
            local toolsOk = shaped.hasTools(matched.tools)
            lines:add(spacer(0, 3))
            lines:add(normalText(('Tools: %s %s')
                :format(table.concat(matched.tools, ', '), toolsOk and '[ok]' or '[missing]')))
        end
        if not haveEnough() then
            lines:add(spacer(0, 3))
            lines:add(normalText('Not enough items'))
        end
    else
        lines:add(normalText('(no recipe)'))
    end

    if layouts[layout.kind].hasProgress then
        lines:add(spacer(0, 6))
        lines:add(progressBar(currentProgress, width))
    end

    return { type = ui.TYPE.Flex, props = { horizontal = false }, content = lines }
end

-- ── window assembly ─────────────────────────────────────────────────────────

local function rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx or not layout then return end

    layouts[layout.kind].resolve()

    local lineW = 280

    local column = {
        type = ui.TYPE.Flex,
        props = { horizontal = false },
        content = ui.content {
            headerText(ctx.context.label or 'Crafting'),
            spacer(0, 8),
            hLine(lineW),
            spacer(0, 10),
            layouts[layout.kind].body(),
            spacer(0, 10),
            hLine(lineW),
            spacer(0, 8),
            footer(lineW),
            spacer(0, 10),
            {
                type = ui.TYPE.Flex,
                props = { horizontal = true },
                content = ui.content {
                    button('Craft', canCraft, function() this.onCraft() end),
                    spacer(16, 0),
                    button('Close', true, function() this.close() end),
                },
            },
        },
    }

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

-- ── public API ──────────────────────────────────────────────────────────────

---@param handlerCtx HandlerContext
function this.open(handlerCtx)
    ctx = handlerCtx
    layout = resolveLayout(ctx.context)
    placed, matched, canCraft, currentProgress = {}, nil, false, 0
    isOpen = true
    I.UI.setMode('Interface') -- show cursor; inventory remains available
    rebuild()
end

---@return boolean
function this.isOpen() return isOpen end

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
    element, layout, ctx, matched = nil, nil, nil, nil
    placed = {}
    I.UI.setMode() -- back to gameplay
end

--- Drive the process progress bar (0..1) from a future timed process.
---@param value number
function this.setProgress(value)
    currentProgress = value
    if isOpen then rebuild() end
end

-- ── event handlers ──────────────────────────────────────────────────────────

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

---@param slotId string
function this.onSlotClick(slotId, ev)
    -- Right click clears a filled slot.
    if ev and ev.button == 3 and placed[slotId] then
        placed[slotId] = nil
        rebuild()
    end
end

---@param slotId string
function this.onSlotDrop(slotId, ev)
    local recordId = extractRecordIdFromDrop(ev)
    if not recordId then
        if type(ev) == 'table' then
            local keys = {}
            for k, v in pairs(ev) do keys[#keys + 1] = tostring(k) .. ':' .. type(v) end
            log.trace('Drop unresolved at slot ' .. slotId .. ' keys=[' .. table.concat(keys, ', ') .. ']')
        end
        return
    end
    if inventoryCount(recordId) <= 0 then return end

    placed[slotId] = { recordId = recordId, icon = iconForRecordId(recordId) }
    rebuild()
end

function this.onCraft()
    if not matched or not canCraft then return end
    -- All placed items are consumed; the global executor removes them by record id
    -- and grants the output. (Same event serves grid and process crafts.)
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
