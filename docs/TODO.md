# Immersive Crafting — TODO / Deferred

Running list of deferred work. See `docs/SPEC.md` for the authoritative design.

## Shaped crafting (in progress)

Interactive **grid** crafting, separate from world-placement cooking. Input = an
inventory-driven grid menu; **tools** (saw, hammer) come from **player inventory**,
outside the grid. Station context defines the grid size (`gridSize`): cloth/tier-0
`[2,2]`, table/tier-1 `[3,3]`, tier-2 TBD.

- ✅ **Phase 1 (engine):** `CShapedRecipe` model; loader branch → `GRegistries.shapedRecipes`
  (a recipe is shaped iff it has a `pattern`); `shapedCrafting.lua` matcher (trim/shift-to-fit,
  `cellsMatch` via `lib.matchesTag`, inventory `hasTools`); `CContext.gridSize`; data
  (`crafting_cloth` 2x2 via `cloth` tag, `crafting_table` 3x3, `shaping` action,
  `wooden_plank` example); `shaping` handler skeleton.
- ❌ **Phase 2 (UI):** the MWUI crafting window — NxM clickable cells filled from inventory,
  a tool slot, a result preview, and a Craft button → `resolveShapedRecipe` →
  consume placed items **from inventory** + grant output (needs an inventory-consume commit
  path; the current global executor removes world stacks).
- Content gaps before the example works end-to-end:
  - **`table` tag** (tier-1 station) not applied — needs a station tag (STAT/ACTI dump) or a
    real table record id.
  - **`saw` tool tag** doesn't exist — add a tools tag (misc) + apply it to saw records.
  - **`wooden_plank` output** is not a real record (D1) — repoint to a real plank record
    (e.g. OAAB) or drop the example.
- Verify in-game: `types.Actor.inventory(self)` for the tool check; MWUI item-slot icons +
  click handling for the grid cells.

### Process stations (tanning rack, furnace) — undecided

Separate from shaped crafting. UI still open: Minecraft-style slots (input / fuel / output)
vs. a grid-less prompt. Decide when we get there.

## Context detection by tag (ad 2)

Stations are detected by **Tagger tag** instead of hard-coded record ids.

- ✅ Engine: `contextManager` scans `nearby.items` + `nearby.activators` and matches
  each context's `recordIds` entries as record id **or** Tagger tag (`lib.matchesTag`).
- ✅ `CContext.requires`: extra tags that must also be present nearby.
- ✅ Data: `mixing_bowl` → `bowl`; `cooking_pot` → `pot` + `requires: ["fire"]`.

Remaining — the **`fire` tag data** (chose tag-based fire):

- Real cooking fires are mostly **Light (LIGH)** records (campfires, fire pits,
  braziers) plus a few fire **Activators**. Need a **LIGH dump** (like INGR/MISC/ACTI)
  to tag the fire-emitting ones into a `ModTags/ImmersiveCrafting_Fire.yaml`, then
  `cooking_pot` will gate correctly. A few fire activators also exist in the ACTI dump.
- **Verify**: confirm fire objects actually appear in `nearby.items` / `nearby.activators`
  (if fires are Light-type objects not in those lists, the `requires` scan needs to
  cover them too).

## Recipe import gaps (Sun's Dusk → `recipes/sunsdusk.json`)

Imported 25 of 54 SD recipes (`tools`/scratch converter, one tag per ingredient).
Skipped and why:

- **`anyOf` ingredients (22 recipes)** — our ingredient schema is one tag/record per
  slot. Mostly Affa's recipes + Vaermina. To support: extend the ingredient schema to
  accept a list of acceptable ids, or map each `anyOf` set to a single tag.
- **No `Herb` / `Crab` tag (4 recipes)** — SD `herb`×3, `crab`×1. Add the tags (and
  apply them in the ingredient CSV), or map `herb`→`Spice`/`Plant`, `crab`→`Fish`.
- **Default/fallback recipes (3)** — SD `sd_food_def_*` have no matchers (catch-all);
  not expressible here.
- Imported recipes carry **no `cookTime`**; the cooking handler currently does an
  instant commit. Add `cookTime` + a heat/simmer process (Cooking phase) and surface
  it via `ViewModel.progress`.

## Output records

- `world.createObject` needs a **real record id**. SD outputs (`sd_food_*`) only exist
  when Sun's Dusk is loaded. Our hand-made outputs (`SeasonedMeat`, `Stew`) are **not**
  real records — they need real records, or `createRecordDraft`/`createRecord`
  (D1 accepted caveat: custom records are Load-context only, not save-serialised).

## Process stations & crafting-window layouts (in progress)

The crafting window (`ui/CraftingGrid.lua`) is now **layout-driven** so new station
shapes are data-driven via `CContext.layout`. A small `layouts` registry in that file
maps `kind` → `{ body, resolve, hasProgress }`; add an entry to support a new shape.

- ✅ **UI:** restyled to the alchemy-window look (MWUI `boxSolid`/`box`/`padding`/
  `horizontalLine` + Flex; no absolute positions; fixed the 0–255 `util.color.rgb` bug).
  Two layouts: `grid` (N×M, engine `shapedCrafting`) and `process` (named role slots +
  output slot + progress bar, engine `processCrafting`). `3x3` table works via `gridSize`.
- ✅ **Engine/data:** `CProcessRecipe` model; loader branch → `GRegistries.processRecipes`
  (a recipe is process iff it has `inputs`); `processCrafting.resolveProcessRecipe`
  (role-slot match via `lib.matchesTag`, most-specific wins, `hasTools`); `processing`
  action + handler; contexts `kiln`/`furnace`/`oven` (fuel+input) and `tanning_rack`
  (2 ingredients + input); sample `recipes/processing.json`. All placed items are
  consumed on craft (reuses the `ImmersiveCrafting_CraftShaped` global executor).

Deferred / to verify:

- **Timed process (deferred by design).** Today **Craft commits instantly**. The real
  process — Start consumes inputs, a **persisted** timer advances over `duration`,
  output is granted on completion — is not built. The UI already shows a progress bar
  driven by `CraftingGrid.setProgress(0..1)`; a process subsystem (using
  `GRegistries.processes`) needs to call it and survive save/load. Shares the
  heat/simmer need with the Cooking phase.
- **Placeholder data.** Output ids (`misc_com_bucket_metal`, `ingred_scrib_jelly_01`)
  and station/ingredient tags (`kiln`, `furnace`, `oven`, `tanning_rack`, `Fuel`,
  `GreenWare`, `RawHide`, `Salt`, `Water`) are placeholders — repoint outputs to real
  records (D1: existing records only) and author the Tagger tags in `ModTags/*.yaml`.
- **In-game UI check.** Whole window is untested live: confirm boxSolid auto-sizing,
  slot drag-drop, the `→` arrow/progress-bar rendering, and that dropping from the
  inventory works in plain `Interface` mode (else `setMode('Interface', {windows={'Inventory'}})`).

## Crafting window: components, item picker, context trigger

- ✅ **Window widget** — the draggable/resizable bordered window shell is broken out into
  `ui/Window.lua`; it accepts a `body` layout + `title` and a `getElement` accessor.
  `ui/Crafting.lua` composes it per layout.
- ✅ **Item picker** — clicking an empty slot opens `ui/ItemPicker.lua` (a grid of the
  player's inventory items, click to pick — no drag-and-drop); the pick is placed in the
  slot. Clicking a filled slot clears it. Placed-slot state lives in `ui/Crafting.lua`.
- ✅ **`CContext.trigger`** — `"proximity"` (default) or `"activate"`. The proximity scanner
  (`contextManager`) now **skips `activate` contexts** so they don't show as nearby prompts.
- ✅ **Activation hook wired.** `trigger:"activate"` contexts (Activator objects) open by
  **activating** the object: the player pushes its activate contexts to the global script on
  load (`ImmersiveCrafting_RegisterActivateContexts`); global registers
  `I.Activation.addHandlerForType(types.Activator, …)`, matches the activated object (exact id
  or `I.TaggerG` tag), and `actor:sendEvent('ImmersiveCrafting_OpenStation', …)` back to the
  player (returning false to suppress default activation). Non-activators can't be activated,
  so they remain proximity-only. Activate stations also show an **info-only** proximity card
  ("Activate to use" + input roles for process stations); `[F]` is disabled for them.
  Demonstrated on the process contexts (kiln/furnace/oven/tanning_rack → `trigger:"activate"`).
- ✅ **Close button added** (alchemy-style rework). Esc handling still open.
- 🟡 **Verify `I.TaggerG.objectHasTag` signature** in the global activation handler (same
  record-id-string vs object question as `lib.matchesTag`).
- ✅ **Recipe resolve + output slot + craft** wired: `Crafting.resolve()` maps the placed
  slots to a recipe (`shapedCrafting`/`processCrafting`) every rebuild; a Minecraft-style
  output slot shows the result, and clicking it commits via `ImmersiveCrafting_CraftShaped`
  (consumes the placed items from inventory, grants the output, clears the grid). The
  output-slot icon is resolved by probing item-type records (`recordIconPath`).
- ✅ **Alchemy-style window + integrated picker** *(2026-07-03)*. The window now mirrors
  the vanilla alchemy layout: Tools row (apparatus-style, the matched recipe's tools) |
  Result panel, then the input slots, then a **Materials strip** — the picker embedded in
  the window (no popup), **filtered** to items usable at this station (any recipe
  ingredient id/tag; falls back to the full inventory while tags are unauthored) and
  **paged** (12 per page). Interaction: click an empty slot to select it → click a
  material to place (auto-advances selection); click a filled slot to clear it. **No
  Create button** — clicking the Result slot *takes* the item: that is the craft (inputs
  consumed, output moved to inventory); the window stays open for batches. Shared
  `ui/Slot.lua` renders every slot. Material counts refresh one interaction after a craft
  (global consume lands next frame).
- ✅ **UI polish pass 2** *(2026-07-03)*: the `scripts.s3` dependency is gone — the few
  builders we used live in `ui/components.lua` (row/column/grid/box/text/spacer/button).
  The materials strip **decrements placed items** (an item in the grid disappears from the
  strip) and **auto-fits its columns/rows to the live window size** (rebuilds preserve the
  user's moved/resized geometry; a resize reflows on the next click). The Close button is
  a bordered MWUI box button. The **Tools row is auto-detected from the inventory**: every
  tool any recipe at this station uses shows up if the player carries a matching item
  (alchemy-apparatus behaviour), padded to 3 slots, wrapping at 5 per row.

## Tiered recipes import (Minecraft-style progression)

Originally: `docs/immersive_crafting_recipes_v2.csv` → `tools/recipes_csv2json.py`
→ a single `recipes/crafting.json`. **As of 2026-07-06 the recipe JSON is
hand-maintained and organized into three kinds of file**: **context** files
(`recipes/{bushcrafting,crafting_table,firepit,kiln,charcoal_pit,tanning_rack,
furnace}.json`) for non-equipment production; **material** files
(`recipes/{chitin,iron,steel,bonemold,glass,bronze,copper}.json`) for a material's
weapons + armor; and `recipes/molds.json` for every mold. The loader globs all
`*.json` in `recipes/`, so filenames are purely organizational — each recipe
still carries its own `context` field. (Ingots use the Tamriel Data records
`T_Com_MetalPiece*`; custom ingots retired.)
The CSV generator (`immersive_crafting_recipes_v2.csv` + `recipes_csv2json.py`)
was **retired 2026-07-06** — JSON is the sole source of truth (editing the CSV
was more cumbersome than the split JSON). Its useful parts live on in
`tools/recipes_lint.py`, which READS the JSON (never writes it) to check
integrity + the tool-vs-consumed rules and regenerate `docs/ic_records.md`.
Run `python3 tools/recipes_lint.py` after editing recipes (or `--check` in CI).

Applied per design review (ratified 2026-07-02):
- ✅ `outcome_count` column added (default 1; arrows/bolts ×20 via `output.count`).
- ✅ Process recipes are **counted multisets** (`inputs: [{id,count}]`, exact match, no
  leftovers); process station layouts use generic slots (firepit 8, kiln 6, furnace 4,
  charcoal pit 4), tanning rack = Input + Reagent roles.
- ✅ Charcoal Pit is a real process station (Charcoal moved there from Firepit); new
  `firepit`/`charcoal_pit`/`bushcrafting` contexts; station build recipes trimmed to fit
  the Bushcrafting 2×2; `ic_station_firepit` id aligned; generic reusable **Armor Mold**
  (tool, not consumed) + Raw/Burnt Armor Mold recipes; superseded sample recipe files
  (`processing.json`, `woodworking.json`) removed.

Open items:
- 🟡 **`ic_*` records ship as plugin records — pipeline in place** *(D1 amendment ratified
  2026-07-03)*: `tes3util.exe` packs `records/<Type>/<id>.yaml` → `immersive_crafting.esp`
  (`_pack.ps1`). **All 46 records drafted** and packing clean (44 MiscItem + Armor
  `ic_armor_hide_mk1` cloned from netch_leather_cuirass + `ic_wood`). Icon/mesh picks are
  borrowed vanilla placeholders (from `docs/vanilla_icons.csv`; regenerate with
  `py tools/extract_icons.py <dump-root>`) — **review pass wanted**, esp.: stick=broom,
  molds=redware/limeware flasks, station kits are carryable MiscItems whose
  drop-to-deploy/Activator design is still open. `ic_chitin_plate` / `ic_netch_hide` are
  drafted but never produced by recipes — they still need world/leveled-list sources.
- ✅ **Bushcrafting = the work cloth** *(ratified 2026-07-02)*. No abstract "craft anywhere"
  trigger: the tier-0 surface is a droppable cloth (or hide) you unroll on the ground — the
  old `crafting_cloth` context was merged into `bushcrafting` (recordIds `["cloth","hide"]`,
  **proximity** trigger — activating an item would pick it up). Bootstrap mirrors the
  found-knife assumption: cheap cloth is everywhere in vanilla. Rule of thumb: portable
  surfaces = proximity + [F]; built structures (kiln, furnace, racks) = activate.
- 🟡 **Tags to author** (14 assumed Tagger tags, list in `docs/ic_records.md`): Charcoal,
  Clay, Fibre, Hide, Knife, Ore, Plant, Raw Glass, Salt, Stone, Water, Wood… — including
  tags applied to `ic_*` records (e.g. `Fibre` → `ic_fibre`, `Charcoal` → `ic_charcoal`).
  The `cloth`/`hide` surface tags should cover vanilla cloth bolts/folded cloth and hides
  (and later `ic_cloth`/`ic_netch_leather`).
- 🟡 Station tags (`firepit`, `kiln`, `furnace`, `charcoal_pit`, `tanning_rack`) need real
  Activator records + Tagger entries.
- 🟡 Verify chitin armor record ids against the tes3-records dump (`chitin cuirass` with
  spaces vs `steel_cuirass` with underscores).
- 🟡 Bootstrap knife assumption ratified: every vanilla start passes the census-office
  dagger; `Knife` tag should cover all daggers.

## Foraging (gaze + condition contexts)

Raw-material gathering from the world, built on two new context triggers:

- ✅ **`trigger:"gaze"`** — a single crosshair raycast per tick (`camera.getPosition()` +
  `viewportToWorldVector` → `nearby.castRay`), matched against gaze contexts' recordIds/tags.
  This is how statics (trees, rocks) are targeted — they never appear in `nearby.*` lists.
  The gaze target wins over proximity contexts (aiming is the stronger signal).
- ✅ **`trigger:"condition"`** — named Lua predicates (`conditions.lua`, extensible via
  `register`); contexts have no recordIds/object. First predicate: `near_water` (player z
  within a band around the cell water level). Shown at a nominal distance of 100 so nearer
  stations still win the overlay.
- ✅ **Foraging definition on the context** (`forage: { verb, label, yield, tools, cooldown }`)
  + `foraging` action/handler: tools required-not-consumed, yield granted via the existing
  `ImmersiveCrafting_CraftShaped` executor (empty consume). Cooldowns are per **object**
  (gaze) / per **context** (condition), in **game seconds** (3600 = 1 game hour — they pass
  while sleeping), persisted in the player save (`forageState.lua`).
- ✅ `HandlerContext.object` — overlay/contextManager now pass the matched world object
  through to handlers (needed for per-object cooldowns; useful generally).
- ✅ Data: `forage_tree` (axe → `ic_wood`), `forage_rock` (→ `ic_stone` ×2),
  `forage_clay` (shovel near water → `ic_clay` ×2). New records `ic_stone`/`ic_clay`
  (placeholder meshes/icons — review with the rest). Tag seeds in
  `ModTags/ImmersiveCrafting.yaml` (`axe`, `shovel`, `tree`, `rock` — **testing seeds**,
  replace from the records dump; tree/rock static ids are guesses).

Verify in-game:
- `nearby.castRay` returns `hitObject` for statics (and that `viewportToWorldVector` +
  `camera.getPosition` behave in both 1st/3rd person; `{ ignore = self }` set).
- `cell.waterLevel` semantics in exteriors (sea level 0) — tune the `near_water` band.
- Gaze-vs-proximity priority feels right (tree prompt while standing at a station).
- Cooldown durations (1 game hour ≈ 2 real minutes at default timescale).

## Sun's Dusk interop (ratified 2026-07-04)

**Division of labour: SD owns the needs system; IC owns (an alternative) cooking.**
SD's own cooking stays enabled. Investigated from the SD 5.x scripts (see chat log):
meals are runtime Potion records minted GLOBAL-side (`world.createRecord` — which
**persists in saves**, correcting the old D1 caveat); hunger values live in SD's
registries, keyed by record id; eating is detected via `onConsume` + lookup.

- ✅ **`recipes/sunsdusk.json` retired** — its `sd_food_*` outputs never exist as
  static records (SD mints a fresh record per cook).
- ✅ **Lane B — SD meals from IC recipes:** recipes may carry `sdMeal { name, icon,
  isSoup, category, food, drink, wake, warmth, sdRecipeId?, virtualFoodware? }`
  instead of `output`. Crafting dispatches SD's global **`SunsDusk_createStew`**
  (the same event SD's own UI sends): SD consumes the ingredients + a bowl/plate,
  mints the meal with stat-bracket name + freshness, grants it. IC consumes
  nothing for these. Values are raw-scale (F=160) and normalised /200 on send.
  Recipes with `sdMeal` are **hidden when `I.SunsDusk` is absent** (soft dep).
- ✅ **Generic cooked food:** IC recipes that output existing vanilla/TR/OAAB food
  records get SD hunger values automatically — SD ships
  `SD_food_and_drinks/vanilla_TD_OAAB.txt` covering them. Sample:
  `grilled_scrib_jerky` (Meat + wood @ firepit → `ingred_scrib_jerky_01`, Medium
  Meal 80 in SD's DB). Only `ic_*` food outputs would need our own TSV drop-in
  (`SD_food_and_drinks/ImmersiveCrafting.txt`) — none exist yet.
- Authoring rules for `sdMeal` recipes: **inputs must be Ingredient-type records**
  (SD only consumes `types.Ingredient` — no misc water/wood in these recipes);
  count values are per-meal; `sdRecipeId` optionally reuses SD recipe typing.

Verify in-game (SD loaded):
- `SunsDusk_createStew` payload accepted from an external mod (event is internal,
  not the versioned interface — pin the SD version / re-check on SD updates).
- Behaviour with **no bowls/plates** in inventory (fallback mesh path).
- Meal freshness + hunger credit on eating an IC-crafted meal; jerky hunger credit.
- Materials strip at the firepit shows meat/vegetables (tags `Meat`/`Vegetable`).

## SD interop round 2 (2026-07-04)

- ✅ **Crafting window no longer jumps** — `Crafting.rebuild()` updates the window
  body **in place** (`element.layout` mutation + `element:update()`); the window
  element (and its dragged/resized geometry) is never recreated. The old
  destroy/recreate path re-ran the relative→absolute conversion each click.
- ✅ **SD firewood tagged `wood`** (`sd_wood_1` + publican/merchant variants) — SD
  woodcutting output feeds our recipes directly.
- ✅ **`CContext.recordPatterns` (+`recordPatternsExclude`)** — Lua patterns matched
  against candidate record ids alongside recordIds/tags, in proximity, gaze, AND
  the global activation handler. Used to adopt **SD's own cooking-fire detection**:
  the `firepit` context now matches SD's activator name families (`fire`, `ember`,
  `light_logpile`, `sd_wood_%d_lit`, `cauldron`, `grill`, `stove`; vetoes `firewat`,
  `grille`) — activating an SD campfire opens our firepit station.
- ✅ **Debug command**: console → `luap` → `I.ImmersiveCrafting.giveMaterials([n])`
  grants every recipe ingredient (tags resolved via the first tagged
  Ingredient/Misc/Potion record; default 5 each; logs unresolved matchers).

### Water interop (BUILT 2026-07-05 — see "SD water interop" section below)

SD water: bottles are dynamic Potion records tracked in `saveData.reverse[recordId]
= { orig, q, liquid }` (orig = the empty container, liquid = 'water'|…), exposed via
`I.SunsDusk.isConsumable(id)` → (entry, "drink"). Plan:
- extend ingredient matching so a special matcher (e.g. `sd:water`) accepts any item
  SD classifies as a water drink — `matchesTag` can't tag dynamic ids;
- on consume, **return the empty container** (`entry.orig`) instead of deleting the
  bottle (new behaviour in the craft executor for these inputs);
- until built, recipes should avoid a literal `Water` ingredient or use tagged
  static water items.

### Next milestone: planters & vegetable farming

Immersive Farming groundwork: `ic_station_planter` exists as a craftable. Needs:
plant/grow/harvest loop (persistent per-planter state in global saveData — the
first real consumer of the timed-process subsystem + `GRegistries.processes`),
seeds (tag vanilla ingredients as seeds?), growth over game time (like forage
cooldowns), planter as activate-context with its own layout. Design session first.

## Farming Phase 1 — planter farming (ratified + built 2026-07-04)

Decisions: **planters first** (terrain planting = Phase 2 on the same subsystem);
**vegetable = seed** (plant the produce itself; no seed records); **planter stays
proximity + [F]** (the item↔activator drop-swap remains a kiln/furnace task, not a
farming dependency); **annuals + perennials** (per-crop `regrow`).

Built:
- **Crop lifecycle (global `globalFarming.lua`)**: `ImmersiveCrafting_Plant` consumes
  one seed, spawns the crop's vanilla flora record above the planter (`+15z`, tune),
  scales 0.3 → 0.65 → 1.0 via **persisted game-time timers** (grow while sleeping;
  timers survive save/load); registry in global `saveData.crops`. Harvest = activating
  the ripe plant: a `types.Container` activation handler intercepts **registered crop
  objects only** (O(1) lookup; wild flora untouched) — unripe → message; ripe → grant
  yield ×N, then remove (annual) or reset + reschedule (perennial). Player gets full
  snapshots (`ImmersiveCrafting_CropSync` → `farmState.lua`) + `ImmersiveCrafting_Notify`
  messages.
- **Card-only UI (`handlers/farming.lua`)**: planter context (proximity, tag `planter` →
  `ic_station_planter`): Empty + "[F] Plant <crop> (hold)"; **tap [F] cycles the seed**
  (new `OnTap` on the handler base + short-press detection in the overlay's hold
  machinery, threshold 0.3s); growing → "Ready in ~N h"; ripe → "Activate the plant to
  harvest".
- **Data**: `crops/crops.json` (kreshweed + marshmerrow perennial, saltrice annual —
  the canonical plantation crops; 24h grow / 12h regrow), `farming` action/handler,
  `planter` context, `GRegistries.crops` (player) + a global-side copy of the same
  files.

Verify in-game:
- planting end-to-end (seed consumed, plant appears above the bed, `+15z` offset right
  for the planter mesh), scale steps look sane, timers fire after sleep/wait
- harvest: ripe activation grants + suppresses the container UI; unripe message;
  perennial shrinks back; annual disappears
- setScale on objects in inactive cells (pcall-guarded — check log for errors)
- flora record ids (`flora_kreshweed_01`/`flora_marshmerrow_01`/`flora_saltrice_01`)
- tap-vs-hold feel (0.3s threshold) with several seed types in the pack

Phase 2 (later): terrain planting — gaze at bare ground (castRay terrain hit = no
hitObject), spacing cap via the registry, same lifecycle. v2 hooks: watering (SD water
interop) shortening growTime; per-crop yield ranges; farming skill?

## Timed processes (built 2026-07-04)

The last big engine piece: process recipes with a `duration` (game seconds; CSV
column `duration`, 27 recipes valued — ingots, charcoal, burnt molds, castings,
bonemold, netch leather, clay pot/crucible/glass) no longer craft instantly.

Flow (globalProcessing.lua + processState.lua mirror, farming-pattern):
- **Start**: taking the result in the crafting window sends
  `ImmersiveCrafting_StartProcess` — inputs verified then consumed up front, run
  registered in global `saveData.processes` (one per station object), a persisted
  GAME-time timer schedules completion (passes while sleeping; survives
  save/load), window closes. Result caption shows "(takes ~N h)".
- **While running**: the station card shows "<label> — in progress · Ready in
  ~N h"; activating the station gives a remaining-time message; the crafting
  window refuses to open ("This station is busy").
- **Done**: notify toast; card flips to "ready! — Activate to collect";
  activating the station grants the output and frees it (init.lua's activation
  handler consults globalProcessing FIRST). Proximity stations collect via [F]
  (`ImmersiveCrafting_CollectProcess`).
- `ImmersiveCrafting_OpenStation` now carries the station **object** so the
  window knows which station a run belongs to.

Verify in-game:
- full kiln loop: place ore+charcoal → take result → "ready in ~1 h" → wait/sleep
  → activate → ingot collected; save/load mid-run
- busy-station guards (window refuses, activation messages)
- sd_meals + shaped recipes unaffected (still instant)

Open (by design, later): cooking doneness states (simmering/cooked/burnt needs
multi-stage, not just done); progress bar on the card (we have remaining time —
a bar needs per-tick refresh like the hold bar); fuel-quality time modifiers.

## Carving + station slot roles (built 2026-07-05)

Two ratified designs (user 2026-07-05):

**Multi-match cycling ("carving").** One placement can now resolve to SEVERAL
shaped recipes — `shapedCrafting.resolveShapedRecipes` returns all matches
(sorted by id, stable) and the Result panel grows a `< i/n >` cycler when
ambiguous; the shown match is what clicking the Result crafts, and the pick
survives rebuilds (resolve re-finds the previous match id). This also fixes the
old nondeterminism where same-pattern recipes shadowed each other randomly
(steel helm/boots/greaves = 2 ingots each; the glass set). Content: 4 CARVING
rows in the CSV (Crafting Table, 1 Wood + Knife → vanilla wooden cup / spoon /
fork / knife — ids need verification vs the tes3-records dump).

**Kiln/furnace slot roles + stacking slots.** Layouts per the ratified spec:
kiln = Input / Reagent / Fuel / Mold, furnace = Input x3 / Fuel / Mold (the
Reagent slot covers water/stone/salt-style additives; tanning rack already had
Input/Reagent). To make big recipes fit (Iron Ingot = 3 Ore + 2 Charcoal),
**process slots hold stacks** Minecraft-furnace-style: picking the same
material again adds one to the selected slot (selection stays put on process
layouts; grids still hold 1 per cell and auto-advance), clicking a filled slot
takes one unit back, the count badge shows stack size. There is NO output slot:
the Result panel is the output for instant crafts, and timed runs deliver at
the station itself (card flips to "ready — Activate to collect").

`CContext.SlotDef` gained optional `accepts` (ids/FlexTags) and
`acceptsPatterns` (Lua patterns) — placement guidance only (the Mold slot takes
only `ic_mold_*`; the materials strip filters to what the selected empty slot
accepts). Recipe matching stays a forgiving counted multiset over ALL slots, so
labels/filters never break a valid recipe.

Verify in-game:
- carving: 1 wood + knife at the table → cycler shows 4 outcomes, cycle + craft
  each; steel helm/boots/greaves now all reachable from 2 ingots
- kiln: 3 Ore stacked in Input + 2 Charcoal in Fuel → Iron Ingot run starts;
  crucible (3 Clay + 2 Stone via Input+Reagent); mold slot refuses non-molds
  and the strip filters to molds while it's selected
- furnace castings: ingots stack in one Input, burnt weapon mold in Mold
- vanilla woodenware record ids exist (user: check tes3-records dump)

Open: process-recipe cycling (resolver still returns the single most-specific
match — extend to a list if two process recipes ever tie); Fuel slot has no
accepts filter yet (needs a Fuel FlexTag authored before it can be strict).

## Kiln = ceramics, Furnace = metallurgy + equipment gating (ratified + built 2026-07-05)

Historically-grounded station split (user ratified): kilns are ceramics tech
and CANNOT smelt; smelting/alloys are furnace (bloomery) tech. The tech tree is
now structural: kiln -> fires the crucible -> crucible builds the furnace ->
furnace unlocks metals and alloys.

**Kiln (Input / Fuel / Mold, 1 input):** ceramics only — clay pot (2 Clay, the
water was dropped: wet clay), crucible (3 Clay, stones dropped), bonemold
(chitin dust, water dropped), firing raw molds. Max 2 distinct stacks fits.

**Furnace (Input x3 / Fuel / Mold):** all smelting + alloys + casting. Iron
Ingot (3 Ore + 2 Charcoal) and Steel (iron + charcoal = carbon, historically
real carburization) moved here; Glass Component became a showcase 3-stack
ALLOY (2 Raw Glass + 1 Salt flux + 2 Charcoal — real glass = sand+soda+lime).
Furnace BUILD moved from the kiln to a Crafting Table shaped recipe (4 Stone +
crucible — you build a furnace, you don't fire one).

**Process multi-match cycling:** dropping water made bonemold helm/boots (and
greaves/shield) identical inputs — resolveProcessRecipes now returns ALL
matches (the old most-items-wins score was vestigial: exact multiset matching
forces equal totals) and the Result cycler works at process stations too.

**Equipment skill gating (ALL armor — looted, bought, crafted):** new
`equipGate.lua` (player script, 0.5s throttle) strips worn armor whose
requirement exceeds the governing skill, with a "(Heavy Armor 60 needed)"
message. Zero authored data: requirement = the record's baseArmor (Morrowind
sets share one AR per set: iron 10 ... glass 50, ebony 60, daedric 80 — maps
straight onto 0-100 skill), pieces at/below MIN_REQUIREMENT=15 are always
wearable (iron/chitin/hide). Governing skill computed the engine's way: weight
vs slot reference GMST (iHelmWeight...) x fLightMaxMod/fMedMaxMod. Vanilla
already scales armor RATING by skill, so "less efficient" was free; this adds
the hard gate.

Verify in-game:
- kiln fits every recipe in 3 slots; furnace smelts iron/steel/glass; furnace
  build appears at the crafting table (needs crucible in the grid)
- 1 chitin dust at kiln -> cycle helm/boots; 2 -> greaves/shield
- equip glass armor at Light Armor < 50 -> stripped + message; skill-up ->
  wearable; boots/helm on beast races still engine-blocked
- verify types.Actor.setEquipment strips cleanly in self context and GMST
  names resolve (iHelmWeight, fLightMaxMod, fMedMaxMod)

Open: alloy tier follow-ups (ebony smelting, daedric = ebony + daedra essence
at a special condition/station, dwemer = melt-down scavenge only); gating mode
setting (block vs debuff-while-worn vs off) — block only for now; make
SKILL_FACTOR/MIN_REQUIREMENT + per-record overrides data-driven (JSON) later.

## Bonemold = paste + mold + kiln, returned inputs (built 2026-07-05)

Bonemold reworked to the ratified mental model ("paste into a mold, fire it"):
lore says bonemold is ground bone bound in RESIN (not clay/water), and vanilla
ships both ingredients — so the chain is all-vanilla inputs:

1. **Bonemold Paste** (new `ic_bonemold_paste` misc record, muck mesh as
   placeholder): 2 Bonemeal + 1 Resin at Bushcrafting with the Mortar & Pestle
   (tags `Bonemeal`, `Resin` — tag vanilla ingred_bonemeal_01,
   ingred_resin_01, ingred_shalk_resin_01).
2. **Fire at the kiln**: paste stack (Input) + Charcoal (Fuel) + the burnt
   armor mold in the MOLD slot — every bonemold recipe now uses all three kiln
   slots. Helm/boots (1 paste) and greaves/shield (2) still cycle.

**New engine feature — `returned` inputs:** a process-recipe input line with
`returned: true` must be PLACED for the match but is not consumed (the mold
comes back). Converter emits it automatically when a REUSABLE_TOOLS item
appears in a process recipe's ingredient columns (grid ingredients still
error, acknowledged Furnace-build excepted); `consumeList()` in Crafting.lua
subtracts returned lines for both instant crafts and timed StartProcess runs
(the mold simply never leaves the inventory), and the Result caption shows
"(mold returned)". Arrows/bolts keep using chitin dust, so that chain stays.

Verify in-game: paste craft; helm fire (mold slot accepts the burnt armor
mold, strip filters to molds); after collect the mold is still in inventory;
cuirass = 3 paste + 2 charcoal + mold fits the 3 kiln slots.

Open: while a timed run cooks, the "placed" mold stays in the player's
inventory (could start a second kiln with the same mold — accepted for now,
same trust level as tools); crucible could become a returned input at the
furnace later instead of a tool.

## Returned items v2: mold stays in the station; crucible demoted (built 2026-07-05)

Bug fix (user report): during a TIMED run the returned mold no longer sits in
the player's inventory — starting a run consumes EVERYTHING placed (the mold
is physically in the kiln), the run entry stores a `returned` list (actual
placed record ids, tags resolved), and collect grants output + returned items
back. Instant crafts still simply never consume the returned part.
`splitPlaced()` in Crafting.lua replaces consumeList and feeds both paths.

Shaped recipes can now retain ingredients too: CShapedRecipe gained a
top-level `returned: [{id, count}]` list (the ids still appear in
pattern/key — they must be placed). The converter emits it automatically for
RETURNED_ITEMS in grid ingredient columns.

Crucible demoted from tool to plain ingredient (user ratified): it is
consumed ONCE building the furnace — historically a "crucible furnace", the
crucible is part of the structure — and the 9 casting recipes lost their
redundant ic_crucible tool requirement. RETURNED_ITEMS = {armor mold} only;
the ACKNOWLEDGED lint exception is gone, and returned items in a TOOL column
are now a lint error.

Verify in-game:
- start a bonemold firing -> armor mold LEAVES the inventory; collect ->
  mold + piece both granted; save/load mid-run keeps the returned list
- casting at the furnace works without a crucible in inventory
- instant craft with a returned ingredient consumes everything but it

Note: returned items are re-created on collect (fresh instances — fine for
plain misc molds, would lose condition/charges on equipment; revisit if
returned ever covers enchantables).

## Player-managed tool slots (ratified + built 2026-07-05)

The auto-detected Tools row (unbounded — bushcrafting was pushing 8 owned
tools) replaced by 3 PLAYER-MANAGED tool slots, vanilla-alchemy style
(3 = the CSV's tool1..3 cap, so any single recipe fits):

- Click a tool slot -> the materials strip switches to the station's tools
  (stationTools filter); pick to slot it; click a filled slot to take it back.
  Slotted tools are never consumed and never enter the station (unlike
  returned molds) — they're "in hand".
- Two-stage matching: resolvers (shaped + process) now match by INPUTS ONLY
  (their inventory hasTools checks removed); craftability is tools ⊆ slotted,
  decided in the window. Input-matched recipes with missing tools still show
  in the Result panel with "(needs Knife)" — fixes the old silent failure —
  and sort after tool-satisfied matches (id tiebreak keeps order stable).
- Alchemy-style AUTO-FILL: the shown match's owned-but-unslotted tools snap
  into free slots automatically, once per recipe id (autoFilled set), so
  hand-clearing a tool sticks; the set resets when the placement changes.
  Common flow stays zero-click: place wood -> knife snaps in -> craft.
- Tool choice now disambiguates same-input recipes (2 Clay + slotted chitin
  dagger = dagger mold; slot the war axe instead for the axe mold) — the
  cycler remains for genuinely identical placements.

Verify in-game:
- knife auto-slots when placing wood at bushcrafting; clearing it flips the
  caption to "(needs Knife)" and blocks the craft until re-slotted
- tool-slot click -> strip shows only tools; input-slot click switches back
- mold recipes: slotting dagger vs war axe changes which mold sorts first
- sd meals with tools (pan) auto-fill correctly

Open: tool QUALITY tiers (slot the steel axe vs chitin axe -> speed/yield
modifiers) — natural next step on this foundation; per-station tool-slot
persistence across window sessions (currently per-session, auto-fill covers).

## SD water interop (built 2026-07-05)

Recipes can consume water without eating the container: the bottle is emptied
into the craft and the empty waterskin/cup stays with the player.

**Matcher — `sd:<liquid>` in any ingredient/tool cell** (`sd:water`,
`sd:sujamma`, `sd:liquid` = any). SD bottles are dynamic Potion records
(untaggable), but every one is minted with `mwscript = "sd_liquid_tracker"` —
readable from the record in ANY context, so "is this an SD liquid" is instant
player-side (sdLiquids.lua). WHICH liquid lives only in SD's global registry
(`saveData.reverse[id] = {orig, q, liquid}`), so unknown ids do one global
round-trip (ImmersiveCrafting_ClassifyLiquids -> _LiquidSync, answered via
SD's GLOBAL I.SunsDusk.isConsumable -> ({orig,q,liquid}, "drink")) into a
player mirror. First sight of a fresh bottle can miss one frame; every later
resolve sees it. NOTE: SD's PLAYER-side isConsumable does NOT cover drinks —
that's why the round-trip exists.

**Consume — return the empty container**: both executors (onCraftShaped and
globalProcessing.onStart) ask globalLiquids.emptyContainerFor(id) after
removing a consumed input and grant `orig` back (count-aware). Timed runs
return the container IMMEDIATELY at start — the water is poured in now; the
skin does not sit in the station like a returned mold.

**Whole-bottle semantics (accepted)**: one placed bottle = one water unit; the
bottle's full content goes into the craft regardless of fill level (pick a
small bottle). Charge-level splitting (consume 250ml, get the q-1 bottle
back) would need SD's internal record minting or its
SunsDusk_WaterBottles_downgradeWaterItem event, whose contract (caller
removes, handler grants next level, +consumedWater side effects) is fragile
across our event ordering — revisit only if the waste ever hurts.

Converter: `sd:` refs are engine matchers, excluded from the record/tag report.

Verify in-game (needs SD):
- recipe cell `sd:water` -> filled waterskin appears in the strip and matches;
  crafting removes the bottle and grants the empty container back
- timed run with sd:water -> empty skin back at START, output on collect
- sujamma/tea bottles do NOT match sd:water; sd:liquid matches all
- without SD loaded: sd:* matchers simply never match, nothing errors

Open: no recipe uses sd:water yet (content is user-owned — e.g. future
Immersive Cooking stews, farming watering); giveMaterials can't mint SD
bottles (logs unresolved — use SD's own water sources when testing).

## Forage polish: gather wood + real hold bar (built 2026-07-05)

**Tree foraging reworked** (user request — SD's wood-chopping owns firewood):
- forage_tree: verb "Gather wood", yields 1-3 STICKS (new `yield.countMax` =
  random count..countMax), bare-handed (axe tool dropped — deadfall sticks
  need no tool, and the chitin-dagger bootstrap needs a stick first).
- `forage.woodYield` (ic_wood x1 on trees): granted ON TOP only while the
  "foraging gives wood" rule is active — new checkbox setting
  `ForagingGivesWood` (default off) OR Sun's Dusk absent (auto: without SD
  there is no other firewood source, so trees must provide). Message reads
  "You gather 2 x Sticks (+1 Wood)".

**Hold bar**: the ASCII `[||||....]` text bar replaced by a real filled bar —
MWUI box border, dark track, solid gold fill (same gold as the selected slot),
LINE_W wide. Fills smoothly (overlay already re-renders every frame during a
hold).

Verify in-game:
- with SD: trees give sticks only; toggle the setting -> +Wood appears
- without SD: +Wood automatic
- hold bar renders as a filled gold bar and resets on release/tap

## Crafting-window polish round (built 2026-07-05)

Four user reports, all fixed:

- **Window jump on first click — ROOT CAUSE FOUND.** Window.lua's mousePress
  converted relativePosition -> absolute via ui.screenSize() (raw pixels),
  but layout coordinates are UI-SCALE units — the first click after every
  open moved the window (tools seemed fine only because a click had already
  converted it). Now the press pins the window via the event itself
  (position - offset, already in layout coords, scale-proof); edge-resize
  detection now also runs in one coordinate space. Added mouseRelease to
  clear drag state (no stale-delta phantom jumps).
- **No vanilla windows**: the crafting window opens with
  setMode('Interface', { windows = {} }) — cursor only, no inventory
  (the materials strip replaces it).
- **Hover tooltips in the strip**: entries carry a `label` (record name /
  recipe name); ItemPicker shows a boxTransparent tooltip on the
  Notification layer that follows the mouse (moved in place, not recreated;
  hidden on click/rebuild/close).
- **Recipe guide v1 ("pick an outcome")**: the strip header gained a
  Recipes/Materials toggle. Recipes mode lists every recipe at this station
  (paged, output icon + count badge, tooltip = name, sdMeal entries gated on
  SD). Clicking one AUTO-PLACES its ingredients from the inventory —
  grid recipes cell by cell, process recipes as stacks into accepting slots
  (mold to the Mold slot), tool auto-fill re-armed so its tools snap in —
  then flips back to Materials; anything short is reported as
  "Missing: 2x Clay, ...". Best-effort: gaps stay empty for hand-filling.

Verify in-game:
- open window fresh -> first ingredient click no longer moves it; drag +
  resize still work; release outside then click inside: no jump
- F opens ONLY our window (cursor, no inventory)
- tooltips on materials, tools (while tool slot selected) and recipes
- recipe guide: pick Iron Ingot at the furnace -> ore+charcoal auto-stack;
  pick a bonemold piece at the kiln -> paste/charcoal/mold slotted right

Open: recipe-guide niceties — ghost icons for missing ingredients in the
slots (COLORS.missing exists), sort craftable recipes first, filter/search.

## Station drop-swap: item <-> activator (built 2026-07-05)

Fixes the user report: activating a placed kiln PICKED IT UP (stations are
misc items). Now placed stations are ACTIVATORS, driven by
data/Immersive-Crafting/stations/stations.json ({item, activator} pairs):

- **Place**: globalStations.onObjectActive swaps a station ITEM lying in a
  cell (just dropped, or pre-existing) for its `_a` activator at the same
  position/rotation (one off the stack). If the activator record isn't in
  the load order yet (plugin not built), it logs and leaves the item alone —
  nothing breaks before the ESP exists.
- **Pack up**: hold F (1.5s) on a placed station's card ->
  ImmersiveCrafting_PackStation -> activator removed, item granted back.
  Refused while a timed run occupies the station ("collect its work first").
  The overlay's F-guard for activate contexts now allows HOLD actions only
  (instant F still does nothing there — activation opens the station).
- **Records**: records/Activator/ic_station_{firepit,kiln,furnace,
  charcoalpit,tanningrack}_a.yaml — meshes currently mirror the misc
  placeholders; USER picks proper meshes from the tes3-records dump (the
  agent environment cannot reach rfuzzo.github.io — network policy blocks
  it) and rebuilds the plugin with tes3util. NOTE: the committed `tes3util`
  binary is the macOS arm64 build (Mach-O) — it cannot run in the Linux
  agent container; commit a Linux x86_64 build if the agent should ever run
  it. The station contexts also carry the `_a` ids in recordIds directly, so
  detection works without tagging.
- Crafting Table + Planter stay proximity-triggered misc items on purpose:
  activating them = picking them up IS the pack-up mechanic there.

Verify in-game (after the plugin with the Activator records is built):
- drop kiln item -> activator appears in place; activate -> station opens
  (not picked up); hold F on its card -> packed back into the inventory
- busy kiln refuses packing; collect first, then pack works
- dropping a STACK of stations converts one; the rest stays lying as items

## Steel armor: cast → hammer two-step (PROTOTYPE, 2026-07-06)

Testing idea 2 (more armor crafting steps) on the steel tier only, to feel
whether the extra beat reads as ritual or chore before generalizing:
- FURNACE cast: steel ingots + part mold (returned) + charcoal → a rough part
  (new ic_steel_<slot>_rough records, 10, placeholder scrap-metal mesh).
- CRAFTING TABLE hammer: rough part + `hammer` TOOL → the finished vanilla
  steel piece. One-cell shaped recipe; tool never consumed.
Keeps the per-part molds meaningful (mold shapes the cast; hammering finishes).
Iron + bonemold stay single-step direct-cast; steel weapons untouched.

OPEN — the `hammer` tag: it already exists but currently holds WEAPON hammers
(banhammer, stendar hammer, etc.), not smith hammers. As-is you'd "smith" armor
with a banhammer. Decide: retag `hammer` to armorer's/repair hammers (the
Repair-type "Armorer's Hammer" records), or point these recipes at a new tag.

Decision pending: if the two-step feels good, generalize to iron + bonemold
(each adds a rough-part record set + hammer recipe); else revert to direct cast.
