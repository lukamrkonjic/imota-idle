extends SceneTree
## One-shot: stamp opaque, frozen numeric ids into the existing data/*.json files
## and build the persistent id registry + content_aliases (legacy slug -> numeric).
##
## Run headless:
##   godot --headless --path C:/Dev/imota-idle --script res://tools/stamp_ids.gd
##
## Idempotent: re-running preserves every assignment (the registry is the record
## of truth) and only mints ids for content that lacks one. After this runs once,
## the data files carry their final ids and saves migrate slug -> numeric.

const ContentId := preload("res://scripts/content/content_id.gd")
const IdRegistry := preload("res://scripts/content/id_registry.gd")

const DATA := "res://data/"


func _init() -> void:
	var reg: IdRegistry = IdRegistry.load_or_new(DATA + "id_registry.json")

	var items: Dictionary = _read("items.json")
	var enemies: Dictionary = _read("enemies.json")
	var nodes: Dictionary = _read("gather_nodes.json")
	var recipes: Dictionary = _read("recipes.json")

	var minted := {"items": 0, "enemies": 0, "nodes": 0, "recipes": 0}

	for name: String in _sorted(items.keys()):
		var legacy := ContentId.item_id(name)
		if not reg.has("items", legacy):
			minted["items"] += 1
		items[name]["id"] = reg.mint("items", legacy)

	for name: String in _sorted(enemies.keys()):
		var legacy := ContentId.enemy_id(name)
		if not reg.has("enemies", legacy):
			minted["enemies"] += 1
		enemies[name]["id"] = reg.mint("enemies", legacy)

	for skill: String in _sorted(nodes.keys()):
		for node: Dictionary in nodes[skill]:
			var legacy := ContentId.node_id(skill, str(node["name"]))
			if not reg.has("nodes", legacy):
				minted["nodes"] += 1
			node["id"] = reg.mint("nodes", legacy)

	for key: String in _sorted(recipes.keys()):
		var r: Dictionary = recipes[key]
		var legacy := ContentId.recipe_id(str(r["skill"]), str(r["name"]))
		if not reg.has("recipes", legacy):
			minted["recipes"] += 1
		r["id"] = reg.mint("recipes", legacy)

	reg.save()
	_write("items.json", items)
	_write("enemies.json", enemies)
	_write("gather_nodes.json", nodes)
	_write("recipes.json", recipes)
	_merge_aliases(reg)

	print("stamp_ids: minted %s" % minted)
	print("registry next: %s" % reg.data["next"])
	quit(0)


func _sorted(keys: Array) -> Array:
	var k := keys.duplicate()
	k.sort()
	return k


func _read(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + name))
	return parsed if parsed is Dictionary else {}


func _write(name: String, d: Dictionary) -> void:
	var f := FileAccess.open(DATA + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("wrote %s (%d)" % [name, d.size()])


## Merge the slug -> numeric maps into content_aliases.json, preserving any
## hand-authored alias entries already present.
func _merge_aliases(reg: IdRegistry) -> void:
	var aliases: Dictionary = _read("content_aliases.json")
	for bucket: String in ["items", "nodes", "recipes", "enemies"]:
		if not aliases.has(bucket):
			aliases[bucket] = {}
	var minted: Dictionary = reg.to_aliases()
	for bucket: String in minted:
		for slug: String in minted[bucket]:
			aliases[bucket][slug] = minted[bucket][slug]
	var f := FileAccess.open(DATA + "content_aliases.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(aliases, "  ", false))
	f.close()
	print("wrote content_aliases.json")
