extends SceneTree
## One-shot: stamp the IP rename map (data/rename_map.json) into the data files
## as a `displayName` field on every item/enemy/node/recipe. The `name` field and
## ids are NOT touched, so cross-references and saves survive (spec §7).
##
## Run headless:
##   godot --headless --path C:/Dev/imota-idle --script res://tools/apply_renames.gd

const ContentRename := preload("res://scripts/content/content_rename.gd")
const DATA := "res://data/"


func _init() -> void:
	var map := ContentRename.load_map()
	var changed := {"items": 0, "enemies": 0, "nodes": 0, "recipes": 0}

	var items: Dictionary = _read("items.json")
	for name: String in items:
		var dn := ContentRename.rename(name, map)
		items[name]["displayName"] = dn
		if dn != name:
			changed["items"] += 1
	_write("items.json", items)

	var enemies: Dictionary = _read("enemies.json")
	for name: String in enemies:
		var dn := ContentRename.rename(name, map)
		enemies[name]["displayName"] = dn
		if dn != name:
			changed["enemies"] += 1
	_write("enemies.json", enemies)

	var nodes: Dictionary = _read("gather_nodes.json")
	for skill: String in nodes:
		for node: Dictionary in nodes[skill]:
			var dn := ContentRename.rename(str(node["name"]), map)
			node["displayName"] = dn
			if dn != str(node["name"]):
				changed["nodes"] += 1
	_write("gather_nodes.json", nodes)

	var recipes: Dictionary = _read("recipes.json")
	for key: String in recipes:
		var r: Dictionary = recipes[key]
		var dn := ContentRename.rename(str(r["name"]), map)
		r["displayName"] = dn
		if dn != str(r["name"]):
			changed["recipes"] += 1
	_write("recipes.json", recipes)

	print("apply_renames: %s" % changed)
	quit(0)


func _read(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + name))
	return parsed if parsed is Dictionary else {}


func _write(name: String, d: Dictionary) -> void:
	var f := FileAccess.open(DATA + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("wrote %s (%d)" % [name, d.size()])
