--[[
    Minimal local UI component builders — replaces the external `scripts.s3`
    dependency. Same call shapes as the handful of s3 components we used
    (row/column/grid/box/text/spacer) plus a bordered button.

    All builders return plain layout tables; callers own mounting and events.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local I = require('openmw.interfaces')

local this = {}

--- Plain text (MWUI textNormal unless a template is given).
---@param opts { text: string, name: string?, template: any?, props: table? }
function this.text(opts)
    local props = {}
    for k, v in pairs(opts.props or {}) do props[k] = v end
    props.text = opts.text
    return {
        type = ui.TYPE.Text,
        name = opts.name,
        template = opts.template or I.MWUI.templates.textNormal,
        props = props,
    }
end

--- Invisible fixed-size gap.
---@param opts { props: { size: any } }
function this.spacer(opts)
    return { type = ui.TYPE.Widget, name = opts and opts.name, props = (opts and opts.props) or {} }
end

--- Horizontal Flex.
---@param opts { name: string?, props: table?, children: table[] }
function this.row(opts)
    local props = {}
    for k, v in pairs(opts.props or {}) do props[k] = v end
    props.horizontal = true
    return {
        type = ui.TYPE.Flex,
        name = opts.name,
        props = props,
        external = opts.external,
        content = ui.content(opts.children or {}),
    }
end

--- Vertical Flex.
---@param opts { name: string?, props: table?, children: table[] }
function this.column(opts)
    local props = {}
    for k, v in pairs(opts.props or {}) do props[k] = v end
    props.horizontal = false
    return {
        type = ui.TYPE.Flex,
        name = opts.name,
        props = props,
        external = opts.external,
        content = ui.content(opts.children or {}),
    }
end

--- Grid: a vertical Flex of horizontal Flex rows, `columns` items per row.
--- `gap` (optional) inserts that many pixels between columns AND rows, so
--- borderless slots (the materials strip) read as distinct tiles.
---@param opts { name: string?, columns: integer?, items: table[], props: table?, gap: integer? }
function this.grid(opts)
    local columns = math.max(1, opts.columns or 1)
    local gap = opts.gap or 0
    local rows = {}
    local currentRow = nil
    for index, item in ipairs(opts.items or {}) do
        if (index - 1) % columns == 0 then
            if gap > 0 and currentRow then
                rows[#rows + 1] = { type = ui.TYPE.Widget, props = { size = util.vector2(0, gap) } }
            end
            currentRow = { type = ui.TYPE.Flex, props = { horizontal = true }, content = ui.content({}) }
            rows[#rows + 1] = currentRow
        elseif gap > 0 then
            currentRow.content:add({ type = ui.TYPE.Widget, props = { size = util.vector2(gap, 0) } })
        end
        currentRow.content:add(item)
    end
    local props = {}
    for k, v in pairs(opts.props or {}) do props[k] = v end
    props.horizontal = false
    return {
        type = ui.TYPE.Flex,
        name = opts.name,
        props = props,
        content = ui.content(rows),
    }
end

--- Thin horizontal divider line (MWUI horizontalLine). It auto-fills the width
--- of its parent column via the template's own relativeSize, so place it in the
--- column whose width it should match (no width arg needed).
---@param opts { name: string? }?
function this.hline(opts)
    return {
        type = ui.TYPE.Image,
        name = opts and opts.name,
        template = I.MWUI.templates.horizontalLine,
    }
end

--- Bordered container (MWUI box unless a template is given).
---@param opts { name: string?, children: table[], template: any?, props: table? }
function this.box(opts)
    return {
        template = opts.template or I.MWUI.templates.box,
        name = opts.name,
        props = opts.props,
        content = ui.content(opts.children or {}),
    }
end

--- Bordered text button (MWUI box + padding + label). `pad` swaps the ~2px
--- padding template for generous interior spacing (12px sides, 3px top/bottom)
--- so a standalone button — the footer Close — reads as a proper button.
---@param opts { label: string, name: string?, onClick: fun()?, pad: boolean? }
function this.button(opts)
    local label = {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = { text = opts.label },
    }
    local inner
    if opts.pad then
        inner = this.column({ children = {
            this.spacer({ props = { size = util.vector2(0, 3) } }),
            this.row({ children = {
                this.spacer({ props = { size = util.vector2(12, 0) } }),
                label,
                this.spacer({ props = { size = util.vector2(12, 0) } }),
            } }),
            this.spacer({ props = { size = util.vector2(0, 3) } }),
        } })
    else
        inner = {
            template = I.MWUI.templates.padding,
            content = ui.content({ label }),
        }
    end
    return {
        template = I.MWUI.templates.box,
        name = opts.name,
        events = opts.onClick and { mouseClick = async:callback(opts.onClick) } or nil,
        content = ui.content({ inner }),
    }
end

return this
