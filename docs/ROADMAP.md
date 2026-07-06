# Roadmap / Backlog

Deferred ideas, roughly in intended order. See docs/CONTEXT.md for the data model.

## Station VFX
- [ ] Smoke during charcoal pit and furnace runs; fire VFX for the furnace.
      `processFx` in stations.json currently supports ONE record per station —
      extend it to a LIST ({ record, offset } entries) so a station can burn
      fire + smoke at once. Find a vanilla/OAAB smoke emitter static.
- [ ] Kiln "loaded" visuals: raw molds visibly sitting in the kiln during a
      run, and/or a model swap when the run finishes. Model swap mid-run means
      re-keying saveData.processes (runs are keyed by station object id) and
      the player-side processState mirror — hold until a fired mesh variant
      exists; the processFx fire covers state signaling for now.

## Crafted weapons
- [ ] Crafted weapon/armor record variants (records/Weapon, records/Armor):
      vanilla stats +10-15% damage, named e.g. "Iron Dagger (crafted)";
      furnace recipe outputs point at them. Keep iron below steel.
- [ ] "Sharpening": cast weapons/armor leave the furnace at LOW condition
      (~10-15%, NOT 0 — 0-condition items are broken/unequippable), finished
      with repair hammers (Armorer XP comes free). Optional recipe field
      (e.g. "condition": 0.12) applied after world.createObject in BOTH grant
      paths: grantOutput (init.lua) and collect (globalProcessing.lua);
      ingots/components stay at full condition.
      Later: a smithing skill (SD SkillFramework?) could scale the bonus.
