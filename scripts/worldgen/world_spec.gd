extends RefCounted
## Authored world layer — the runtime half of the AI World Director / Compiler
## (see docs/AI_WORLD_AUTHORING.md). Loads a single active WorldSpec from
## data/world/worldspec/<active>.json and answers "do you own this cell / chunk /
## tile?" queries. Every generator pass consults this FIRST and falls back to the
## procedural generator when the spec is inactive or does not cover the location,
## so the infinite procedural world keeps working unchanged.
##
## All authored placement is in CHUNK space (deterministic, seed-independent), so
## the same brief always compiles to the same layout. Regions are discs of chunks
## that force a biome, a zone name and an entry-level requirement; anchors pin a
## POI (settlement / landmark / dungeon) to an exact chunk and may pin a boss.

const WG := preload("res://scripts/worldgen/wg.gd")

const INDEX_PATH := "res://data/world/worldspec/index.json"
const SPEC_DIR := "res://data/world/worldspec/"

var active := false
var id := ""
var spec_name := ""
var version := 0
var seed_override := -1
var generator_version := 0

var regions: Array = []           # region dicts (with computed center/radius)
var anchors: Array = []           # authored anchor dicts
var routes: Array = []            # {from, to} anchor-id pairs (or "spawn")
var relationships: Array = []     # declarative constraints (validated, not solved)

var _region_for_chunk: Dictionary = {}   # "cx:cy" -> region dict (or {})
var _anchor_for_chunk: Dictionary = {}    # "cx:cy" -> anchor dict (or {})


## Load the active spec named by index.json. Safe to call when files are absent:
## leaves active == false and the generator stays fully procedural.
func load_active() -> void:
	active = false
	regions.clear()
	anchors.clear()
	routes.clear()
	relationships.clear()
	_region_for_chunk.clear()
	_anchor_for_chunk.clear()
	var active_id := _read_active_id()
	if active_id.is_empty():
		return
	var doc := _read_json(SPEC_DIR + active_id + ".json")
	if doc.is_empty():
		return
	_ingest(doc)


func _read_active_id() -> String:
	var idx := _read_json(INDEX_PATH)
	if idx.is_empty():
		return ""
	if not bool(idx.get("enabled", true)):
		return ""
	return str(idx.get("active", ""))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ingest(doc: Dictionary) -> void:
	id = str(doc.get("id", ""))
	spec_name = str(doc.get("name", id))
	version = int(doc.get("version", 1))
	seed_override = int(doc.get("seed", -1))
	generator_version = int(doc.get("generatorVersion", 0))
	for r: Dictionary in doc.get("regions", []):
		var shape: Dictionary = r.get("shape", {})
		var center: Array = shape.get("center", [0, 0])
		var region := {
			"id": str(r.get("id", "")),
			"name": str(r.get("name", r.get("id", "Region"))),
			"biome": str(r.get("biome", "")),
			"req": int(r.get("req", 1)),
			"tier": str(r.get("tier", "")),
			"danger": str(r.get("danger", "safe")),
			"motif": str(r.get("motif", "")),
			"material": str(r.get("material", "")),
			"silhouette": str(r.get("silhouette", "")),
			"locked": bool(r.get("locked", false)),
			"regen": r.get("regen", []),
			"cx": int(center[0]), "cy": int(center[1]),
			"radius": float(shape.get("radius", 1)),
		}
		regions.append(region)
	for a: Dictionary in doc.get("anchors", []):
		var ch: Array = a.get("chunk", [0, 0])
		anchors.append({
			"id": str(a.get("id", "")),
			"poi": str(a.get("poi", "")),
			"label": str(a.get("label", a.get("id", ""))),
			"chunk": Vector2i(int(ch[0]), int(ch[1])),
			"region": str(a.get("region", "")),
			"boss": str(a.get("boss", "")),
			"teleport": bool(a.get("teleport", false)),
			"locked": bool(a.get("locked", true)),
		})
	routes = doc.get("routes", [])
	relationships = doc.get("relationships", [])
	active = not regions.is_empty() or not anchors.is_empty()


# ----------------------------------------------------------------- regions ----

## Region whose disc (chunk space) contains chunk (cx, cy); when several overlap,
## the nearest center wins, then the smaller radius (the more specific region).
func region_for_chunk(cx: int, cy: int) -> Dictionary:
	if not active:
		return {}
	var key := "%d:%d" % [cx, cy]
	if _region_for_chunk.has(key):
		return _region_for_chunk[key]
	var best: Dictionary = {}
	var best_d := INF
	var best_r := INF
	for r: Dictionary in regions:
		var dx := float(cx - int(r["cx"]))
		var dy := float(cy - int(r["cy"]))
		var d := sqrt(dx * dx + dy * dy)
		if d > float(r["radius"]) + 0.0001:
			continue
		if d < best_d - 0.0001 or (absf(d - best_d) <= 0.0001 and float(r["radius"]) < best_r):
			best = r
			best_d = d
			best_r = float(r["radius"])
	_region_for_chunk[key] = best
	return best


func region_by_id(region_id: String) -> Dictionary:
	for r: Dictionary in regions:
		if str(r["id"]) == region_id:
			return r
	return {}


## Authored biome id forced on chunk (cx, cy), or "" when none.
func biome_for_chunk(cx: int, cy: int) -> String:
	var r := region_for_chunk(cx, cy)
	return "" if r.is_empty() else str(r.get("biome", ""))


## Authored biome forced at a global tile (tx, ty), or "" when none.
func biome_for_tile(tx: float, ty: float) -> String:
	var c := WG.tile_to_chunk(Vector2i(floori(tx), floori(ty)))
	return biome_for_chunk(c.x, c.y)


## Authored zone override for a chunk (name pops on entry / gates by req), or {}.
func zone_for_chunk(cx: int, cy: int) -> Dictionary:
	var r := region_for_chunk(cx, cy)
	if r.is_empty():
		return {}
	return {
		"id": "region:" + str(r["id"]),
		"site_chunk": Vector2i(int(r["cx"]), int(r["cy"])),
		"req": int(r["req"]),
		"tier": str(r["tier"]) if not str(r["tier"]).is_empty() else _tier_label(int(r["req"])),
		"biome": str(r["biome"]),
		"name": str(r["name"]),
		"authored": true,
	}


static func _tier_label(req: int) -> String:
	if req < 20:
		return "Beginner"
	if req < 60:
		return "Intermediate"
	if req < 120:
		return "Advanced"
	return "Elite"


# ----------------------------------------------------------------- anchors ----

## Authored anchor pinned to chunk (cx, cy), or {}. Shaped like anchor_planner's
## procedural anchors so poi_placement can consume it unchanged (plus a `boss`).
func anchor_for_chunk(cx: int, cy: int) -> Dictionary:
	if not active:
		return {}
	var key := "%d:%d" % [cx, cy]
	if _anchor_for_chunk.has(key):
		return _anchor_for_chunk[key]
	var found: Dictionary = {}
	for a: Dictionary in anchors:
		if Vector2i(a["chunk"]) == Vector2i(cx, cy):
			found = {
				"id": str(a["id"]), "label": str(a["label"]),
				"poi": str(a["poi"]), "cell": Vector2i(cx, cy),
				"chunk": Vector2i(cx, cy), "ring": 0,
				"boss": str(a["boss"]), "authored": true,
			}
			break
	_anchor_for_chunk[key] = found
	return found


func anchor_by_id(anchor_id: String) -> Dictionary:
	if anchor_id == "spawn":
		return {"id": "spawn", "chunk": Vector2i.ZERO, "label": "Home Camp", "poi": ""}
	for a: Dictionary in anchors:
		if str(a["id"]) == anchor_id:
			return a
	return {}


## Planned authored anchors as anchor_planner-shaped dicts (debug / roads / tests).
func planned_anchors() -> Array:
	var out: Array = []
	for a: Dictionary in anchors:
		out.append(anchor_for_chunk(Vector2i(a["chunk"]).x, Vector2i(a["chunk"]).y))
	return out


# ------------------------------------------------------------------- roads ----

## Authored road segments in TILE coords ({from, to, phase}), chunk-center to
## chunk-center, for anchor_planner.road_segments() when the spec is active.
func road_segments_tiles(world_seed: int) -> Array:
	var out: Array = []
	for link: Dictionary in routes:
		var a := anchor_by_id(str(link.get("from", "spawn")))
		var b := anchor_by_id(str(link.get("to", "spawn")))
		if a.is_empty() or b.is_empty():
			continue
		var ca: Vector2i = Vector2i(a.get("chunk", Vector2i.ZERO))
		var cb: Vector2i = Vector2i(b.get("chunk", Vector2i.ZERO))
		var center := float(WG.CHUNK_TILES) * 0.5
		out.append({
			"from": Vector2(float(ca.x * WG.CHUNK_TILES) + center, float(ca.y * WG.CHUNK_TILES) + center),
			"to": Vector2(float(cb.x * WG.CHUNK_TILES) + center, float(cb.y * WG.CHUNK_TILES) + center),
			"phase": WG.r01(world_seed, cb.x, cb.y, 903) * TAU,
		})
	return out


# --------------------------------------------------------------- provenance ----

## Why does the element at this chunk exist? (powers `worldc --explain`).
func explain_chunk(cx: int, cy: int) -> Dictionary:
	var out := {"chunk": [cx, cy]}
	var r := region_for_chunk(cx, cy)
	if not r.is_empty():
		out["region"] = r
	var a := anchor_for_chunk(cx, cy)
	if not a.is_empty():
		out["anchor"] = a
	return out
