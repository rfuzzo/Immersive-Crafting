# Tagging tools

## Foraging static tags (trees, rocks)

`static_tags.py` generates the FlexTag file
`../ModTags/ImmersiveCrafting_Statics.yaml` used by gaze foraging. It scans a
tes3-records dump and classifies every `Static` by keyword-matching its id and
mesh path.

From the repo root (dump assumed at `../tes3-records`):

```sh
py tools/static_tags.py                 # --db ../tes3-records --out ModTags/ImmersiveCrafting_Statics.yaml
py tools/static_tags.py --db /path/to/tes3-records
```

- `tree` matches the substring `tree` (covers `flora_bc_tree_*`, `ashtree`,
  `treestump`, …).
- `rock` matches `rock`/`boulder`, minus structural/scenery uses (bridges,
  stairs, doorrocks, rock-nest columns, minecart fills — see `EXCLUDE`).
- Classification is automatic (no CSV); to tune coverage, edit `INCLUDE` /
  `EXCLUDE` in the script and regenerate. Standard library only.

The generated file is marked `# GENERATED … do not hand-edit`; the `tree`/`rock`
target tags must **not** be duplicated in the hand-maintained
`ImmersiveCrafting.yaml` (which now holds only tool tags like `axe`/`shovel`).

## Ingredient tags

Generate the FlexTag ingredient tag file
(`../ModTags/ImmersiveCrafting_Ingredients.yaml`) from a reviewable CSV.

**Source of truth is [`../ingredients_tags.csv`](../ingredients_tags.csv)**
(columns: `id,name,tags,comment`). Edit the CSV, then regenerate the YAML.

## Regenerate the YAML after editing the CSV

From the repo root:

```sh
py tools/csv2yaml.py
```

Optional explicit paths:

```sh
py tools/csv2yaml.py ingredients_tags.csv ModTags/ImmersiveCrafting_Ingredients.yaml
```

`csv2yaml.py` reads only the `id` and `tags` columns, dedupes ids (union of
tags), skips untagged rows, and writes FlexTag-schema YAML (UTF-8, no BOM, LF
endings) - a flat mapping of tag name to a list of record ids, e.g.:

```yaml
Meat:
  - "ingred_rat_meat_01"
```

The `comment` column is editor-only metadata and is **not** written to the YAML.

The tag list is **extracted directly from the CSV** (sorted alphabetically), so
adding a new tag in the CSV needs no script change. Ids under each tag are sorted
alphabetically; ordering is cosmetic since FlexTag stores tags as a set.

## Notes

- Classification is hand-maintained in the CSV. After any edit, just re-run the
  command above.
- FlexTag lowercases tag names and record ids, so casing in the CSV/YAML is
  cosmetic. Multiple tags per record are supported (e.g. a clam is `Meat,Fish`).
- Requires Python 3 (`py` launcher on Windows). Standard library only.
- Earlier awk/PowerShell versions of this generator (and the one-off bootstrap
  scripts) are in git history if ever needed.
