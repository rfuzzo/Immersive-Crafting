#!/usr/bin/env python3
"""Build the creature-edit-free Hunterwind plugin for IC's field dressing.

Hunterwind injects its carcasses by OVERRIDING 274 creature records (including
OAAB/TR/TD creatures) — the compatibility-heavy part of the mod. IC's field
dressing replaces that injection: dead creatures are dressed via the contextual
card (Hunter Knife, hold F) using the same creature->carcass mapping
(data/Immersive-Crafting/dressing/creatures.json, generated from Hunterwind's
own records).

This script strips ONLY the Creature records from hunterwind.omwaddon and
repacks it. Everything else (carcass items + butchering scripts, ingredients,
dialogue, traps) is untouched. Field dressing works with the UNPATCHED plugin
too (it takes the carcass out of the corpse's loot instead of minting one) —
the patch just removes the record overrides for a conflict-free load order.

Usage:
    python3 tools/patch_hunterwind.py /path/to/hunterwind.omwaddon \
        [--tes3util ./tes3util] [--out hunterwind_ic.omwaddon]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('plugin', help='path to hunterwind.omwaddon')
    ap.add_argument('--tes3util', default='./tes3util', help='tes3util binary')
    ap.add_argument('--out', default='hunterwind_ic.omwaddon', help='output plugin')
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([args.tes3util, 'dump', args.plugin, '-o', tmp, '-c'], check=True)
        # dump -c creates <tmp>/<plugin name>/
        dump_dir = os.path.join(tmp, os.path.splitext(os.path.basename(args.plugin))[0])
        creature_dir = os.path.join(dump_dir, 'Creature')
        if os.path.isdir(creature_dir):
            n = len(os.listdir(creature_dir))
            shutil.rmtree(creature_dir)
            print(f'stripped {n} creature records')
        else:
            print('no Creature records found (already patched?)')
        subprocess.run([args.tes3util, 'pack', dump_dir, args.out], check=True)
    print(f'wrote {args.out} — load it INSTEAD of hunterwind.omwaddon '
          f'(the original mod archive is still required for its assets)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
