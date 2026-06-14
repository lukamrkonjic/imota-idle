extends RefCounted
class_name SaveMigration
## Migrates save dictionaries between schema versions.

const CURRENT_SCHEMA := 3
const CURRENT_GAME_VERSION := "0.3.0"


static func migrate_game_save(data: Dictionary) -> Dictionary:
	var version := int(data.get("schemaVersion", 1))
	if version >= CURRENT_SCHEMA:
		return data
	var out: Dictionary = data.duplicate(true)
	if version < 2:
		out = _migrate_v1_to_v2(out)
	if version < 3:
		out = _migrate_v2_to_v3(out)
	out["schemaVersion"] = CURRENT_SCHEMA
	out["gameVersion"] = CURRENT_GAME_VERSION
	return out


static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	# Inventory: name -> id
	var inv: Array = []
	for stack: Dictionary in out.get("inventory", []):
		var raw: String = str(stack.get("id", stack.get("name", "")))
		var id := DataRegistry.resolve_item_id(raw)
		if id.is_empty():
			push_warning("Save migration: unknown item '%s' dropped from inventory" % raw)
			continue
		inv.append({"id": id, "qty": int(stack["qty"])})
	out["inventory"] = inv
	# Bank: name keys -> id keys
	var bank: Dictionary = {}
	for k: String in out.get("bank", {}):
		var id := DataRegistry.resolve_item_id(k)
		if id.is_empty():
			push_warning("Save migration: unknown bank item '%s' skipped" % k)
			continue
		bank[id] = int(out["bank"][k]) + int(bank.get(id, 0))
	out["bank"] = bank
	# Equipment: slot -> item id
	var eq: Dictionary = {}
	for slot: String in out.get("equipment", {}):
		var id := DataRegistry.resolve_item_id(str(out["equipment"][slot]))
		if not id.is_empty():
			eq[slot] = id
	out["equipment"] = eq
	# Activity
	var act: Dictionary = out.get("activity", {})
	if not act.is_empty():
		match str(act.get("kind", "")):
			"gather":
				var node_raw: String = str(act.get("node_id", act.get("node", "")))
				act["node_id"] = DataRegistry.resolve_node_id(str(act["skill"]), node_raw)
				act.erase("node")
			"combat":
				var enemy_raw: String = str(act.get("enemy_id", act.get("enemy", "")))
				act["enemy_id"] = DataRegistry.resolve_enemy_id(enemy_raw)
				act.erase("enemy")
			"craft":
				var recipe_raw: String = str(act.get("recipe_id", act.get("recipe", "")))
				act["recipe_id"] = DataRegistry.resolve_recipe_id(str(act["skill"]), recipe_raw)
				act.erase("recipe")
		out["activity"] = act
	return out


## v2 saves hold the old *slug* ids (`item.suncoil_logs`); v3 freezes content
## behind opaque numeric ids (`item.1042`). Every slug resolves to its numeric id
## through `content_aliases.json` (populated by tools/stamp_ids.gd), so this is a
## pure re-resolution — no item is dropped as long as its alias exists.
static func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var inv: Array = []
	for stack: Dictionary in out.get("inventory", []):
		var raw: String = str(stack.get("id", ""))
		var id := DataRegistry.resolve_item_id(raw)
		if id.is_empty():
			push_warning("Save migration v3: unknown item '%s' dropped from inventory" % raw)
			continue
		inv.append({"id": id, "qty": int(stack["qty"])})
	out["inventory"] = inv
	var bank: Dictionary = {}
	for k: String in out.get("bank", {}):
		var id := DataRegistry.resolve_item_id(k)
		if id.is_empty():
			push_warning("Save migration v3: unknown bank item '%s' skipped" % k)
			continue
		bank[id] = int(out["bank"][k]) + int(bank.get(id, 0))
	out["bank"] = bank
	var eq: Dictionary = {}
	for slot: String in out.get("equipment", {}):
		var id := DataRegistry.resolve_item_id(str(out["equipment"][slot]))
		if not id.is_empty():
			eq[slot] = id
	out["equipment"] = eq
	var act: Dictionary = out.get("activity", {})
	if not act.is_empty():
		match str(act.get("kind", "")):
			"gather":
				act["node_id"] = DataRegistry.resolve_node_id(str(act.get("skill", "")), str(act.get("node_id", "")))
			"combat":
				act["enemy_id"] = DataRegistry.resolve_enemy_id(str(act.get("enemy_id", "")))
			"craft":
				act["recipe_id"] = DataRegistry.resolve_recipe_id(str(act.get("skill", "")), str(act.get("recipe_id", "")))
		out["activity"] = act
	return out


static func migrate_world_save(data: Dictionary) -> Dictionary:
	var version := int(data.get("schemaVersion", 1))
	if version >= CURRENT_SCHEMA:
		return data
	var out: Dictionary = data.duplicate(true)
	out["schemaVersion"] = CURRENT_SCHEMA
	if not out.has("generatorVersion"):
		out["generatorVersion"] = 1
	if not out.has("chunkSnapshots"):
		out["chunkSnapshots"] = {}
	return out
