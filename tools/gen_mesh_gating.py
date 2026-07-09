#!/usr/bin/env python3
"""Generate the mesh -> material map for equip gating.

Player-enchanted items mint DYNAMIC records whose ids can never be tagged
ahead of time — but they keep the base item's MESH. This script scans the
record dumps (extern/tes3-records, opt-in submodule) for every Armor/Weapon
record that carries a material tag (ModTags/<Plugin>_{Armor,Weapon}.yaml,
materials = the keys of data/.../gating/materials.json) and writes

    data/Immersive-Crafting/gating/meshes.json   { "<mesh>": "<material>" }

which equipGate.lua consults when an item's record id matches no material
tag (the dynamic-record case), before falling back to raw value/damage.

Mesh keys are normalized: lowercase, forward slashes, no leading "meshes/".
A mesh shared by records of DIFFERENT materials takes the HIGHEST requirement
(conservative gating); conflicts are printed for review.

    python3 tools/gen_mesh_gating.py     # requires the extern/ submodule
"""
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit('pyyaml required: pip install pyyaml')

ROOT = Path(__file__).resolve().parent.parent
RECORDS = ROOT / 'extern' / 'tes3-records'
MODTAGS = ROOT / 'ModTags'
GATING = ROOT / 'data' / 'Immersive-Crafting' / 'gating'

PLUGINS = ['Morrowind', 'OAAB_Data', 'TR_Mainland', 'Tamriel_Data',
           'Ashlander Crafting', 'Hunterwind', 'Yurt Crafting']
KINDS = ['Armor', 'Weapon']


def norm_mesh(path: str) -> str:
    p = (path or '').strip().lower().replace('\\', '/')
    if p.startswith('meshes/'):
        p = p[len('meshes/'):]
    return p


def load_tags(tagfile: Path) -> dict[str, set[str]]:
    """record id (lower) -> tag set, from one flat ModTags yaml."""
    tags: dict[str, set[str]] = {}
    if not tagfile.exists():
        return tags
    cur = None
    for line in tagfile.read_text(encoding='utf-8').splitlines():
        m = re.match(r'^([A-Za-z_ ]+):\s*$', line)
        if m:
            cur = m.group(1).strip().lower()
            continue
        m = re.match(r'^\s+-\s+(.*)$', line)
        if m and cur:
            tags.setdefault(m.group(1).strip().lower(), set()).add(cur)
    return tags


def main() -> int:
    if not RECORDS.is_dir() or not any(RECORDS.iterdir()):
        sys.exit('extern/tes3-records missing — git submodule update --init extern/tes3-records')

    materials = json.loads((GATING / 'materials.json').read_text(encoding='utf-8'))

    mesh_to: dict[str, str] = {}
    conflicts = []
    n_records = 0
    for plugin in PLUGINS:
        for kind in KINDS:
            recdir = RECORDS / plugin / kind
            if not recdir.is_dir():
                continue
            tags = load_tags(MODTAGS / f'{plugin}_{kind}.yaml')
            for f in recdir.glob('*.yaml'):
                rec = yaml.safe_load(f.read_text(encoding='utf-8'))
                if not isinstance(rec, dict):
                    continue
                rid = (rec.get('id') or '').lower()
                mesh = norm_mesh(rec.get('mesh') or '')
                if not rid or not mesh:
                    continue
                mats = [t for t in tags.get(rid, ()) if t in materials]
                if not mats:
                    continue
                n_records += 1
                # a record with several material tags gates at the max —
                # the mesh should map to that same max material
                mat = max(mats, key=lambda m: materials[m])
                prev = mesh_to.get(mesh)
                if prev and prev != mat:
                    conflicts.append((mesh, prev, mat))
                    if materials[mat] > materials[prev]:
                        mesh_to[mesh] = mat
                else:
                    mesh_to[mesh] = mat

    out = GATING / 'meshes.json'
    out.write_text(
        json.dumps(dict(sorted(mesh_to.items())), indent=2) + '\n', encoding='utf-8')
    print(f'{out.relative_to(ROOT)}: {len(mesh_to)} meshes '
          f'from {n_records} tagged records')
    for mesh, a, b in conflicts:
        print(f'  conflict {mesh}: {a} vs {b} -> kept the higher tier')
    return 0


if __name__ == '__main__':
    sys.exit(main())
