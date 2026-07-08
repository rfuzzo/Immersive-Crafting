--[[
    Tutorial popup — a dismissable, semi-transparent bordered card (top-center)
    shown when a progression milestone unlocks. Texts are data
    (data/Immersive-Crafting/milestones/*.json -> GRegistries.milestones).

    One popup at a time; further milestones queue and show as each is
    dismissed (click, or the auto-hide timer). The "Tutorial popups" setting
    turns the whole surface off.
]]

local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local async = require('openmw.async')
local storage = require('openmw.storage')

local c = require('scripts.Immersive-Crafting.ui.components')
local log = require('scripts.Immersive-Crafting.log')

local v2 = util.vector2

local AUTO_HIDE_SECONDS = 14
local PAD_X, PAD_Y = 10, 8
local DIM = util.color.rgb(0.60, 0.52, 0.38)

local settings = storage.playerSection('SettingsImmersiveCrafting')

local this = {}

local element = nil
local shownFor = 0
local queue = {} ---@type { title: string, lines: string[] }[]

function this.hide()
    if element then
        element:destroy()
        element = nil
    end
    shownFor = 0
end

--- Build and mount the card for one popup definition.
---@param def { title: string, lines: string[] }
local function mount(def)
    this.hide()

    local rows = {
        c.text({ text = def.title or '', template = I.MWUI.templates.textHeader }),
        c.spacer({ props = { size = v2(0, 4) } }),
        c.hline(),
        c.spacer({ props = { size = v2(0, 6) } }),
    }
    for _, line in ipairs(def.lines or {}) do
        rows[#rows + 1] = c.text({ text = line })
        rows[#rows + 1] = c.spacer({ props = { size = v2(0, 2) } })
    end
    rows[#rows + 1] = c.spacer({ props = { size = v2(0, 6) } })
    rows[#rows + 1] = c.text({ text = '(click to dismiss)', props = { textColor = DIM } })

    local padded = { c.spacer({ props = { size = v2(0, PAD_Y) } }) }
    for _, r in ipairs(rows) do padded[#padded + 1] = r end
    padded[#padded + 1] = c.spacer({ props = { size = v2(0, PAD_Y) } })

    element = ui.create({
        layer = 'Windows', -- interactive: the card takes the dismiss click
        name = 'ic_popup',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = v2(0.5, 0.16),
            anchor = v2(0.5, 0),
        },
        events = {
            mouseClick = async:callback(function() this.next() end),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    c.row({ children = {
                        c.spacer({ props = { size = v2(PAD_X, 0) } }),
                        c.column({ name = 'popup_rows', children = padded }),
                        c.spacer({ props = { size = v2(PAD_X, 0) } }),
                    } }),
                },
            },
        },
    })
end

--- Dismiss the current popup and show the next queued one, if any.
function this.next()
    this.hide()
    local def = table.remove(queue, 1)
    if def then mount(def) end
end

--- Queue a popup (shown immediately when nothing is up).
---@param def { title: string, lines: string[] }
function this.show(def)
    if not def then return end
    if settings:get('TutorialPopups') == false then return end
    if element then
        queue[#queue + 1] = def
    else
        mount(def)
    end
end

--- Show the popup for a milestone id (no-op when no text is defined for it).
---@param id string
function this.milestone(id)
    local def = GRegistries and GRegistries.milestones and GRegistries.milestones[id]
    if def then
        this.show(def)
    else
        log.info('No milestone popup text for: ' .. tostring(id))
    end
end

--- Auto-hide clock (driven from the player script's onUpdate).
---@param dt number
function this.onUpdate(dt)
    if not element then return end
    shownFor = shownFor + dt
    if shownFor >= AUTO_HIDE_SECONDS then this.next() end
end

return this
