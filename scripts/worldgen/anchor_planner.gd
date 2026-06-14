extends RefCounted
## High-level world layout pass: decides which zone Voronoi cells host hub
## anchors (mining camp, fishing dock, outposts...) and which road corridors
## connect the home camp to its nearest hubs. Runs before any chunk exists —
## chunk-level passes (tiles, POIs) consult it, never the other way around
## (the CDDA overmap / Veloren civ idea, scaled down to our cell grid).
##
## Everything is deterministic from the world seed and data-driven from
## data/world/anchors.json + generation_rules.json "roads". One anchor max
## per zone cell; the anchor's placeholder POI is placed by poi_placement.gd
## in the cell's site chunk. Roads are painted by world_generator.gd and
## chunk_renderer.gd via road_byte_at().

const WG := preload("res://scripts/worldgen/wg.gd")

## How far out (in zone-cell rings) anchors are planned. Beyond this the
## wilderness is hubless by design until more rings are added.
const PLAN_RINGS := 8

var reg: RefCounted
var zone_map: RefCounted
var world_seed: int = 0

var _cell_cache: Dictionary = {}    # "zx:zy" -> anchor dict (or {} when none)
var _chunk_cache: Dictionary = {}   # "cx:cy" -> anchor dict (or {})
var _road_segments: Array = []      # [{from: Vector2 tile, to: Vector2 tile, phase: float}]
var _roads_ready := false
var _road_cfg: Dictionary = {}
var _road_byte := -1


func setup(p_reg: RefCounted, p_zone_map: RefCounted, p_seed: int) -> void:
	reg = p_reg
	zone_map = p_zone_map
	world_seed = p_seed
	_cell_cache.clear()
	_chunk_cache.clear()
	_road_segments.clear()
	_roads_ready = false
	_road_cfg = reg.gen_rules.get("roads", {})
	_road_byte = int(reg.tile_index.get(str(_road_cfg.get("tile", "dirt")), -1))


## Anchor hosted by a zone cell, or {} — deterministic and cached.
## The home cell always hosts the starting town (the existing campsite).
func anchor_for_cell(zx: int, zy: int) -> Dictionary:
	var key := "%d:%d" % [zx, zy]
	if _cell_cache.has(key):
		return _cell_cache[key]
	var anchor := _plan_cell(zx, zy)
	_cell_cache[key] = anchor
	return anchor


func _plan_cell(zx: int, zy: int) -> Dictionary:
	var home: Vector2i = zone_map.home_cell()
	if zx == home.x and zy == home.y:
		return {
			"id": "starting_town", "label": "Home Camp", "poi": "",
			"cell": Vector2i(zx, zy), "chunk": Vector2i.ZERO, "ring": 0,
		}
	var ring := maxi(absi(zx - home.x), absi(zy - home.y))
	var zone: Dictionary = zone_map.zone_cell(zx, zy)
	var biome := str(zone.get("biome", ""))
	var candidates: Array = []
	for t: Dictionary in reg.anchor_types:
		if ring < int(t.get("ringMin", 0)) or ring > int(t.get("ringMax", 99)):
			continue
		var allowed: Array = t.get("biomes", [])
		if not allowed.is_empty() and not allowed.has(biome):
			continue
		candidates.append(t)
	if candidates.is_empty():
		return {}
	var t: Dictionary = candidates[WG.hash_i(world_seed, zx, zy, 901) % candidates.size()]
	if WG.r01(world_seed, zx, zy, 902) >= float(t.get("chance", 1.0)):
		return {}
	return {
		"id": str(t["id"]), "label": str(t.get("label", t["id"])),
		"poi": str(t.get("poi", "")),
		"cell": Vector2i(zx, zy),
		"chunk": Vector2i(zone.get("site_chunk", Vector2i.ZERO)),
		"ring": ring,
	}


## Anchor whose placeholder POI belongs in chunk (cx, cy), or {}. A chunk can
## only be the site chunk of a nearby cell, so checking the 3x3 cells around
## the chunk's own cell is exhaustive.
func anchor_for_chunk(cx: int, cy: int) -> Dictionary:
	var key := "%d:%d" % [cx, cy]
	if _chunk_cache.has(key):
		return _chunk_cache[key]
	# Authored anchors (WorldSpec) pin settlements / landmarks / dungeons to an
	# exact chunk and take precedence over the procedural ring planner.
	if reg.spec != null and reg.spec.active:
		var sa: Dictionary = reg.spec.anchor_for_chunk(cx, cy)
		if not sa.is_empty():
			_chunk_cache[key] = sa
			return sa
	var base_z := floori(float(cx) / WG.ZONE_CELL)
	var base_zy := floori(float(cy) / WG.ZONE_CELL)
	var found: Dictionary = {}
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var a := anchor_for_cell(base_z + dx, base_zy + dy)
			if not a.is_empty() and Vector2i(a["chunk"]) == Vector2i(cx, cy):
				found = a
	_chunk_cache[key] = found
	return found


## All planned anchors within PLAN_RINGS of home (debug overlay, tests), plus
## any authored anchors from the active WorldSpec.
func planned_anchors() -> Array:
	var home: Vector2i = zone_map.home_cell()
	var out: Array = []
	if reg.spec != null and reg.spec.active:
		out.append_array(reg.spec.planned_anchors())
	for zy: int in range(home.y - PLAN_RINGS, home.y + PLAN_RINGS + 1):
		for zx: int in range(home.x - PLAN_RINGS, home.x + PLAN_RINGS + 1):
			var a := anchor_for_cell(zx, zy)
			if not a.is_empty():
				out.append(a)
	return out


func anchor_world_pos(anchor: Dictionary) -> Vector2:
	var c: Vector2i = anchor["chunk"]
	var center := WG.CHUNK_TILES / 2
	return WG.tile_to_world(c.x * WG.CHUNK_TILES + center, c.y * WG.CHUNK_TILES + center)


# ------------------------------------------------------------------- roads ----

## Corridors from the home camp to its nearest hubs, in tile coordinates.
func road_segments() -> Array:
	if _roads_ready:
		return _road_segments
	_roads_ready = true
	if _road_byte < 0:
		return _road_segments
	# Authored routes (WorldSpec) replace the procedural home->hub corridors with
	# a deliberate, limited set of primary roads between named anchors.
	if reg.spec != null and reg.spec.active:
		var authored: Array = reg.spec.road_segments_tiles(world_seed)
		if not authored.is_empty():
			_road_segments = authored
			return _road_segments
	var home_tile := Vector2(float(WG.CHUNK_TILES) * 0.5, float(WG.CHUNK_TILES) * 0.5)
	var hubs: Array = []
	for a: Dictionary in planned_anchors():
		if str(a["poi"]).is_empty() or int(a["ring"]) > 3:
			continue
		hubs.append(a)
	hubs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var c_a: Vector2i = a["chunk"]
		var c_b: Vector2i = b["chunk"]
		var d_a := Vector2(c_a).length_squared()
		var d_b := Vector2(c_b).length_squared()
		if d_a != d_b:
			return d_a < d_b
		return "%d:%d" % [c_a.x, c_a.y] < "%d:%d" % [c_b.x, c_b.y])
	var count := mini(int(_road_cfg.get("connectHubs", 2)), hubs.size())
	for i: int in count:
		var hub: Dictionary = hubs[i]
		var c: Vector2i = hub["chunk"]
		var center := float(WG.CHUNK_TILES) * 0.5
		_road_segments.append({
			"from": home_tile,
			"to": Vector2(float(c.x * WG.CHUNK_TILES) + center, float(c.y * WG.CHUNK_TILES) + center),
			"phase": WG.r01(world_seed, c.x, c.y, 903) * TAU,
		})
	return _road_segments


## Normalized road presence at a global tile position: 1.0 on the wobbled
## centerline fading to 0.0 at halfWidth. The renderer blends ground colors
## toward the path palette by this, so trails get soft worn edges instead of
## a hard one-tile stripe.
func road_strength_at(gx: float, gy: float) -> float:
	if _road_byte < 0:
		return 0.0
	var p := Vector2(gx, gy)
	var cfg_half := float(_road_cfg.get("halfWidth", 1.6))
	var amp := float(_road_cfg.get("wobbleAmp", 1.6))
	var freq := float(_road_cfg.get("wobbleFreq", 0.035))
	var best := INF
	for seg: Dictionary in road_segments():
		var from: Vector2 = seg["from"]
		var to: Vector2 = seg["to"]
		var pad := cfg_half + amp + 1.0
		if p.x < minf(from.x, to.x) - pad or p.x > maxf(from.x, to.x) + pad \
				or p.y < minf(from.y, to.y) - pad or p.y > maxf(from.y, to.y) + pad:
			continue
		var ab := to - from
		var len_sq := ab.length_squared()
		if len_sq < 0.001:
			continue
		var t := clampf((p - from).dot(ab) / len_sq, 0.0, 1.0)
		var closest := from + ab * t
		var n := Vector2(-ab.y, ab.x).normalized()
		var signed := (p - closest).dot(n)
		var along := t * ab.length()
		var offset := sin(along * freq * TAU + float(seg["phase"])) * amp
		best = minf(best, absf(signed - offset))
	if best >= cfg_half:
		return 0.0
	return 1.0 - best / cfg_half


## Byte tile id for the walkable painted road core (inner ~55% of the band),
## or -1. Callers must still refuse to paint over water/hazard tiles.
func road_byte_at(gx: float, gy: float) -> int:
	return _road_byte if road_strength_at(gx, gy) > 0.45 else -1
