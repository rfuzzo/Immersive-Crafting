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
---@param opts { title?: string, body: openmw.ui.Content, props?: table, getElement: fun():any }
---@return table layout
local function Window(opts)
    local getElement = opts.getElement

    local headerSection = {
        props = { size = v2(0, 20) },
        external = { grow = 1, stretch = 1 },
    }

    --- Resize one axis pair with the MIN_SIZE floor. `dw`/`dh` grow/shrink the
    --- size; `moveX`/`moveY` make the position follow (left/top edges) — by the
    --- APPLIED delta only, so hitting the floor never slides the window.
    local function applyResize(props, dw, dh, moveX, moveY)
        local newW = math.max(MIN_SIZE.x, props.size.x + dw)
        local newH = math.max(MIN_SIZE.y, props.size.y + dh)
        local appliedW, appliedH = newW - props.size.x, newH - props.size.y
        props.position = v2(
            props.position.x - (moveX and appliedW or 0),
            props.position.y - (moveY and appliedH or 0))
        props.size = v2(newW, newH)
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

            local onLeft       = mx >= elemX and mx <= elemX + edgeMargin
            local onRight      = mx >= elemX + elemW - edgeMargin and mx <= elemX + elemW
            local onTop        = my >= elemY and my <= elemY + edgeMargin
            local onBottom     = my >= elemY + elemH - edgeMargin and my <= elemY + elemH

            if onTop and onLeft then
                element.layout.userData.edgeWhenMouseDown = "top-left"
            elseif onTop and onRight then
                element.layout.userData.edgeWhenMouseDown = "top-right"
            elseif onBottom and onLeft then
                element.layout.userData.edgeWhenMouseDown = "bottom-left"
            elseif onBottom and onRight then
                element.layout.userData.edgeWhenMouseDown = "bottom-right"
            elseif onLeft then
                element.layout.userData.edgeWhenMouseDown = "left"
            elseif onRight then
                element.layout.userData.edgeWhenMouseDown = "right"
            elseif onTop then
                element.layout.userData.edgeWhenMouseDown = "top"
            elseif onBottom then
                element.layout.userData.edgeWhenMouseDown = "bottom"
            else
                element.layout.userData.edgeWhenMouseDown = nil
            end

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
            if edge ~= nil then
                local props = element.layout.props
                if edge == "left" then
                    applyResize(props, -delta.x, 0, true, false)
                elseif edge == "right" then
                    applyResize(props, delta.x, 0, false, false)
                elseif edge == "top" then
                    applyResize(props, 0, -delta.y, false, true)
                elseif edge == "bottom" then
                    applyResize(props, 0, delta.y, false, false)
                elseif edge == "top-left" then
                    applyResize(props, -delta.x, -delta.y, true, true)
                elseif edge == "top-right" then
                    applyResize(props, delta.x, -delta.y, false, true)
                elseif edge == "bottom-left" then
                    applyResize(props, -delta.x, delta.y, true, false)
                elseif edge == "bottom-right" then
                    applyResize(props, delta.x, delta.y, false, false)
                end
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
            -- clear the drag state so a later click elsewhere can never apply
            -- a stale delta (phantom window jump)
            element.layout.userData.lastMouseDownPosition = nil
            element.layout.userData.edgeWhenMouseDown = nil
            element.layout.userData.draggingWindow = nil
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
                    {
                        name = 'body',
                        template = I.MWUI.templates.bordersThick,
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
