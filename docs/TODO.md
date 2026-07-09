# Immersive Crafting — TODO

Forward-looking list only. The chronological design/build record (every
ratified decision + per-feature verify lists) is `docs/CHANGELOG.md`;
the authoritative engine design is `docs/SPEC.md`.

## In-game verification backlog (user)

Newest first — each CHANGELOG entry has the detailed checklist:

- **Equip gating rework** (material-first, weapons too — see CHANGELOG).
- **Round 2**: welcome popup on fresh load; build firepit (drop 2 stone +
  2 wood, hold F) -> popup; pit-fire bricks (some crack); kiln from 6 bricks
  + 2 clay; furnace from 8 bricks + crucible; charcoal pit needs a shovel;
  dismantle salvage; guide hides molds until kiln built/USED (world kilns
  count); ShowAllRecipes bypass; legacy station items still swap + pack.
- **Round 1**: kiln consumes dropped fuel (2 clay + 1 wood); batches
  ("batch of 2", double output, 1.5x time); excess furnace fuel no longer
  an error and survives; charcoal-pit remainder stays loaded; steel needs
  charcoal even with wood fuel.
- Older, never confirmed: SD water interop; field dressing on a real
  Hunterwind install; `types.Miscellaneous.getSoul` on 0.51 (daedric ingot);
  crosshair station picking after the merge.

## Art & records (user-owned)

- `ic_clay_brick` — interim mesh is the VANILLA BREAD LOAF. Replace.
- `ic_ingot_copper` — TD bronze-ingot mesh path written by convention;
  verify against the real `T_Com_MetalPieceBronze_01` record before packing.
- `ic_ingot_ebony` / `ic_ingot_daedric` — interim raw-ebony mesh.
- Steel rough parts (10) — placeholder scrap-metal mesh.
- General mesh pass over `records/` placeholders (pick from
  `extern/tes3-records`).

## Balance (user-owned)

- Build component counts + salvage ratios; pit-fire failChance (0.25) and
  durations; batch time factor (0.5/extra batch).
- Fuel values (wood 1, charcoal 3, coal 4); per-recipe fuel units.
- Melt-down return ratio (2 items -> 1 ingot); equip-gate skill thresholds.
- All recipe counts are first-draft throughout.
- Copper pan recipe consumes iron pieces (rebalance when copper equipment
  lands).

## Deferred features

- **Skill gating follow-ups**: AC quality tiers behind Armorer skill;
  tool QUALITY tiers (steel vs chitin axe -> speed/yield).
- **Cooking doneness** (simmer/cooked/burnt); SD meal path stays parallel.
- **Farming Phase 2**: terrain planting (gaze at bare ground) — user is
  waiting on this one deliberately.
- **Recipe guide niceties, round 2**: craft-again button; open grid stations
  on the Recipes strip by default. (Ghost slots + Craftable filter: DONE.)
- **Equipment sets from the new ingots** (copper/bronze/orichalcum/
  adamantium/ebony/daedric weapons + armor via the mold system) — user-owned
  design + balance.
- **Debuff-instead-of-block equip gate mode** (setting) — see the gating
  entry in CHANGELOG for the design fork.
- AC "menus-off" ESP patch when the mwscript UI wears thin; HW bloods/fats
  tagging for cooking; dressState pruning; carcass quality tiers (_l/_h).

## Housekeeping

- `docs/ic_records.md` is generated (tools/recipes_lint.py) — don't edit.
- `tools/patch_hunterwind.py` needs the tes3util binary beside it.
- Old `ic_station_*` ITEM records stay for save compatibility (legacy items
  drop-swap to activators, pack to salvage) — retire someday.
