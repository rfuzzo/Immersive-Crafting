# Ingredient tagging tools

Scripts that build the Tagger ingredient tag file
(`../ModTags/ImmersiveCrafting_Ingredients.yaml`) from a reviewable CSV.

**Source of truth is [`../ingredients_tags.csv`](../ingredients_tags.csv)**
(columns: `id,name,tags,comment`). Edit the CSV, then regenerate the YAML.
All scripts are GNU awk (`gawk`); on Windows run them from Git Bash.

## Day-to-day: regenerate the YAML after editing the CSV

```bash
gawk -f tools/csv2yaml.awk ingredients_tags.csv > ModTags/ImmersiveCrafting_Ingredients.yaml
```

`csv2yaml.awk` reads only the `id` and `tags` columns, dedupes ids (union of
tags), skips untagged rows, and emits Tagger-schema YAML. The `comment` column
is editor-only metadata and is **not** written to the YAML. The canonical tag
list and emission order are defined by the `ORDER` variable at the top of the
script — add new tags there.

## One-off: re-bootstrapping the CSV from a fresh record dump

These were used to create the initial CSV and are kept for reproducibility.

- `classify.awk` — keyword classifier. Input: TSV of `id<TAB>name<TAB>mod`
  (dumped ingredient records). Output: `id<TAB>name<TAB>tags`. Edit the
  per-category keyword rules here to change classifications.
- `parse_wiki.awk` — parses a saved UESP `*:Ingredients` HTML page into
  `game<TAB>id<TAB>name<TAB>description<TAB>effects`. Run per page with
  `-v GAME=<name>`. The `description` field feeds the CSV `comment` column.

Rough bootstrap flow (see git history of the CSV for the exact joins):

```bash
# 1. classify the dump
gawk -f tools/classify.awk ingredients.tsv > classified.tsv
# 2. parse each downloaded UESP page for descriptions
for g in morrowind tribunal bloodmoon tamriel_data tamriel_rebuilt; do
  gawk -v GAME=$g -f tools/parse_wiki.awk wiki/$g.html
done > wiki_ingredients.tsv
# 3. join descriptions in as the comment column, dedupe by id -> ingredients_tags.csv
# 4. tools/csv2yaml.awk ingredients_tags.csv -> the YAML
```

## Notes

- Classification is keyword-based and imperfect; the CSV is meant to be
  hand-corrected. After any manual CSV edit, just re-run step "Day-to-day".
- Tagger lowercases tag names and record ids, so casing in the CSV/YAML is
  cosmetic. Multiple tags per record are supported (e.g. a clam is `Meat,Fish`).
