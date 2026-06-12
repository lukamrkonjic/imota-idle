extends RefCounted
class_name ValidateContent
## Schema validation for res://data content. Returns array of error strings.

const ContentId := preload("res://scripts/content/content_id.gd")


## Returns { "errors": String[], "warnings": String[] }.
static func run() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	_check_duplicate_ids(errors)
	_check_items(errors)
	_check_gather_nodes(warnings)
	_check_recipes(warnings)
	_check_enemies(warnings)
	_check_world_biomes(errors)
	return {"errors": errors, "warnings": warnings}


static func _check_duplicate_ids(errors: Array) -> void:
	var seen: Dictionary = {}
	for id: String in DataRegistry.items_by_id:
		if seen.has(id):
			errors.append("Duplicate item id: %s" % id)
		seen[id] = true
	for id: String in DataRegistry.enemies_by_id:
		if seen.has(id):
			errors.append("Duplicate enemy id: %s" % id)
		seen[id] = true
	for id: String in DataRegistry.recipes_by_id:
		if seen.has(id):
			errors.append("Duplicate recipe id: %s" % id)
		seen[id] = true
	for id: String in DataRegistry.nodes_by_id:
		if seen.has(id):
			errors.append("Duplicate node id: %s" % id)
		seen[id] = true


static func _check_items(errors: Array) -> void:
	for id: String in DataRegistry.items_by_id:
		var item: Dictionary = DataRegistry.items_by_id[id]
		if str(item.get("id", "")) != id:
			errors.append("Item %s: id field mismatch" % id)
		if not item.has("name") and not item.has("displayName"):
			errors.append("Item %s: missing display name" % id)
		if not item.has("value"):
			errors.append("Item %s: missing value" % id)


static func _check_gather_nodes(errors: Array) -> void:
	for skill: String in DataRegistry.gather_nodes:
		for node: Dictionary in DataRegistry.gather_nodes[skill]:
			var nid: String = str(node.get("id", ""))
			if nid.is_empty():
				errors.append("Gather node %s/%s: missing id" % [skill, node.get("name", "?")])
			for item_name: String in node.get("items", []):
				if DataRegistry.resolve_item_id(item_name).is_empty():
					errors.append("Node %s references unknown item '%s'" % [nid, item_name])


static func _check_recipes(errors: Array) -> void:
	for id: String in DataRegistry.recipes_by_id:
		var r: Dictionary = DataRegistry.recipes_by_id[id]
		for inp: Dictionary in r.get("inputs", []):
			var item_name: String = str(inp.get("item", ""))
			if DataRegistry.resolve_item_id(item_name).is_empty():
				errors.append("Recipe %s input '%s' not found" % [id, item_name])
		var out: Dictionary = r.get("output", {})
		if not out.is_empty():
			var out_item: String = str(out.get("item", ""))
			if DataRegistry.resolve_item_id(out_item).is_empty():
				errors.append("Recipe %s output '%s' not found" % [id, out_item])


static func _check_enemies(errors: Array) -> void:
	for id: String in DataRegistry.enemies_by_id:
		var e: Dictionary = DataRegistry.enemies_by_id[id]
		for d: Dictionary in e.get("drops", []):
			var item_name: String = str(d.get("item", ""))
			if DataRegistry.resolve_item_id(item_name).is_empty():
				errors.append("Enemy %s drop '%s' not found" % [id, item_name])


static func _check_world_biomes(errors: Array) -> void:
	const WorldRegistry := preload("res://scripts/worldgen/world_registry.gd")
	var reg: RefCounted = WorldRegistry.new()
	reg.load_all()
	for tile_id: String in reg.tiles:
		if not reg.tile_index.has(tile_id):
			errors.append("Biome tile id missing from index: %s" % tile_id)
	for biome: Dictionary in reg.biomes:
		if not biome.has("id"):
			errors.append("Biome missing id")
