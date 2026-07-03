#!/usr/bin/env python3
"""Extract an icon/mesh reference from tes3-records YAML dumps.

Builds a searchable CSV of every record that has an `icon`, so custom-record
YAMLs (records/<Type>/<id>.yaml for tes3util.exe) can borrow vanilla icons and
meshes by searching this list by name/type instead of digging through dumps.

Usage:
    py tools/extract_icons.py "D:/modding tes3/_test/tes3-records/Morrowind" \
        [more dump roots ...] [--out docs/vanilla_icons.csv]

Each dump root is walked recursively; a record's `type` is read from the YAML
(falling back to its parent directory name), and the `plugin` column is the
dump-root name plus any nested plugin folder (the Morrowind dump nests
Tribunal/ and Bloodmoon/ inside it).

No YAML library needed: the dumped records keep id/name/icon/mesh as
top-level scalars, so a line parser is sufficient.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

# top-level scalar fields we care about (no indentation in the dump format)
FIELD_RE = re.compile(r"^(type|id|name|icon|mesh):\s*(.*)\s*$")

# record-type directory names that never carry icons — skipped without reading
NO_ICON_TYPES = {'Header', 'Static', 'Activator', 'Container', 'Cell', 'Region',
                 'Dialogue', 'Info', 'LandscapeTexture', 'LevelledCreature',
                 'LevelledItem', 'PathGrid', 'Script', 'Sound', 'SoundGen'}


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        value = value[1:-1]
    return value.strip()


def parse_record(path):
    fields = {}
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                m = FIELD_RE.match(line)
                if m:
                    fields[m.group(1)] = unquote(m.group(2))
                    if len(fields) == 5:
                        break
    except OSError as e:
        print(f'WARN cannot read {path}: {e}', file=sys.stderr)
    return fields


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('roots', nargs='+', help='dump root folder(s), e.g. .../tes3-records/Morrowind')
    ap.add_argument('--out', default='docs/vanilla_icons.csv')
    args = ap.parse_args()

    rows = []
    scanned = 0
    for root in args.roots:
        root = Path(root)
        if not root.is_dir():
            print(f'ERROR not a directory: {root}', file=sys.stderr)
            return 1
        for path in root.rglob('*.yaml'):
            rel = path.relative_to(root)
            type_dir = rel.parent.name if rel.parent != Path('.') else ''
            if type_dir in NO_ICON_TYPES:
                continue
            scanned += 1
            fields = parse_record(path)
            icon = fields.get('icon', '')
            if not icon:
                continue
            # plugin = dump root + any nested plugin folders above the type dir
            nested = [p for p in rel.parent.parts[:-1]]
            plugin = '/'.join([root.name] + nested)
            rows.append({
                'icon': icon,
                'record_type': fields.get('type', type_dir),
                'id': fields.get('id', path.stem),
                'name': fields.get('name', ''),
                'mesh': fields.get('mesh', ''),
                'plugin': plugin,
            })

    rows.sort(key=lambda r: (r['record_type'], r['icon'], r['id']))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['icon', 'record_type', 'id', 'name', 'mesh', 'plugin'])
        writer.writeheader()
        writer.writerows(rows)

    by_type = {}
    for r in rows:
        by_type[r['record_type']] = by_type.get(r['record_type'], 0) + 1
    unique_icons = len({r['icon'].lower() for r in rows})
    print(f'{len(rows)} records with icons (of {scanned} scanned) -> {out}')
    print(f'{unique_icons} unique icon paths')
    for t in sorted(by_type):
        print(f'  {t:<12} {by_type[t]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
