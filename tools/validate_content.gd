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
	_check_drop_probabilities(errors)
	_check_economy_summary(warnings)
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


## Hard data-integrity errors: drop chances must be a valid probability and quantity
## ranges must be sane, regardless of the (separate) content re-origination work.
static func _check_drop_probabilities(errors: Array) -> void:
	for id: String in DataRegistry.enemies_by_id:
		var e: Dictionary = DataRegistry.enemies_by_id[id]
		for d: Dictionary in e.get("drops", []):
			var item_name: String = str(d.get("item", "?"))
			var chance := float(d.get("chance", 0.0))
			if chance <= 0.0 or chance > 1.0:
				errors.append("Enemy %s drop '%s': invalid chance %s (must be 0<c<=1)" % [id, item_name, chance])
			var lo := float(d.get("min", 1.0))
			var hi := float(d.get("max", 1.0))
			if lo < 0.0 or hi < lo:
				errors.append("Enemy %s drop '%s': invalid quantity range [%s..%s]" % [id, item_name, lo, hi])


## Economy health, emitted as a concise SUMMARY (per-item detail lives in
## docs/content/content-audit.json). These stay WARNINGS until the re-origination pass
## clears the orphan/dead-skill backlog, after which they should be promoted to errors.
static func _check_economy_summary(warnings: Array) -> void:
	# Items that are produced somewhere (drop / recipe output / gather node).
	var sourced: Dictionary = {}
	for id: String in DataRegistry.enemies_by_id:
		for d: Dictionary in DataRegistry.enemies_by_id[id].get("drops", []):
			sourced[str(d.get("item", ""))] = true
	for id: String in DataRegistry.recipes_by_id:
		var out: Dictionary = DataRegistry.recipes_by_id[id].get("output", {})
		if not out.is_empty():
			sourced[str(out.get("item", ""))] = true
	var content_skills: Dictionary = {}   # skills that produce or consume something
	for skill: String in DataRegistry.gather_nodes:
		if not DataRegistry.gather_nodes[skill].is_empty():
			content_skills[skill] = true
		for node: Dictionary in DataRegistry.gather_nodes[skill]:
			for it: String in node.get("items", []):
				sourced[str(it)] = true
	# Items consumed somewhere (recipe input) or directly usable (equipment/tool/food).
	var used: Dictionary = {}
	for id: String in DataRegistry.recipes_by_id:
		var r: Dictionary = DataRegistry.recipes_by_id[id]
		content_skills[str(r.get("skill", ""))] = true
		for inp: Dictionary in r.get("inputs", []):
			used[str(inp.get("item", ""))] = true

	var orphans := 0
	for iid: String in DataRegistry.items_by_id:
		var v: Dictionary = DataRegistry.items_by_id[iid]
		var nm: String = str(v.get("displayName", v.get("name", "")))
		var has_use := used.has(nm) or _is_directly_usable(v)
		if not sourced.has(nm) and not has_use:
			orphans += 1
	if orphans > 0:
		warnings.append("Economy: %d orphan items (no source AND no use) — see content-audit.json" % orphans)

	# Skills with no economy content at all (data-side). Combat/support skills are wired in
	# code, not data, so only flag the gather/production skills here.
	var data_skills := ["woodcutting", "mining", "fishing", "foraging", "thieving", "hunter",
		"farming", "cooking", "smithing", "firemaking", "fletching", "crafting", "alchemy"]
	var dead: Array = []
	for s: String in data_skills:
		if not content_skills.has(s):
			dead.append(s)
	if not dead.is_empty():
		warnings.append("Economy: gather/production skills with no data content: %s" % ", ".join(dead))


static func _is_directly_usable(v: Dictionary) -> bool:
	for f: String in ["accuracy", "damage", "rangeDamage", "magicDamage", "damageReduction", "progress"]:
		if float(v.get(f, 0.0)) != 0.0:
			return true
	return false


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
