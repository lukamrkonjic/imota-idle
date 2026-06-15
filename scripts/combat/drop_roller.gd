extends RefCounted
class_name DropRoller
## The single place that turns a source's drop table into concrete loot. Used by
## combat now; gathering / clues reuse it later. Returns [{ "item": String,
## "qty": int }] using legacy item *names* (callers resolve to ids on add).
##
## Tiers (always / common / rare) are encoded by each entry's `chance`; this
## roller is tier-agnostic. `roll_tertiary` handles the independent rolls
## (pets, clue scrolls, resource bonuses) and the shared rare-drop table — both
## are placeholders today (empty data), the system is just in place (spec §12).

const RARE_TABLE_PATH := "res://data/rare_drop_table.json"


## Roll the main per-source table: each entry independently by its chance.
static func roll(drops: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for d: Dictionary in drops:
		if rng.randf() <= float(d.get("chance", 0.0)):
			out.append({
				"item": str(d["item"]),
				"qty": rng.randi_range(int(d.get("min", 1)), int(d.get("max", 1))),
			})
	return out


## Independent tertiary rolls: per-source `tertiary` entries (pets/clues) plus the
## shared rare-drop table. Both are data-driven and currently empty placeholders.
static func roll_tertiary(source: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for t: Dictionary in source.get("tertiary", []):
		if rng.randf() <= float(t.get("chance", 0.0)):
			out.append({"item": str(t["item"]), "qty": int(t.get("qty", 1))})
	var rare := _rare_table()
	var gate := float(rare.get("chance", 0.0))
	var entries: Array = rare.get("drops", [])
	if gate > 0.0 and not entries.is_empty() and rng.randf() <= gate:
		var pick: Dictionary = entries[rng.randi() % entries.size()]
		out.append({"item": str(pick["item"]), "qty": rng.randi_range(int(pick.get("min", 1)), int(pick.get("max", 1)))})
	return out


static var _rare_cache: Dictionary = {}
static var _rare_loaded := false

static func _rare_table() -> Dictionary:
	if not _rare_loaded:
		_rare_loaded = true
		if FileAccess.file_exists(RARE_TABLE_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RARE_TABLE_PATH))
			if parsed is Dictionary:
				_rare_cache = parsed
	return _rare_cache
