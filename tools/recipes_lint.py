#!/usr/bin/env python3
"""Lint the hand-maintained recipe JSON and regenerate the record inventory.

The recipe JSON (data/Immersive-Crafting/recipes/*.json) is the SOURCE OF TRUTH,
organized into three kinds of file (the loader globs them all, so filenames are
purely for humans — every recipe still carries its own `context`):
  - CONTEXT files (bushcrafting, crafting_table, kiln, furnace, …): non-equipment
    PRODUCTION — materials, stations, tools, containers;
  - MATERIAL files (chitin, iron, steel, bonemold, glass, bronze, copper): that
    material's weapons + armor, any context;
  - molds.json: every mold recipe (raw + burnt, weapon + armor + ingot).
This tool READS those files (it never writes them) and:

  1. checks structural integrity (duplicate ids; equipment in the right material
     file; molds in molds.json; context files free of equipment/molds and their
     `context` matching the filename);
  2. lints the tool-vs-consumed rules (consumed weapon molds never in a tool
     column; reusable armor/ingot molds placed as a `returned` input, never a
     plain consumed one);
  3. regenerates docs/ic_records.md — the inventory of `ic_*` records the
     recipes depend on, assumed FlexTags, and vanilla record references.

Exit status is non-zero if any error-level problem is found (usable in CI).

    python3 tools/recipes_lint.py                 # lint + regenerate the doc
    python3 tools/recipes_lint.py --check         # lint only (no doc write)
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import OrderedDict

RECIPES_DIR = 'data/Immersive-Crafting/recipes'
RECORDS_DOC = 'docs/ic_records.md'

# recipe files grouped by station context (filename == context id): hold
# non-equipment, non-mold PRODUCTION (materials, stations, tools, containers)
CONTEXT_FILES = {
    'bushcrafting', 'crafting_table', 'firepit', 'kiln',
    'charcoal_pit', 'tanning_rack', 'furnace', 'oven',
}
# cross-context EQUIPMENT files grouped by material (filename == material):
# hold that material's weapons + armor, any context
MATERIAL_FILES = {'chitin', 'iron', 'steel', 'bonemold', 'glass', 'bronze', 'copper'}
# all mold recipes (raw + burnt, weapon + armor + ingot) live here
MOLDS_FILE = 'molds'
# world-placement cooking + SD meals: not linted for placement
OTHER_FILES = {'cooking', 'sd_meals'}

# consumed on casting -> may appear as ingredients, never as tools
CONSUMED_MOLDS = {
    f'ic_mold_{w}_{s}'
    for w in ('dagger', 'waraxe', 'spear', 'longsword', 'warhammer')
    for s in ('raw', 'burnt')
}
# placed for the match but RETURNED (never truly consumed): must be a
# `returned` input line, never a plain ingredient or a tool. Armor molds are
# reusable (unlike single-use weapon molds): the generic one plus the burnt
# per-part molds (boots, greaves, helm, l/r pauldron, l/r bracer, shield,
# tower shield).
_ARMOR_MOLD_PARTS = ('cuirass', 'boots', 'greaves', 'helm',
                     'pauldron_left', 'pauldron_right',
                     'bracer_left', 'bracer_right',
                     'gauntlet_left', 'gauntlet_right',
                     'shield', 'tower_shield')
# reusable molds: the armor part molds plus the ingot mold (the furnace casts
# ingots in it and hands it back). Weapon molds are single-use (CONSUMED_MOLDS).
RETURNED_ITEMS = ({f'ic_mold_{p}_burnt' for p in _ARMOR_MOLD_PARTS}
                  | {'ic_mold_ingot_burnt'})

# output-name classification (word-boundary; ids may join words with _ or space)
WEAPON_KW = ['dagger', 'war axe', 'waraxe', 'spear', 'longsword', 'warhammer',
             'claymore', 'halberd', 'club', 'shortsword', 'short bow', 'long bow',
             'bow', 'arrow', 'bolt', 'mace', 'staff', 'katana', 'tanto', 'wakizashi']
ARMOUR_KW = ['cuirass', 'helm', 'helmet', 'boots', 'greaves', 'shield',
             'towershield', 'pauldron', 'gauntlet', 'bracer', 'armor', 'armour',
             'skirt']


def category_of(output_id):
    """weapons / armour / None for an output record id (molds & stations = None)."""
    out = (output_id or '').lower()
    if not out or out.startswith('ic_mold_') or out.startswith('ic_station_'):
        return None
    norm = re.sub(r'[_\s]+', ' ', out)
    if any(re.search(r'\b' + re.escape(k) + r'\b', norm) for k in WEAPON_KW):
        return 'weapons'
    if any(re.search(r'\b' + re.escape(k) + r'\b', norm) for k in ARMOUR_KW):
        return 'armour'
    return None


def material_of(output_id):
    """Leading material token of an equipment output ('iron boots' -> 'iron')."""
    return (output_id or '').lower().replace('_', ' ').split()[0] if output_id else ''


def load_recipes():
    """[(recipe, filestem)] across every recipes/*.json."""
    out = []
    for path in sorted(glob.glob(f'{RECIPES_DIR}/*.json')):
        stem = os.path.splitext(os.path.basename(path))[0]
        try:
            data = json.load(open(path, encoding='utf-8'))
        except json.JSONDecodeError as e:
            out.append((None, stem, f'{path}: invalid JSON ({e})'))
            continue
        for r in data:
            out.append((r, stem, None))
    return out


def lint(recipes):
    errors, warnings = [], []
    seen = {}

    for r, stem, load_err in recipes:
        if load_err:
            errors.append(load_err)
            continue

        rid = r.get('id')
        if not rid:
            errors.append(f'{stem}.json: recipe with no id')
            continue

        # duplicate id across all files
        if rid in seen:
            errors.append(f'{rid}: duplicate id (in {seen[rid]}.json and {stem}.json)')
        else:
            seen[rid] = stem

        # placement: does this recipe belong in this file?
        out_id = (r.get('output') or {}).get('id')
        is_mold = (out_id or '').startswith('ic_mold_')
        cat = category_of(out_id)
        if stem == MOLDS_FILE:
            if not is_mold:
                errors.append(f'{rid}: in molds.json but output "{out_id}" is not a mold')
        elif stem in MATERIAL_FILES:
            if is_mold:
                errors.append(f'{rid}: mold "{out_id}" should live in molds.json, not {stem}.json')
            elif cat is None:
                errors.append(f'{rid}: output "{out_id}" is not equipment — does not belong in {stem}.json')
            elif material_of(out_id) != stem:
                errors.append(f'{rid}: {material_of(out_id)} equipment "{out_id}" filed in {stem}.json')
        elif stem in CONTEXT_FILES:
            if is_mold:
                errors.append(f'{rid}: mold "{out_id}" should live in molds.json, not {stem}.json')
            elif cat is not None:
                errors.append(f'{rid}: {cat} "{out_id}" should live in {material_of(out_id)}.json, not {stem}.json')
            elif r.get('context') and r['context'] != stem:
                errors.append(f'{rid}: context "{r["context"]}" but filed in {stem}.json')
        # OTHER_FILES: no placement rule

        # tool-vs-consumed rules
        for t in r.get('tools') or []:
            if t in CONSUMED_MOLDS:
                errors.append(f'{rid}: consumed mold "{t}" used as a tool (must be an ingredient)')
            if t in RETURNED_ITEMS:
                errors.append(f'{rid}: returned item "{t}" used as a tool (must be a returned input)')

        for line in r.get('inputs') or []:
            iid = line.get('id')
            if iid in RETURNED_ITEMS and not line.get('returned'):
                errors.append(f'{rid}: "{iid}" must be a returned input (add "returned": true) — it is reusable')
            if iid in CONSUMED_MOLDS and line.get('returned'):
                warnings.append(f'{rid}: consumed mold "{iid}" marked returned (it is destroyed on casting)')

        # shaped recipes may carry a top-level returned list
        for entry in r.get('returned') or []:
            if entry.get('id') in CONSUMED_MOLDS:
                warnings.append(f'{rid}: consumed mold "{entry["id"]}" listed as returned')

    return errors, warnings, seen


def build_report(recipes):
    ic_outputs, ic_refs, assumed_tags, record_refs = set(), set(), set(), set()
    for r, _stem, load_err in recipes:
        if load_err:
            continue
        out_id = (r.get('output') or {}).get('id')
        if out_id and out_id.startswith('ic_'):
            ic_outputs.add(out_id)

        refs = []
        for v in (r.get('key') or {}).values():
            refs.append(v)
        for line in r.get('inputs') or []:
            refs.append(line.get('id'))
        for entry in r.get('returned') or []:
            refs.append(entry.get('id'))
        refs += r.get('tools') or []

        for ref in refs:
            if not ref:
                continue
            if ref.startswith('sd:'):
                continue  # engine matcher (SD dynamic liquids), not a record/tag
            elif ref.startswith('ic_'):
                ic_refs.add(ref)
            elif ref[:1].isupper():
                assumed_tags.add(ref)
            else:
                record_refs.add(ref)

    return {
        'ic_outputs': sorted(ic_outputs),
        'ic_refs': sorted(ic_refs),
        'assumed_tags': sorted(assumed_tags),
        'record_refs': sorted(record_refs),
    }


def write_records_doc(path, report):
    lines = [
        '# Custom (`ic_*`) record inventory — GENERATED by tools/recipes_lint.py',
        '',
        'Records the hand-maintained recipe JSON (recipes/*.json) depends on.',
        'Custom outputs need real plugin records; tags must be authored in the',
        'ModTags FlexTag YAMLs.',
        '',
        '## `ic_*` records produced as outputs',
        '',
    ]
    lines += [f'- `{r}`' for r in report['ic_outputs']]
    only_refs = [r for r in report['ic_refs'] if r not in set(report['ic_outputs'])]
    if only_refs:
        lines += ['', '## `ic_*` records referenced but never produced (check!)', '']
        lines += [f'- `{r}`' for r in only_refs]
    lines += ['', '## Assumed FlexTags (capitalised ingredient/tool names)', '']
    lines += [f'- `{t}`' for t in report['assumed_tags']]
    lines += ['', '## Vanilla record references (verify against the records dump)', '']
    lines += [f'- `{r}`' for r in report['record_refs']]
    lines.append('')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--check', action='store_true',
                    help='lint only; do not regenerate docs/ic_records.md')
    args = ap.parse_args()

    recipes = load_recipes()
    errors, warnings, seen = lint(recipes)

    for w in warnings:
        print(f'WARN  {w}')
    for e in errors:
        print(f'ERROR {e}')

    if errors:
        print(f'\n{len(errors)} error(s), {len(warnings)} warning(s) — lint failed.')
        return 1

    print(f'OK: {len(seen)} recipes across '
          f'{len({s for _, s, _ in recipes})} files, {len(warnings)} warning(s).')

    if not args.check:
        report = build_report(recipes)
        write_records_doc(RECORDS_DOC, report)
        print(f'Wrote {RECORDS_DOC} '
              f'({len(report["ic_outputs"])} ic_* outputs, '
              f'{len(report["assumed_tags"])} assumed tags).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
