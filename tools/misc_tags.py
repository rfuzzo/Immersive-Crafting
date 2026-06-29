#!/usr/bin/env python3
"""Build a tag CSV for misc items from a record dump.

Walks a dump of MiscItem records (`<root>/<Mod>/MiscItem/*.yaml`) and writes one
CSV with columns: id, name, tags, mod (the first folder under the root, e.g.
Morrowind / Bloodmoon / Tamriel_Data). Every record is included; rows that match
no rule simply have an empty tags cell.

Tagging rules (keyword matching is whole-word, case-insensitive, plural-aware):
  - key      : id starts with "key_", data.flags is KEY, or "key" appears in the name
  - basket   : basket
  - bottle   : bottle, flask
  - bucket   : bucket
  - ladle    : ladle
  - cup      : goblet, cup, tankard, pitcher, jug
  - plate    : plate
  - fork     : fork
  - knife    : knife, knives
  - bowl     : bowl
  - teapot   : teapot
  - cloth    : cloth
  - shell    : shell
  - pot      : pot
  - spoon    : spoon
  - hammer   : hammer

Usage:
    py tools/misc_tags.py [DUMP_DIR] [OUT_CSV]
Defaults: "D:\\modding tes3\\_test\\_out\\MISC" -> misc_tags.csv
"""
import csv
import os
import re
import sys

DEFAULT_IN = r"D:\modding tes3\_test\_out\MISC"
DEFAULT_OUT = "misc_tags.csv"

# tag -> keyword list. Matched as whole words, case-insensitive, optional 's'.
KEYWORD_TAGS = {
    "basket": ["basket"],
    "bottle": ["bottle", "flask"],
    "bucket": ["bucket"],
    "ladle":  ["ladle"],
    "cup":    ["goblet", "cup", "tankard", "pitcher", "jug"],
    "plate":  ["plate"],
    "fork":   ["fork"],
    "knife":  ["knife", "knives"],
    "bowl":   ["bowl"],
    "teapot": ["teapot"],
    "cloth":  ["cloth"],
    "shell":  ["shell"],
    "pot":    ["pot"],
    "spoon":  ["spoon"],
    "hammer": ["hammer"],
}
KEY_NAME_RE = re.compile(r"\bkeys?\b", re.I)
PATTERNS = {
    tag: re.compile(r"\b(?:" + "|".join(kw + "s?" for kw in kws) + r")\b", re.I)
    for tag, kws in KEYWORD_TAGS.items()
}


def strip_quotes(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        inner = value[1:-1]
        if value[0] == "'":
            inner = inner.replace("''", "'")  # YAML single-quote escape
        return inner
    return value


def read_record(path):
    """Pull the top-level id/name and whether data.flags marks this as a KEY."""
    rid = name = None
    is_key = False
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            if rid is None and line.startswith("id:"):
                rid = strip_quotes(line[3:])
            elif name is None and line.startswith("name:"):
                name = strip_quotes(line[5:])
            elif line[:1].isspace() and line.strip().lower().startswith("flags:"):
                # indented flags line lives under data: (top-level flags is unindented)
                if line.split(":", 1)[1].strip().strip("'\"").upper() == "KEY":
                    is_key = True
    return rid or "", name or "", is_key


def tags_for(rid, name, is_key):
    tags = []
    if is_key or rid.lower().startswith("key_") or KEY_NAME_RE.search(name):
        tags.append("key")
    low = name.lower()
    for tag, pattern in PATTERNS.items():
        if pattern.search(low):
            tags.append(tag)
    return tags


def main():
    dump_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IN
    out_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    rows = []
    for dirpath, _dirs, files in os.walk(dump_dir):
        for fname in files:
            if not fname.lower().endswith(".yaml"):
                continue
            path = os.path.join(dirpath, fname)
            rid, name, is_key = read_record(path)
            if not rid:
                continue
            mod = os.path.relpath(path, dump_dir).split(os.sep)[0]
            tags = tags_for(rid, name, is_key)
            rows.append((rid, name, ",".join(tags), mod))

    rows.sort(key=lambda r: r[1].lower())  # by name

    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "tags", "mod"])
        writer.writerows(rows)

    tagged = sum(1 for r in rows if r[2])
    print(f"Wrote {out_path} - {len(rows)} records, {tagged} tagged.")


if __name__ == "__main__":
    main()
