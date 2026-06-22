extends Control
## Procedural inventory icon: a 16x16 chunky-pixel shape per item TYPE, recolored
## by material tier. No sprite assets — mirrors node_icon.gd. The type is inferred
## from the item name/stats (classify()). First pass: one shape per type, recolored
## per material; refine to per-item art later.

const GRID := 16

var kind := "misc":
	set(v):
		kind = v
		queue_redraw()
var tint := Color(0.66, 0.66, 0.70):
	set(v):
		tint = v
		queue_redraw()

# Legend: '.' clear  '#' primary(tint)  '*' light  'o' dark edge  '+' wood/handle
#         '=' grey metal  '~' accent (brighter tint)  ',' shadow
const MAPS := {
	"sword": [
		"......oo........", "......##........", ".....o##*.......", ".....o##*.......",
		".....o##*.......", ".....o##*.......", ".....o##*.......", "....oo##*o......",
		"...=====o.......", "......++........", "......++........", ".....+++o.......",
		"......++........", "......oo........", "................", "................"],
	"axe": [
		"................", "......oooo......", ".....o####o.....", "....o######*....",
		"...o###*###*+...", "...o##*..##*+...", "....oo...##*+...", ".........++.....",
		"........+++.....", "........++......", ".......+++......", ".......++.......",
		"......+++.......", "......oo........", "................", "................"],
	"pickaxe": [
		"................", "..o..........o..", "..o*o......o*o..", "...=*o....o*=...",
		"....=*o..o*=....", ".....=*++*=.....", "......*++*......", ".......++.......",
		".......++.......", "......+++.......", ".......++.......", ".......++.......",
		"......+++.......", ".......oo.......", "................", "................"],
	"bow": [
		".....o##*.......", "....o#*.++......", "...o#*..++......", "...##...++......",
		"..o#*...++......", "..##....++......", "..##....++......", "..##....++......",
		"..##....++......", "..o#*...++......", "...##...++......", "...o#*..++......",
		"....o#*.++......", ".....o##*.......", "................", "................"],
	"staff": [
		".......~~.......", "......~##~......", "......*##*......", ".......##.......",
		"......+++.......", ".......++.......", ".......++.......", ".......++.......",
		".......++.......", ".......++.......", ".......++.......", ".......++.......",
		".......++.......", "......+++.......", "................", "................"],
	"shield": [
		"...oooooooooo...", "..o##########o..", "..o##*####*##o..", "..o##########o..",
		"..o###*##*###o..", "..o##########o..", "..o####**####o..", "...o########o...",
		"...o###**###o...", "....o######o....", ".....o####o.....", "......o##o......",
		".......oo.......", "................", "................", "................"],
	"helm": [
		"................", "....oooooooo....", "..oo########oo..", ".o############o.",
		".o##*######*##o.", ".o############o.", ".o##oo####oo##o.", ".o#o..o##o..o#o.",
		".o############o.", "..o##########o..", "..o##oooooo##o..", "..oo......oo....",
		"................", "................", "................", "................"],
	"body": [
		"................", "..oo......oo....", ".o##o....o##o...", ".o##oooooo##o...",
		".o##########o..", "o#####**#####o.", "o###*####*###o.", "o############o.",
		"o###*####*###o.", "o############o.", "o###*####*###o.", ".o##########o..",
		".o##########o..", "..oooooooooo....", "................", "................"],
	"legs": [
		"...oooooooooo...", "..o##########o..", "..o##########o..", "..o###*##*###o..",
		"..o##########o..", "..o####oo####o..", "..o###o..o###o..", "..o###o..o###o..",
		"..o###o..o###o..", "..o###o..o###o..", "..o###o..o###o..", "..o##o....o##o..",
		"..ooo......ooo..", "................", "................", "................"],
	"food": [
		"................", "........,.......", ".......o#o......", "......o###o.....",
		".....o##*##o....", "....o##*~*##o...", "...o##*~~~*##o..", "...o##*~~~*##o..",
		"....o##***##o...", ".....o#####+....", "......o###++....", ".......o#++.....",
		"........++......", "........+.......", "................", "................"],
	"fish": [
		"................", "................", "....oooo........", "..o#####o....o..",
		".o##*###o...o#o.", "o###*o###o.o##o.", "o##~..####oo#*o.", "o##~..#######o..",
		"o##~..####oo#*o.", ".o##*o###o.o##o.", "..o#####o...o#o.", "....oooo....o...",
		"................", "................", "................", "................"],
	"log": [
		"................", "................", "..ooooooooooo...", ".o~========~o..",
		"o*~+@+@+@+~*=o.", "o#~@+@+@+@~#=o.", "o*~+@+@+@+~*=o.", "o#~@+@+@+@~#=o.",
		".o~========~o..", "..ooooooooooo...", "................", "................",
		"................", "................", "................", "................"],
	"ore": [
		"................", "................", ".....oooo.......", "....o####o......",
		"...o##~#*##o....", "..o##~#*#~##o...", "..o#*##~#*##o...", "..o##~#*##~#o...",
		"...o##*#~##o....", "....o####o......", ".....oooo.......", "................",
		"................", "................", "................", "................"],
	"bar": [
		"................", "................", "................", "....oooooooo....",
		"...o########o...", "..o##########o..", ".o*##*####*##*o.", "o############o..",
		"oooooooooooooo..", "................", "................", "................",
		"................", "................", "................", "................"],
	"potion": [
		"................", ".......oo.......", ".......++.......", "......o##o......",
		"......o##o......", ".....o####o.....", "....o##~~##o....", "...o##~##~##o...",
		"...o#~####~#o...", "...o#~####~#o...", "...o##~~~~##o...", "....o######o....",
		".....oooooo.....", "................", "................", "................"],
	"gem": [
		"................", "................", "....oooooo......", "...o*####*o.....",
		"..o##*~~*##o....", ".o##~####~##o...", ".o#~######~#o...", "..o##~~~~##o....",
		"...o##~~##o.....", "....o####o......", ".....o##o.......", "......oo........",
		"................", "................", "................", "................"],
	"coin": [
		"................", "................", "...oo......oo...", "..o##o....o##o..",
		".o##~o...o##~o..", ".o#~#o...o#~#o..", ".o##~o..oo##~o..", "..o##oo*##~#o...",
		"...o*######~o...", "...o#~####~#o...", "...o##~~~~##o...", "....o######o....",
		".....oooooo.....", "................", "................", "................"],
	"bone": [
		"................", "...oo.....oo....", "..o##o...o##o...", "..o##ooooo##o...",
		"...o#######o....", "....o#####o.....", ".....o###o......", "......o#o.......",
		".....o###o......", "....o#####o.....", "...o##ooo##o....", "..o##o...o##o...",
		"..o##o...o##o...", "...oo.....oo....", "................", "................"],
	"ring": [
		"................", "................", "......oooo......", ".....o*~~*o.....",
		"....o##oo##o....", "...o##o..o##o...", "...o#o....o#o...", "...o#o....o#o...",
		"...o##o..o##o...", "....o##oo##o....", ".....o####o.....", "......oooo......",
		"................", "................", "................", "................"],
	"lock": [
		"................", "......oooo......", ".....o#**#o.....", ".....o#..#o.....",
		".....##..##.....", "....o######o....", "...o########o...", "...o#******#o...",
		"...o#*####*#o...", "...o#*#oo#*#o...", "...o#*#oo#*#o...", "...o#*####*#o...",
		"...o########o...", "....oo####oo....", "................", "................"],
	"misc": [
		"................", "................", "...oooooooooo...", "..o~~~~~~~~~~o..",
		".o##########o..", ".o#*######*#o..", ".o##########o..", ".o##########o..",
		".o##*####*##o..", ".o##########o..", ".o##########o..", "..o########o...",
		"...oooooooooo...", "................", "................", "................"],
	"boots": [
		"................", "................", "....ooo.........", "...o###o........",
		"...o#*#o........", "...o#*#o........", "...o#*#o........", "...o#*#oooo.....",
		"...o#*#####o....", "...o#######o....", "...o*#####*o....", "...oooooooooo...",
		"................", "................", "................", "................"],
	"gloves": [
		"................", ".....o.o.o......", "....o#o#o#o.....", "....o#####o.....",
		"...o#######o....", "...o##*#*##o....", "...o#######o....", "...o#######o....",
		"....o#####o.....", "....o##*##o.....", ".....o###o......", ".....ooooo......",
		"................", "................", "................", "................"],
	"cape": [
		"................", "....oo...oo.....", "...o##ooo##o....", "...o##*#*##o....",
		"...o#######o....", "...o#######o....", "...o##*#*##o....", "...o#######o....",
		"...o#######o....", "...o##*#*##o....", "....o#####o.....", "....o#####o.....",
		".....o###o......", ".....ooooo......", "................", "................"],
	"arrow": [
		"................", "............o*..", "...........o##*.", "..........o##*..",
		".........*##*...", "........*##*....", ".......*##*.....", "......*##*......",
		".....*##*......", "....*##*.......", "...o#*o........", "..o#*o.........",
		".oo##*.........", ".o*o*..........", "o#o............", "oo.............."],
	"heart": [
		"................", "...oo.....oo....", "..o##oo.oo##o...", ".o##~#oo#~##o...",
		"o###~####~###o.", "o##~######~##o.", "o#~########~#o.", "o############o.",
		".o##########o..", ".o##*######o...", "..o########o...", "...o######o....",
		"....o####o.....", ".....o##o......", "......oo.......", "................"],
	"fist": [
		"................", "................", "...oo.oo.oo.....", "..o##o##o##o....",
		"..o#######o....", ".o#########o...", "o###*#*#*###o..", "o############o.",
		"o##########o#o.", "o###########o..", ".o#########o...", ".o##*#*#*##o...",
		"..o########o...", "...oooooooo....", "................", "................"],
	"skull": [
		"................", "....oooooo......", "...o######o.....", "..o########o....",
		".o##########o..", ".o#oo####oo#o..", ".o#oo####oo#o..", ".o####oo####o..",
		".o##########o..", "..o#o#o#o#o#o...", "..o########o...", "...o#o#o#o#o....",
		"...oo.oo.oo....", "................", "................", "................"],
	"fire": [
		"................", "........o.......", ".......o#o......", "......o##*o.....",
		".....o##~#o.....", "....o##~~*#o....", "...o##~**~##o...", "..o##~*~~*##o...",
		"..o#~*~~~*~#o..", "..o#~~o#o~~#o..", "..o##~*#*~##o..", "...o##~#~##o...",
		"....o######o...", ".....oooooo.....", "................", "................"],
	"leaf": [
		"................", "..........oo....", ".........o##o...", "........o##*o...",
		".......o##*o....", "....oo*##*o.....", "...o#*##*o......", "..o#*##*o.......",
		"..o##*o*o.......", "..o#*o.+o.......", "...oo..+o.......", ".......+o.......",
		"......+o........", "......o.........", "................", "................"],
	"seed": [
		"................", "........o.......", ".......o#o......", "....o..o#o..o...",
		"...o#o.o#o.o#o..", "...o#~oo#oo~#o..", "....o##~#~##o...", ".....o#####o....",
		"......o###o.....", ".......o#o......", ".......o#o......", "......o###o.....",
		".....o#####o....", "....ooooooooo...", "................", "................"],
	"prayer": [
		"................", ".......oo.......", "......o##o......", "......o##o......",
		"...oo.o##o.oo...", "..o#~oo##oo~#o..", "..o#~~####~~#o..", "...o##~##~##o...",
		"....o######o....", "....o#*##*#o....", "...o########o...", "...o##~~~~##o...",
		"....o######o....", ".....oooooo.....", "................", "................"],
}


## Best-guess item type from the display name (+ a couple of stat hints).
static func classify(item_name: String, item: Dictionary = {}) -> String:
	var n := item_name.to_lower()
	if n.contains("pickaxe"):
		return "pickaxe"
	if n.contains("axe") or n.contains("hatchet"):
		return "axe"
	if n.contains("bow") or n.contains("crossbow"):
		return "bow"
	if n.contains("staff") or n.contains("wand"):
		return "staff"
	if n.contains("sword") or n.contains("scimitar") or n.contains("dagger") or n.contains("mace") \
			or n.contains("blade") or n.contains("spear") or n.contains("rapier") or n.contains("whip"):
		return "sword"
	if n.contains("shield") or n.contains("defender"):
		return "shield"
	if n.contains("helm") or n.contains("hat") or n.contains("coif") or n.contains("hood") or n.contains("mask"):
		return "helm"
	if n.contains("body") or n.contains("platebody") or n.contains("chest") or n.contains("robe") \
			or n.contains("top") or n.contains("tunic") or n.contains("chainbody"):
		return "body"
	if n.contains("legs") or n.contains("skirt") or n.contains("chaps") or n.contains("trousers") or n.contains("bottom"):
		return "legs"
	if n.contains("ring"):
		return "ring"
	if n.contains("amulet") or n.contains("necklace") or n.contains("pendant"):
		return "ring"
	if n.contains("potion") or n.contains("flask") or n.contains("vial") or n.contains("brew") \
			or n.contains("decanter") or n.contains("bottle") or n.contains("(unf)"):
		return "potion"
	if n.contains("bar") or n.contains("ingot"):
		return "bar"
	if n.contains("ore") or n.contains("rock") or n.contains("clay") or n.contains("sandstone") \
			or n.contains("geode") or n.contains("coal") or n.contains("salt"):
		return "ore"
	if n.contains("log") or n.contains("plank"):
		return "log"
	if n.contains("gem") or n.contains("diamond") or n.contains("ruby") or n.contains("sapphire") \
			or n.contains("emerald") or n.contains("crystal") or n.contains("onyx") or n.contains("amethyst"):
		return "gem"
	if n.contains("coin") or n.contains("gold") or n.contains("token"):
		return "coin"
	if n.contains("bone") or n.contains("skull") or n.contains("ashes") or n.contains("ash"):
		return "bone"
	if n.contains("raw ") or n.contains("fish") or n.contains("tuna") or n.contains("bass") \
			or n.contains("shark") or n.contains("salmon") or n.contains("trout") or n.contains("lobster") \
			or n.contains("shrimp") or n.contains("herring") or n.contains("carp") or n.contains("marlin"):
		return "fish"
	if n.contains("meat") or n.contains("beef") or n.contains("chevon") or n.contains("pie") \
			or n.contains("cake") or n.contains("bread") or n.contains("stew") or n.contains("fruit") \
			or n.contains("berry") or n.contains("berries") or n.contains("banana") or n.contains("cooked"):
		return "food"
	# Stat fallbacks for anything unnamed-but-equippable.
	if float(item.get("damage", 0)) > 0 or float(item.get("rangeDamage", 0)) > 0:
		return "sword"
	if float(item.get("damageReduction", 0)) > 0:
		return "body"
	return "misc"


## Material-tier colour from the name (covers OSRS tiers + the renamed materials).
static func material_color(item_name: String) -> Color:
	var n := item_name.to_lower()
	const TIERS := {
		"bronze": Color(0.72, 0.45, 0.26), "iron": Color(0.55, 0.56, 0.58),
		"steel": Color(0.74, 0.76, 0.80), "black": Color(0.27, 0.28, 0.31),
		"mithril": Color(0.36, 0.42, 0.74), "adamant": Color(0.32, 0.62, 0.45),
		"rune": Color(0.36, 0.66, 0.74), "dragon": Color(0.78, 0.23, 0.20),
		"gold": Color(0.86, 0.72, 0.30), "silver": Color(0.78, 0.80, 0.84),
		"azurite": Color(0.32, 0.50, 0.86), "dawnite": Color(0.90, 0.74, 0.42),
		"hemalite": Color(0.74, 0.26, 0.30), "zephite": Color(0.56, 0.80, 0.88),
		"emberite": Color(0.86, 0.45, 0.24), "glaciite": Color(0.62, 0.82, 0.92),
		"oak": Color(0.62, 0.46, 0.28), "willow": Color(0.50, 0.56, 0.34),
		"maple": Color(0.66, 0.38, 0.26), "yew": Color(0.42, 0.46, 0.30),
		"magic": Color(0.52, 0.42, 0.74),
	}
	for key: String in TIERS:
		if n.contains(key):
			return TIERS[key]
	return Color(0.62, 0.62, 0.66)


func _palette() -> Dictionary:
	var hi := tint.lightened(0.32)
	var dk := tint.darkened(0.45)
	return {
		"#": tint, "*": hi, "~": tint.lightened(0.5),
		"o": dk, ",": Color(0, 0, 0, 0.35),
		"+": Color(0.46, 0.32, 0.18), "@": Color(0.34, 0.23, 0.13),
		"=": Color(0.55, 0.56, 0.58),
	}


func _ready() -> void:
	# Anchored into a slot, the size arrives after layout — redraw then, or the
	# first (size 0) draw leaves the slot blank.
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var map: Array = MAPS.get(kind, MAPS["misc"])
	var px := minf(size.x, size.y) / float(GRID)
	var ox := (size.x - px * GRID) * 0.5
	var oy := (size.y - px * GRID) * 0.5
	var pal := _palette()
	for y: int in map.size():
		var row: String = map[y]
		for x: int in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var col: Variant = pal.get(ch)
			if col == null:
				continue
			draw_rect(Rect2(Vector2(ox + x * px, oy + y * px), Vector2(px + 0.6, px + 0.6)), col)
