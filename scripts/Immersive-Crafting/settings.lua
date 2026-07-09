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
        {
            key = 'EquipGating',
            renderer = 'checkbox',
            name = 'Skill-gate armor and weapons',
            description = 'Gear above your skill cannot be worn or wielded: the '
                .. 'requirement comes from the item\'s material tier (iron 10 ... '
                .. 'ebony 65, daedric 80), checked against its own governing skill '
                .. '(armor weight class / weapon skill). Fortify Skill effects '
                .. 'count while they last.',
            default = true,
        },
        {
            key = 'CraftedBonus',
            renderer = 'checkbox',
            name = 'Crafted gear is finer ("Wrought")',
            description = 'Weapons and armor YOU forge come out as a Wrought version: '
                .. 'a bit more damage or armor, more durability, more value — the '
                .. 'reward for walking the whole chain instead of buying off a shelf.',
            default = true,
        },
        {
            key = 'TutorialPopups',
            renderer = 'checkbox',
            name = 'Tutorial popups',
            description = 'Show a short explanation card when a progression milestone '
                .. 'unlocks (first firepit, kiln, furnace...). Turn off if you know '
                .. 'the mod.',
            default = true,
        },
        {
            key = 'ShowAllRecipes',
            renderer = 'checkbox',
            name = 'Show all recipes in the guide',
            description = 'The recipe guide normally hides recipes of station tiers '
                .. 'you have not built or used yet (raw molds before your first kiln). '
                .. 'Enable to always list everything. Crafting itself is never gated.',
            default = false,
        },
    },
}

return
