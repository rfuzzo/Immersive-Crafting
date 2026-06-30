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
