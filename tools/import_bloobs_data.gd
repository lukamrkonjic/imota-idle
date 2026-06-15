extends SceneTree
## Imports the Bloobs Adventure Idle data export into slim res://data/*.json files.
## Run headless:
##   godot --headless --path C:/Dev/bloobs-godot --script res://tools/import_bloobs_data.gd
##
## Reads from EXPORT_DIR (absolute path on this machine), strips Unity asset
## bookkeeping (m_Script, image refs, pathIds), parses drop strings into
## structured tables, and parses raw text lists (trees) that have no JSON form.

const EXPORT_DIR := "C:/Dev/aldenfall/data/bloobs-export"
const OUT_DIR := "res://data"

const ContentId := preload("res://scripts/content/content_id.gd")
const IdRegistry := preload("res://scripts/content/id_registry.gd")
const SkillRemap := preload("res://scripts/content/skill_remap.gd")
const ContentRename := preload("res://scripts/content/content_rename.gd")
var _rename_map: Dictionary = {}

# Mints/preserves opaque numeric ids; re-imports keep every existing assignment
# and only mint for genuinely new content. See scripts/content/id_registry.gd.
var _reg: IdRegistry

# Per-action XP for gather nodes is scene-embedded in Unity (Trees.xpOnChop et
# al) and absent from the export — see docs/DATA_GAPS.md. Calibrated against
# the code default (25 XP at level 1).
static func gather_xp_for_level(level: int) -> int:
	return int(round(25.0 + float(level - 1) * 1.5))


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_reg = IdRegistry.load_or_new()
	_rename_map = ContentRename.load_map()
	import_xp_table()
	var items := import_items()
	import_enemies()
	# Craftable gear (swords, armor, ...) only exists as recipe assets; the
	# recipe entry carries the output item's stats, so recipes also feed the
	# item index.
	import_recipes(items)
	for name: String in items:
		# Mint the id from the original name slug, then remap skill keys (spec §2).
		items[name]["id"] = _reg.mint("items", ContentId.item_id(name))
		items[name]["displayName"] = ContentRename.rename(name, _rename_map)
		for field: String in ["reqs", "bonusXp"]:
			items[name][field] = _remap_skill_keys(items[name].get(field, {}))
	write_json("items.json", items)
	print("items (incl. recipe outputs): %d" % items.size())
	import_gather_nodes()
	write_shop_stock(items)
	_reg.save()
	_merge_aliases()
	print("Import finished in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


## Merge the registry's slug -> numeric maps into content_aliases.json so live
## saves holding old slug ids resolve to the frozen numeric ids on load.
func _merge_aliases() -> void:
	var path := OUT_DIR + "/content_aliases.json"
	var aliases: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			aliases = parsed
	var minted: Dictionary = _reg.to_aliases()
	for bucket: String in minted:
		if not aliases.has(bucket):
			aliases[bucket] = {}
		for slug: String in minted[bucket]:
			aliases[bucket][slug] = minted[bucket][slug]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(aliases, "  ", false))
	f.close()


## Remaps the skill keys of a reqs/bonusXp dict to the Imota roster, summing when
## two old skills fold into one (imbuing+soulbinding -> crafting).
func _remap_skill_keys(src: Dictionary) -> Dictionary:
	var dst := {}
	for skill: String in src:
		var ns := SkillRemap.to_new(skill)
		dst[ns] = src[skill] if not dst.has(ns) else dst[ns] + src[skill]
	return dst


func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s" % path)
		quit(1)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("Cannot parse %s" % path)
		quit(1)
	return parsed


func write_json(name: String, data: Variant) -> void:
	var f := FileAccess.open(OUT_DIR + "/" + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("wrote %s/%s" % [OUT_DIR, name])


func import_xp_table() -> void:
	var raw: Dictionary = read_json(EXPORT_DIR + "/json/xp-tables.json")[0]
	var table: Array = raw["xpRequired"]["Array"]
	write_json("xp_table.json", {"maxLevel": raw["maxLevel"], "xpRequired": table})


static func slim_item(e: Dictionary) -> Dictionary:
	var slim := {
		"name": e.get("itemName", ""),
		"value": e.get("value", 0),
		"info": e.get("information", ""),
		"accuracy": e.get("accuracy", 0.0),
		"damage": e.get("damage", 0),
		"damageReduction": e.get("damageReduction", 0.0),
		"progress": e.get("progress", 0),
		"rangeDamage": e.get("rangeDamage", 0),
		"magicDamage": e.get("magicDamage", 0),
		"rangeAccuracy": e.get("rangeAccuracy", 0.0),
		"magicAccuracy": e.get("magicAccuracy", 0.0),
		"runSpeed": e.get("runSpeed", 0.0),
		"critChance": e.get("critalChance", 0.0),
		"reqs": {},
		"bonusXp": {},
	}
	var req_map := {
		"woodcutting": "requiredWoodcuttingLevel", "mining": "requiredMiningLevel",
		"fishing": "requiredFishingLevel", "foraging": "requiredForagingLevel",
		"attack": "requiredAttackLevel", "magic": "requiredMagicLevel",
		"ranged": "requiredRangeLevel", "defence": "requiredDefenceLevel",
	}
	for skill: String in req_map:
		var v: float = e.get(req_map[skill], 0)
		if v > 0:
			slim["reqs"][skill] = int(v)
	var bonus_map := {
		"hitpoints": "hitPointsBonusXp", "attack": "attackBonusXP",
		"strength": "strengthBonusXp", "defence": "defenceBonusXP",
		"ranged": "rangeBonusXP", "magic": "magicBonusXP",
		"devotion": "devotionBonusXp", "beastmastery": "beastMateryBonusXp",
		"dexterity": "dexterityBonusXp", "foraging": "foragingBonusXp",
		"herbology": "herbologyBonusXp", "crafting": "craftingBonusXp",
		"fletching": "bowCraftingBonusXp", "imbuing": "imbuingBonusXp",
		"thieving": "thievingBonusXp", "soulbinding": "soulBindingBonusXp",
		"mining": "miningBonusXp", "smithing": "smithingBonusXp",
		"fishing": "fishingBonusXp", "cooking": "cookingBonusXp",
		"woodcutting": "woodcuttingBonusXp", "firemaking": "firemakingBonusXp",
		"tracking": "trackingBonusXp", "homesteading": "homesteadingBonusXp",
	}
	for skill: String in bonus_map:
		var v: float = e.get(bonus_map[skill], 0.0)
		if v != 0.0:
			slim["bonusXp"][skill] = v
	return slim


func import_items() -> Dictionary:
	var raw: Array = read_json(EXPORT_DIR + "/json/items-full.json")
	var items := {}
	for e: Dictionary in raw:
		var item_name: String = e.get("itemName", "")
		if item_name.is_empty():
			continue
		# Duplicate itemNames exist (suffixed asset variants like "Amberleaf HS");
		# prefer the asset whose m_Name matches the itemName exactly.
		if not items.has(item_name) or e.get("m_Name", "") == item_name:
			items[item_name] = slim_item(e)
	print("items from items-full: %d" % items.size())
	return items


## Drop strings come in two rarity notations:
##   "Bones (100%)", "Imbued Substance (2-4 43.8%)"        — percent
##   "Golden Fleece (1 in 10k)", "Uncut Opal (25-55 1 in 278)" — 1-in-N
static func parse_drops(drops_str: String) -> Array:
	var out: Array = []
	var pct_re := RegEx.create_from_string("^(.*?)\\s*\\((?:(\\d+)-(\\d+)\\s+)?([\\d.]+)%\\)$")
	var ratio_re := RegEx.create_from_string("^(.*?)\\s*\\((?:(\\d+)-(\\d+)\\s+)?(\\d+)\\s+in\\s+([\\d.]+)(k?)\\)$")
	for part: String in drops_str.split("),"):
		part = part.strip_edges()
		if part.is_empty():
			continue
		if not part.ends_with(")"):
			part += ")"
		var chance := 0.0
		var m := pct_re.search(part)
		if m != null:
			chance = float(m.get_string(4)) / 100.0
		else:
			m = ratio_re.search(part)
			if m == null:
				push_warning("Unparsed drop entry: '%s'" % part)
				continue
			var denom := float(m.get_string(5)) * (1000.0 if m.get_string(6) == "k" else 1.0)
			chance = float(m.get_string(4)) / denom
		var min_q := 1
		var max_q := 1
		if not m.get_string(2).is_empty():
			min_q = int(m.get_string(2))
			max_q = int(m.get_string(3))
		out.append({
			"item": m.get_string(1),
			"min": min_q,
			"max": max_q,
			"chance": chance,
		})
	return out


func import_enemies() -> void:
	var raw: Array = read_json(EXPORT_DIR + "/json/enemies.json")
	var enemies := {}
	for e: Dictionary in raw:
		var f: Dictionary = e["fields"]
		enemies[e["name"]] = {
			"name": e["name"],
			"level": int(f.get("Combat Level", "1")),
			"style": f.get("Combat Style", "Melee"),
			"damage": float(f.get("Attack Damage", "1")),
			"cooldown": float(f.get("Cooldown", "2.4")),
			"accuracy": float(f.get("Accuracy", "50%").trim_suffix("%")) / 100.0,
			"damageReduction": float(f.get("Damage Reduction", "0")),
			"critChance": float(f.get("Crit Chance", "1%").trim_suffix("%")) / 100.0,
			"critMultiplier": float(f.get("Crit Multiplier", "1.15")),
			"combatXp": float(f.get("Combat XP", "0")),
			"hitpointsXp": float(f.get("HitPoints XP", "0")),
			"maxHealth": float(f.get("Max Health", "4")),
			"beastMasteryXp": float(f.get("Beast Mastery XP", "0")),
			"beastMasteryReq": int(f.get("Beast Mastery Requirement", "0")),
			"isBoss": f.get("isBoss", "False") == "True",
			"drops": parse_drops(f.get("Drops", "")),
		}
	for name: String in enemies:
		enemies[name]["id"] = _reg.mint("enemies", ContentId.enemy_id(name))
		enemies[name]["displayName"] = ContentRename.rename(name, _rename_map)
	write_json("enemies.json", enemies)
	print("enemies: %d" % enemies.size())


func import_recipes(items: Dictionary) -> void:
	var raw: Array = read_json(EXPORT_DIR + "/json/recipes-full.json")
	var skill_for_class := {
		"Recipe": "cooking",
		"RecipeSmithing": "smithing",
		"RecipeCrafting": "crafting",
		"RecipeHerbology": "herbology",
		"RecipeBowCrafting": "fletching",
		"RecipeDevotion": "devotion",
		"RecipeImbuing": "imbuing",
	}
	var time_fields := ["cookingTime", "smithingTime", "craftingTime", "BowCraftingTime", "ImbuingTime", "potionTime", "devotionTime"]
	var recipes := {}
	for e: Dictionary in raw:
		var cls: String = e.get("scriptClass", "Recipe")
		var skill: String = skill_for_class.get(cls, "cooking")
		var craft_time := 3.0
		for tf: String in time_fields:
			if e.has(tf) and float(e[tf]) > 0.0:
				craft_time = float(e[tf])
				break
		var inputs: Array = []
		for i: int in [1, 2]:
			var iname: String = e.get("inputItemName%d" % i, "")
			var iamt: float = e.get("inputItemAmount%d" % i, 0)
			if not iname.is_empty() and iamt > 0:
				inputs.append({"item": iname, "qty": int(iamt)})
		var rname: String = e.get("itemName", e.get("m_Name", ""))
		if rname.is_empty() or inputs.is_empty():
			continue
		# The recipe asset doubles as the output item's definition (stats,
		# value, equip requirements). items-full's copy, when present, is a
		# stat-less flavor duplicate — the recipe entry wins if it has stats.
		var as_item := slim_item(e)
		var existing: Dictionary = items.get(rname, {})
		if existing.is_empty() or _has_combat_stats(as_item) and not _has_combat_stats(existing):
			items[rname] = as_item
		var recipe := {
			"name": rname,
			"skill": skill,
			"inputs": inputs,
			"output": {"item": e.get("outputItemName", rname), "qty": int(e.get("outputItemAmount", 1))},
			"xp": float(e.get("xpGain", 0)),
			"time": craft_time,
			"levelReq": int(e.get("levelRequirement", 1)),
			"hpValue": int(e.get("hpvalue", 0)),
			"unburnable": bool(e.get("unburnable", false)),
		}
		# Duplicates: keep first (mirrors Resources.LoadAll order being authoritative).
		var key := skill + "/" + rname
		if not recipes.has(key):
			recipes[key] = recipe
	# Mint each id from the ORIGINAL Bloobs skill slug (stable across re-imports),
	# then remap the skill field + re-key to the Imota roster (spec §2).
	var remapped := {}
	for key: String in recipes:
		var r: Dictionary = recipes[key]
		r["id"] = _reg.mint("recipes", ContentId.recipe_id(str(r["skill"]), str(r["name"])))
		r["displayName"] = ContentRename.rename(str(r["name"]), _rename_map)
		r["skill"] = SkillRemap.to_new(str(r["skill"]))
		var new_key: String = str(r["skill"]) + "/" + str(r["name"])
		if not remapped.has(new_key):
			remapped[new_key] = r
	write_json("recipes.json", remapped)
	print("recipes: %d" % recipes.size())


static func _has_combat_stats(item: Dictionary) -> bool:
	for f: String in ["accuracy", "damage", "damageReduction", "rangeDamage",
			"magicDamage", "rangeAccuracy", "magicAccuracy", "critChance"]:
		if float(item.get(f, 0)) != 0.0:
			return true
	return false


func import_gather_nodes() -> void:
	var parsed: Dictionary = read_json(EXPORT_DIR + "/json/text-parsed.json")
	var nodes := {"woodcutting": [], "mining": [], "fishing": [], "foraging": []}

	# Trees only exist as a raw text list: "Oak Tree - Level 10 | Log: Oak Logs"
	var tree_file := FileAccess.open(EXPORT_DIR + "/raw/assets/treeList.txt", FileAccess.READ)
	var tree_re := RegEx.create_from_string("^(.*?)\\s*-\\s*Level\\s+(\\d+)\\s*\\|\\s*Log:\\s*(.*)$")
	while not tree_file.eof_reached():
		var line := tree_file.get_line().strip_edges()
		if line.is_empty():
			continue
		var m := tree_re.search(line)
		if m == null:
			push_warning("Unparsed tree line: " + line)
			continue
		var lvl := int(m.get_string(2))
		nodes["woodcutting"].append({
			"name": m.get_string(1).strip_edges(),
			"level": lvl,
			"items": [m.get_string(3).strip_edges()],
			"xp": gather_xp_for_level(lvl),
		})

	for src: Array in [[parsed["ores"], "mining", "ores"], [parsed["fish"], "fishing", "fish"], [parsed["forage"], "foraging", "items"]]:
		var list: Array = src[0]
		var skill: String = src[1]
		var items_key: String = src[2]
		for n: Dictionary in list:
			var lvl: int = int(n.get("level", 1))
			nodes[skill].append({
				"name": n.get("nodeName", "?"),
				"level": lvl,
				"items": n.get(items_key, []),
				"xp": gather_xp_for_level(lvl),
			})
	for skill: String in nodes:
		var arr: Array = nodes[skill]
		arr.sort_custom(func(a, b): return a["level"] < b["level"])
		for node: Dictionary in arr:
			node["id"] = _reg.mint("nodes", ContentId.node_id(skill, str(node["name"])))
			node["displayName"] = ContentRename.rename(str(node["name"]), _rename_map)
	write_json("gather_nodes.json", nodes)
	for skill: String in nodes:
		print("gather %s: %d nodes" % [skill, nodes[skill].size()])


## Shop stock: the standard tool ladder (Bronze→Sunwrought axes/pickaxes/
## rods/lenses). Tools are real recipe-output items ("progress" = gather
## damage per action); the shop lists the affordable ladder so a fresh
## character can buy upgrades like at the Bloobs store, excluding the
## 2M-gold Golden/Gilded prestige variants.
func write_shop_stock(items: Dictionary) -> void:
	var stock := {}
	for item_name: String in items:
		var item: Dictionary = items[item_name]
		if float(item.get("progress", 0)) <= 0.0 or float(item.get("value", 0)) > 1000.0:
			continue
		var reqs: Dictionary = item["reqs"]
		var skill := ""
		var req_level := 1
		for s: String in reqs:
			skill = s
			req_level = int(reqs[s])
		stock[item_name] = {
			"name": item_name,
			"skill": skill,
			"level": req_level,
			"progress": int(item["progress"]),
			"value": int(item["value"]),
		}
	write_json("tools.json", stock)
	print("shop tools: %d" % stock.size())
