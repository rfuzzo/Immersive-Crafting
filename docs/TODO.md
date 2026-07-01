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
- ❌ **Activation hook (deferred).** Setting `trigger:"activate"` currently just hides the
  context from proximity — nothing opens it yet. Wiring it needs an engine activation
  handler (global `onActivate` / `I.Activation`) that round-trips to the player to open the
  window; the context data is player-side (`GRegistries`), so the global side needs the
  activate record-ids/tags pushed to it at load, then an event back to the player.
- Recipe resolve / craft commit for the click-driven window is still a stub
  (`Crafting.onCraft`, `*.Resolve`); wire placed slots → recipe → `ImmersiveCrafting_CraftShaped`.
- The item picker lists **all** inventory items with no scroll/filter; may overflow for large
  inventories. Consider filtering (misc/ingredient) or a scroll container.
