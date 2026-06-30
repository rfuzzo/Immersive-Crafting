--[[
    Crafting Grid UI (shaped crafting, Phase 2 — FIRST PASS / untested in-game)

    An interactive grid window opened at a crafting station. The player picks an
    item from the inventory list (left), then clicks grid cells to place it; a
    matched recipe shows in the result line. Craft dispatches the consume/produce
    to the global executor.

    OpenMW notes (verify in-game):
    - Custom interactive UI = element on the interactive 'Windows' layer +
      I.UI.setMode('Interface', {windows = {}}) to show the cursor; setMode() to exit.
      (OpenMW cannot create new named windows; this is the supported custom-UI path.)
    - Click handling: events = { mouseClick = async:callback(fn) }; mouseClick arg is nil.
    - Inventory: types.Actor.inventory(self):getAll(); item name via item.type.record(item).name.
    - Text-based for now (no item icons yet — a later polish).
    - Esc handling not wired yet: use the Close button (see TODO).
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

local MAX_INV_ROWS = 15

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local cols, rows = 2, 2
local cells = {}          ---@type table<integer, table<integer, {recordId:string, name:string}>>
local held = nil          ---@type {recordId:string, name:string}?
local ctx = nil           ---@type HandlerContext?
local element = nil
local matched = nil       ---@type CShapedRecipe?

-- ── helpers ─────────────────────────────────────────────────────────────────

---@param item any
---@return string
local function itemName(item)
    local ok, rec = pcall(function() return item.type.record(item) end)
    if ok and rec and rec.name and rec.name ~= '' then return rec.name end
    return item.recordId
end

--- Aggregate the player's inventory by record id: { recordId, name, count }[].
local function inventoryStacks()
    local out, index = {}, {}
    local items = types.Actor.inventory(self):getAll()
    for _, item in ipairs(items) do
        local id = item.recordId
        local entry = index[id]
        if entry then
            entry.count = entry.count + (item.count or 1)
        else
            entry = { recordId = id, name = itemName(item), count = item.count or 1 }
            index[id] = entry
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
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
    local have = {}
    for _, s in ipairs(inventoryStacks()) do have[s.recordId] = s.count end
    for id, n in pairs(need) do
        if (have[id] or 0) < n then return false end
    end
    return true
end

local function refreshMatch()
    if not ctx then return end
    matched = shaped.resolveShapedRecipe(asGrid(), ctx.action, ctx.context)
end

-- ── widget builders ─────────────────────────────────────────────────────────

local function short(s) return #s > 10 and (s:sub(1, 9) .. '…') or s end

local function button(label, enabled, cb)
    return {
        type = ui.TYPE.Text,
        template = enabled and I.MWUI.templates.textButtonNormal or I.MWUI.templates.disabled,
        props = { text = label, textSize = 18 },
        events = enabled and { mouseClick = async:callback(cb) } or nil,
    }
end

local function cellWidget(r, c)
    local cell = cells[r] and cells[r][c]
    return {
        type = ui.TYPE.Container,
        template = I.MWUI.templates.boxSolid,
        props = { size = util.vector2(64, 28) },
        events = { mouseClick = async:callback(function() this.onCellClick(r, c) end) },
        content = ui.content { {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = { text = cell and short(cell.name) or '·', textAlignH = ui.ALIGNMENT.Center },
        } },
    }
end

local function invRow(stack)
    local selected = held and held.recordId == stack.recordId
    return {
        type = ui.TYPE.Text,
        template = selected and I.MWUI.templates.textHeader or I.MWUI.templates.textNormal,
        props = { text = ('%s (%d)'):format(short(stack.name), stack.count) },
        events = { mouseClick = async:callback(function() this.onPick(stack) end) },
    }
end

--- (Re)build and show the whole window from current state.
local function rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx then return end

    -- left: inventory list
    local invFlex = { type = ui.TYPE.Flex, props = { horizontal = false }, content = ui.content {} }
    invFlex.content:add({ type = ui.TYPE.Text, template = I.MWUI.templates.textHeader, props = { text = 'Inventory' } })
    local stacks = inventoryStacks()
    for i = 1, math.min(#stacks, MAX_INV_ROWS) do invFlex.content:add(invRow(stacks[i])) end
    if #stacks > MAX_INV_ROWS then
        invFlex.content:add({ type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
            props = { text = ('…(%d more)'):format(#stacks - MAX_INV_ROWS) } })
    end

    -- right: grid + result
    local gridFlex = { type = ui.TYPE.Flex, props = { horizontal = false }, content = ui.content {} }
    gridFlex.content:add({ type = ui.TYPE.Text, template = I.MWUI.templates.textHeader,
        props = { text = ('%s (%dx%d)'):format(ctx.context.label or 'Crafting', cols, rows) } })
    for r = 1, rows do
        local row = { type = ui.TYPE.Flex, props = { horizontal = true }, content = ui.content {} }
        for c = 1, cols do row.content:add(cellWidget(r, c)) end
        gridFlex.content:add(row)
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
    gridFlex.content:add({ type = ui.TYPE.Text, template = I.MWUI.templates.textNormal, props = { text = resultText } })

    -- buttons
    local btnRow = { type = ui.TYPE.Flex, props = { horizontal = true }, content = ui.content {} }
    btnRow.content:add(button('Craft', canCraft, function() this.onCraft() end))
    btnRow.content:add(button('  Close', true, function() this.close() end))
    gridFlex.content:add(btnRow)

    -- assemble
    local body = { type = ui.TYPE.Flex, props = { horizontal = true }, content = ui.content { invFlex, gridFlex } }
    element = ui.create({
        type = ui.TYPE.Container,
        layer = 'Windows',
        template = I.MWUI.templates.boxSolid,
        props = { relativePosition = util.vector2(0.5, 0.5), anchor = util.vector2(0.5, 0.5) },
        content = ui.content { body },
    })
end

-- ── public API / event handlers ─────────────────────────────────────────────

---@param handlerCtx HandlerContext
function this.open(handlerCtx)
    ctx = handlerCtx
    local gs = ctx.context.gridSize or { 2, 2 }
    cols, rows = gs[1] or 2, gs[2] or 2
    cells, held, matched = {}, nil, nil
    isOpen = true
    -- cursor on, no built-in windows. Interface mode needs no target (stub is over-strict).
    ---@diagnostic disable-next-line: missing-fields
    I.UI.setMode('Interface', { windows = {} })
    rebuild()
end

function this.close()
    isOpen = false
    if element then element:destroy() end
    element = nil
    held, matched, ctx = nil, nil, nil
    I.UI.setMode() -- back to gameplay
end

function this.onPick(stack)
    held = { recordId = stack.recordId, name = stack.name }
    rebuild()
end

function this.onCellClick(r, c)
    cells[r] = cells[r] or {}
    if cells[r][c] then
        cells[r][c] = nil            -- clicking a filled cell clears it
    elseif held then
        cells[r][c] = held           -- place the held item
    end
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
