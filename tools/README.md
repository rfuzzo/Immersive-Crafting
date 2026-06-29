# Ingredient tagging tools

Generate the Tagger ingredient tag file
(`../ModTags/ImmersiveCrafting_Ingredients.yaml`) from a reviewable CSV.

**Source of truth is [`../ingredients_tags.csv`](../ingredients_tags.csv)**
(columns: `id,name,tags,comment`). Edit the CSV, then regenerate the YAML.

## Regenerate the YAML after editing the CSV

From the repo root, in PowerShell:

```powershell
./tools/csv2yaml.ps1
```

Optional explicit paths:

```powershell
./tools/csv2yaml.ps1 -CsvPath ingredients_tags.csv -OutPath ModTags/ImmersiveCrafting_Ingredients.yaml
```

`csv2yaml.ps1` reads only the `id` and `tags` columns, dedupes ids (union of
tags), skips untagged rows, and writes Tagger-schema YAML (UTF-8, no BOM). The
`comment` column is editor-only metadata and is **not** written to the YAML.

The full tag set is **derived from the CSV**, so adding a new tag in the CSV
needs no script change. The `$Order` array near the top of the script only
controls display grouping; any tag not listed there is still emitted, appended
after the listed ones in alphabetical order (and reported as a hint when the
script runs). Add a new tag to `$Order` only if you want it grouped in a
specific spot.

## Notes

- Classification is hand-maintained in the CSV. After any edit, just re-run the
  command above.
- Tagger lowercases tag names and record ids, so casing in the CSV/YAML is
  cosmetic. Multiple tags per record are supported (e.g. a clam is `Meat,Fish`).
- The original awk bootstrap scripts (`classify.awk`, `parse_wiki.awk`,
  `csv2yaml.awk`) that built the first CSV from a record dump + UESP pages were
  removed; they remain available in git history if a re-bootstrap is ever needed.
