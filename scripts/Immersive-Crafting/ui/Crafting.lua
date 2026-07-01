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
    so the window auto-sizes and matches the vanilla ui.

    OpenMW notes (verified against the UI reference):
    - util.color.rgb(r, g, b) components are 0..1 (not 0..255).
    - Custom interactive UI = element on the 'Windows' layer + I.UI.setMode('Interface')
      to show the cursor; setMode() to exit.
    - Inventory: types.Actor.inventory(self):getAll(); icon from item.type.record(item).icon.

    NOTE: the process layout's progress bar is driven by `currentProgress` (0..1). The
    timed process that advances it (start -> consume -> wait duration -> grant output,
    persisted across saves) is deferred; today Craft commits instantly like the grid.
]]

local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')

local dialog = require 'scripts.s3.components.dialog'
local container = require 'scripts.s3.components.container'
local column = require 'scripts.s3.components.column'
local spacer = require 'scripts.s3.components.spacer'

local grid = require('scripts.Immersive-Crafting.ui.CraftingGrid')
local process = require('scripts.Immersive-Crafting.ui.CraftingProcess')
local log = require('scripts.Immersive-Crafting.log')
local v2 = util.vector2

local this = {}

-- ── state ───────────────────────────────────────────────────────────────────
local isOpen = false
local ctx = nil ---@type HandlerContext?
local layout = nil ---@type CContext.Layout? resolved layout (see resolveLayout)
local element = nil
local canCraft = false

-- ── window assembly ─────────────────────────────────────────────────────────

---@class CraftingLayout
---@field body fun():table returns the body content (slots) for the layout
---@field resolve fun() resolves the layout's state (placed items, matched recipe, canCraft)

--- Layout registry: add an entry here to support a new station shape.
local layouts = {
    grid = { body = grid.Body, resolve = grid.Resolve },
    process = { body = process.Body, resolve = process.Resolve },
} ---@type table<string, CraftingLayout>

local colorFromGMST = function(gmst)
    local colorString = core.getGMST(gmst)
    local numberTable = {}
    for numberString in colorString:gmatch("([^,]+)") do
        if #numberTable == 3 then break end
        local number = tonumber(numberString:match("^%s*(.-)%s*$"))
        if number then
            table.insert(numberTable, number / 255)
        end
    end

    if #numberTable < 3 then error('Invalid color GMST name: ' .. gmst) end

    return util.color.rgb(table.unpack(numberTable))
end

local function rebuild()
    if element then element:destroy() end
    if not isOpen or not ctx or not layout then return end

    local body = layouts[layout.kind].body(layout)
    if not body then
        log.error('Failed to build crafting window body for layout kind: ' .. layout.kind)
        return
    end

    local headerSection = {
        props = {
            size = util.vector2(0, 20),
        },
        external = {
            grow = 1,
            stretch = 1,
        }
    }

    local events = {
        mousePress = async:callback(function(mouseEvent, layout)
            if not element then return end
            element.layout.userData.lastMouseDownPosition = mouseEvent.position

            -- Convert any relativeSize to absolute size
            if (element.layout.props.relativeSize) then
                local widthAbsolute = element.layout.props.relativeSize.x * ui.screenSize().x
                local heightAbsolute = element.layout.props.relativeSize.y * ui.screenSize().y
                element.layout.props.size = v2(widthAbsolute, heightAbsolute)
                element.layout.props.relativeSize = nil
            end

            -- Convert any relativePosition to absolute position
            if (element.layout.props.relativePosition) then
                local xAbsolute = element.layout.props.relativePosition.x * ui.screenSize().x
                local yAbsolute = element.layout.props.relativePosition.y * ui.screenSize().y
                -- We must now incorporate the anchor property
                if (element.layout.props.anchor) then
                    xAbsolute = xAbsolute - element.layout.props.anchor.x * element.layout.props.size.x
                    yAbsolute = yAbsolute - element.layout.props.anchor.y * element.layout.props.size.y
                    element.layout.props.anchor = nil
                end
                element.layout.props.position = v2(xAbsolute, yAbsolute)
                element.layout.props.relativePosition = nil
            end

            local elemX, elemY, elemW, elemH = element.layout.props.position.x, element.layout.props.position.y,
                element.layout.props.size.x, element.layout.props.size.y
            local mx                         = mouseEvent.position.x
            local my                         = mouseEvent.position.y
            local edgeMargin                 = 15 -- How many pixels from the edge counts as clicking the edge

            local onLeft                     = mx >= elemX and mx <= elemX + edgeMargin
            local onRight                    = mx >= elemX + elemW - edgeMargin and mx <= elemX + elemW
            local onTop                      = my >= elemY and my <= elemY + edgeMargin
            local onBottom                   = my >= elemY + elemH - edgeMargin and my <= elemY + elemH

            local edge                       = nil
            if (onTop and onLeft) then
                element.layout.userData.edgeWhenMouseDown = "top-left"
            elseif (onTop and onRight) then
                element.layout.userData.edgeWhenMouseDown = "top-right"
            elseif (onBottom and onLeft) then
                element.layout.userData.edgeWhenMouseDown = "bottom-left"
            elseif (onBottom and onRight) then
                element.layout.userData.edgeWhenMouseDown = "bottom-right"
            elseif (onLeft) then
                element.layout.userData.edgeWhenMouseDown = "left"
            elseif (onRight) then
                element.layout.userData.edgeWhenMouseDown = "right"
            elseif (onTop) then
                element.layout.userData.edgeWhenMouseDown = "top"
            elseif (onBottom) then
                element.layout.userData.edgeWhenMouseDown = "bottom"
            else
                element.layout.userData.edgeWhenMouseDown = nil
            end
        end),
        mouseMove = async:callback(function(mouseEvent, layout)
            if not element then return end
            if (mouseEvent.button == 1) then
                -- Left mouse is down
                if (element.layout.userData.lastMouseDownPosition) then
                    local delta = mouseEvent.position - element.layout.userData.lastMouseDownPosition
                    element.layout.userData.lastMouseDownPosition = mouseEvent.position

                    -- Handle resizing
                    if (element.layout.userData.edgeWhenMouseDown ~= nil) then
                        if (element.layout.userData.edgeWhenMouseDown == "left") then
                            element.layout.props.size = v2(element.layout.props.size.x - delta.x,
                                element.layout.props.size.y)
                            element.layout.props.position = element.layout.props.position + v2(delta.x, 0)
                        elseif (element.layout.userData.edgeWhenMouseDown == "right") then
                            element.layout.props.size = v2(element.layout.props.size.x + delta.x,
                                element.layout.props.size.y)
                        elseif (element.layout.userData.edgeWhenMouseDown == "top") then
                            element.layout.props.size = v2(element.layout.props.size.x,
                                element.layout.props.size.y - delta.y)
                            element.layout.props.position = element.layout.props.position + v2(0, delta.y)
                        elseif (element.layout.userData.edgeWhenMouseDown == "bottom") then
                            element.layout.props.size = v2(element.layout.props.size.x,
                                element.layout.props.size.y + delta.y)
                        elseif (element.layout.userData.edgeWhenMouseDown == "top-left") then
                            element.layout.props.size = v2(element.layout.props.size.x - delta.x,
                                element.layout.props.size.y - delta.y)
                            element.layout.props.position = element.layout.props.position + delta
                        elseif (element.layout.userData.edgeWhenMouseDown == "top-right") then
                            element.layout.props.size = v2(element.layout.props.size.x + delta.x,
                                element.layout.props.size.y - delta.y)
                            element.layout.props.position = element.layout.props.position + v2(0, delta.y)
                        elseif (element.layout.userData.edgeWhenMouseDown == "bottom-left") then
                            element.layout.props.size = v2(element.layout.props.size.x - delta.x,
                                element.layout.props.size.y + delta.y)
                            element.layout.props.position = element.layout.props.position + v2(delta.x, 0)
                        elseif (element.layout.userData.edgeWhenMouseDown == "bottom-right") then
                            element.layout.props.size = v2(element.layout.props.size.x + delta.x,
                                element.layout.props.size.y + delta.y)
                        end
                    else
                        -- No resize, so let's move/drag the entire element
                        local currentPos = element.layout.props.position or v2(0, 0)
                        element.layout.props.position = currentPos + delta
                    end

                    element:update()
                end
            end
        end),
    }

    local dlg = {
        layer = "Windows",
        props = {
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.4, 0.5),
            size = v2(300, 300)
        },
        userData = {
            lastMouseDownPosition = nil,
            edgeWhenMouseDown = nil,
        },
        name = 'crafting_dialog',
        events = events,
        template = I.MWUI.templates.bordersThick,
        content = ui.content({
            {
                name = 'background',
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture({
                        path = "transparent"
                    }),
                    color = colorFromGMST('fontcolor_color_background'),
                    relativeSize = util.vector2(1, 1),
                }
            },
            {
                name = 'foreground',
                type = ui.TYPE.Flex,
                props = {
                    relativeSize = util.vector2(1, 1),
                },
                content = ui.content {
                    {
                        name = 'header',
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                        },
                        external = {
                            stretch = 1,
                        },
                        content = ui.content {
                            headerSection,
                            spacer({ props = { size = v2(8, 0) } }),
                            {
                                name = 'title',
                                template = I.MWUI.templates.textHeader,
                                props = {
                                    text = 'Crafting Station: ' .. (ctx and ctx.context and ctx.context.label or 'Unknown'),
                                }
                            },
                            spacer({ props = { size = v2(8, 0) } }),
                            headerSection,
                        },

                    },
                    {
                        name = 'body',
                        template = I.MWUI.templates.bordersThick,
                        external = {
                            grow = 1,
                            stretch = 1,
                        },
                        content = ui.content({ body }),
                    },
                }
            }
        })
    }

    element = ui.create(dlg)
end

-- ── event handlers ──────────────────────────────────────────────────────────

function this.onCraft()
    -- if not matched or not canCraft then return end
    -- -- All placed items are consumed; the global executor removes them by record id
    -- -- and grants the output. (Same event serves grid and process crafts.)
    -- local consume = {}
    -- for id, count in pairs(placedCounts()) do consume[#consume + 1] = { id = id, count = count } end
    -- core.sendGlobalEvent('ImmersiveCrafting_CraftShaped', {
    --     actor = self.object,
    --     consume = consume,
    --     output = matched.output,
    -- })
    -- log.info('Crafted ' .. (matched.label or matched.id))
    this.close()
end

-- ── public API ──────────────────────────────────────────────────────────────

---@return boolean
function this.isOpen() return isOpen end

---@return string?
function this.getContextId()
    if not ctx or not ctx.context then return nil end
    return ctx.context.id
end

---@param handlerCtx HandlerContext
function this.open(handlerCtx)
    ctx = handlerCtx
    layout = ctx.context.layout

    isOpen = true
    I.UI.setMode('Interface') -- show cursor; inventory remains available
    rebuild()
end

function this.close()
    isOpen = false
    if element then element:destroy() end
    ctx = nil
    layout = nil

    I.UI.setMode() -- back to gameplay
end

---@param handlerCtx HandlerContext
function this.toggle(handlerCtx)
    if isOpen then
        this.close()
        return
    end
    this.open(handlerCtx)
end

return this
