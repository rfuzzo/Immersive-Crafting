# Immersive Crafting — Engine Spec & Decisions Record

This document is the **authoritative, code-grounded** reference for the Immersive Crafting engine.
It describes what the code *actually does today*, the real data schemas and handler contract, and the
design decisions that govern future work (including the planned Immersive **Cooking** and **Farming**
mods built on the same engine).

`docs/CONTEXT.md` describes the design *vision*; this file describes the *implementation*. Where they
disagree, this file wins for "what exists", and the Decisions Record below wins for "what we will do".

> **Legend:** ✅ built and working · 🟡 partial / declared-but-unwired · ❌ aspirational (not built)

---

## 1. Scope & hard constraints

- **Target:** OpenMW **0.51+**, **OpenMW-Lua only**. This is not MWSE.
- **Forbidden (will not load / will silently mislead):** `tes3*`, `tes3ui`, `event.register`,
  `mwscript`, and any MWSE idiom. The #1 project risk is that LLM training skews toward MWSE, so
  generated code drifts to plausible-but-wrong patterns that only fail at in-game load. When in
  doubt, verify against the OpenMW-Lua 0.51 API reference, not memory.
- **Allowed APIs:** `openmw.core`, `openmw.types`, `openmw.world` (**global context only**),
  `openmw.self`, `openmw.nearby`, `openmw.ui`, `openmw.input`, `openmw.util`, `openmw.async`,
  `openmw.interfaces`, `openmw.vfs`. Respect the **global / local / player / menu** context split.
- **Hard dependency:** **Tagger** (S3ctor's S3cret St4sh ≥ 0.5) — the tag source of truth (see D2).
- **Data is JSON, loaded at runtime** via `vfs.pathsWithPrefix` + a vendored decoder. There is **no
  build/compile step** and **no built-in 0.51 JSON API** — decoding uses the vendored pure-Lua
  `scripts/Immersive-Crafting/ext/dkjson.lua`. (Tag data is YAML, loaded by Tagger, not by this mod.)

---

## 2. Runtime flow

### Entry points — `Immersive-Crafting.omwscripts`
| Context | Script | Role |
|---|---|---|
| `GLOBAL` | `scripts/Immersive-Crafting/init.lua` | ✅ save/load passthrough (`saveData`) **+ the commit executor** — the `ImmersiveCrafting_Commit` event handler that performs the world/inventory mutation (D1). ❌ No activation handler (detection is proximity, not activation). |
| `PLAYER` | `scripts/Immersive-Crafting/player.lua` | ✅ The driver: loads data, runs `onUpdate` (contextManager + overlay), binds the `ContextualAction` input. |
| `MENU` | `scripts/Immersive-Crafting/settings.lua` | ✅ Registers settings page + rebindable hotkey (default **F**) bound to action key `ContextualAction`. |

### Flow
1. **Data load** (player) — `player.onLoad` → `dataManager.loadAllData()` scans
   `data/Immersive-Crafting/` via `vfs.pathsWithPrefix`, decodes each JSON with `io.loadJsonFile`, and
   populates the global `GRegistries` (actions/contexts/recipes via `mergeById`; uiTemplates via
   `mergeMap`). Tags are **not** loaded here — Tagger owns them.
2. **Proximity detection** ✅ (player) — `contextManager.onUpdate`, throttled to **0.25s**:
   - `gatherNearby` collects candidates from **`nearby.items` + `nearby.activators`** within range
     (stations may be misc items like `bowl`/`pot` or activators like furniture/fire pits).
   - For each context, a candidate matches if its `recordId` equals **or is Tagger-tagged with** any of
     the context's `recordIds` entries (`lib.matchesTag`), within `activationRange` (default **150**).
   - Optional `CContext.requires` tags must also be present among candidates (`hasRequired`) — e.g.
     `cooking_pot` requires a `fire` nearby.
   - The **closest** matching context wins; on change it refreshes the overlay.
3. **Overlay render** ✅ (player) — `ui/ContextualOverlay.lua`, throttled 0.25s. For the current
   context's actions it resolves the handler, calls `handler:present(ctx)` to get a `ViewModel`, and
   draws a HUD box (top-right): header / status / action button (`"Press [F] to <label>"`) / optional
   detail lines, using `MWUI` templates.
4. **Commit** ✅ — **F** → `player` → `overlay.onContextualAction` builds a `HandlerContext` and calls
   `handler:OnActivate(ctx)` → `lib.commitRecipe` re-resolves the recipe, picks concrete stacks
   (`collectConsumption`), and `core.sendGlobalEvent('ImmersiveCrafting_Commit', …)`. The **GLOBAL**
   executor in `init.lua` removes the consumed stacks and creates + grants the output. (No cooking
   process yet — commit is instant; see §6.)

### `GRegistries` shape (`dataManager.lua`)
```
GRegistries = {
  uiTemplates = {},  -- table<id, table>  (loaded via mergeMap)
  actions     = {},  -- table<id, CAction>
  contexts    = {},  -- table<id, CContext>
  recipes     = {},  -- table<id, CRecipe>
  handlers    = {},  -- table<name, CAbstractHandler subclass>
  processes   = {},  -- ❌ declared, unused (reserved for in-progress cooking state)
}
```
The old `tags` registry was **removed** (D2 — Tagger owns tags). Globals are intentional in this
codebase: `GRegistries` (player) and `saveData` (global).

---

## 3. Real data schemas

Each is loaded from its own folder under `data/Immersive-Crafting/` and merged by `id`. Models live
in `scripts/Immersive-Crafting/models/` and validate via `:fromTable` (returns `nil` on missing
required fields) — recipes **included** (see the CRecipe note).

### CContext — `models/context.lua` · `contexts/*.json`
| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✅ | registry key |
| `label` | string | ✅ in model | overlay header. *(`contexts/crafting.json` omits it → would fail `fromTable`.)* |
| `recordIds` | string[] | ✅ | record ids **or Tagger tags** that identify this station/tool (e.g. `"bowl"`, `"pot"`) |
| `requires` | string[]? | — | extra Tagger tags that must also be present nearby (e.g. `["fire"]`) |
| `activationRange` | number? | — | default **150** units |
| `actions` | (Id \| CAction)[] | ✅ | actions offered at this context |

```json
{ "id": "cooking_pot", "label": "Cooking Pot",
  "recordIds": ["pot"], "requires": ["fire"],
  "actions": ["cooking"] }
```

### CAction — `models/action.lua` · `actions/*.json`
| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✅ | registry key |
| `label` | string | ✅ | verb shown to player |
| `handler` | Id | ✅ | name of the handler module that executes it |

```json
{ "id": "mixing", "label": "Mix", "handler": "mixing" }
```

### CRecipe — `models/recipe.lua` · `recipes/*.json`
| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✅ | registry key |
| `label` | string | ✅ | display name of result |
| `context` | Id | ✅ | must match a context `id` |
| `action` | Id | ✅ | must match an action `id` |
| `ingredients` | `{id, count}[]` | ✅ | `id` is a record id **or Tagger tag** (no wildcard — D2) |
| `cookTime` | number? | — | **cooking-only**; seconds for the (future) simmer process. Omitted for instant crafting/mixing. |
| `output` | `{id, count}` | ✅ | produced item — must be an **existing record id** (D1) |

> **✅ Validation enforced:** `loadRecipes` iterates each entry and calls `CRecipe:fromTable`, dropping
> (and logging) any recipe missing required fields. Note: a recipe-level `"requires"` field is **dead**
> — gating lives on `CContext.requires`, not the recipe; the model ignores it.

```json
{ "id": "simple_stew", "label": "Simple Stew",
  "context": "cooking_pot", "action": "cooking",
  "ingredients": [ {"id": "Meat", "count": 1},
                   {"id": "Vegetable", "count": 1},
                   {"id": "Water", "count": 1} ],
  "cookTime": 10, "output": {"id": "Stew", "count": 1} }
```

### tags — **Tagger framework (external), `ModTags/*.yaml`**

Tags are **not a JSON registry in this mod** (the old `tags/tags.json`, `loadTags`, and
`GRegistries.tags` were removed). Per **D2**, Tagger is the source of truth and a **hard dependency**.
We ship our tag data as `ModTags/*.yaml` in Tagger's schema (`tags:` list + `applied_tags: recordId →
[tag]`); Tagger loads it into its own storage at runtime. Matching is done by asking Tagger per
scanned object (`lib.matchesTag`), so **no reverse index is needed** — sidestepping Tagger's missing
`getObjectsWithTag`.

```yaml
tags: ["Meat", "Water"]
applied_tags:
  "ingred_rat_meat": ["Meat"]
  "misc_water": ["Water"]
```

**Authoring pipeline** (`tools/`): record dumps are exported to CSV (`ingredients_tags.csv`,
`misc_tags.csv`), edited, then converted to Tagger YAML via `tools/csv2yaml.py` / `tools/misc_tags.py`
→ `ModTags/ImmersiveCrafting_*.yaml`. See `tools/README.md` and `docs/TODO.md`.

### uiTemplates — `uiTemplates/ui_templates.json`
Declarative UI descriptors keyed by id.
> **✅ Load fixed:** `loadUiTemplates` uses a map-aware `mergeMap` (copies `key → value`) instead of
> `mergeById`, so `GRegistries.uiTemplates` populates. **Still unconsumed** — the renderer
> (`ContextualOverlay.lua`) builds widgets imperatively (§6 open decision).

---

## 4. Handler contract

Handlers are **OOP Lua classes** in `scripts/Immersive-Crafting/handlers/`. `dataManager.loadHandlers`
scans `handlers/*.lua`, `require`s each, and registers it by filename (minus `.lua`).
`dataManager.resolveHandler(id)` instantiates via `handlerClass:new()`.

### Base — `handlers/CAbstractHandler.lua`
```
HandlerContext = { action: CAction, context: CContext }

CAbstractHandler:new()                  -- constructor (metatable/__index)
CAbstractHandler:present(ctx)           -- calls evaluate(ctx); wraps result into a ViewModel
CAbstractHandler:onUpdate(dt)           -- optional per-frame hook (override; default no-op)
CAbstractHandler:evaluate(ctx)  -> ViewModel  -- MUST override
CAbstractHandler:OnActivate(ctx)              -- MUST override (executes the action)
```
`present` builds the `ViewModel` header from `ctx.context.label` and copies
`status / details / action / progress` from whatever `evaluate` returns.

### ViewModel — `models/viewModel.lua`
```
ViewModel = {
  header:   string?,
  status:   string?,
  details:  string[]?,
  action:   { id, label, enabled, disabledReason? }?,   -- ViewModel.ActionInfo
  progress: number?,
}
```

### Worked examples — `handlers/mixing.lua`, `handlers/cooking.lua`
Both follow the same shape (cooking is currently a near-clone of mixing):
- `evaluate(ctx)`: `lib.scanNearbyIngredients(200)` → `lib.resolveRecipe(scan, ctx.action,
  ctx.context)`. No recipe → status `"No valid mixture"` / `"Nothing to cook"` + `Missing: …`
  (`lib.formatMissing`). Matched → status `"Ready"` + enabled action `"Mix/Cook <recipe.label>"`.
- `OnActivate(ctx)`: ✅ `lib.commitRecipe(ctx)` → dispatches the consume/produce to the global executor,
  then `ui.showMessage(message)`. Cooking is **instant** (no heat/cookTime process yet — §6 TODO).

### Resolution & commit — `lib.lua`
- `scanNearbyIngredients(range)` ✅ — scans `nearby.items`, keyed by `recordId`, **summing stack
  counts** (`IngredientScanResult = { object, distance, count }`).
- `matchesTag(recordId, query)` ✅ — **2-tier (D2):** (1) exact case-insensitive record id, (2)
  `I.TaggerL.objectHasTag(recordId, query)`. Warns once if Tagger is unavailable. **No wildcard.**
- `resolveRecipe(scan, action, context)` ✅ — filters recipes by `action.id` + `context.id`, sorts by
  **complexity (most ingredients wins)**, returns the first recipe whose every ingredient has
  `available ≥ needed` (counts summed via `matchesTag`), else the best partial match + a `missing` list.
- `collectConsumption(range, recipe)` ✅ — allocates concrete nearby stacks to ingredients (each stack
  used at most once), honouring counts; returns the consume list or `nil` if insufficient.
- `commitRecipe(ctx, range)` ✅ — scan → resolve → collect → `core.sendGlobalEvent
  ('ImmersiveCrafting_Commit', { consume, output, actor })`; returns a user-facing message.
- `formatMissing(missing)` ✅ — formats `{id,count}[]` into `"Meat, Water x2"`.

The **GLOBAL executor** (`init.lua` → `onCommit`) trusts the request (D1), `obj:remove(count)`s each
consumed stack, then `world.createObject(output.id, count):moveInto(actor)`; the whole thing is
`pcall`-wrapped so a bad request can't brick global activation.

---

## 5. Decisions record

### D1 — Execution model = **player-side** (with a thin global commit)
Detection, recipe evaluation, and overlay rendering run in the **player** script. We do **not** adopt
the handoff's "global re-validates before consuming/producing" trust model.

**✅ Built.** `openmw.world` and inventory/record mutation are **global-context only**, so the commit
round-trips: `lib.commitRecipe` (player) → `core.sendGlobalEvent('ImmersiveCrafting_Commit')` → the
executor in `init.lua` (global) consumes + produces. The executor **trusts the player request** (no
server-side re-validation) — accepted simplification.

**Outputs = existing records only** *(ratified 2026-06-29).* `world.createObject` requires an existing
record id; we do **not** author custom records via `createRecordDraft`/`createRecord`. Implications:
- Outputs must reference real record ids (vanilla, or from a required master/mod, e.g. Sun's Dusk
  `sd_food_*` which only resolve when Sun's Dusk is loaded).
- The hand-made placeholders `SeasonedMeat` and `Stew` are **not real records** and will fail until
  repointed to real ids (cleanup item, §6).
- This sidesteps the "custom records are Load-context only / not save-serialised" caveat entirely.

### D2 — Tags = **Tagger framework (hard dependency)** *(ratified 2026-06-29)*

Supersedes the original "extend the JSON `tags` registry" plan. **Tagger** (S3cret St4sh ≥0.5) is the
**single source of truth and a hard dependency** — Immersive-Crafting will not function without it.
The in-mod JSON `tags` registry (`tags/tags.json`, `loadTags`, `GRegistries.tags`) was **removed**.

- **Matching is 2-tier and wired** (✅ `lib.matchesTag`): **exact record id → Tagger tag**. **Wildcard
  is intentionally dropped** (no `ingred_meat_*`). Accessed via `I.TaggerL` (player/local context).
- Tag data ships as `ModTags/*.yaml`, authored through the `tools/` CSV→YAML pipeline (§3).
- **`anyOf` ingredients** (a slot accepting one of several items, used by ~22 imported Sun's Dusk
  recipes) are handled by **mapping each set to a single union Tagger tag** (no per-slot list in the
  schema) — author the union tag, apply it to the members, then use one matcher per slot.

### D3 — Layering target = `engine/ · content/ · glue/`  *(deferred, not started)*
- `engine/` — generic, mod-agnostic Lua (registries, proximity, overlay, handler base, resolution).
- `content/` — JSON only (`actions`, `contexts`, `recipes`, `uiTemplates`) + `ModTags/*.yaml`.
- `glue/` — per-mod `.omwscripts` + registration.

Goal: adding **Cooking** should touch only `content/` + `glue/` + new handler class(es). Build order:
**Crafting → Cooking → Farming** (Crafting forces the contracts; Farming last so its
persistent/world-placement/time-growth needs don't bleed into core early).

---

## 6. Known gaps / TODO
- ✅ GLOBAL commit executor built (`init.lua`); `mixing`/`cooking` `OnActivate` consume+produce via it.
- ✅ `uiTemplates` loads via `mergeMap`; JSON `tags` registry removed (Tagger, D2).
- ✅ Recipe validation enforced; `cookTime` made optional (cooking-only); `matchesTag` 2-tier wired;
  `formatMissing` replaces the old `table.concat(missing)` bug.
- 🟡 **Content reconciliation so recipes actually resolve in-game:** ensure ingredient ids match real
  Tagger tags (`Meat`/`Vegetable`/`Water`/`Spice`), the `bowl`/`pot` station tags are applied, and the
  `fire` tag exists. Tracked in `docs/TODO.md`.
- 🟡 **Repoint placeholder outputs** (`SeasonedMeat`, `Stew`) to real record ids (D1 — existing
  records only).
- 🟡 **Sun's Dusk import** (`recipes/sunsdusk.json`): 25/54 imported. Remaining blocked on `anyOf`
  (→ union tags, D2), missing `Herb`/`Crab` tags, and fallback/default recipes. See `docs/TODO.md`.
- ❌ **Cooking process state:** use `GRegistries.processes` + `cookTime` for heat/simmer/cooked/burnt
  and surface progress via `ViewModel.progress`; gate cooking on a `fire`/heat requirement.
- 🟡 Decide whether the renderer should consume `uiTemplates` or keep building widgets imperatively.
- Empty/placeholder data files: `actions/{crafting,tanning,foraging}.json`, `recipes/woodworking.json`.

---

## 7. Open verification items (require in-game or external source)
- **`objectHasTag` signature:** `lib.matchesTag` passes a **record-id string** to
  `I.TaggerL.objectHasTag`. Confirm Tagger accepts a record-id string (some Tagger APIs expect a
  GameObject) — if it needs an object, pass the scanned `obj` instead.
- **Fire detection:** `cooking_pot`'s `requires:["fire"]` scans `nearby.items` + `nearby.activators`,
  but Morrowind campfires are mostly **LIGH (Light)** records that may not appear in either list. Needs
  an in-game check + possibly a `ModTags/..._Fire.yaml` LIGH dump (see `docs/TODO.md`).
- **Tagger key alignment:** confirm `applied_tags` keys match the in-game item record ids.
- Confirm `world.createObject(id, count):moveInto(actor)` behavior on the user's exact 0.51 build.
- Confirm proximity scan cost is acceptable at the 0.25s cadence (items + activators) in dense cells.
