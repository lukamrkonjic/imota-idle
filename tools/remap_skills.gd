extends SceneTree
## One-shot: apply the Bloobs -> Imota skill remap (SkillRemap.MAP) to the data
## files. Ids are already frozen (Phase 0) and are NOT touched here — only the
## human-readable skill fields/keys change, so this is save-safe.
##
## Run headless:
##   godot --headless --path C:/Dev/imota-idle --script res://tools/remap_skills.gd
##
## Rewrites:
##   recipes.json — each recipe's `skill` field + the "skill/name" top-level key.
##   items.json   — `reqs` and `bonusXp` keys (skill -> new skill).

const SkillRemap := preload("res://scripts/content/skill_remap.gd")
const DATA := "res://data/"


func _init() -> void:
	_remap_recipes()
	_remap_items()
	quit(0)


func _remap_recipes() -> void:
	var recipes: Dictionary = _read("recipes.json")
	var out := {}
	var changed := 0
	for key: String in recipes:
		var r: Dictionary = recipes[key]
		var old_skill := str(r["skill"])
		var new_skill := SkillRemap.to_new(old_skill)
		if new_skill != old_skill:
			changed += 1
		r["skill"] = new_skill
		var new_key := new_skill + "/" + str(r["name"])
		# On a collision (same name re-homed into an existing skill) keep the
		# first, mirroring the importer's dedup order.
		if not out.has(new_key):
			out[new_key] = r
	_write("recipes.json", out)
	print("recipes: %d skill fields remapped, %d -> %d keys" % [changed, recipes.size(), out.size()])


func _remap_items() -> void:
	var items: Dictionary = _read("items.json")
	var changed := 0
	for name: String in items:
		var item: Dictionary = items[name]
		for field: String in ["reqs", "bonusXp"]:
			var src: Dictionary = item.get(field, {})
			if src.is_empty():
				continue
			var dst := {}
			for skill: String in src:
				var ns := SkillRemap.to_new(skill)
				if ns != skill:
					changed += 1
				# Sum if two old skills fold into one (imbuing+soulbinding->crafting).
				dst[ns] = src[skill] if not dst.has(ns) else dst[ns] + src[skill]
			item[field] = dst
	_write("items.json", items)
	print("items: %d reqs/bonusXp skill keys remapped" % changed)


func _read(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + name))
	return parsed if parsed is Dictionary else {}


func _write(name: String, d: Dictionary) -> void:
	var f := FileAccess.open(DATA + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("wrote %s (%d)" % [name, d.size()])
