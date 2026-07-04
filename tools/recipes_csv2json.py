#!/usr/bin/env python3
"""Convert the tiered crafting recipes CSV into the engine's recipe JSON.

Usage:
    python3 tools/recipes_csv2json.py \
        [--csv docs/immersive_crafting_recipes_v2.csv] \
        [--out data/Immersive-Crafting/recipes/crafting.json] \
        [--records-out docs/ic_records.md]

CSV columns:
    outcome, outcome_id, outcome_count, duration, station, tool1..3, ingredient1..9, notes
(`duration` = game seconds for timed process runs; empty/0 = instant craft)
Comment lines starting with `#` are ignored.

Mapping (see docs/SPEC.md):
- Grid stations (Bushcrafting 2x2, Crafting Table 3x3) -> CShapedRecipe:
  ingredient1..N are positional (row-major); emitted as `pattern` rows + `key`
  (one symbol per distinct ingredient). Action: "shaping".
- Process stations (Firepit, Kiln, Furnace, Charcoal Pit, Tanning Rack) ->
  CProcessRecipe: ingredients are non-positional; emitted as counted
  `inputs: [{id, count}]`. Action: "processing".
- tool1..3 -> `tools` (required from inventory, NEVER consumed).
- outcome_id/outcome_count -> `output {id, count}`.

Lint rules (design-critical, see the recipes handoff):
- Weapon molds (raw + burnt) are CONSUMED -> must never appear in a tool column.
- The burnt armor mold and the crucible are reusable TOOLS -> must never appear
  in an ingredient column (exception: the Furnace build consumes a crucible as
  a component; reported as an acknowledged warning).
"""
import argparse
import csv
import json
import string
import sys
from collections import OrderedDict

# station -> (context id, kind, grid size or None)
STATIONS = {
    'Bushcrafting': ('bushcrafting', 'grid', (2, 2)),
    'Crafting Table': ('crafting_table', 'grid', (3, 3)),
    'Firepit': ('firepit', 'process', None),
    'Kiln': ('kiln', 'process', None),
    'Furnace': ('furnace', 'process', None),
    'Charcoal Pit': ('charcoal_pit', 'process', None),
    'Tanning Rack': ('tanning_rack', 'process', None),
}

ACTIONS = {'grid': 'shaping', 'process': 'processing'}

# consumed on casting -> ingredients only
CONSUMED_MOLDS = {
    f'ic_mold_{w}_{s}'
    for w in ('dagger', 'waraxe', 'spear', 'longsword', 'warhammer')
    for s in ('raw', 'burnt')
}
# reusable -> tools only
REUSABLE_TOOLS = {'ic_mold_armor_burnt', 'ic_crucible'}
# acknowledged exceptions: (recipe id, item) pairs allowed despite the rules
ACKNOWLEDGED = {('ic_station_furnace', 'ic_crucible')}  # crucible built into the furnace


def parse_rows(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        header = None
        for line in f.read().splitlines():
            if line.startswith('#') or not line.strip():
                continue
            fields = next(csv.reader([line]))
            if header is None:
                header = fields
                continue
            if len(fields) > len(header):  # unquoted comma in notes
                fields = fields[:len(header) - 1] + [','.join(fields[len(header) - 1:])]
            rows.append(dict(zip(header, fields + [''] * (len(header) - len(fields)))))
    return rows


def to_pattern(ingredients, size):
    """Row-major positional fill -> pattern rows + symbol key."""
    cols, rows = size
    key = OrderedDict()
    symbols = string.ascii_uppercase
    pattern = []
    for r in range(rows):
        row_chars = []
        for c in range(cols):
            item = ingredients[r * cols + c] if r * cols + c < len(ingredients) else ''
            if item:
                if item not in key:
                    key[item] = symbols[len(key)]
                row_chars.append(key[item])
            else:
                row_chars.append(' ')
        pattern.append(''.join(row_chars))
    return pattern, {sym: item for item, sym in key.items()}


def convert(rows):
    recipes, errors, warnings = [], [], []
    seen_ids = {}
    station_max = {}
    ic_outputs, ic_refs, assumed_tags, record_refs = set(), set(), set(), set()

    for row in rows:
        outcome_id = row['outcome_id'].strip()
        station = row['station'].strip()
        label = row['outcome'].strip()
        rid = outcome_id

        if station not in STATIONS:
            errors.append(f'{rid}: unknown station "{station}"')
            continue
        context, kind, size = STATIONS[station]

        tools = [row[f'tool{i}'].strip() for i in range(1, 4) if row[f'tool{i}'].strip()]
        # positional list, preserving column gaps for grid shapes
        slots = [row[f'ingredient{i}'].strip() for i in range(1, 10)]
        while slots and not slots[-1]:
            slots.pop()
        items = [s for s in slots if s]

        if not items:
            errors.append(f'{rid}: no ingredients')
            continue
        try:
            count = int(row.get('outcome_count', '1') or '1')
        except ValueError:
            errors.append(f'{rid}: bad outcome_count "{row["outcome_count"]}"')
            continue

        # ── lint: consumed vs reusable ────────────────────────────────────
        if (row.get('duration') or '').strip() and kind == 'grid':
            warnings.append(f'{rid}: duration is ignored on grid (shaped) recipes')
        for t in tools:
            if t in CONSUMED_MOLDS:
                errors.append(f'{rid}: consumed mold "{t}" used as a tool (must be an ingredient)')
        for it in items:
            if it in REUSABLE_TOOLS:
                if (rid, it) in ACKNOWLEDGED:
                    warnings.append(f'{rid}: reusable tool "{it}" consumed as ingredient (acknowledged)')
                else:
                    errors.append(f'{rid}: reusable tool "{it}" used as an ingredient (must be a tool)')

        if rid in seen_ids:
            errors.append(f'{rid}: duplicate recipe id (also at {seen_ids[rid]})')
            continue
        seen_ids[rid] = station

        # ── bookkeeping for the report ────────────────────────────────────
        for ref in items + tools:
            if ref.startswith('ic_'):
                ic_refs.add(ref)
            elif ref[:1].isupper():
                assumed_tags.add(ref)
            else:
                record_refs.add(ref)
        if outcome_id.startswith('ic_'):
            ic_outputs.add(outcome_id)
        station_max[station] = max(station_max.get(station, 0), len(items))

        # ── emit ──────────────────────────────────────────────────────────
        recipe = OrderedDict()
        recipe['id'] = rid
        recipe['label'] = label
        recipe['context'] = context
        recipe['action'] = ACTIONS[kind]

        if kind == 'grid':
            capacity = size[0] * size[1]
            if len(slots) > capacity:
                errors.append(f'{rid}: {len(items)} ingredients exceed {station} {size[0]}x{size[1]} grid')
                continue
            pattern, key = to_pattern(slots, size)
            recipe['pattern'] = pattern
            recipe['key'] = key
        else:
            inputs = OrderedDict()
            for it in items:
                inputs[it] = inputs.get(it, 0) + 1
            recipe['inputs'] = [{'id': k, 'count': v} for k, v in inputs.items()]
            duration = (row.get('duration') or '').strip()
            if duration:
                try:
                    recipe['duration'] = int(duration)
                except ValueError:
                    errors.append(f'{rid}: bad duration "{duration}"')
                    continue

        if tools:
            recipe['tools'] = tools
        recipe['output'] = {'id': outcome_id, 'count': count}
        recipes.append(recipe)

    report = {
        'station_max': station_max,
        'ic_outputs': sorted(ic_outputs),
        'ic_refs': sorted(ic_refs),
        'assumed_tags': sorted(assumed_tags),
        'record_refs': sorted(record_refs),
    }
    return recipes, errors, warnings, report


def write_records_doc(path, report):
    lines = [
        '# Custom (`ic_*`) record inventory — GENERATED by tools/recipes_csv2json.py',
        '',
        'Records the recipe data depends on. Custom outputs need real plugin records',
        '(see docs/TODO.md — D1 amendment pending); tags must be authored in Tagger YAML.',
        '',
        '## `ic_*` records produced as outputs',
        '',
    ]
    lines += [f'- `{r}`' for r in report['ic_outputs']]
    only_refs = [r for r in report['ic_refs'] if r not in set(report['ic_outputs'])]
    if only_refs:
        lines += ['', '## `ic_*` records referenced but never produced (check!)', '']
        lines += [f'- `{r}`' for r in only_refs]
    lines += ['', '## Assumed Tagger tags (capitalised ingredient/tool names)', '']
    lines += [f'- `{t}`' for t in report['assumed_tags']]
    lines += ['', '## Vanilla record references (verify against the tes3-records dump)', '']
    lines += [f'- `{r}`' for r in report['record_refs']]
    lines.append('')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--csv', default='docs/immersive_crafting_recipes_v2.csv')
    ap.add_argument('--out', default='data/Immersive-Crafting/recipes/crafting.json')
    ap.add_argument('--records-out', default='docs/ic_records.md')
    args = ap.parse_args()

    rows = parse_rows(args.csv)
    recipes, errors, warnings, report = convert(rows)

    for w in warnings:
        print(f'WARN  {w}')
    for e in errors:
        print(f'ERROR {e}')
    if errors:
        print(f'\n{len(errors)} error(s) — no output written.')
        return 1

    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, indent=2, ensure_ascii=False)
        f.write('\n')
    if args.records_out:
        write_records_doc(args.records_out, report)

    shaped = sum(1 for r in recipes if 'pattern' in r)
    print(f'\nWrote {len(recipes)} recipes ({shaped} shaped, {len(recipes) - shaped} process) -> {args.out}')
    print('Max ingredients per process station (size the context layouts accordingly):')
    for station, mx in sorted(report['station_max'].items()):
        if STATIONS[station][1] == 'process':
            print(f'  {station:<15} {mx}')
    print(f'ic_* outputs: {len(report["ic_outputs"])}, assumed tags: {len(report["assumed_tags"])}'
          f' -> {args.records_out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
