extends Node
## Loads the imported Bloobs data (res://data/*.json) and indexes it by stable id.

const ContentId := preload("res://scripts/content/content_id.gd")

var items: Dictionary = {}           # display name -> item dict (legacy key)
var items_by_id: Dictionary = {}     # stable id -> item dict
var item_id_for_name: Dictionary = {}  # display name -> stable id

var enemies: Dictionary = {}         # display name -> enemy dict
var enemies_by_id: Dictionary = {}
var enemy_id_for_name: Dictionary = {}

var recipes: Dictionary = {}         # "skill/name" -> recipe dict
var recipes_by_id: Dictionary = {}
var recipe_id_for_key: Dictionary = {}  # "skill/name" -> stable id

var gather_nodes: Dictionary = {}    # skill -> Array of node dicts (with id)
var nodes_by_id: Dictionary = {}     # node id -> node dict

var tools: Dictionary = {}
var xp_required: Array = []
var max_level: int = 1000

var recipes_by_skill: Dictionary = {}
var food_hp: Dictionary = {}       # item id -> hp restored

var aliases: Dictionary = {
	"items": {},
	"nodes": {},
	"recipes": {},
	"enemies": {},
}


func _ready() -> void:
	load_all()


func load_all() -> void:
	aliases = _read("content_aliases.json")
	if aliases.is_empty():
		aliases = {"items": {}, "nodes": {}, "recipes": {}, "enemies": {}}
	items = _read("items.json")
	enemies = _read("enemies.json")
	recipes = _read("recipes.json")
	gather_nodes = _read("gather_nodes.json")
	tools = _read("tools.json")
	var xp: Dictionary = _read("xp_table.json")
	xp_required = xp.get("xpRequired", [])
	max_level = int(xp.get("maxLevel", 1000))
	_index_items()
	_index_enemies()
	_index_gather_nodes()
	_index_recipes()
	_build_recipe_indexes()


func _read(name: String) -> Dictionary:
	var path := "res://data/" + name
	if not FileAccess.file_exists(path):
		push_error("Missing data file %s — run tools/import_bloobs_data.gd first" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _index_items() -> void:
	items_by_id.clear()
	item_id_for_name.clear()
	for name: String in items:
		var item: Dictionary = items[name]
		var id := str(item.get("id", ContentId.item_id(name)))
		item["id"] = id
		item["displayName"] = str(item.get("displayName", item.get("name", name)))
		items_by_id[id] = item
		item_id_for_name[name] = id
		if item["displayName"] != name:
			item_id_for_name[str(item["displayName"])] = id


func _index_enemies() -> void:
	enemies_by_id.clear()
	enemy_id_for_name.clear()
	for name: String in enemies:
		var enemy: Dictionary = enemies[name]
		var id := str(enemy.get("id", ContentId.enemy_id(name)))
		enemy["id"] = id
		enemy["displayName"] = str(enemy.get("displayName", enemy.get("name", name)))
		enemies_by_id[id] = enemy
		enemy_id_for_name[name] = id


func _index_gather_nodes() -> void:
	nodes_by_id.clear()
	for skill: String in gather_nodes:
		var indexed: Array = []
		for n: Dictionary in gather_nodes[skill]:
			var node: Dictionary = n.duplicate(true)
			var node_name: String = str(node["name"])
			var id := str(node.get("id", ContentId.node_id(skill, node_name)))
			node["id"] = id
			node["skill"] = skill
			node["displayName"] = str(node.get("displayName", node_name))
			# Resolve output item names to ids for validation; keep names for compat.
			var item_ids: Array = []
			for item_name: String in node.get("items", []):
				var iid := resolve_item_id(item_name)
				if not iid.is_empty():
					item_ids.append(iid)
			node["itemIds"] = item_ids
			nodes_by_id[id] = node
			indexed.append(node)
		gather_nodes[skill] = indexed


func _index_recipes() -> void:
	recipes_by_id.clear()
	recipe_id_for_key.clear()
	for key: String in recipes:
		var r: Dictionary = recipes[key]
		var skill: String = str(r["skill"])
		var recipe_name: String = str(r["name"])
		var id := str(r.get("id", ContentId.recipe_id(skill, recipe_name)))
		r["id"] = id
		r["displayName"] = str(r.get("displayName", recipe_name))
		recipes_by_id[id] = r
		recipe_id_for_key[key] = id


func _build_recipe_indexes() -> void:
	recipes_by_skill = {}
	food_hp.clear()
	for key: String in recipes:
		var r: Dictionary = recipes[key]
		var skill: String = r["skill"]
		if not recipes_by_skill.has(skill):
			recipes_by_skill[skill] = []
		recipes_by_skill[skill].append(r)
		if r["hpValue"] > 0:
			var out_item: String = str(r["output"]["item"])
			var out_id := resolve_item_id(out_item)
			if not out_id.is_empty():
				food_hp[out_id] = r["hpValue"]
	for skill: String in recipes_by_skill:
		recipes_by_skill[skill].sort_custom(func(a, b): return a["levelReq"] < b["levelReq"])


# ------------------------------------------------------------- id resolve ----

func resolve_item_id(value: String) -> String:
	if value.is_empty():
		return ""
	if aliases["items"].has(value):
		value = str(aliases["items"][value])
	if items_by_id.has(value):
		return value
	if item_id_for_name.has(value):
		return str(item_id_for_name[value])
	if ContentId.is_stable_id(value):
		push_warning("Unknown item id: %s" % value)
	return ""


func resolve_node_id(skill: String, value: String) -> String:
	if value.is_empty():
		return ""
	var alias_key := "%s/%s" % [skill, value]
	if aliases["nodes"].has(alias_key):
		value = str(aliases["nodes"][alias_key])
	if aliases["nodes"].has(value):
		value = str(aliases["nodes"][value])
	if nodes_by_id.has(value):
		return value
	for n: Dictionary in gather_nodes.get(skill, []):
		if str(n["name"]) == value or str(n.get("displayName", "")) == value:
			return str(n["id"])
	if ContentId.is_stable_id(value):
		push_warning("Unknown node id: %s" % value)
	return ""


func resolve_enemy_id(value: String) -> String:
	if value.is_empty():
		return ""
	if aliases["enemies"].has(value):
		value = str(aliases["enemies"][value])
	if enemies_by_id.has(value):
		return value
	if enemy_id_for_name.has(value):
		return str(enemy_id_for_name[value])
	if ContentId.is_stable_id(value):
		push_warning("Unknown enemy id: %s" % value)
	return ""


func resolve_recipe_id(skill: String, value: String) -> String:
	if value.is_empty():
		return ""
	var alias_key := "%s/%s" % [skill, value]
	if aliases["recipes"].has(alias_key):
		value = str(aliases["recipes"][alias_key])
	if aliases["recipes"].has(value):
		value = str(aliases["recipes"][value])
	if recipes_by_id.has(value):
		return value
	var key := skill + "/" + value
	if recipe_id_for_key.has(key):
		return str(recipe_id_for_key[key])
	if ContentId.is_stable_id(value):
		push_warning("Unknown recipe id: %s" % value)
	return ""


# --------------------------------------------------------------- lookups ----

func get_item(name_or_id: String) -> Dictionary:
	var id := resolve_item_id(name_or_id)
	return items_by_id.get(id, {})


func item_display_name(name_or_id: String) -> String:
	var item := get_item(name_or_id)
	if item.is_empty():
		return name_or_id
	return str(item.get("displayName", item.get("name", name_or_id)))


func get_enemy(name_or_id: String) -> Dictionary:
	var id := resolve_enemy_id(name_or_id)
	return enemies_by_id.get(id, {})


func enemy_display_name(name_or_id: String) -> String:
	var enemy := get_enemy(name_or_id)
	if enemy.is_empty():
		return name_or_id
	return str(enemy.get("displayName", enemy.get("name", name_or_id)))


func get_recipe(skill: String, recipe_name_or_id: String) -> Dictionary:
	var id := resolve_recipe_id(skill, recipe_name_or_id)
	return recipes_by_id.get(id, {})


func get_recipe_by_id(recipe_id: String) -> Dictionary:
	return recipes_by_id.get(recipe_id, {})


func get_gather_node(skill: String, node_name_or_id: String) -> Dictionary:
	var id := resolve_node_id(skill, node_name_or_id)
	return nodes_by_id.get(id, {})


func get_gather_node_by_id(node_id: String) -> Dictionary:
	return nodes_by_id.get(node_id, {})


func xp_for_level(level: int) -> int:
	if xp_required.is_empty():
		return 0
	level = clampi(level, 1, xp_required.size() - 1)
	return int(xp_required[level])


func level_for_xp(xp: float) -> int:
	var lo := 1
	var hi := mini(max_level, xp_required.size() - 1)
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(xp_required[mid]) <= xp:
			lo = mid
		else:
			hi = mid - 1
	return lo


func item_value(name_or_id: String) -> int:
	return int(get_item(name_or_id).get("value", 0))
