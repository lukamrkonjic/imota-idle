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
## that force a parent biome, a zone name and an entry-level requirement (your
## sub-biomes still stamp on top); anchors pin a POI (settlement / landmark /
## dungeon) to an exact chunk and may pin a boss.

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
var settlements: Array = []       # {id, kind, theme, tile:Vector2i, services}
var roads: Array = []             # {id, kind, width, points:[Vector2i tiles]}
var features: Array = []          # {kind, ...} rivers/lakes/landmarks/etc.

## Finite-world bounds in CHUNK space. When `finite`, everything outside is open
## ocean and the generator is only consulted for chunks flagged `fixed:false`.
var finite := false
var bounds := Rect2i()            # chunk-space rect [min..max] inclusive-ish
var ocean_beyond_bounds := true

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
	settlements.clear()
	roads.clear()
	features.clear()
	finite = false
	bounds = Rect2i()
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
		# radius is a scalar (circle) OR [rx, ry] (ellipse). rotation in degrees; optional warp.
		var rad: Variant = shape.get("radius", 1)
		var rx: float = float(rad[0]) if rad is Array else float(rad)
		var ry: float = float(rad[1]) if (rad is Array and (rad as Array).size() > 1) else rx
		var warp: Dictionary = shape.get("warp", {})
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
			# Ellipse mask: half-extents rx/ry (chunks), rotation, organic-edge warp. `radius` is
			# kept as the larger half-extent so the land-guarantee/POI code still has one number.
			"rx": rx, "ry": ry, "rot": deg_to_rad(float(shape.get("rotation", 0.0))),
			"warp_seed": int(warp.get("seed", 0)), "warp_strength": float(warp.get("strength", 0.0)),
			"radius": maxf(rx, ry),
			"shape_type": str(shape.get("type", "circle")),
			# Overlap resolution: higher priority wins, then the more specific (smaller) region.
			"priority": int(r.get("priority", 40)),
			"blend": float(r.get("blendWidth", 3.0)),
			"macro": str(r.get("macroRegion", "")),
			"role": str(r.get("role", "major")),
			"allow_outside": bool(r.get("allowOutsideRegion", false)),
			"allow_clip": bool(r.get("allowBoundsClipping", false)),
			"fixed": bool(r.get("fixed", true)),   # false => stays procedural at runtime
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
			"allow_outside": bool(a.get("allowOutsideRegion", false)),
		})
	routes = doc.get("routes", [])
	relationships = doc.get("relationships", [])
	_ingest_world(doc)
	active = not regions.is_empty() or not anchors.is_empty()


## Finite bounds + the deliberate placement data (settlements, roads, features).
func _ingest_world(doc: Dictionary) -> void:
	var b: Dictionary = doc.get("bounds", {})
	if not b.is_empty():
		var mn: Array = b.get("min", [0, 0])
		var mx: Array = b.get("max", [0, 0])
		bounds = Rect2i(int(mn[0]), int(mn[1]),
			int(mx[0]) - int(mn[0]) + 1, int(mx[1]) - int(mn[1]) + 1)
		finite = true
		ocean_beyond_bounds = bool(doc.get("oceanBeyondBounds", true))
	for s: Dictionary in doc.get("settlements", []):
		var st: Array = s.get("tile", [0, 0])
		settlements.append({
			"id": str(s.get("id", "")),
			"kind": str(s.get("kind", "village")),
			"label": str(s.get("label", s.get("id", ""))),
			"theme": str(s.get("theme", "")),
			"tile": Vector2i(int(st[0]), int(st[1])),
			"services": s.get("services", []),
		})
	for r: Dictionary in doc.get("roads", []):
		var pts: Array = []
		for p: Array in r.get("points", []):
			pts.append(Vector2i(int(p[0]), int(p[1])))
		roads.append({
			"id": str(r.get("id", "")),
			"kind": str(r.get("kind", "minor")),
			"width": int(r.get("width", 1)),
			"points": pts,
		})
	for f: Dictionary in doc.get("features", []):
		var feat: Dictionary = {"kind": str(f.get("kind", "")), "label": str(f.get("label", ""))}
		if f.has("points"):
			var fp: Array = []
			for p: Array in f["points"]:
				fp.append(Vector2i(int(p[0]), int(p[1])))
			feat["points"] = fp
		if f.has("tile"):
			feat["tile"] = Vector2i(int(f["tile"][0]), int(f["tile"][1]))
		if f.has("width"):
			feat["width"] = int(f["width"])
		if f.has("radius"):
			feat["radius"] = int(f["radius"])
		features.append(feat)


# ----------------------------------------------------------------- regions ----

## Nominal elliptical distance of chunk (cx,cy) from a region's centre: 0 at the centre, 1 on
## the (un-warped) coastline ellipse. Rotation-aware. Used for membership + overlap + validation;
## the organic edge WARP is applied only in the climate generator (visual), not for zoning.
static func region_ed(r: Dictionary, cx: float, cy: float) -> float:
	var dx := cx - float(r["cx"])
	var dy := cy - float(r["cy"])
	var rot := float(r.get("rot", 0.0))
	var ca := cos(-rot)
	var sa := sin(-rot)
	var lx := (dx * ca - dy * sa) / maxf(float(r.get("rx", r.get("radius", 1.0))), 0.001)
	var ly := (dx * sa + dy * ca) / maxf(float(r.get("ry", r.get("radius", 1.0))), 0.001)
	return sqrt(lx * lx + ly * ly)


## True when chunk (cx,cy) is inside the region's nominal ellipse (with a small tolerance).
func region_contains_chunk(r: Dictionary, cx: int, cy: int) -> bool:
	return region_ed(r, float(cx), float(cy)) <= 1.0 + 0.0001


## Region whose ellipse (chunk space) covers chunk (cx, cy); when several overlap, the highest
## `priority` wins, then the more specific (smaller-area) region — array order never decides.
func region_for_chunk(cx: int, cy: int) -> Dictionary:
	if not active:
		return {}
	var key := "%d:%d" % [cx, cy]
	if _region_for_chunk.has(key):
		return _region_for_chunk[key]
	var best: Dictionary = {}
	var best_pri := -INF
	var best_area := INF
	for r: Dictionary in regions:
		if region_ed(r, float(cx), float(cy)) > 1.0 + 0.0001:
			continue
		var pri := float(r.get("priority", 40))
		var area: float = float(r.get("rx", 1.0)) * float(r.get("ry", 1.0))
		if pri > best_pri + 0.0001 or (absf(pri - best_pri) <= 0.0001 and area < best_area):
			best = r
			best_pri = pri
			best_area = area
	_region_for_chunk[key] = best
	return best


func region_by_id(region_id: String) -> Dictionary:
	for r: Dictionary in regions:
		if str(r["id"]) == region_id:
			return r
	return {}


## Authored parent-biome id forced on chunk (cx, cy), or "" when none.
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

## Authored anchor pinned to chunk (cx, cy), or {}. Shaped so poi_placement can
## consume it directly (plus a `boss` to pin a specific bestiary boss).
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


## Planned authored anchors as poi-placement-shaped dicts (debug / tests).
func planned_anchors() -> Array:
	var out: Array = []
	for a: Dictionary in anchors:
		out.append(anchor_for_chunk(Vector2i(a["chunk"]).x, Vector2i(a["chunk"]).y))
	return out


# ------------------------------------------------------------- finite world ----

## True when chunk (cx,cy) lies inside the authored finite continent.
func in_bounds(cx: int, cy: int) -> bool:
	if not finite:
		return true
	return bounds.has_point(Vector2i(cx, cy))


## True when chunk (cx,cy) should still be generated procedurally at runtime
## (a region flagged fixed:false — caverns, designated wilderness). Baked chunks
## are everything else inside bounds.
func is_procedural_zone(cx: int, cy: int) -> bool:
	var r := region_for_chunk(cx, cy)
	return not r.is_empty() and not bool(r.get("fixed", true))


## Chunks that should be baked: in-bounds and not a procedural zone.
func should_bake(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and not is_procedural_zone(cx, cy)


## Roads whose polyline passes near chunk (cx,cy) (cheap AABB test in tiles).
func roads_through_chunk(cx: int, cy: int) -> Array:
	var out: Array = []
	for road: Dictionary in roads:
		if _polyline_touches_chunk(road["points"], cx, cy, int(road.get("width", 1)) + 1):
			out.append(road)
	return out


func _polyline_touches_chunk(points: Array, cx: int, cy: int, pad: int) -> bool:
	var x0: int = cx * WG.CHUNK_TILES - pad
	var y0: int = cy * WG.CHUNK_TILES - pad
	var x1: int = (cx + 1) * WG.CHUNK_TILES + pad
	var y1: int = (cy + 1) * WG.CHUNK_TILES + pad
	for p: Vector2i in points:
		if p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1:
			return true
	# also catch long segments crossing the chunk without a vertex inside it
	for i: int in range(points.size() - 1):
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		if mini(a.x, b.x) <= x1 and maxi(a.x, b.x) >= x0 \
				and mini(a.y, b.y) <= y1 and maxi(a.y, b.y) >= y0:
			return true
	return false


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
