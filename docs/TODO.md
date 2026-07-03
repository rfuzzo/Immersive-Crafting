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

`docs/immersive_crafting_recipes_v2.csv` → `tools/recipes_csv2json.py` →
`recipes/crafting.json` (86 recipes: 57 shaped, 29 process). Rerun the script after
editing the CSV. It lints the tool-vs-consumed rules (consumed weapon molds never in
tool columns; reusable crucible/armor mold never in ingredient columns) and generates
the `ic_*` record inventory → `docs/ic_records.md`.

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
