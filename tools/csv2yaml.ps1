<#
.SYNOPSIS
  Generate the Tagger ingredient YAML from ingredients_tags.csv (the source of truth).

.DESCRIPTION
  CSV columns: id,name,tags,comment. Only id + tags are emitted to YAML; the
  comment column is editor-only metadata. Ids are deduped (union of tags).

  The full tag set is derived from the CSV, so adding a new tag in the CSV needs
  no script change - it flows through automatically and is never dropped. Tags
  are ordered by the canonical $Order below for readability; any tag not listed
  there is appended afterwards in alphabetical order (and reported as a hint).

  Tagger lowercases tag names and record ids, so casing is cosmetic. Multiple
  tags per record are supported.

.EXAMPLE
  ./tools/csv2yaml.ps1
  ./tools/csv2yaml.ps1 -CsvPath ingredients_tags.csv -OutPath ModTags/ImmersiveCrafting_Ingredients.yaml
#>
[CmdletBinding()]
param(
    [string]$CsvPath = "ingredients_tags.csv",
    [string]$OutPath = "ModTags/ImmersiveCrafting_Ingredients.yaml"
)

$ErrorActionPreference = 'Stop'

# Preferred display order (grouped). Tags not listed here are still emitted -
# appended alphabetically after these - so the CSV can grow without edits here.
$Order = @(
    'Meat','Fish','Vegetable','Fruit','Mushroom','Egg','Dairy','Grain','Spice',
    'Seed','Sweet','Liquid','Tea','Meal',
    'Plant','Flower','Pulp','Resin','Slime',
    'CreaturePart','Pelt','Hide','Leather','Feather','Claw','Scale','Venom',
    'Gem','Ore','Mineral','Salt','Dust'
)
$rank = @{}
for ($i = 0; $i -lt $Order.Count; $i++) { $rank[$Order[$i]] = $i }

# Sort key: canonical rank if known, else after all known tags, then alphabetical.
function Get-OrderedTags {
    param([System.Collections.Generic.HashSet[string]]$Tags)
    $Tags | Sort-Object `
        @{ Expression = { if ($rank.ContainsKey($_)) { $rank[$_] } else { [int]::MaxValue } } }, `
        @{ Expression = { $_ } }
}

$rows = Import-Csv -Path $CsvPath

# Dedupe by id, union tags, preserve first-seen (CSV) order. Track all tags seen.
$byId = [ordered]@{}
$allTags = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $rows) {
    $id = $r.id
    if ([string]::IsNullOrWhiteSpace($r.tags)) { continue }
    if (-not $byId.Contains($id)) { $byId[$id] = [System.Collections.Generic.HashSet[string]]::new() }
    foreach ($t in ($r.tags -split ',')) {
        $t = $t.Trim()
        if ($t) { [void]$byId[$id].Add($t); [void]$allTags.Add($t) }
    }
}

$q = '"'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Immersive-Crafting ingredient tag definitions for the Tagger framework (S3cret St4sh).')
$lines.Add('# GENERATED from ingredients_tags.csv by tools/csv2yaml.ps1 - edit the CSV, then regenerate. Do not hand-edit.')
$lines.Add('# Tagger lowercases tag names and record ids; multiple tags per record are allowed.')
$lines.Add('tags:')
foreach ($t in (Get-OrderedTags $allTags)) { $lines.Add('  - ' + $q + $t + $q) }
$lines.Add('applied_tags:')
foreach ($id in $byId.Keys) {
    $list = ((Get-OrderedTags $byId[$id]) | ForEach-Object { $q + $_ + $q }) -join ', '
    $lines.Add('  ' + $q + $id + $q + ': [' + $list + ']')
}

# Resolve to an absolute path (WriteAllText ignores the PowerShell location),
# then write UTF-8 without BOM and LF line endings.
if (-not [System.IO.Path]::IsPathRooted($OutPath)) {
    $OutPath = Join-Path (Get-Location).Path $OutPath
}
$text = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($OutPath, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("Wrote {0} - {1} tagged records, {2} tags." -f $OutPath, $byId.Count, $allTags.Count)
$extra = (Get-OrderedTags $allTags) | Where-Object { -not $rank.ContainsKey($_) }
if ($extra) { Write-Host ("Note: tags not in canonical `$Order (appended alphabetically): {0}" -f ($extra -join ', ')) }
