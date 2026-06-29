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
- **Data is JSON, loaded at runtime** via `vfs.pathsWithPrefix` + a vendored decoder. There is **no
  build/compile step** and **no built-in 0.51 JSON API** — decoding uses the vendored pure-Lua
  `scripts/Immersive-Crafting/ext/dkjson.lua`.

---

## 2. Runtime flow

### Entry points — `Immersive-Crafting.omwscripts`
| Context | Script | Role |
|---|---|---|
| `GLOBAL` | `scripts/Immersive-Crafting/init.lua` | ✅ save/load passthrough only (`saveData`). ❌ No activation handler, no event executor yet. |
| `PLAYER` | `scripts/Immersive-Crafting/player.lua` | ✅ The real driver: loads data, runs `onUpdate`, binds the `ContextualAction` input. |
| `MENU` | `scripts/Immersive-Crafting/settings.lua` | ✅ Registers settings page + rebindable hotkey (default **F**) bound to action key `ContextualAction`. |

### Flow (all of this currently runs **player-side**)
1. **Data load** — `player.onLoad` → `dataManager.loadAllData()` scans `data/Immersive-Crafting/`
   via `vfs.pathsWithPrefix`, decodes each JSON with `io.loadJsonFile`, and populates the global
   `GRegistries`. Each domain merges entries by `id` via `mergeById`.
2. **Proximity detection** ✅ — `contextManager.onUpdate`, throttled to **0.25s**, scans
   `nearby.activators`, matches each object's `recordId` (case-insensitive) against every context's
   `recordIds`, keeps matches within `activationRange` (default **150**), and selects the **closest**
   context. On context change it refreshes the overlay. (Detection is **proximity**, ❌ *not*
   activation-event driven.)
3. **Overlay render** ✅ — `ui/ContextualOverlay.lua`, also throttled 0.25s. For the current
   context's actions it resolves the handler, calls `handler:present(ctx)` to get a `ViewModel`, and
   draws a HUD box (top-right) with header / status / action button (`"Press [F] to <label>"`) /
   optional detail lines, using `MWUI` templates.
4. **Commit** 🟡 — the **F** input action → `player` → `overlay.onContextualAction` → for each current
   action, `handler:OnActivate()`. The only handler, `mixing`, has a **stub** `OnActivate`
   (`ui.showMessage`); it does not yet consume ingredients or produce output.

### `GRegistries` shape (`dataManager.lua`)
```
GRegistries = {
  tags        = {},  -- table<tag, recordId[]>
  uiTemplates = {},  -- table<id, table>
  actions     = {},  -- table<id, CAction>
  contexts    = {},  -- table<id, CContext>
  recipes     = {},  -- table<id, CRecipe-shaped table>
  handlers    = {},  -- table<name, CAbstractHandler subclass>
  processes   = {},  -- ❌ declared, unused (reserved for in-progress cooking state)
}
```
Globals are intentional in this codebase: `GRegistries` (player) and `saveData` (global).

---

## 3. Real data schemas

Each is loaded from its own folder under `data/Immersive-Crafting/` and merged by `id`. Models live
in `scripts/Immersive-Crafting/models/` and validate via `:fromTable` (returns `nil` on missing
required fields) — **except recipes, see the note**.

### CContext — `models/context.lua` · `contexts/*.json`
| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✅ | registry key |
| `label` | string | ✅ in model | overlay header. *(Some shipped JSON omits it — e.g. `contexts/crafting.json` — which would fail `fromTable`.)* |
| `recordIds` | string[] | ✅ | vanilla object record IDs that act as this station/tool |
| `activationRange` | number? | — | default **150** units |
| `actions` | (Id \| CAction)[] | ✅ | actions offered at this context |

```json
{ "id": "mixing_bowl", "label": "Mixing Bowl",
  "recordIds": ["mixing_bowl_01"], "activationRange": 100,
  "actions": ["mixing"] }
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
| Field | Type | Required by model | Notes |
|---|---|---|---|
| `id` | string | ✅ | registry key |
| `label` | string | ✅ | display name of result |
| `context` | Id | ✅ | must match a context `id` |
| `action` | Id | ✅ | must match an action `id` |
| `ingredients` | `{id, count}[]` | ✅ | `id` may be a record id, a tag, or a `wildcard_*` (🟡 see §5) |
| `cookTime` | number | ✅ | seconds; used by future cooking process |
| `output` | `{id, count}` | ✅ | produced item |

> **🟡 Validation gap:** `dataManager.loadRecipes` `mergeById`s the **raw JSON** and never calls
> `CRecipe:fromTable`, so recipe required-field validation is **not enforced** at load. Several
> shipped recipes also omit `cookTime` (e.g. `seasoned_meat` in `recipes/cooking.json`). Recipes may
> also carry extra fields not in the model (e.g. `"requires": "heat"`).

```json
{ "id": "simple_stew", "label": "Simple Stew",
  "context": "cooking_pot", "action": "cooking", "requires": "heat",
  "ingredients": [ {"id": "Any Meat", "count": 1},
                   {"id": "Any Vegetable", "count": 1},
                   {"id": "Water", "count": 1} ],
  "cookTime": 10, "output": {"id": "Stew", "count": 1} }
```

### tags — `tags/tags.json`
Flat `tag → recordId[]` object map.
```json
{ "Meat": ["ingred_rat_meat", "ingred_guar_meat"], "Water": ["misc_water"] }
```
> **🟡 Load bug:** `loadTags` calls `mergeById`, but `mergeById` only handles a table with a
> top-level `.id` or an **array** of `{id=…}` entries. This file is a plain object map (no `.id`,
> empty array part), so `ipairs` iterates nothing and **`GRegistries.tags` ends up empty**. Tags
> must either be reshaped to an array-of-entries or loaded with a map-aware merge before D2 matching
> can work.

### uiTemplates — `uiTemplates/ui_templates.json`
Declarative UI descriptors keyed by id.
> **🟡 Same load bug as tags** (plain object map vs. `mergeById`), so `GRegistries.uiTemplates` also
> ends up empty. Independently, the current renderer (`ContextualOverlay.lua`) builds widgets
> imperatively and would not consume these even if loaded.

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
CAbstractHandler:evaluate(ctx) -> ViewModel   -- MUST override
CAbstractHandler:OnActivate()                 -- MUST override (executes the action)
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

### Worked example — `handlers/mixing.lua` (`CMixingHandler`)
- `evaluate(ctx)`: `lib.scanNearbyIngredients(200)` → `lib.resolveRecipe(scan, ctx.action,
  ctx.context)`. If no recipe: status `"No valid mixture"` + `Missing: …` details. If matched:
  status `"Ready"` + an enabled action `"Mix <recipe.label>"`.
- `OnActivate()`: 🟡 **stub** — `ui.showMessage(...)`. TODO: consume ingredients + grant output.

### Recipe resolution — `lib.lua`
- `scanNearbyIngredients(range)` ✅ — collects `nearby.items` within range, keyed by `recordId`.
- `resolveRecipe(scan, action, context)` 🟡 — filters recipes matching `action.id` + `context.id`,
  sorts by **complexity (most ingredients wins)**, returns the first fully-satisfied recipe, else the
  best partial match + a `missing` list. **Matching is exact case-insensitive `recordId` only** — it
  does **not** resolve tags or wildcards yet, so tag-style ids like `"Any Meat"`/`"Water"` match
  nothing today.

---

## 5. Decisions record

### D1 — Execution model = **player-side** (with a thin global commit)
Detection, recipe evaluation, and overlay rendering remain in the **player** script, as today. We do
**not** adopt the handoff's "global re-validates before consuming/producing" trust model.

**Unavoidable nuance:** `openmw.world` and inventory/record mutation are **global-context only**. A
player-side `OnActivate` therefore cannot itself spawn or move items — the **commit** step must
`core.sendGlobalEvent` to a thin executor in `init.lua` (GLOBAL) that performs the mutation
(`world.createObject(id, count):moveInto(actor)` for existing records; `createRecordDraft` /
`createRecord` for new ones). That executor **trusts the player request** (no server-side
re-validation) — this is the accepted simplification.

**Accepted caveats:**
- No anti-cheat / no re-validation on the global side.
- Custom-record outputs are **Load-context only and not save-serialised** — primarily a Cooking
  concern (custom ingredients won't persist across save/load).

### D2 — Tags = **extend the existing JSON `tags` registry**
Keep `GRegistries.tags` as the source of truth. The real gap is wiring **3-tier ingredient matching**
into `lib.resolveRecipe`, in priority order:
1. **Exact** record id (e.g. `ingred_meat_01`)
2. **Tag** (e.g. `"Meat"` → any recordId listed under that tag in `tags/*.json`)
3. **Wildcard** (e.g. `ingred_meat_*` prefix match)

External **Tagger** (S3cret St4sh ≥0.5: `I.TaggerG`/`I.TaggerL`, `objectHasTag`, `objectTags`,
`AppliedTags`) is treated as an **optional later bridge** *into* `GRegistries.tags`, **not** a
dependency now. Note Tagger has no reverse index (`getObjectsWithTag` does not exist); a reverse
index would be built from `AppliedTags` at load if adopted.

### D3 — Layering target = `engine/ · content/ · glue/`
- `engine/` — generic, mod-agnostic Lua (registries, proximity, overlay, handler base, resolution).
- `content/` — JSON only (`tags`, `actions`, `contexts`, `recipes`, `uiTemplates`).
- `glue/` — per-mod `.omwscripts` + registration.

Goal: adding **Cooking** should touch only `content/` + `glue/`, plus new handler class(es) — no
engine changes. Build order: **Crafting → Cooking → Farming** (Crafting forces the contracts; Farming
last so its persistent/world-placement/time-growth needs don't bleed into core early).

---

## 6. Known gaps / TODO
- 🟡 Fix `mergeById` (or the data shape) so `tags` and `uiTemplates` object maps actually load —
  currently both registries populate empty (see §3). Blocks D2.
- 🟡 Wire 3-tier (exact → tag → wildcard) matching into `lib.resolveRecipe` (D2).
- 🟡 Implement `mixing.OnActivate` consume/produce via the global commit executor (D1).
- ❌ Build the GLOBAL commit executor in `init.lua` (currently save/load only).
- 🟡 Enforce recipe validation (`loadRecipes` should call `CRecipe:fromTable`); reconcile `cookTime`
  being required vs. omitted in shipped data; decide where `requires` ("heat") lives in the schema.
- ❌ Cooking process state: use `GRegistries.processes` + `cookTime` for heat/simmer/cooked/burnt and
  surface progress via `ViewModel.progress`.
- 🟡 Decide whether the renderer should consume `uiTemplates` or keep building widgets imperatively.
- Empty/placeholder data files: `actions/{crafting,tanning,foraging}.json`, `recipes/woodworking.json`.

---

## 7. Open verification items (require in-game or external source)
- **Tagger key alignment:** do Tagger `AppliedTags` keys match inventory item record IDs? (Needed
  before any Tagger bridge — out of repo.)
- Confirm `world.createObject(...):moveInto(actor)` and `createRecordDraft`/`createRecord` behavior
  on the user's exact 0.51 build.
- Confirm proximity scan cost is acceptable at the 0.25s cadence in dense cells.
