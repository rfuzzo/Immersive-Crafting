#!/usr/bin/env python3
"""Generate the Tagger ingredient YAML from ingredients_tags.csv.

The CSV (columns: id,name,tags,comment) is the source of truth. Only id + tags
are emitted; the comment column is editor-only metadata. The tag list is
extracted straight from the CSV (no predefined order). Ids are deduped, unioning
their tags. Untagged rows are skipped.

Usage:
    py tools/csv2yaml.py [CSV_PATH] [OUT_PATH]
Defaults: ingredients_tags.csv -> ModTags/ImmersiveCrafting_Ingredients.yaml
"""
import csv
import os
import sys

DEFAULT_CSV = "ingredients_tags.csv"
DEFAULT_OUT = "ModTags/ImmersiveCrafting_Ingredients.yaml"


def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CSV
    out_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    records = {}      # id -> [tags] (deduped, first-seen order)
    all_tags = set()  # every distinct tag used

    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rid = (row.get("id") or "").strip()
            tags_field = (row.get("tags") or "").strip()
            if not rid or not tags_field:
                continue
            bucket = records.setdefault(rid, [])
            for tag in tags_field.split(","):
                tag = tag.strip()
                if tag:
                    all_tags.add(tag)
                    if tag not in bucket:
                        bucket.append(tag)
            if not bucket:
                del records[rid]

    tag_list = sorted(all_tags, key=str.lower)

    lines = [
        "# Immersive-Crafting tag definitions for the Tagger framework (S3cret St4sh).",
        f"# GENERATED from {os.path.basename(csv_path)} by tools/csv2yaml.py - edit the CSV, then regenerate. Do not hand-edit.",
        "# Tagger lowercases tag names and record ids; multiple tags per record are allowed.",
        "tags:",
    ]
    lines += [f'  - "{tag}"' for tag in tag_list]
    lines.append("applied_tags:")
    for rid, tags in records.items():
        joined = ", ".join(f'"{tag}"' for tag in tags)
        lines.append(f'  "{rid}": [{joined}]')

    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Wrote {out_path} - {len(records)} tagged records, {len(tag_list)} tags.")


if __name__ == "__main__":
    main()
