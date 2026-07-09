#!/usr/bin/env python3
"""Asset + matcher audit — regenerates docs/asset_audit.md.

Two audits, both report-only:

1. RECORDS (records/**/*.yaml): every mesh/icon that is (a) marked interim/
   placeholder in a comment, or (b) not found among the known asset paths
   (docs/vanilla_icons.csv + every mesh/icon referenced by the record dumps
   in extern/tes3-records) — i.e. paths nothing in the load order ships.

2. RECIPE MATCHERS (recipes/*.json + constructions.json): every ingredient/
   tool/component matcher classified against the record dumps and the tag
   data (this repo's ModTags/ + the upstream extern/tes3-records/ModTags).
   Flags:
   - BROKEN: matches no record id and no tag anywhere;
   - UPSTREAM-ONLY: tag exists only in extern/tes3-records (works in-game if
     the full tag data is installed, but this repo's ModTags doesn't ship it);
   - SPECIFIC-ID: an exact record id used where one or more multi-member tags
     cover it — candidates to widen to a tag (judgment call, hence a report).

    python3 tools/audit_assets.py     # requires the extern/ submodule
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDS = ROOT / 'records'
EXTERN = ROOT / 'extern' / 'tes3-records'
OUT = ROOT / 'docs' / 'asset_audit.md'

INTERIM_RE = re.compile(r'interim|placeholder|replace|VERIFY|FIXME|TODO', re.I)
# generic classification tags that never make sense as recipe ingredients
GENERIC_TAGS = {
    'armor', 'weapon', 'miscitem', 'ingredient', 'clutter', 'unique',
    'tableware', 'ammunition', 'thrown', 'marksman', 'light', 'medium',
    'heavy', 'left', 'right', 'boots', 'cuirass', 'helmet', 'helm',
    'greaves', 'pauldron', 'gauntlet', 'bracer', 'shield', 'arrow', 'bolt',
    'blunt', 'blade', 'long blade', 'short blade', 'instrument', 'key',
}


def norm(p: str) -> str:
    return (p or '').strip().lower().replace('\\', '/')


def known_assets() -> set[str]:
    known = set()
    csv_path = ROOT / 'docs' / 'vanilla_icons.csv'
    if csv_path.exists():
        for row in csv.reader(csv_path.open(encoding='utf-8', errors='replace')):
            if len(row) >= 5:
                known.add(norm(row[0]))  # icon
                known.add(norm(row[4]))  # mesh
    if EXTERN.is_dir():
        for f in EXTERN.rglob('*.yaml'):
            try:
                text = f.read_text(encoding='utf-8', errors='replace')
            except OSError:
                continue
            for m in re.finditer(r'^(?:mesh|icon):\s*(.+)$', text, re.M):
                known.add(norm(m.group(1)))
    return known


# Real records verified against plugins that extern/tes3-records does NOT dump
# (Hunterwind was dumped in-session; consider adding it upstream).
EXTERNAL_KNOWN = {'hb_brokenhunterknife', 'hb_hunters_knife'}


def dump_record_ids() -> set[str]:
    ids = set(EXTERNAL_KNOWN)
    if EXTERN.is_dir():
        for plugin in EXTERN.iterdir():
            if plugin.is_dir() and plugin.name not in ('ModTags', 'site', 'scripts',
                                                       '_out', 'icons', 'tes3util'):
                for f in plugin.rglob('*.yaml'):
                    ids.add(f.stem.lower())
    for f in RECORDS.rglob('*.yaml'):
        ids.add(f.stem.lower())
    return ids


def load_tagfile(path: Path, into: dict[str, set[str]]):
    cur = None
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'^([A-Za-z_][A-Za-z_ ]*):\s*$', line)
        if m:
            cur = m.group(1).strip().lower()
            continue
        m = re.match(r'^\s+-\s+(.*)$', line)
        if m and cur:
            into.setdefault(cur, set()).add(m.group(1).strip().lower())


def audit_records(known: set[str]):
    interim, unknown = [], []
    for f in sorted(RECORDS.rglob('*.yaml')):
        text = f.read_text(encoding='utf-8', errors='replace')
        rel = f.relative_to(ROOT)
        comments = ' '.join(l for l in text.splitlines() if l.lstrip().startswith('#'))
        flagged = bool(INTERIM_RE.search(comments))
        for kind in ('mesh', 'icon'):
            m = re.search(rf'^{kind}:\s*(.+)$', text, re.M)
            path = norm(m.group(1)) if m else ''
            path = path.strip('"\'')
            if flagged:
                interim.append((str(rel), kind, path or '(none)'))
            elif not path:
                unknown.append((str(rel), kind, '(empty)'))
            elif path not in known:
                unknown.append((str(rel), kind, path))
    return interim, unknown


def recipe_matchers():
    """[(file, recipe id, role, matcher)] across recipes + constructions."""
    out = []
    rdir = ROOT / 'data' / 'Immersive-Crafting' / 'recipes'
    for p in sorted(rdir.glob('*.json')):
        for r in json.load(p.open(encoding='utf-8')):
            rid = r.get('id', '?')
            for v in (r.get('key') or {}).values():
                out.append((p.name, rid, 'ingredient', v))
            for line in r.get('inputs') or []:
                if line.get('id'):
                    out.append((p.name, rid, 'input', line['id']))
            for line in r.get('returned') or []:
                out.append((p.name, rid, 'returned', line['id']))
            for t in r.get('tools') or []:
                out.append((p.name, rid, 'tool', t))
    cpath = ROOT / 'data' / 'Immersive-Crafting' / 'constructions' / 'constructions.json'
    for c in json.load(cpath.open(encoding='utf-8')):
        for comp in c.get('components') or []:
            out.append(('constructions.json', c['id'], 'component', comp['id']))
        for s in c.get('salvage') or []:
            out.append(('constructions.json', c['id'], 'salvage', s['id']))
        for t in c.get('tools') or []:
            out.append(('constructions.json', c['id'], 'tool', t))
    return out


def main() -> int:
    if not EXTERN.is_dir():
        sys.exit('extern/tes3-records missing — git submodule update --init extern/tes3-records')

    known = known_assets()
    record_ids = dump_record_ids()

    repo_tags: dict[str, set[str]] = {}
    for f in sorted((ROOT / 'ModTags').glob('*.yaml')):
        load_tagfile(f, repo_tags)
    upstream_tags: dict[str, set[str]] = {}
    for f in sorted((EXTERN / 'ModTags').rglob('*.yaml')):
        load_tagfile(f, upstream_tags)

    interim, unknown = audit_records(known)

    # record id (lower) -> tags containing it (for the specific-id audit)
    member_of: dict[str, set[str]] = {}
    for source in (repo_tags, upstream_tags):
        for tag, members in source.items():
            for rid in members:
                member_of.setdefault(rid, set()).add(tag)

    # part-specific by design: a boots mold must be THE boots mold — widening
    # to the mold_raw/mold_burnt family would let any mold match
    BY_DESIGN_EXACT = {'mold_raw', 'mold_burnt'}

    broken, upstream_only, specific = [], [], []
    seen = set()
    for fname, rid, role, matcher in recipe_matchers():
        key = (fname, rid, role, matcher)
        if key in seen:
            continue
        seen.add(key)
        m = matcher.lower()
        if m.startswith('sd:'):
            continue  # engine matcher
        if role == 'salvage':
            continue  # salvage grants records — it can never be a tag
        is_record = m in record_ids
        in_repo = m in repo_tags
        in_upstream = m in upstream_tags
        if not (is_record or in_repo or in_upstream):
            broken.append(key)
        elif not is_record and not in_repo and in_upstream:
            upstream_only.append(key + (len(upstream_tags[m]),))
        elif is_record and not in_repo and not in_upstream:
            # exact record id: would a multi-member tag cover it?
            cands = []
            for tag in sorted(member_of.get(m, ())):
                members = (repo_tags.get(tag) or upstream_tags.get(tag) or set())
                if tag not in GENERIC_TAGS and tag not in BY_DESIGN_EXACT \
                        and len(members) >= 2:
                    cands.append(f'{tag}({len(members)})')
            if cands:
                specific.append(key + (', '.join(cands),))

    lines = [
        '# Asset & matcher audit — GENERATED by tools/audit_assets.py', '',
        'Report-only. Regenerate after mesh passes or tag-data updates.', '',
        '## Records with INTERIM meshes/icons (comment-flagged)', '',
    ]
    lines += [f'- `{f}` {k}: `{p}`' for f, k, p in interim] or ['- (none)']
    lines += ['', '## Records whose mesh/icon path is UNKNOWN to the load order', '',
              '(not in vanilla_icons.csv and referenced by no dumped record —',
              'either a typo, or an asset this mod must ship itself)', '']
    lines += [f'- `{f}` {k}: `{p}`' for f, k, p in unknown] or ['- (none)']
    lines += ['', '## BROKEN matchers (no record id, no tag anywhere)', '']
    lines += [f'- `{f}` / `{r}` [{role}]: `{m}`' for f, r, role, m in broken] or ['- (none)']
    lines += ['', '## Tags that exist only UPSTREAM (extern/tes3-records ModTags)', '',
              '(work in-game when the full tag data is installed; consider',
              'shipping the needed entries in this repo\'s ModTags/)', '']
    lines += [f'- `{f}` / `{r}` [{role}]: `{m}` ({n} members upstream)'
              for f, r, role, m, n in upstream_only] or ['- (none)']
    lines += ['', '## Specific record ids where a MULTI-MEMBER tag exists', '',
              '(candidates to widen to a tag — judgment calls, not bugs)', '']
    lines += [f'- `{f}` / `{r}` [{role}]: `{m}` -> {c}'
              for f, r, role, m, c in specific] or ['- (none)']
    lines.append('')

    OUT.write_text('\n'.join(lines), encoding='utf-8')
    print(f'{OUT.relative_to(ROOT)}: {len(interim)} interim, {len(unknown)} unknown paths, '
          f'{len(broken)} broken, {len(upstream_only)} upstream-only, '
          f'{len(specific)} specific-id candidates')
    return 0


if __name__ == '__main__':
    sys.exit(main())
