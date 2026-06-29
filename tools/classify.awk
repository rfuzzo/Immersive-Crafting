#!/usr/bin/awk -f
# Classify ingredient names into food + non-food category tags.
# Input : id \t name \t mod   (TSV)
# Output: id \t name \t Tag1,Tag2 \t mod
# Multi-tag; keyword/substring rules with word boundaries where risky.

BEGIN { FS="\t"; OFS="\t"; ORDER="Meat Fish Vegetable Fruit Mushroom Egg Dairy Grain Spice Sweet Liquid Gem Ore Mineral CreaturePart Pelt Hide Leather Feather Claw Plant" }

function add(tag){ T[tag]=1 }

{
  id=$1; name=$2; mod=$3
  n=tolower(name)
  delete T

  # ---------- FOOD ----------
  if (n ~ /\<(meat|beef|mutton|ham|pork|bacon|venison|jerky|flesh|lard|liver|sausage|tripe|corprusmeat|chicken|drumstick|fat)\>/) add("Meat")
  if (n ~ /\<(fish|cod|salmon|tuna|barracuda|angelfish|parrotfish|eel|filet|fillet|clam|crab|lobster|oyster|shrimp|prawn|scallop|mussel|sardine|herring|trout|carp|pike|perch|catfish|tailfin|longfin|slaughterfish|dolphin|siyat|starfish|sturgeon|roe|stridfish|spearmouth|jellyfish|gillsieve)\>/) add("Fish")
  if (n ~ /\<(yam|carrot|cabbage|leek|onion|garlic|potato|corn|bean|beans|pea|peas|pumpkin|gourd|radish|turnip|beet|celery|lettuce|marshmerrow|hackle-lo|scallion|spinach|kale|squash|cucumber|arrowroot|tomato)\>/) add("Vegetable")
  if (n ~ /\<(apple|pear|fig|figs|mango|grape|grapes|orange|lemon|peach|plum|cherry|melon|coconut|olive|olives|banana|apricot|gooseberry|gooseberries|blackberry|blackberries|blueberry|blueberries|comberry|chokeberry|raspberry|raspberries|strawberry|strawberries|cranberry|cranberries|date|raisin|fruit|berries|berry|currant|pomegranate|pineapple|kiwi|muscat|gorapple|altachi|lotte)\>/) add("Fruit")
  if (n ~ /\<(mushroom|mushrooms|bolete|russula|amanita|polypore|fungus|fungal|chanterelle|morel|morchella|truffle|hypha|shroom|toadstool|cap|caps|funnel|saddle|bluefoot|dustcap|mindcap|stinkhorn|coprinus|corpinus|fomentarius|hydnum|exidia|ramaria|mycena|urnula|bloat|bungler)\>/) add("Mushroom")
  if (n ~ /\<(egg|eggs)\>/) add("Egg")
  if ((n ~ /\<(cheese|butter|cream|yogurt|curd)\>/) || (n ~ /milk/ && n !~ /thistle/)) add("Dairy")
  if (n ~ /\<(bread|flour|dough|wheat|rye|oat|oats|rice|grain|biscuit|cracker|hardtack|noodle|noodles|pastry|loaf|bun|cornbread|longbread|ironrye|saltrice|wickwheat|dumpling|porridge|pie|scone|tart|sfiha|sweetroll|crumpet)\>/) add("Grain")
  if (n ~ /\<(pepper|peppercorn|cinnamon|ginger|cardamon|cardamom|anise|fennel|nigella|mustard|cumin|clove|cloves|nutmeg|saffron|paprika|basil|thyme|oregano|coriander|seasoning|spice|seeds|seed|salt|turmeric)\>/) add("Spice")
  if (n ~ /\<(honey|sugar|chocolate|jam|jelly|candy|syrup|custard|muffin|cake|marmalade|toffee|caramel|sweet|sweetroll|honeycomb)\>/ && n !~ /tea cake/) add("Sweet")
  if ((n ~ /\<(water)\>/ && n !~ /(lily|lilly|hyacinth|lettuce|weed|strider|cress)/) || n ~ /\<(oil|wine|ale|mead|juice|broth|brandy|cider|liquor|grog|sujamma|mazte|flin|shein|vinegar)\>/ || (n ~ /\<tea\>/ && n !~ /(cake|leaf|leaves)/)) add("Liquid")

  # ---------- NON-FOOD ----------
  if (n ~ /\<(diamond|emerald|ruby|sapphire|amethyst|topaz|opal|garnet|pearl|amber|jade|citrine|aquamarine|agate|onyx|malachite|moonstone|tourmaline|lapis|obsidian|ametrine|beryl|chrysoprase|peridot|turquoise|quartz|gem|ivory|coral|jet|spinel|diopside|crystal|bloodstone|tektite|firejade|chrysophant|asteria)\>/) add("Gem")
  if (n ~ /\<(ore|ingot|gold|silver|tin|zinc|ebony|stalhrim|orichalc|metal|glass|copper|iron|brass|cobalt)\>/) add("Ore")
  if (n ~ /\<(salts|bonemeal|chalk|coal|charcoal|mercury|sulfur|sulphur|antimony|lodestone|meteor|gravedust|gypsum|saltpeter|niter|cinnabar|caput|caustic|arsenic|realgar|verdigris|vermilion|ochre|dye|musk|dust|powder|gel)\>/) add("Mineral")
  if (n ~ /\<(hide|pelt|fur|leather|claw|talon|tusk|horn|antler|teeth|tooth|fang|scale|scales|shell|chitin|heart|eyeball|eye|wing|feather|hair|bone|skin|venom|gland|poison|blood|tongue|beak|hoof|paw|webbing|thorax|tail|ear|earwax|stinger|spine|bristle|tentacle|ectoplasm|wax|silk|fiber|hide|feathers|plume|plumes|wool|carapace|membrane|cuttle|weepings|gravetar)\>/) add("CreaturePart")
  # CreaturePart subtypes (fine-grained; kept alongside the CreaturePart umbrella)
  if (n ~ /\<(pelt|pelts)\>/) add("Pelt")
  if (n ~ /\<(hide|hides)\>/) add("Hide")
  if (n ~ /\<(leather)\>/) add("Leather")
  if (n ~ /\<(feather|feathers|plume|plumes|quill|quills)\>/) add("Feather")
  if (n ~ /\<(claw|claws|talon|talons)\>/) add("Claw")
  if (n ~ /\<(flower|flowers|petal|petals|leaf|leaves|sprig|blossom|pollen|bark|lichen|grass|weed|stalk|frond|fronds|thistle|nettle|rose|lily|kanet|root|pod|fern|vine|thorn|moss|seed|seeds|berries|berry|sedge|reed|herb|bloom|nectar|resin|sap|bulb|tuber|pistil|anther|stamen|sprout|shoot|spore|wort|bell|sage|clover|mantle|smock|mistletoe|nightshade|belladonna|nirnroot|bloodgrass|pulp|flax|hibiscus|lavender|heather|ginseng|mandrake|monkshood|hemlock|hellebore|foxglove|tobacco|nut|nuts|hyacinth|cress|lily|lilly|stalks|slime|twinstipe|chokeweed|heartwood|muck|scathecraw|roobrush|evenfall|roland)\>/) add("Plant")

  # assemble in stable order
  out=""; m=split(ORDER, ord, " ")
  for(i=1;i<=m;i++){ if(T[ord[i]]){ out=(out=="")?ord[i]:out","ord[i] } }
  print id, name, out, mod
}
