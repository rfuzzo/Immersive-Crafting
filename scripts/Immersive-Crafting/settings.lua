local storage = require('openmw.storage')
local interfaces = require('openmw.interfaces')

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
            key = 'ContextualActionHotekey',
            renderer = 'inputBinding',
            name = 'Choose hotkey for contextual actions',
            description = 'Click and press a key to bind the contextual action overlay',
            default = 'F',
            argument = {
                type = 'action',
                key = 'ContextualAction',
            },
        }
    },
}
