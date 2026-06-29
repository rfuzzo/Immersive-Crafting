# Generate the Tagger ingredient YAML from ingredients_tags.csv (the source of truth).
# CSV columns: id,name,tags,comment  (all fields double-quoted, "" = literal quote).
# Only id + tags are emitted to YAML; comment is editor-only metadata.
BEGIN{
  ORDER="Meat Fish Vegetable Fruit Mushroom Egg Dairy Grain Spice Sweet Liquid Gem Ore Mineral CreaturePart Pelt Hide Leather Feather Claw Plant"
}
function unq(s){ gsub(/^"|"$/,"",s); gsub(/""/,"\"",s); return s }
NR==1{ next }                                   # skip header
{
  line=$0
  sub(/^"/,"",line); sub(/"$/,"",line)
  n=split(line, f, /","/)
  id=f[1]; tags=f[3]
  if(tags=="") next                             # untagged -> not emitted
  # union/dedupe tags for this id, preserve canonical order
  delete seen
  t=split(tags, a, ",")
  for(i=1;i<=t;i++) seen[a[i]]=1
  if(!(id in have)){ order[++k]=id; have[id]=1 }
  for(i=1;i<=t;i++) tagset[id SUBSEP a[i]]=1
}
END{
  print "# Immersive-Crafting ingredient tag definitions for the Tagger framework (S3cret St4sh)."
  print "# GENERATED from ingredients_tags.csv — edit the CSV, then regenerate. Do not hand-edit."
  print "# Tagger lowercases tag names and record ids; multiple tags per record are allowed."
  print "tags:"
  m=split(ORDER, ord, " ")
  for(i=1;i<=m;i++) print "  - \"" ord[i] "\""
  print "applied_tags:"
  for(j=1;j<=k;j++){ id=order[j]; list=""
    for(i=1;i<=m;i++) if(tagset[id SUBSEP ord[i]]) list=(list=="")?"\""ord[i]"\"":list", \""ord[i]"\""
    printf "  \"%s\": [%s]\n", id, list
  }
}
