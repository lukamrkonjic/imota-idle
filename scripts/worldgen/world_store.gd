extends RefCounted
## World persistence (user://world.json). Explored chunk snapshots preserve
## generated terrain across generator version bumps; depletions, obelisks, and
## visited zones are stored separately.

const SAVE_PATH := "user://world.json"
const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const SaveMigration := preload("res://autoload/save_migration.gd")

## Bump when generation logic changes; stale explored snapshots regenerate.
const GENERATOR_VERSION := 1

var world_seed: int = 0
var obelisks: Dictionary = {}       # chunk_key -> {name, x, y}
var depleted: Dictionary = {}        # chunk_key -> {site_index_str: respawn_at_unix}
var visited_zones: Dictionary = {}   # zone id -> true
var chunk_snapshots: Dictionary = {} # chunk_key -> snapshot dict
var suppress := false


func load_file(default_seed: int) -> void:
	world_seed = default_seed
	if suppress or not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_error("Corrupt world save ignored")
		return
	parsed = SaveMigration.migrate_world_save(parsed)
	world_seed = int(parsed.get("seed", default_seed))
	obelisks = parsed.get("obelisks", {})
	visited_zones = parsed.get("visitedZones", {})
	chunk_snapshots = parsed.get("chunkSnapshots", {})
	depleted = {}
	var raw: Dictionary = parsed.get("depleted", {})
	for k: String in raw:
		var sites: Dictionary = {}
		for idx: String in raw[k]:
			sites[idx] = float(raw[k][idx])
		depleted[k] = sites


func save_file() -> void:
	if suppress:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write world save")
		return
	f.store_string(JSON.stringify({
		"schemaVersion": SaveMigration.CURRENT_SCHEMA,
		"generatorVersion": GENERATOR_VERSION,
		"seed": world_seed,
		"obelisks": obelisks,
		"visitedZones": visited_zones,
		"depleted": depleted,
		"chunkSnapshots": chunk_snapshots,
	}))
	f.close()


func record_depletion(chunk_key: String, site_index: int, respawn_at: float) -> void:
	if not depleted.has(chunk_key):
		depleted[chunk_key] = {}
	depleted[chunk_key][str(site_index)] = respawn_at


func clear_depletion(chunk_key: String, site_index: int) -> void:
	if depleted.has(chunk_key):
		depleted[chunk_key].erase(str(site_index))
		if depleted[chunk_key].is_empty():
			depleted.erase(chunk_key)


func apply_to_chunk(chunk: RefCounted) -> void:
	var entries: Dictionary = depleted.get(chunk.key(), {})
	if entries.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	for idx_str: String in entries.keys():
		var idx := int(idx_str)
		if idx < 0 or idx >= chunk.sites.size():
			continue
		if float(entries[idx_str]) <= now:
			clear_depletion(chunk.key(), idx)
		else:
			chunk.sites[idx]["available"] = false
			chunk.sites[idx]["respawn_at"] = float(entries[idx_str])


func unlock_obelisk(chunk_key: String, name: String, pos: Vector2) -> bool:
	if obelisks.has(chunk_key):
		return false
	obelisks[chunk_key] = {"name": name, "x": pos.x, "y": pos.y}
	return true


# --------------------------------------------------------- chunk snapshots ----

func has_chunk_snapshot(chunk_key: String) -> bool:
	if not chunk_snapshots.has(chunk_key):
		return false
	var snapshot: Dictionary = chunk_snapshots[chunk_key]
	return int(snapshot.get("generatorVersion", 0)) == GENERATOR_VERSION


func save_chunk_snapshot(chunk: RefCounted) -> void:
	chunk_snapshots[chunk.key()] = _serialize_chunk(chunk)


func load_chunk_snapshot(layer: int, cx: int, cy: int) -> RefCounted:
	var key := WG.key(layer, cx, cy)
	if not chunk_snapshots.has(key):
		return null
	var snapshot: Dictionary = chunk_snapshots[key]
	if int(snapshot.get("generatorVersion", 0)) != GENERATOR_VERSION:
		return null
	return _deserialize_chunk(snapshot)


func invalidate_snapshots() -> void:
	chunk_snapshots.clear()


func _serialize_chunk(chunk: RefCounted) -> Dictionary:
	var tiles: Array = []
	for b: int in chunk.tiles:
		tiles.append(b)
	var biomes: Array = []
	for b: int in chunk.biomes_t:
		biomes.append(b)
	var zone: Dictionary = chunk.zone.duplicate(true)
	if zone.get("site_chunk") is Vector2i:
		zone["site_chunk"] = _vec2i_to_json(zone["site_chunk"])
	var pois: Array = _deep_copy_array(chunk.pois)
	for poi: Dictionary in pois:
		if poi.get("anchor") is Vector2i:
			poi["anchor"] = _vec2i_to_json(poi["anchor"])
	return {
		"layer": chunk.layer,
		"cx": chunk.cx,
		"cy": chunk.cy,
		"generatorVersion": GENERATOR_VERSION,
		"tiles": tiles,
		"biomes": biomes,
		"zone": zone,
		"safe": chunk.safe,
		"sites": _deep_copy_array(chunk.sites),
		"pois": pois,
		"monsters": _deep_copy_array(chunk.monsters),
	}


func _deserialize_chunk(data: Dictionary) -> RefCounted:
	var chunk: RefCounted = Chunk.new()
	chunk.setup(int(data["layer"]), int(data["cx"]), int(data["cy"]))
	for i: int in data["tiles"].size():
		chunk.tiles[i] = int(data["tiles"][i])
	for i: int in data["biomes"].size():
		chunk.biomes_t[i] = int(data["biomes"][i])
	chunk.zone = data.get("zone", {}).duplicate(true)
	if chunk.zone.has("site_chunk"):
		chunk.zone["site_chunk"] = _json_to_vec2i(chunk.zone["site_chunk"])
	chunk.safe = bool(data.get("safe", false))
	chunk.sites = data.get("sites", []).duplicate(true)
	chunk.pois = data.get("pois", []).duplicate(true)
	for poi: Dictionary in chunk.pois:
		if poi.has("anchor"):
			poi["anchor"] = _json_to_vec2i(poi["anchor"])
	chunk.monsters = data.get("monsters", []).duplicate(true)
	return chunk


static func _vec2i_to_json(v: Vector2i) -> Array:
	return [v.x, v.y]


## Accepts [x, y] (current format), "(x, y)" (legacy stringified Vector2i
## from pre-fix saves), or a live Vector2i (in-memory snapshot this session).
static func _json_to_vec2i(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	if v is String:
		var parts: PackedStringArray = v.trim_prefix("(").trim_suffix(")").split(",")
		if parts.size() == 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	push_warning("WorldStore: unparseable Vector2i in snapshot: %s" % str(v))
	return Vector2i.ZERO


static func _deep_copy_array(arr: Array) -> Array:
	var out: Array = []
	for v: Variant in arr:
		if v is Dictionary:
			out.append(v.duplicate(true))
		elif v is Array:
			out.append(v.duplicate(true))
		else:
			out.append(v)
	return out
