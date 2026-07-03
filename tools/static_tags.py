#!/usr/bin/env python3
"""Generate FlexTag tags for foraging statics (trees, rocks) from a record dump.

Walks every ``<Source>/**/Static/*.yaml`` file in a tes3-records dump and
classifies each Static as a gaze-forage target by keyword-matching its id and
mesh path. Writes the FlexTag YAML consumed by the mod:

    ModTags/ImmersiveCrafting_Statics.yaml

    tree:
      - "flora_bc_tree_08"
      - ...
    rock:
      - "terrain_rock_bc_17"
      - ...

Static records carry no display name, so classification uses the record id and
the mesh filename (both lowercased). Trees match the token ``tree``. Rocks match
``rock`` or ``boulder`` but are rejected when the id/mesh also names a structural
piece (bridge, stair, doorrock, wall, rock-nest column, ...) so we don't tag
scenery the player can't plausibly gather stone from.

FlexTag lowercases tag names and record ids, so casing here is cosmetic; ids are
emitted as they appear in the dump.

Usage:
    py tools/static_tags.py [--db PATH] [--out PATH]
Defaults: --db ../tes3-records  --out ModTags/ImmersiveCrafting_Statics.yaml
Standard library only (matches the other tools/).
"""
import argparse
import os
import sys

DEFAULT_DB = os.path.join("..", "tes3-records")
DEFAULT_OUT = os.path.join("ModTags", "ImmersiveCrafting_Statics.yaml")

# tag -> keyword list. A static matches a tag if any keyword appears as a
# substring of its lowercased "id mesh" text. Substring (not whole-word) is
# deliberate: it keeps concatenations like "ashtree"/"treestump"/"lavarock"
# that a word boundary would drop. Verified against the dumps to add no
# non-tree/non-rock hits beyond the EXCLUDE cases below.
INCLUDE = {
    "tree": ["tree"],
    "rock": ["rock", "boulder"],
}

# A candidate is rejected if any of these words appears anywhere in its text.
# These are structural/scenery uses of "rock" (bridges, stairs, walls) or props
# (minecart fills) that are not gatherable stone. Trees have no false positives.
EXCLUDE = [
    "bridge", "stair", "door", "wall", "arch", "gate", "ramp", "road",
    "column", "nest", "gravel", "pave", "step", "platform", "ruin_floor",
    "minecart",
]


def _read_record(path):
    """Pull id + mesh from a flat Static YAML without a yaml dependency."""
    rec_id, mesh = None, ""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if rec_id is None and line.startswith("id:"):
                rec_id = line[3:].strip()
            elif line.startswith("mesh:"):
                mesh = line[5:].strip()
            if rec_id is not None and mesh:
                break
    return rec_id, mesh


def classify(rec_id, mesh):
    """Return the set of tags for a static (may be empty)."""
    text = (rec_id + " " + mesh).replace("\\", "/").lower()
    if any(bad in text for bad in EXCLUDE):
        return set()
    tags = set()
    for tag, keywords in INCLUDE.items():
        if any(kw in text for kw in keywords):
            tags.add(tag)
    return tags


def walk_statics(db_root):
    """Yield (path) for every Static/*.yaml under the dump, any source depth."""
    for dirpath, _dirs, files in os.walk(db_root):
        if os.path.basename(dirpath).lower() != "static":
            continue
        for name in files:
            if name.lower().endswith(".yaml"):
                yield os.path.join(dirpath, name)


def build(db_root):
    tags = {tag: set() for tag in INCLUDE}
    scanned = 0
    for path in walk_statics(db_root):
        rec_id, mesh = _read_record(path)
        if not rec_id:
            continue
        scanned += 1
        for tag in classify(rec_id, mesh):
            tags[tag].add(rec_id)
    return tags, scanned


def write_yaml(tags, out_path):
    lines = [
        "# Immersive-Crafting foraging static tags for the FlexTag framework.",
        "# GENERATED from a tes3-records dump by tools/static_tags.py - do not hand-edit.",
        "# FlexTag lowercases tag names and record ids; multiple tags per record are allowed.",
    ]
    for tag in sorted(tags):
        lines.append("%s:" % tag)
        for rec_id in sorted(tags[tag], key=str.lower):
            lines.append('  - "%s"' % rec_id)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=DEFAULT_DB, help="tes3-records dump root")
    ap.add_argument("--out", default=DEFAULT_OUT, help="output FlexTag YAML")
    args = ap.parse_args()

    if not os.path.isdir(args.db):
        sys.exit("record dump not found: %s" % args.db)

    tags, scanned = build(args.db)
    write_yaml(tags, args.out)
    print("scanned %d statics from %s" % (scanned, args.db))
    for tag in sorted(tags):
        print("  %-6s %d records" % (tag, len(tags[tag])))
    print("wrote %s" % args.out)


if __name__ == "__main__":
    main()
