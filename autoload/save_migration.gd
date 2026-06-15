extends RefCounted
class_name SaveMigration
## Migrates save dictionaries between schema versions.

const SkillRemap := preload("res://scripts/content/skill_remap.gd")

const CURRENT_SCHEMA := 7
const CURRENT_GAME_VERSION := "0.7.0"


static func migrate_game_save(data: Dictionary) -> Dictionary:
	var version := int(data.get("schemaVersion", 1))
	if version >= CURRENT_SCHEMA:
		return data
	var out: Dictionary = data.duplicate(true)
	if version < 2:
		out = _migrate_v1_to_v2(out)
	if version < 3:
		out = _migrate_v2_to_v3(out)
	if version < 4:
		out = _migrate_v3_to_v4(out)
	if version < 5:
		out = _migrate_v4_to_v5(out)
	if version < 6:
		out = _migrate_v5_to_v6(out)
	if version < 7:
		out = _migrate_v6_to_v7(out)
	out["schemaVersion"] = CURRENT_SCHEMA
	out["gameVersion"] = CURRENT_GAME_VERSION
	return out


## v6 (Phase 5 combat depth): add the persisted combat style. Pure additive
## default — older saves simply start training Attack.
static func _migrate_v5_to_v6(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	if not out.has("combat_style"):
		out["combat_style"] = "attack"
	return out


## v7 (Phase 6 skill loops): add run energy + the farming block. Additive
## defaults — older saves start with full run energy and empty plots.
static func _migrate_v6_to_v7(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	if not out.has("run_energy"):
		out["run_energy"] = 100.0
	if not out.has("farming"):
		out["farming"] = {"plotCount": 3, "plots": []}
	return out


## v5 rewrites Bloobs skill keys to the OSRS-style roster (spec §2). XP/levels
## are preserved; skills that fold together (imbuing+soulbinding->crafting,
## beastmastery->slayer) sum their XP so no progress is lost.
static func _migrate_v4_to_v5(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var old_skills: Dictionary = out.get("skills", {})
	var new_skills := {}
	for key: String in old_skills:
		var nk := SkillRemap.to_new(key)
		var entry: Dictionary = old_skills[key]
		if new_skills.has(nk):
			# Fold: combine XP and re-derive the level from the merged XP.
			var merged_xp := float(new_skills[nk].get("xp", 0.0)) + float(entry.get("xp", 0.0))
			new_skills[nk] = {"xp": merged_xp, "level": DataRegistry.level_for_xp(merged_xp)}
		else:
			new_skills[nk] = {"xp": float(entry.get("xp", 0.0)), "level": int(entry.get("level", 1))}
	out["skills"] = new_skills
	return out


## v4 renames the currency field gold -> coins (Imota spec §0). Pure field rename.
static func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	if out.has("gold") and not out.has("coins"):
		out["coins"] = int(out["gold"])
	out.erase("gold")
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
