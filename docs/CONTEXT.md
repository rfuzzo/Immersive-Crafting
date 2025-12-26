# Immersive Crafting – Design Context & Architecture Summary

This document summarizes the design decisions, architecture, and data model
for the **Immersive Crafting** OpenMW Lua mod.

It is intended to be used as **persistent context** for local LLM tooling
(Codex / Continue / Cursor / etc.) during implementation.

OpenMW LUA overview: <https://openmw.readthedocs.io/en/latest/reference/lua-scripting/overview.html>

---

## 1. Core Design Goals

- Native to **Morrowind / OpenMW**, not Minecraft-style UI-first crafting
- **World-first, contextual interaction**
- Data-driven (JSON) wherever possible
- Minimal, reusable Lua logic
- No MWSE (`tes3`) APIs — **OpenMW Lua only**
- Avoid dynamic clutter spawning in the world

---

## 2. Interaction Paradigms

There are **three crafting paradigms**, each used only where appropriate.

### 2.1 Shaped Crafting (Proximity-based)

- Classic grid-based crafting (2x2, 3x3)
- Contextual overlay shows "Craft" button when near station
- Hold-to-act opens crafting grid UI
- Stateless
- Example: workbench, crafting table

### 2.2 Contextual Crafting (World-based)

- No grid UI
- Contextual overlay UI (CP2077-style)
- Uses **hold-to-act** for direct transformation
- Inputs detected from:
  - nearby world items
  - focused container/tool
- Example: cooking at a campfire

### 2.3 Process Crafting (State-based)

- Long-running, multi-step processes
- Explicit **data-driven states**
- No generic FSM framework; simple state descriptors
- World owns time, not UI
- Example: tanning rack, drying rack, fermenting

---

## 3. Key Interaction Grammar

This grammar is reused everywhere:

- **Contextual overlay**, always present when relevant
- **Hold-to-act** (cancelable)
- Time passes in the world
- UI reflects state, never controls logic

Foraging is the **introductory feature** that teaches this grammar.

### Overlay Interaction Patterns

1. **Direct action**: Hold → immediate effect (foraging, simple crafting)
2. **Open interface**: Hold → opens specialized UI (shaped crafting grid)
3. **Process toggle**: Hold → start/stop/interact with process (tanning rack)

---

## 4. Foraging (First Vertical Slice)

### Why Foraging

- No stations
- No recipes
- Stateless
- Teaches:
  - contextual availability
  - hold-to-act
  - time passing
  - fuzzy outcomes

### Behavior

- Available outdoors, safe, not swimming, not in combat
- Overlay shows:

Wilderness
[ Hold ] Forage

- Holding completes action:
- time advances (e.g. 1 hour)
- small chance-based rewards (twigs, rocks)
- No world spawning

Foraging is a **global contextual action**, not crafting.

---

## 5. Cooking Model (Important Insight)

Cooking ambiguity (meat + veg → soup OR fry) is solved via **intent by focus**:

- Campfire = station (provides heat)
- Containers express intent:
- cooking pot → stew/soup
- frying pan → fried food
- Overlay switches based on **cursor focus**
- No recipe lists or scrolling

Cooking pot is a **parametrized process container**:

- idle → cooking → done
- Recipe injects cook time + output
- Heat pauses/resumes process

---

## 6. Tanning Rack Model

- Purely contextual, **no OnActivate**
- Hide becomes part of the station (visual + state)
- Liquid added contextually (using container)
- Long-running process (in-game day or more)
- Interaction only when state allows (attach hide, remove leather)

This uses a **simple data-driven state machine**, not a generic FSM.

---

## 7. Data Architecture (Very Important)

> Data never calls data.  
> Data references by **string IDs only**.  
> Lua resolves everything at runtime.

### 7.1 Data Domains

| Domain       | Purpose                                  |
|-------------|-------------------------------------------|
| tags        | Abstract item categories → game IDs       |
| stations    | Where crafting happens                    |
| containers  | How intent/state is expressed             |
| recipes     | What transformations are possible         |
| processes   | How things evolve over time               |
| actions     | Stateless contextual actions (foraging)   |
| ui_templates| Semantic UI regions (not layout)          |

---

## 8. Intended Data Layout

```
data/
├── tags.json
├── ui_templates.json
├── actions/
│   └── foraging.json
├── stations/
│   ├── shaped.json
│   ├── contextual.json
│   └── process.json
├── containers/
│   ├── cooking.json
│   └── tools.json
├── recipes/
│   ├── shaped/
│   │   └── woodworking.json
│   └── contextual/
│       └── cooking.json
├── processes/
│   ├── tanning.json
│   └── cooking.json
```

---

## 9. Dependency Rules (No Cycles in Data)

- `tags.json` is the base vocabulary
- Recipes reference:
  - station IDs
  - container IDs
  - tag IDs
- Containers reference:
  - station IDs
  - process IDs
- Stations reference:
  - UI template IDs
- Processes reference nothing else
- Actions reference:
  - abstract contexts
  - tag IDs (for results)

All resolution happens in Lua registries.

---

## 10. Lua Architecture (Current State)

Modules already sketched / implemented:

interaction/
HoldAction.lua        – reusable hold-to-act logic

context/
ForagingContext.lua  – availability checks

features/
Foraging.lua         – gameplay effect (time + rewards)

ui/
ContextualOverlay.lua – generic overlay UI

main.lua / player.lua
– wires everything together

All code uses **OpenMW Lua APIs only**:

- `openmw.world`
- `openmw.ui`
- `openmw.input`
- `openmw.core`

No**Contextual overlay is always present** when player is in valid context

- UI never owns time
- UI never owns logic
- World state is authoritative
- Processes are explicit, linear, readable
- If something has memory or phases → process
- If something is ambiguous → intent via focus
- If something is early-game bootstrap → contextual action
- **All crafting entry points use hold-to-act**, whether for direct action or opening interfaces
- UI never owns logic
- World state is authoritative
- Processes are explicit, linear, readable
- If something has memory or phases → process
- If something is ambiguous → intent via focus

### Shaped Crafting (First)

1. Implement JSON loading (file IO + JSON decode)
2. Populate:
   - `tags.json`
   - `stations/shaped.json`
   - `recipes/shaped/woodworking.json`
3. Implement proximity detection for shaped stations
4. Add "Craft" button to contextual overlay when near station
5. Hold-to-act opens shaped crafting grid UI
6. Validate end-to-end

### Foraging & Contextual Crafting (After)

1. Populate `actions/foraging.json`
2. Validate foraging end-to-end
3. Add first contextual station: campfire
4. Add first container: cooking pot
5. Populate:
   - `tags.json`
   - `actions/foraging.json`
6. Validate foraging end-to-end
7. Add first contextual station: campfire
8. Add first container: cooking pot
9. Reuse HoldAction + Overlay unchanged

---

## 13. Philosophy (Why This Matters)

This framework:

- leverages what Morrowind already does well
- avoids UI-heavy crafting
- scales to other mods cleanly
- is explainable to other modders
- minimizes hardcoded logic

The goal is not “Minecraft in Morrowind”,
but **immersive, world-native interaction**.
