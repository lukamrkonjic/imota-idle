extends RefCounted
class_name ValidateContent
## Schema validation for res://data content. Returns array of error strings.

const ContentId := preload("res://scripts/content/content_id.gd")

## Currency drops are authored as a pseudo-item token, not a real inventory item — the
## drop system converts them to Coins (economy wiring is Phase 7). Whitelisted from the
## item-reference checks so they don't read as dangling content.
const CURRENCY_TOKENS := ["Gold", "Coins"]


## Returns { "errors": String[], "warnings": String[] }.
static func run() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	_check_duplicate_ids(errors)
	_check_items(errors)
	# Reference integrity is now a HARD error: every recipe/node/drop must point at a real
	# item (the content graph must resolve). The currency token is whitelisted below.
	_check_gather_nodes(errors)
	_check_recipes(errors)
	_check_enemies(errors)
	_check_drop_probabilities(errors)
	_check_economy_summary(warnings)
	_check_world_biomes(errors)
	_check_pois(errors)
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
				if item_name in CURRENCY_TOKENS:
					continue
				if DataRegistry.resolve_item_id(item_name).is_empty():
					errors.append("Node %s references unknown item '%s'" % [nid, item_name])


static func _check_recipes(errors: Array) -> void:
	for id: String in DataRegistry.recipes_by_id:
		var r: Dictionary = DataRegistry.recipes_by_id[id]
		for inp: Dictionary in r.get("inputs", []):
			var item_name: String = str(inp.get("item", ""))
			if item_name in CURRENCY_TOKENS:
				continue
			if DataRegistry.resolve_item_id(item_name).is_empty():
				errors.append("Recipe %s input '%s' not found" % [id, item_name])
		var out: Dictionary = r.get("output", {})
		if not out.is_empty():
			var out_item: String = str(out.get("item", ""))
			if out_item not in CURRENCY_TOKENS and DataRegistry.resolve_item_id(out_item).is_empty():
				errors.append("Recipe %s output '%s' not found" % [id, out_item])


static func _check_enemies(errors: Array) -> void:
	for id: String in DataRegistry.enemies_by_id:
		var e: Dictionary = DataRegistry.enemies_by_id[id]
		for d: Dictionary in e.get("drops", []):
			var item_name: String = str(d.get("item", ""))
			if item_name in CURRENCY_TOKENS:
				continue
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


## POI authoring integrity: every part's guardian/boss enemy, npc and biome whitelist
## must resolve, so a typo in pois.json fails the gate instead of silently vanishing
## from the world. (Bosses can be pinned by name or auto-picked, so a bare boss part
## with no name is fine.)
static func _check_pois(errors: Array) -> void:
	const WorldRegistry := preload("res://scripts/worldgen/world_registry.gd")
	var reg: RefCounted = WorldRegistry.new()
	reg.load_all()
	var biome_ids: Dictionary = {}
	for b: Dictionary in reg.biomes:
		biome_ids[str(b.get("id", ""))] = true
	for type: String in reg.pois:
		var def: Dictionary = reg.pois[type]
		for bid: String in def.get("biomes", []):
			if not biome_ids.has(bid):
				errors.append("POI '%s' lists unknown biome '%s'" % [type, bid])
		for part: Dictionary in def.get("parts", []):
			var en := str(part.get("enemy", ""))
			if not en.is_empty() and DataRegistry.get_enemy(en).is_empty():
				errors.append("POI '%s' guardian enemy not found: '%s'" % [type, en])
			var npc := str(part.get("npc", ""))
			if not npc.is_empty() and not DataRegistry.npcs.has(npc):
				errors.append("POI '%s' npc not found: '%s'" % [type, npc])
