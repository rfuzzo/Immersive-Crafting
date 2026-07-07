--[[
    Window widget — a draggable / resizable bordered window on the 'Windows' layer.

    Reusable shell extracted from the crafting window: it renders a titled, bordered
    box and drops a caller-supplied `body` layout into the content area. The window
    manages its own drag (move) and edge-resize behaviour; the owner just supplies a
    `getElement` accessor so those handlers can mutate the live element.

    Usage:
        local element
        local layout = Window({
            title = 'My Window',
            body  = someBodyLayout,
            props = { anchor = v2(0.5,0.5), relativePosition = v2(0.4,0.5), size = v2(300,300) },
            getElement = function() return element end,
        })
        element = ui.create(layout)
]]

local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')

local v2 = util.vector2

--- Read an MWUI colour GMST ("r,g,b" 0..255) into a util.color (0..1).
---@param gmst string
local function colorFromGMST(gmst)
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

local MIN_SIZE = v2(280, 240) -- resize floor: the frame stays usable
local HEADER_GRAB = 26        -- px from the top that drag (move) the window

--- Build the draggable/resizable window layout.
---@param opts { title?: string, body: openmw.ui.Content, props?: table, getElement: fun():any, onResize: (fun())|nil } onResize fires when an edge-resize drag ends, so the owner can reflow content to the new size
---@return table layout
local function Window(opts)
    local getElement = opts.getElement

    local headerSection = {
        props = { size = v2(0, 20) },
        external = { grow = 1, stretch = 1 },
    }

    --- Grow/shrink by a delta with the MIN_SIZE floor (bottom-right resize:
    --- the position never moves).
    local function applyResize(props, dw, dh)
        props.size = v2(
            math.max(MIN_SIZE.x, props.size.x + dw),
            math.max(MIN_SIZE.y, props.size.y + dh))
    end

    local events = {
        mousePress = async:callback(function(mouseEvent)
            local element = getElement()
            if not element then return end
            element.layout.userData.lastMouseDownPosition = mouseEvent.position

            -- First interaction: pin the window at its CURRENT on-screen spot.
            -- Never convert relativePosition via ui.screenSize() — that returns
            -- raw pixels while layout coordinates are UI-scale units, so the
            -- conversion moved the window on the first click (the old
            -- "window jumps when placing an ingredient" bug). The event itself
            -- knows where the window is: position - offset, already in layout
            -- coordinates.
            local props = element.layout.props
            if props.relativePosition or props.anchor then
                props.position = mouseEvent.position - mouseEvent.offset
                props.anchor = nil
                props.relativePosition = nil
            end
            if props.relativeSize then
                -- our windows pass an absolute size; fallback for completeness
                props.size = v2(props.relativeSize.x * ui.screenSize().x,
                    props.relativeSize.y * ui.screenSize().y)
                props.relativeSize = nil
            end

            local elemX, elemY = element.layout.props.position.x, element.layout.props.position.y
            local elemW, elemH = element.layout.props.size.x, element.layout.props.size.y
            local mx, my       = mouseEvent.position.x, mouseEvent.position.y
            local edgeMargin   = 15 -- pixels from the edge that count as an edge grab

            local onRight      = mx >= elemX + elemW - edgeMargin and mx <= elemX + elemW
            local onBottom     = my >= elemY + elemH - edgeMargin and my <= elemY + elemH

            -- resizing is the BOTTOM-RIGHT corner only — the other borders are
            -- inert, so near-edge clicks can't accidentally squash the window
            element.layout.userData.edgeWhenMouseDown =
                (onRight and onBottom) and "bottom-right" or nil

            -- moving is a HEADER grab only — a press in the body (slots,
            -- strip, buttons) must never drag the window around
            element.layout.userData.draggingWindow =
                element.layout.userData.edgeWhenMouseDown == nil
                and my <= elemY + HEADER_GRAB
        end),
        mouseMove = async:callback(function(mouseEvent)
            local element = getElement()
            if not element then return end
            if mouseEvent.button ~= 1 then return end
            if not element.layout.userData.lastMouseDownPosition then return end

            local delta = mouseEvent.position - element.layout.userData.lastMouseDownPosition
            element.layout.userData.lastMouseDownPosition = mouseEvent.position

            local edge = element.layout.userData.edgeWhenMouseDown
            if edge == "bottom-right" then
                applyResize(element.layout.props, delta.x, delta.y)
            elseif element.layout.userData.draggingWindow then
                -- header grab: move the whole window
                local currentPos = element.layout.props.position or v2(0, 0)
                element.layout.props.position = currentPos + delta
            else
                return -- body press: neither move nor resize
            end

            element:update()
        end),
        mouseRelease = async:callback(function()
            local element = getElement()
            if not element then return end
            local wasResizing = element.layout.userData.edgeWhenMouseDown ~= nil
            -- clear the drag state so a later click elsewhere can never apply
            -- a stale delta (phantom window jump)
            element.layout.userData.lastMouseDownPosition = nil
            element.layout.userData.edgeWhenMouseDown = nil
            element.layout.userData.draggingWindow = nil
            -- a resize drag just ended: let the owner reflow its content to
            -- the new size (e.g. the materials strip recalculates rows/cols)
            if wasResizing and opts.onResize then opts.onResize() end
        end),
    }

    return {
        layer = "Windows",
        name = 'crafting_dialog',
        props = opts.props or {
            anchor = v2(0.5, 0.5),
            relativePosition = v2(0.4, 0.5),
            size = v2(300, 300),
        },
        userData = {
            lastMouseDownPosition = nil,
            edgeWhenMouseDown = nil,
            draggingWindow = nil,
        },
        events = events,
        template = I.MWUI.templates.bordersThick,
        content = ui.content({
            {
                name = 'background',
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture({ path = "transparent" }),
                    color = colorFromGMST('fontcolor_color_background'),
                    relativeSize = v2(1, 1),
                },
            },
            {
                name = 'foreground',
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = v2(1, 1)
                },
                content = ui.content {
                    {
                        name = 'header',
                        type = ui.TYPE.Flex,
                        props = { horizontal = true },
                        external = { stretch = 1 },
                        content = ui.content {
                            headerSection,
                            { type = ui.TYPE.Widget, props = { size = v2(8, 0) } },
                            {
                                name = 'title',
                                template = I.MWUI.templates.textHeader,
                                props = { text = opts.title or '' },
                            },
                            { type = ui.TYPE.Widget, props = { size = v2(8, 0) } },
                            headerSection,
                        },
                    },
                    -- divider under the title; the body below is a PLAIN growing
                    -- Flex (no second bordersThick) so the frame reads as one
                    -- window border, not two concentric ones. Inner padding is
                    -- the caller's job (Crafting.lua's symmetric PAD frame).
                    { type = ui.TYPE.Widget, props = { size = v2(0, 6) } },
                    { type = ui.TYPE.Image, template = I.MWUI.templates.horizontalLine },
                    {
                        name = 'body',
                        type = ui.TYPE.Flex,
                        external = { grow = 1, stretch = 1 },
                        content = opts.body,
                    },

                },
            },
        }),
    }
end

return Window
