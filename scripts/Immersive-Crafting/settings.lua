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
        }
    },
}

return
