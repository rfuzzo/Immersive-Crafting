# Immersive Crafting – Design Context & Architecture Summary

## Cooking

Cooking is a contextual action that can be performed at either a cooking station (e.g. campfire) or using a cooking tool (e.g. mixing bowl). Both need to be placed in the world, the ingredients must be placed around it and are detected by the contextual UI.

The UI is a HUD overlay that shows the detected station or tool, if there are multiple tools or stations nearby, then it choses the closest one or the last focused one with the cursor. The overlay UI shows all detected containers, tools and ingredients in the vicinity but no action prompt.

Hovering over any container shows its state (like temperature) and shows an action prompt like "create stew" if the right ingredients are present.

Example process flow:

1. Player approaches a campfire.
2. The contextual overlay UI appears, showing the campfire as the station. Since the player has not placed any pots or ingredients yet, those sections are empty.
3. Player places a pot on the campfire.
4. The overlay UI updates to show the pot as a detected container.
5. Player places ingredients (e.g. meat, onions, salt) near the campfire
6. The overlay UI updates to show the detected ingredients. Water must be added by action, e.g. "Fill pot with water" before cooking can start.
7. If I hover over the pot, I see an action prompt "Make stew" because all required ingredients are present.
8. When I press the action prompt, the cooking process starts, consuming the ingredients.
9. The overlay UI of the pot shows the cooking progress: not heated / simmering / cooked / burnt.
10. When cooking is complete, I can hover over the pot again to see an action prompt "Take stew".

### Station cooking

Recipes must specify all of these three compoenents to be valid:

- a station as the cooking environment (e.g. a campfire)
- then we detect all containers, e.g. pots in the environment
- same as all ingredients placed in the world

Examples

- Stew: Fire + pot + Any meat + onions + salt
- Boiled egg: Fire + pot + water + egg + salt
- Fish stew: Fire + pot + Any fish + water + salt + herbs
- Roasted fish: Fire + Any grill + Any fish + salt + lemon
- Steak: Fire + Any grill + Any meat + salt + pepper
- Bread: Fire + oven + dough + water

### Tool cooking

Some recipes don't require a station, e.g. making dough from flour and water, but they may require a tool, e.g. a mixing bowl.

Recipes must specify both of these two components to be valid:

- a tool as the cooking environment (e.g. mixing bowl)
- ingredients placed in the tool

Examples

- Dough: Mixing bowl + flour + water
- Batter: Mixing bowl + flour + egg + milk
- Marinade: Mixing bowl + oil + herbs + spices + acid
- Juice: Juicer + fruit + water + sugar

Example process flow:

1. Player places a mixing bowl on the ground.
2. The contextual overlay UI appears, showing the mixing bowl as the tool. Since the player has not placed any ingredients yet, that section is empty.
3. Player places ingredients (e.g. flour, water) near the mixing bowl.
4. Hovering over the mixing bowl shows an action prompt "Make dough" because all required ingredients are present.
5. When I press the action prompt, the cooking process starts, consuming the ingredients.
