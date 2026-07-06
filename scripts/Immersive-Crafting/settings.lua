local interfaces = require('openmw.interfaces')
local input = require('openmw.input')

input.registerAction {
    key = 'ContextualAction',
    type = input.ACTION_TYPE.Boolean,
    l10n = 'none',
    name = 'ContextualAction',
    description = 'Button to trigger overlay action',
    defaultValue = false
}

interfaces.Settings.registerPage {
    key = 'ImmersiveCrafting',
    l10n = 'none',
    name = 'Immersive Crafting',
    description = 'Settings for Immersive Crafting mod',
}

interfaces.Settings.registerGroup {
    key = 'SettingsImmersiveCrafting',
    page = 'ImmersiveCrafting',
    l10n = 'none',
    name = 'ImmersiveCrafting',
    order = 0,
    description = '',
    permanentStorage = true,
    settings = {
        {
            key = 'ContextualActionHotkey',
            renderer = 'inputBinding',
            name = 'Choose hotkey for contextual actions',
            description = 'Click and press a key to bind the contextual action overlay',
            default = 'F',
            argument = {
                type = 'action',
                key = 'ContextualAction',
            },
        },
        {
            key = 'SDCookingAtStations',
            renderer = 'checkbox',
            name = "Sun's Dusk cooking at fire stations",
            description = "Sun's Dusk also offers its campfire cooking menu at placed "
                .. "Immersive-Crafting fire stations (e.g. the firepit). "
                .. "Only applies when Sun's Dusk is installed.",
            default = true,
        },
        {
            key = 'StationLoading',
            renderer = 'checkbox',
            name = 'Load stations by dropping items',
            description = 'UI-less stations: items dropped onto the kiln/charcoal pit are '
                .. 'loaded into it (hold fire to it to light it); a seed dropped onto a '
                .. 'planter is sown into the soil (hold F to plant it). The crafting window '
                .. 'and seed cycling still work as before.',
            default = true,
        },
        {
            key = 'ForagingGivesWood',
            renderer = 'checkbox',
            name = 'Foraging gives wood',
            description = "Gathering at trees also yields firewood, not just sticks. "
                .. "Auto-enabled when Sun's Dusk is not installed; with Sun's Dusk, "
                .. "leave this off and use its wood-chopping mechanic instead.",
            default = false,
        },
    },
}

return
