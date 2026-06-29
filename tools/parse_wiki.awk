# Parse a UESP ingredient page into: game \t id \t name \t description \t effects
# One ingredient per <tr ...> record. Uses index/substr to avoid lazy regex.
BEGIN { RS="<tr "; OFS="\t" }

function between(s, a, b,    p, q) {
  p = index(s, a); if (p==0) return ""
  s = substr(s, p+length(a))
  q = index(s, b); if (q==0) return ""
  return substr(s, 1, q-1)
}

{
  rec=$0

  # name: ...padding-top: 32px;"><a href="...">NAME</a>
  if (match(rec, /padding-top: 32px;"><a href="[^"]*"[^>]*>([^<]*)<\/a>/, mn)) name=mn[1]; else next
  gsub(/&amp;/,"\\&",name)

  # id: text between  smaller;">  and  </div>  (strip <wbr> tags + whitespace)
  id = between(rec, "font-size: smaller;\">", "</div>")
  gsub(/<wbr[^>]*>/,"",id); gsub(/[[:space:]]+/,"",id)
  if (id=="") next

  # description: text in the  max-width: 50ch  td
  desc = between(rec, "max-width: 50ch;\">", "</td>")
  gsub(/<[^>]*>/,"",desc); gsub(/&#160;/," ",desc); gsub(/&amp;/,"\\&",desc)
  gsub(/[\r\n\t]+/," ",desc); gsub(/^ +| +$/,"",desc)

  # effects: each EffectPos/Neg div ends with  >Name</a></div>
  eff=""; n=split(rec, parts, /class="Effect/)
  for(i=2;i<=n;i++){ if(match(parts[i], />([^<]+)<\/a><\/div>/, me)){ e=me[1]; gsub(/&#160;/," ",e); eff=(eff=="")?e:eff"; "e } }

  print GAME, id, name, desc, eff
}
