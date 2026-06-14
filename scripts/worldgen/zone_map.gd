extends RefCounted
## Voronoi level zones. The chunk grid is divided into ZONE_CELL-sized cells;
## each cell gets one seed-jittered site, and a chunk belongs to the nearest
## site — so zones are organic blobs, not rings. A zone's level requirement
## scales with its site's distance from the origin, the zone containing the
## home chunk is always level 1, and each zone gets a procedural name from
## biome-appropriate word lists (zone_names.json).

const WG := preload("res://scripts/worldgen/wg.gd")

const REQ_CAP := 300  # bestiary tops out around level 300

var reg: RefCounted
var classifier: RefCounted
var world_seed: int = 0

var _zones: Dictionary = {}        # "zx:zy" -> zone dict
var _chunk_zone: Dictionary = {}   # "cx:cy" -> zone dict
var _home_cell := Vector2i.ZERO


func setup(p_reg: RefCounted, p_classifier: RefCounted, p_seed: int) -> void:
	reg = p_reg
	classifier = p_classifier
	world_seed = p_seed
	_zones.clear()
	_chunk_zone.clear()
	_home_cell = _nearest_cell(Vector2(0.5, 0.5))


## Jittered site position (in chunk space) for a zone cell.
func cell_site(zx: int, zy: int) -> Vector2:
	var jx := 0.15 + 0.7 * WG.r01(world_seed, zx, zy, 21)
	var jy := 0.15 + 0.7 * WG.r01(world_seed, zx, zy, 22)
	return Vector2((float(zx) + jx) * WG.ZONE_CELL, (float(zy) + jy) * WG.ZONE_CELL)


func _nearest_cell(chunk_pos: Vector2) -> Vector2i:
	var base := Vector2i(floori(chunk_pos.x / WG.ZONE_CELL), floori(chunk_pos.y / WG.ZONE_CELL))
	var best := base
	var best_d := INF
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var z := base + Vector2i(dx, dy)
			var d := cell_site(z.x, z.y).distance_squared_to(chunk_pos)
			if d < best_d:
				best_d = d
				best = z
	return best


func zone_for_chunk(cx: int, cy: int) -> Dictionary:
	var ck := "%d:%d" % [cx, cy]
	if _chunk_zone.has(ck):
		return _chunk_zone[ck]
	# Zones (level requirements) follow the radial/Voronoi distance model so they
	# stay consistent with the natural centre-out progression and the biome
	# danger field — i.e. monster/resource tiers fit their zone everywhere.
	# (Authored WorldSpec regions no longer override the req; they only name POIs
	# and anchor settlements.)
	var cell := _nearest_cell(Vector2(float(cx) + 0.5, float(cy) + 0.5))
	var z := _zone(cell.x, cell.y)
	_chunk_zone[ck] = z
	return z


func zone_at_world(pos: Vector2) -> Dictionary:
	var c := WG.world_to_chunk(pos)
	return zone_for_chunk(c.x, c.y)


func _zone(zx: int, zy: int) -> Dictionary:
	var zk := "%d:%d" % [zx, zy]
	if _zones.has(zk):
		return _zones[zk]
	var site := cell_site(zx, zy)
	var dist := site.length()
	var req := 1
	if Vector2i(zx, zy) != _home_cell:
		var jitter := 0.8 + 0.4 * WG.r01(world_seed, zx, zy, 23)
		req = clampi(maxi(2, roundi(pow(dist, 1.25) * 1.1 * jitter)), 2, REQ_CAP)
	var site_chunk := Vector2i(floori(site.x), floori(site.y))
	var center_tile := Vector2(
		(float(site_chunk.x) + 0.5) * WG.CHUNK_TILES,
		(float(site_chunk.y) + 0.5) * WG.CHUNK_TILES)
	var b_idx: int = classifier.biome_idx(center_tile.x, center_tile.y)
	var biome_id := str(reg.biomes[b_idx]["id"])
	var z := {
		"id": zk, "site_chunk": site_chunk, "req": req,
		"tier": tier_label(req), "biome": biome_id,
		"name": _zone_name(zx, zy, biome_id),
	}
	_zones[zk] = z
	return z


static func tier_label(req: int) -> String:
	if req < 20:
		return "Beginner"
	if req < 60:
		return "Intermediate"
	if req < 120:
		return "Advanced"
	return "Elite"


func _zone_name(zx: int, zy: int, biome_id: String) -> String:
	var words: Dictionary = reg.zone_words.get(biome_id, reg.zone_words.get("generic", {}))
	var adjectives: Array = words.get("adjectives", ["Nameless"])
	var nouns: Array = words.get("nouns", ["Lands"])
	var adj := str(adjectives[WG.hash_i(world_seed, zx, zy, 31) % adjectives.size()])
	var noun := str(nouns[WG.hash_i(world_seed, zx, zy, 32) % nouns.size()])
	return "%s %s" % [adj, noun]


## The level a player needs to enter a zone. Idle-friendly: the gate accepts
## either combat level or the player's best skill, so pure skillers progress.
static func player_entry_level() -> int:
	var atk := GameState.level("attack")
	var str_l := GameState.level("strength")
	var def := GameState.level("defence")
	var hp := GameState.level("hitpoints")
	var rng := GameState.level("ranged")
	var mag := GameState.level("magic")
	var melee := float(atk + str_l)
	var best_style := maxf(melee, maxf(float(rng) * 1.5, float(mag) * 1.5))
	var combat := int(float(def + hp) * 0.25 + best_style * 0.325)
	var top_skill := 1
	for s: String in GameState.SKILLS:
		top_skill = maxi(top_skill, GameState.level(s))
	return maxi(combat, top_skill)
