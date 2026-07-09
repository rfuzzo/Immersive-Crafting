# Immersive Crafting — build log

Chronological design + build record (ratified decisions, what was built,
and each feature's in-game verification list). The forward-looking list
lives in TODO.md.

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
  - `foraging` action/handler: tools required-not-consumed, yield granted via the existing
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
round-trip (ImmersiveCrafting_ClassifyLiquids ->_LiquidSync, answered via
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

## UI-less kiln & charcoal pit (ratified + built 2026-07-06)

The immersive loop (user ratified): DROP items onto the station to load it,
hold FIRE to it to light it, activate when done to collect. Kiln + charcoal
pit only (stations.json `loadable: true`); the furnace keeps the window —
a crucible furnace is a complicated thing. Fully additive: an EMPTY station
still opens the crafting window as before.

- **Load** (global): init.lua's onObjectActive chain — station items swap to
  activators first; any other ITEM dropped within 150 units of an idle
  loadable station joins its charge (saveData.charges[stationId], whole
  stack, absorbed; "Loaded 3 x Ore into the Kiln"). Gated by the new
  "Load stations by dropping items" setting (default ON), pushed to the
  global script via ImmersiveCrafting_SetOptions (on load + on change).
- **Status**: charges mirror to the player inside ProcessSync
  (processState.chargeFor); the card shows "Loaded — Contains: 3x Ore,
  2x Charcoal" and activating a cold loaded station reports the charge
  instead of opening the window.
- **Light it** (player): with fire in hand — a lit torch (Light in
  CarriedLeft) or any item tagged `firestarter` (user-authored tag) — the
  card offers hold-F "Light the fire" (1.5s). The handler resolves the
  charge via resolveProcessRecipes (exact multiset), checks tools against
  the INVENTORY (no tool slots UI-less), splits returned mold lines, and
  sends ImmersiveCrafting_IgniteStation; global consumes the WHOLE charge,
  registers the run (shared registerRun with the window path), lights the
  processFx fire. No match -> "That will not make anything"; missing tools
  -> "Needs: ..."; without fire the card says "Needs fire in hand (a torch)".
- **Collect / pack**: unchanged collect-by-activation; packing a cold loaded
  station returns its charge first (PackStation wrapper in init.lua).

Ambiguity note: identical charges (bonemold helm vs boots = 1 paste) light
the FIRST match by id — the window's cycler remains the precise tool.

Verify in-game:

- drop ore+charcoal at kiln -> loaded card; activate -> contents message;
  torch in hand -> hold F -> fire lights, run starts; collect ingot
- charcoal pit: 4 wood -> light -> charcoal
- pack a loaded cold kiln -> charge + kiln item back; busy kiln refuses
- setting OFF -> drops stay on the ground; window flow unaffected
- fireball ignition (stretch, unverified API): detecting a fire-school cast
  while gazing at the station — research OpenMW spell-cast hooks first

Planter (open, user undecided): hold-F planting STAYS (make-believe wins
over drop-to-plant). Improvement idea on the table: planters REMEMBER their
last crop and default to replanting it, so tap-cycling is only needed when
switching crops.

## Planter: sow by dropping + planter memory (ratified + built 2026-07-06)

The planting grammar, ratified after the hold-F discussion — hold-F STAYS as
the planting verb; what changes is how the seed is CHOSEN (most immersive
first):

1. **Sown seed** — DROP a seed onto the planter: "You set Marshmerrow into
   the soil" (one off the stack, absorbed into saveData.sown, same
   onObjectActive chain as station loading, 100-unit radius, nearest empty
   planter; gated by the same "Load stations by dropping items" setting).
   The card flips to "Marshmerrow in the soil — [F] Plant (hold)"; the hold
   plants exactly that seed (consumed from the soil, not the inventory).
   Tap-cycling is disabled while a seed sits in the soil. Picking the
   planter up returns the unplanted seed (Misc activation hook).
2. **Planter memory** — every successful plant records the crop
   (saveData.planterMemory); the remembered crop sorts FIRST in the seed
   list, so plain hold-F replants it and cycling is only needed to switch.
   Memory dies with the planter object (cleared on pickup).
3. **Tap-cycle** — unchanged fallback for first-time/expedition planting.

Mirrors: CropSync now carries { crops, sown, memory }; farmState gained
sownFor/memoryFor. globalFarming.onPlant takes `fromSown` (verify sown entry,
clear only after the plant actually spawns). init.lua's onObjectActive chain:
station swap -> seed sowing -> station charge; SetOptions fans out to both
globalProcessing and globalFarming.

Verify in-game:

- drop 1 saltrice on an empty planter -> sown message + card; hold F ->
  planted, no inventory consumed twice; grow/harvest normal
- drop near planter AND kiln (overlapping radii) -> planter wins for seeds
- harvest annual -> card offers "Plant Saltrice" first (memory), no cycling
- pick up planter with sown seed -> seed returned; memory forgotten
- setting OFF -> dropped seeds stay on the ground; cycling unaffected

## Slot accepts: patterns -> tags (2026-07-06)

User ratified: `accepts` filters should be TAGS like everything else. The
kiln/furnace Mold slots' `acceptsPatterns: ["^ic_mold_.*_burnt$"]` replaced by
`accepts: ["mold_burnt"]`; `mold_burnt` + `mold_raw` FlexTags in
ModTags/ImmersiveCrafting.yaml. `acceptsPatterns` stays as an engine capability
but is now documented as ONLY for record families that cannot be tagged (other
mods' dynamic/mass records — same rule as CContext.recordPatterns for SD fires);
no data uses it anymore.
Verify in-game: mold slot still claims burnt molds only (via the tag).

Merge note (2026-07-06): after main added the full mold family (armor part
molds, gauntlets, ingot mold; `ic_mold_armor` renamed to `ic_mold_cuirass`),
`mold_burnt`/`mold_raw` were regenerated from records to cover all 18 molds
each. Every new burnt mold must be added to `mold_burnt` to be placeable in the
Mold slot — the pattern `^ic_mold_.*_burnt$` would auto-cover instead, if the
explicit tag ever becomes a maintenance burden.

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

## Mod integrations: Ashlander Crafting, Hunterwind, Yurt (ratified + built 2026-07-06)

Investigation (tes3util Linux dumps) + ratified decisions: parallel chains
(keep IC's), tag-and-keep-both chitin, quality tiers = costlier recipes
(skill-gate later), AC's mwscript menus stay as a parallel path for now.

**Engine — soft mod dependencies:** dataManager now SKIPS any recipe whose
output record is not in the load order (probed across item record stores at
load, logged). Recipes for AC/Hunterwind/Yurt/OAAB/TD outputs are safe without
those mods — no consumed-inputs-for-nothing crafts.

**Ashlander Crafting port (records/menus untouched; ESP loads as-is):**

- Tannin: grind corkbulb/hackle-lo/trama root (Mortar & Pestle, bushcrafting).
- Leather chain at the tanning rack (TIMED, parallel to ic_netch_leather):
  hide/pelt + saltrice -> Cured Hide (1h); + tannin + knife -> Tanned Leather
  (1h); + resin -> Hardened Leather (30min).
- New material files hide.json (4 pieces) + leather.json (8) using AC records.
- Chitin: recipes migrated from exact ic_chitin_plate to the new
  `chitin_fragment` tag (ic_chitin_plate + a_msc_chitin_01 — NOT the bare
  'chitin' tag, which classifies chitin ARMOR in the per-plugin files); added
  vanilla pauldrons/gauntlets ("guantlet" — vanilla typo, ids from AC's
  AddItem lines), throwing stars x10, chitin arrows x10; dark chitin armor
  (8 AC records, +1 resin each); Fine/Superior (_02/_03) weapon tiers
  (+1 fragment / +1 fragment +resin); bonemold bows 02/03.
- Arrows: corkbulb/ebony (crafting table), glass (glass.json), all x10 + stick.
- Repair prongs 01-04 from 1-4 scrap metal (hammer).
- ic_chitin_plate reskinned to AC's chitin mesh/icon; tanning-rack ACTIVATOR
  now uses AC's dedicated activator mesh (ian_rack_empty_02).

**Hunterwind (stays standalone):** generated ModTags/Hunterwind_{Ingredient,
MiscItem}.yaml — 37 pelts/skins -> hide+pelt (feeding the tanning chain!),
12 meats -> meat, 5 shells -> chitin_fragment, Hunter Knife -> knife (works as
an IC tool). Recipes: craft the Hunter Knife (iron ingot + stick + string,
hammer) and REFORGE the broken one at the furnace (broken + charcoal, 30min)
— replaces the 20-drake dialogue repair with actual smithing.

**Yurt Crafting:** one recipe — the Yurt Crafting Kit (4 plank + 2 cloth +
2 string, knife) as the FRAME bundle; the mod's own deploy script still
consumes 10 guar hides + 10 kresh fiber + 5 corkbulb on placement (no double
cost, coherent story: kit = frame + tools, deploy wraps it in your hides).
The interior worktable (global-variable-driven placement) is deliberately NOT
ported. Yurt = natural Tent Mk2.

Verify in-game (needs the respective ESPs):

- without AC/Hunterwind/Yurt loaded: their recipes absent, log shows skips
- AC chain end-to-end: grind tannin -> cure guar hide -> tan -> harden ->
  hardened cuirass; Hunterwind pelt cures at the rack (hide tag)
- chitin recipes accept BOTH ic plates and AC fragments (+beetle shells)
- hunter knife reforge; yurt kit crafts then deploys (mod charges materials)
- balance pass: all counts are first-draft (user-owned)

Open: AC quality tiers should later require Armorer skill (skill-gated
recipes, roadmap); "menus-off" patched AC ESP via tes3util when the user
tires of the mwscript UI; bloods/fats/glands from Hunterwind untagged
(cooking candidates); a_msc_crafting_tool/tanner-specific tools unused (IC
uses the generic knife/hammer tags).

## Field dressing + Salt fix (ratified + built 2026-07-06)

**Salt cures hides, not grain** (user): the two AC cure recipes swapped
`ingred_saltrice_01` -> the `Salt` tag (IC's original design).

**Field dressing** replaces Hunterwind's 274 creature-record loot edits with
IC's contextual grammar (ratified: leave the corpse; take-from-loot-else-mint;
the HUNTER KNIFE specifically):

- data/dressing/creatures.json: 272 creature -> carcass entries GENERATED from
  Hunterwind's own creature inventories (their injection method IS the
  mapping); loaded into GRegistries.dressing with the same soft-dependency
  filter as recipes (no Hunterwind = empty registry = no cards).
- Engine: contexts gain `targets: "corpse"` — DEAD actors (nearby.actors +
  types.Actor.isDead) join the candidate scan for corpse contexts only;
  living actors never card, corpse contexts never match items/activators.
- handlers/dressing.lua: "Guar — dead / [F] Field dress (hold 1.5s)", requires
  the Hunter Knife (hb_hunters_knife); once per corpse (dressState, player
  save, forageState-style); the corpse STAYS for vanilla looting/disposal.
- globalDressing.onFieldDress: take-from-loot-else-mint — with UNPATCHED
  Hunterwind the carcass is pulled out of the corpse's inventory (no
  doubles); with the patched plugin it's minted. Both configs identical.
- tools/patch_hunterwind.py: strips the creature overrides from
  hunterwind.omwaddon via tes3util (verified round-trip); patched plugin
  loads instead of the original (assets still from the original download —
  shipping plugin-only patches is fine per user; never HW's assets).
- Downstream: Hunterwind's own carcass-item scripts (butchering into TD
  meats, carcass removal) process what field dressing produces — unchanged.

Verify in-game: kill a guar -> card appears only when dead; no knife ->
"Requires: Hunter Knife"; dress -> carcass granted, second attempt refused;
unpatched HW -> corpse loot loses the carcass (moved, not duplicated);
patched -> carcass minted; NPC corpses never card; isDead API on 0.51.

Open: quality tiers (_l vs_h carcasses by skill — HW's hunter level;
IC could gate on a vanilla skill later); dressState pruning (dressed ids
outlive corpses harmlessly; prune if saves ever bloat); gaze-switch branch
(claude/gaze-context-switch) touches the same contextManager region — merge
that one first or expect a small conflict here.

## ic_* record audit: replace with vanilla/OAAB/TD records (built 2026-07-06)

User directive: drop every `ic_*` record that an existing record (vanilla,
OAAB_Data, Tamriel_Data, or a mod dependency) can stand in for. 10 records
retired (recipe ids renamed to the new output ids; `records/MiscItem/*.yaml`
deleted; the esp shrinks accordingly on the next `_pack.ps1`):

| retired            | replacement                | source    |
|--------------------|----------------------------|-----------|
| ic_bowl            | misc_com_wood_bowl_02      | vanilla   |
| ic_bucket          | misc_com_bucket_01         | vanilla   |
| ic_mortar_pestle   | apparatus_a_mortar_01      | vanilla   |
| ic_fibre           | ingred_kresh_fiber_01      | vanilla   |
| ic_netch_hide      | ingred_netch_leather_01    | vanilla (input-side only) |
| ic_pan             | AB_Misc_ComCopperPan01     | OAAB      |
| ic_water_bladder   | AB_Misc_Waterskin          | OAAB      |
| ic_clay_pot        | AB_Misc_PottersClayPot01   | OAAB      |
| ic_charcoal        | T_IngMine_Charcoal_01      | Tamriel Data |
| ic_crucible        | T_Rga_Crucible_01          | Tamriel Data |

Two latent bugs fixed on the way:

- the "Mortar and Pestle" tool matcher matched NOTHING (no such tag, and the
  record id was ic_mortar_pestle) -> new `mortar` tag on the five vanilla
  apparatus mortars; all five bushcrafting recipes now use it.
- ic_netch_hide was unobtainable (tanning input with no source recipe/forage)
  -> the netch cure now takes vanilla `ingred_netch_leather_01` (raw drop)
  and still yields `ic_netch_leather` (the cured crafting material).

New tags in ModTags/ImmersiveCrafting.yaml: `crucible` (T_Rga_Crucible_01 —
the furnace-build "crucible" key finally resolves), `mortar`, `fibre`
(feeds the ic_string "Fibre" key), `firestarter` (AB_Misc_FlintAndSteel +
AB_Misc_Flint — the UI-less ignite path had the tag check but no tagged
records). `charcoal` tag no longer lists ic_charcoal.

Soft-dep note: OAAB/TD outputs ride the existing outputRecordExists() filter —
without the master the recipe is skipped, nothing breaks.

KEPT (no equivalent found): ic_wood, ic_stone, ic_stick, ic_plank, ic_string,
ic_cloth, ic_pot, ic_grill, ic_spit, ic_tent_mk1, ic_bedroll_mk1,
ic_netch_leather, ic_chitin_plate, ic_chitin_dust, ic_bonemold_paste,
ic_glass_component, all molds, all stations, all steel roughs.

Judgment calls for the user:

- ic_string: T_Com_Rope_01 exists but rope != string — kept ours.
- ic_pot: TD/OAAB only have kettles/cauldrons — kept ours.
- ic_cloth: no generic cloth record found (TD folded cloths are outfits) — kept.
- the pan recipe still consumes iron pieces but now outputs a COPPER pan —
  rebalance when copper enters (TD has no copper ingot; bronze exists).

## SimplyMining interop (evaluated + built 2026-07-06)

Evaluation: SimplyMining is OpenMW-native Lua (player/global/menu scripts, no
MWSE) — runs alongside IC with zero engine work. It spawns ore-node containers
(TR/PC/Sky meshes + its own coal vein) and swing-mining grants the REAL
records: TD ores (T_IngMine_OreIron/Copper/Silver/Gold/Orichalcum_01,
T_IngMine_Coal_01) and vanilla ingred_raw_ebony/raw_glass/diamond/
adamantium_ore_01. The sm_* RepairItem clones are only a vendor-restock trick
(converted back to the real ingredient on purchase) — nothing to tag there.
Its nodes are Containers, so IC's context scan (items/activators/corpses)
never cards them; no collision with gather-stone gaze foraging. Pick
requirement is hardcoded (miner's pick, BM Nordic Pick, id:find("pick")) —
no tag hook needed on their side.

Already-working interop (no change needed): mined T_IngMine_Coal_01 is in
IC's `charcoal` tag -> direct furnace/kiln fuel; raw ebony feeds the ebony
arrow recipe; the dataset `ore` tag covers all TD ores.

IC changes (the metalwork gap-closing):

- furnace iron ingot input `Ore` (tag) -> exact T_IngMine_OreIron_01: the
  broad tag was fine when ore was vendor-only, but with mining it would smelt
  3 of ANY ore (gold!) into an iron ingot.
- LATENT BUG #3 this session: `Raw Glass` tag didn't exist either -> new
  `raw_glass` tag (ingred_raw_glass_01 +_tinos), glass component recipe
  fixed.
- new furnace lines (same shape as iron: 3 ore + 2 charcoal + returned ingot
  mold, 3600s): Silver -> T_Com_MetalPieceSilver_01, Gold ->
  T_Com_MetalPieceGold_01, Bronze <- 3 COPPER ore ->
  T_Com_MetalPieceBronze_01 (TD has no copper ingot; simplified alloy —
  revisit when the alloy mechanic / bronze armor lands. JUDGMENT CALL:
  historically bronze = copper + tin).
- new crafting-table recipe: Miner's Pick (2 iron ingots + 2 sticks, hammer)
  — closes the loop pick -> mine -> smelt -> forge pick.

Not covered (no target records): orichalcum/adamantium/diamond ingots — TD
ingots stop at Bronze/Gold/Iron/Silver/Steel; park for the alloy design.

## Copper ingot + melt-down recycling (built 2026-07-06)

**ic_ingot_copper** (new MiscItem record): 3 copper ore + 2 charcoal +
returned ingot mold at the furnace (replaces the interim copper->bronze
line). Interim mesh/icon: Tamriel_Data's BRONZE ingot, per user — the path in
records/MiscItem/ic_ingot_copper.yaml is written by TD convention
(t\t_com_metalpiecebronze_01.nif) and MUST be verified against the real
T_Com_MetalPieceBronze_01 record before packing (tes3-records site is
unreachable from this environment). No `copper` tag exists yet in the tag
data — add one (+ this record) when copper equipment lands.

**Melt-down recipes** (user: "smelting items with the tag into their
ingots") — furnace, 2 material-tagged items + 1 charcoal + returned ingot
mold, 1800s -> 1 ingot: melt_iron / melt_steel / melt_silver / melt_gold /
melt_bronze -> the TD MetalPiece ingots. Rides the dataset material tags on
weapons AND armor AND misc items. Known quirks (accepted):

- the ingots themselves carry their material tag: melting 2 ingots + charcoal
  back into 1 ingot is possible player error (exact-multiset matching, the
  result shows before starting — self-inflicted only);
- `gold` covers TD coin collectibles / gold dishes / the golden egg — melting
  those is a feature;
- `bronze`/`silver`/`gold` misc clutter (candlesticks etc.) melts too —
  intended recycling;
- ores do NOT carry material tags (only ore/mineral/ingredient) — no shadowing
  of the ore-smelting lines;
- no melt lines for glass/ebony/chitin/dwemer (no ingot records) — glass
  could melt into ic_glass_component later if wanted.

Balance note: 2 iron items -> 1 ingot = 50% return vs the 1-2 ingots most
iron pieces cost to cast. User owns the ratio.

## String -> rope, alloying + ebony/daedric paths (ratified + built 2026-07-06)

**String = rope** (user ruling): ic_string retired -> T_Com_Rope_01 (TD).
New `rope` tag; every ic_string/"string"/"String" reference now uses it — the
lowercase "string" keys (ic_cloth, tanning rack station) were LATENT BUG #4
this session: no `string` tag ever existed, those recipes matched nothing.
The fibre->string recipe now outputs the TD rope.

**Alloy/material paths** (user: copper, bronze, glass, ebony, daedric;
daedric alloyed with a FILLED soul gem):

- copper: ore -> ic_ingot_copper (built earlier today);
- bronze: alloy_bronze = 2 copper ingots + charcoal + ingot mold ->
  T_Com_MetalPieceBronze_01 (simplified: real bronze wants tin; revisit if a
  tin record ever exists) — plus melt_bronze recycling;
- glass: already covered (raw_glass -> ic_glass_component);
- ebony: 3 raw ebony + 2 charcoal + mold -> NEW ic_ingot_ebony (5400s);
  melt_ebony recycles ebony gear (2 -> 1 ingot);
- daedric: 2 ebony ingots + 1 FILLED soul gem + 3 charcoal + mold ->
  NEW ic_ingot_daedric (7200s); melt_daedric recycles daedric gear.

**Engine: instance gates** (`soul: "filled"` on a process input line).
Filled and empty gems share a record id, so id/tag matching can't tell them
apart. The line matches placement by the `soul gem` tag (the 5 vanilla gems;
Azura's Star is NOT in the tag — it can't be consumed); at start time the
window forwards the gate with the consume entry and the GLOBAL consume counts/
removes only instances where types.Miscellaneous.getSoul() is non-empty —
starting with only empty gems refuses with "Requires a filled soul gem" and
consumes nothing. Filled/empty never stack together (different item data), so
stack removal stays safe.

Interim meshes (VERIFY/replace, user-owned): ic_ingot_ebony + ic_ingot_daedric
reuse vanilla raw ebony (n\Ingred_RawEbony_01.NIF); ic_ingot_copper reuses the
TD bronze ingot (path by convention — confirm against the real record).

Open / next:

- equipment recipes FROM the new ingots (copper/bronze/ebony/daedric weapons
  - armor via the existing mold system) — user owns the sets + balance;
- melt_daedric yields daedric ingots WITHOUT a soul gem (recycling existing
  gear) — accepted, flag if it bothers;
- soul gate covers the process path only (shaped recipes don't use soul lines
  yet); UI-less charge loading (kiln/pit) never runs furnace recipes, so no
  gate needed there;
- verify in-game: getSoul API on 0.51; empty-gem refusal; filled gem consumed
  (and the right instance).

## Crosshair picks between stacked stations (built 2026-07-06)

User report: crafting cloth placed ON the crafting table — closest-wins made
the card unpredictable. The per-poll crosshair raycast (previously gaze-only)
now also disambiguates proximity/activate contexts: gaze contexts (trees,
rocks) still win outright; failing that, LOOKING at an object that matches one
of this poll's qualified contexts (range + requires already gated) selects
that context and cards the exact object under the crosshair. Looking at
neither keeps closest-wins, so the card doesn't vanish while glancing around.
One raycast per 0.25s poll (refactored crosshairTarget serves both uses).

Verify in-game: cloth on table -> look at cloth = bushcrafting card, look at
table = crafting table card; look at the farther of two tables -> that one's
card ([F]/pack-up act on the looked-at object); hold-to-forage unaffected.

## UI-less stations: unload by activating (built 2026-07-07)

User: no way to remove dropped-in items, and a second fuel could jam the
charge. Fix: activating a cold LOADED station now pops the LAST loaded stack
back into the inventory (LIFO undo; the old activation behaviour was only a
status message — the card's "Contains:" line already shows the charge).
Wrong fuel = one activation to fix; empty again -> activation falls through
to normal station handling. Load filtering stays permissive on purpose:
recipe-aware rejection would need FlexTag matching, which is player-side
only (the global drop handler can't tag-match).

## Charge pre-validation + align-to-ground placement (built 2026-07-07)

**Card pre-validation** (user: hold-F was wasted before learning the charge
is invalid): the loaded-station card resolves the charge against the recipes
UP FRONT via the shared resolveCharge() (also used by the ignite itself) —
invalid shows the reason on the card ("This will not make anything" /
"Needs: hammer" / "This needs the crafting window") and offers NO ignite
action; valid shows "Will make: X" before the fire requirement.

**Align-to-ground** (charcoal pile clipped into slopes): stations.json
`"alignToGround": true` (charcoal pit). Raycasts are local-only, so the swap
round-trips: global defers the item->activator swap, asks the player to probe
(ImmersiveCrafting_ProbeGround: castRay straight down, World+HeightMap,
ignoring the item), and finishes in onGroundProbe — position snapped to the
hit point, up-axis tilted onto the hit normal (yaw kept; tilt = rotate(angle
between up and normal, up x normal)). No hit / no player -> plain swap.
Verify in-game: tilt DIRECTION on a slope (if mirrored, negate the angle),
and that upright stations (kiln, furnace) are unaffected (no flag).

## UI padding/polish pass (2026-07-07)

Prototyped in the openmw-ui viewer (rfuzzo/openmw-ui — headless Chromium
renders real openmw.ui/MWUI Lua), then ported to the shared UI. Applies to
EVERY station window (grid + process) since it lives in the shared shell.

Window.lua: divider line under the title; body is now a plain growing Flex
(dropped its bordersThick) so the frame reads as ONE window border, not two
concentric ones (window > {grid, strip}).

Crafting.lua: content wrapped in a symmetric PAD (16px all sides) frame instead
of the old top-left-only position(20,20); one GAP (12px) rhythm between
sections (was 10/6/8); a divider above the footer; WINDOW_SIZE 470 -> 500 to
pay for the added dividers/padding while keeping ~2 material rows; stripSpace
constant retuned.

ItemPicker.lua: the Recipes/Materials toggle is pushed to the header's right
edge (grow spacer); divider lines under the header and above the search;
4px gaps between the borderless slots so items read as distinct tiles
(ICON_PITCH 42->44, grid gap); the Search field is now a full-width GROWING
bordered Flex (was a fixed 140px box that didn't stretch).

components.lua: grid() gained an optional `gap`; new hline() helper
(MWUI horizontalLine, auto-fills parent width — the width arg on the old
Crafting.hLine was a no-op, the template's relativeSize already fills).

Branch claude/ui-padding-pass. Verify in-game: open each station (bushcrafting
2x2, crafting table 3x3, kiln/furnace/tanning rack process, firepit) — footer
must stay inside the frame, strip shows >=2 material rows, search field spans
the strip width and still takes focus/typing (action-key gating intact).

## Vanilla-alchemy-aligned crafting layout (2026-07-07)

Restructured the crafting window's upper area to mirror the vanilla alchemy
window (the mod's model): a compact LEFT column (Tools stacked over the input
grid = Apparatus over Ingredients) beside a large RIGHT Result panel that fills
the height (= Created Effects). This kills the dead space that used to sit right
of the grid and gives the result + its notes (takes/needs/mold returned) real
room. The aside Mold slot (kiln/furnace) moves under the inputs in the left
column. Materials strip stays full-width below (= ingredient list); padded
Close bottom-right (= Cancel).

Crafting.lua: `tools_result_row` + separate grid replaced by a `upper_row`
(left_column | 16px | result_panel[bordersThick, grows]). Window height stays
500 (the upper area's vertical extent is unchanged — tools+grid already set it;
the result just moved into the right panel), so strip still shows ~2 rows
(grid) / ~4 rows (process).
components.button: `pad` option (12px sides / 3px top+bottom) for a proper
standalone footer button; closeButton uses it.

Prototyped + verified in the openmw-ui viewer. Branch claude/ui-padding-pass.
Verify in-game: result panel fills the right on every station (grid + process),
process aside Mold slot renders under the inputs, Close is comfortably inside.

## Contextual overlay card polish (2026-07-07)

Same styling language as the window pass, applied to ContextualOverlay.lua (the
[F] card near stations / forageables):
- the "[F] <label>" text is now a KEYCAP badge: the bound key in a small
  bordered box + the label (header template when enabled) — reads as a prompt.
- secondary detail lines (Missing: X, input roles, forage label) are dimmed to
  a muted tan (textColor) so they sit below the status/action in the hierarchy.
- interior CARD_PAD margin (6px sides / 5px ends) so content doesn't kiss the
  border; hold bar a touch taller (8->10); LINE_W 190->196.
Prototyped + verified in the openmw-ui viewer. Branch claude/ui-padding-pass.
Verify in-game: keycap renders on station + forage cards; disabled action uses
the normal (not header) label; dimmed details legible; hold bar still fills
smoothly while the forage key is held.

## Crafting-flow review: ratified decisions (2026-07-07)

User's in-game review + answers:
1. Big stations -> BUILT IN PLACE: kiln, firepit, charcoal pit, furnace (drop
   components on the ground, hold F to build the activator there). CARRIED:
   crafting table, tanning rack. New chain: CLAY BRICKS are pit-fired at the
   firepit and become the kiln/furnace build components. Bootstrap: build
   firepit from ground materials -> pit-fire bricks -> build kiln.
2. "Swallow fuel" = the kiln should ACCEPT and CONSUME dropped fuel. Root
   cause found: kiln ceramics had NO fuel lines, so dropped fuel made the
   exact-multiset match FAIL (and pots fired with just a torch). Fixed by
   fuel values (below).
3. Fuel excess -> REFUND (consume the minimal covering subset; the rest is
   never consumed).
4. Pit firing -> YES: the firepit fires ceramics/molds slowly with a failure
   chance (tier below the kiln). [Round 2]
5. Grid clicking: acceptable; recipe guide is the low-click path — polish
   later (open grid stations on Recipes strip? craft-again?). [parked]
6. Fuel values by tag, MC-style. [Round 1, below]

## Round 1: fuel values + batch firing (built 2026-07-07)

**Fuels registry** — data/fuels/fuels.json `{matcher: units}`: wood 1,
charcoal 3, T_IngMine_Coal_01 4. lib.fuelValue(recordId) = MAX over matching
entries (a record entry can upgrade a broader tag). Loaded into
GRegistries.fuels.

**Fuel lines** — process inputs may now be `{"fuel": N}` (units per batch)
instead of an id/count line: ANY fuel-valued item feeds it. Matching claims
the minimal covering subset LARGEST-VALUE-FIRST; excess fuel is allowed and
NEVER consumed (refund by never-claiming). Overfilling the fire stopped being
an error.

**Batch matching** — processCrafting rewritten: each recipe matches at its
largest k where the placement holds k exact input sets (+ k x fuel). Output
xk; duration = base x (1 + 0.5 x (k-1)) — firing together is the point of a
kiln. `returned` lines (molds) serve the WHOLE batch (never scaled). Matches
are proxies (__index recipe) carrying batch, scaled output/duration and
claimedCounts — every consumer (result panel, tools, ignite) reads through
transparently. sdMeal recipes never batch (SD mints one meal).

**Consumption by claims** — windowed onCraft and UI-less ignite consume
exactly claimedCounts. Open-charge kiln: claims removed from the loose items
on it (excess fuel stays lying there). Stored charges (charcoal pit): claims
subtracted, REMAINDER STAYS LOADED. Result panel notes "(batch of k)".

**Recipe conversion** — every `Charcoal xN` line -> `fuel 3N` across furnace/
molds/steel/bonemold/iron; kiln ceramics GAINED fuel (pot 3, crucible 6);
steel ingot keeps 1 Charcoal as its CARBON SOURCE (material) plus fuel 6 —
wood alone can't make steel.

Verify in-game: kiln with 2 clay + 1 wood -> pot consumes the wood; 4 clay +
fuel -> "(batch of 2)", both consumed, double output, 1.5x duration; excess
charcoal in the furnace no longer blocks the match and survives the run;
charcoal pit remainder stays loaded after ignite; steel needs charcoal even
with wood fuel; molds still fire (fuel 3 each).

## Round 2: build-in-place, bricks, pit firing, progression (built 2026-07-07)

**Build-in-place** (ratified: kiln/firepit/charcoal pit/furnace BUILT; crafting
table + tanning rack stay carried items):
- data/constructions/constructions.json: firepit (2 Stone + 2 Wood), charcoal
  pit (4 Wood + 2 Stone, needs a SHOVEL in the inventory), kiln (6 clay bricks
  + 2 Clay), furnace (8 clay bricks + 1 crucible). holdTime + salvage per
  entry.
- buildScan.lua (player): scans loose items around the player for a COMPLETE
  component set; registers the `construction_ready` condition; the
  "Construction" card (contexts/building.json + handlers/building.lua) shows
  "<Station> — materials ready / [F] Build (hold)". Card only on a full set —
  no partial-progress noise, dropped wood near a pit stays a charge.
- globalBuilding.lua: re-validates the set in the cell, spawns the activator
  at the components' CENTROID, consumes the loose items, fires the milestone.
  Places the station FIRST (missing record -> nothing consumed).
- Pack-up: built stations DISMANTLE into salvage (globalStations.onPack
  precedence; partial returns — mortar doesn't come off bricks cleanly);
  item-swap stations unchanged. Legacy station ITEMS still swap to activators
  when dropped (old saves), and pack to salvage afterwards.
- The 4 station shaped recipes are GONE (ic_station_kiln @firepit,
  ic_station_firepit @bushcrafting, charcoalpit + furnace @crafting table).

**Clay bricks + pit firing**:
- ic_clay_brick (NEW record; interim mesh: the vanilla bread loaf — most
  brick-shaped mesh in the game, replace in the mesh pass).
- firepit: ic_clay_brick_pit — 2 Clay + fuel 3 -> 2 bricks, 3600s,
  failChance 0.25 (pit firing: each BATCH rolls on collect; cracked batches
  yield nothing; "(pit-fired — may crack)" note in the result panel; held
  molds still return). kiln: ic_clay_brick — same but 1800s and reliable
  (pit version excluded from the kiln's firepit inherit).
- Bootstrap: forage wood/stone -> build firepit -> dig clay -> pit-fire
  bricks -> build kiln -> fire reliably -> crucible -> furnace.

**Progression + tutorial popups**:
- progressState.lua (player save `progress`): milestone set. Granted on BUILD
  (globalBuilding -> ImmersiveCrafting_Milestone) and on FIRST USE of a
  station context (Crafting.open — a world-found kiln unlocks too), plus
  'welcome' on first load.
- ui/Popup.lua: dismissable semi-transparent card (top-center, click or 14s),
  queued; texts in data/milestones/milestones.json (welcome/firepit/kiln/
  furnace/charcoal_pit chain teaches the bootstrap).
- Recipe-guide gating: recipes carry `milestone` (raw molds -> kiln, steel
  hammering -> furnace); the GUIDE hides them until unlocked; matching is
  never gated. Settings: "Tutorial popups" (default on), "Show all recipes
  in the guide" (default off).

Verify in-game: welcome popup on fresh load; drop 2+2 -> firepit build card ->
built + popup; pit-fire bricks (some crack); kiln build from 6 bricks + 2
clay; furnace from 8 bricks + crucible; dismantle salvage; charcoal pit needs
shovel; molds hidden in table guide until kiln built/used; found world kiln
unlocks on open; ShowAllRecipes bypass; legacy station items still swap+pack.
Open: mesh for ic_clay_brick (bread interim!); balance failChance/durations;
gaze-context-switch branch still unmerged (contextManager conflicts).

## Equip gating rework: material-first, weapons too (built 2026-07-07)

Design (user): gate by MATERIAL first, fall back to armor value / weapon
damage only for untagged items; the gate skill is the item's OWN governing
skill (chitin staff -> Blunt Weapon, glass tower shield -> Light Armor).
Verified against the record data that material-first is NOT redundant:
a daedric dagger (max dmg 12) must gate as daedric while an iron warhammer
(max dmg 28) stays entry-tier — raw stats order them backwards.

- data/gating/materials.json: material tag -> required skill level (iron 10,
  steel 15, bonemold 20, silver 20, dwemer 35, dreugh/orcish 40,
  stalhrim/adamantium 50, glass 55, ebony 65, daedric 80). 0 entries (fur,
  hide, leather, wood, chitin 5...) explicitly NEVER gate, so cheap-material
  uniques don't fall through to the fallback. Multiple matches take the MAX.
  ('nordic' deliberately absent: the tag spans junk nordic fur AND mid nordic
  mail — fur resolves via 'fur' 0, mail falls back by its AR.)
- equipGate.lua rewritten: WEAPONS now gate too (weapon type -> skill:
  short/long blade, blunt, axe, spear, marksman; ammo never); armor keeps the
  engine's weight-class formula. Fallback for untagged items: baseArmor /
  best max damage, ungated at/below 15. Gate checks the MODIFIED skill —
  Fortify Skill effects let you overreach while they last (the watcher
  strips the piece when they expire).
- HARD BLOCK (strip + message) kept over a debuff: vanilla ALREADY has the
  soft penalties (hit chance by weapon skill, armor rating scaled by armor
  skill) — a debuff would duplicate them; the tier gate is the mod's
  value-add and directly kills the run-to-Vivec daedric-at-level-1 classic.
  A "penalty instead of block" setting stays on the TODO as a possible mode.
- Settings: "Skill-gate armor and weapons" checkbox (default on).
- Sanity table (script over extern/tes3-records + ModTags): chitin cuirass 5,
  iron warhammer 10, steel longbow 15, indoril cuirass 45 (fallback by AR),
  glass 55, ebony 65, daedric dagger/longsword/towershield 80.

Also this session: docs/TODO.md split into docs/CHANGELOG.md (this build log)
+ a lean forward-looking TODO; rfuzzo/tes3-records added as a shallow
reference submodule at extern/ (opt-in, not runtime data).

Verify in-game: daedric loot strips at low skill with the message; fortify
skill potion lets it stay until it expires; chitin staff gates on Blunt
Weapon; arrows never gate; toggle off works; skill-up while wearing nothing
odd (cache); FlexTag stagger — an item equipped in the first seconds may
gate by fallback until relog (accepted, conservative).
