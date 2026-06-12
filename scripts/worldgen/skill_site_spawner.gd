extends RefCounted
## Populates chunks with gather sites (trees, rocks, fishing spots, bushes...).
## Which node spawns where is decided by data: biome skillWeights pick the
## skill, then data/world/skill_sites.json rules + the zone's level requirement
## pick a node from the Bloobs export. Richer, higher-level nodes appear in
## higher-tier zones; cave layers shift the band up via oreLevelBonus.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const BASE_SITES_PER_CHUNK := 3.2
const PLACE_ATTEMPTS := 28
const FOREST_BIOMES := ["forest", "dense_forest", "swamp"]
const WATER_TREE_BIOMES := ["plains", "forest", "dense_forest", "swamp", "beach"]
const COMMON_TREE_SPACING := 3.15
const SOLITARY_TREE_SPACING := 5.0
var reg: RefCounted
var world_seed: int = 0


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed


func populate(chunk: RefCounted, occupied: Dictionary) -> void:
	var req := int(chunk.zone.get("req", 1))
	var weights := {}
	var density := 1.0
	var cave_cfg := {}
	var center_biome := {}
	if chunk.layer == 0:
		center_biome = _center_biome(chunk)
		weights = center_biome.get("skillWeights", {})
		density = float(center_biome.get("siteDensity", 1.0))
	else:
		cave_cfg = reg.cave_layers.get(chunk.layer, {})
		weights = cave_cfg.get("skillWeights", {})
		density = float(cave_cfg.get("siteDensity", 1.0))
		req += int(cave_cfg.get("oreLevelBonus", 0))

	_place_clusters(chunk, occupied, weights, req)
	if chunk.layer == 0:
		if chunk.cx == 0 and chunk.cy == 0:
			_place_home_regular_trees(chunk, occupied)
		_place_forest_patches(chunk, occupied, req, str(center_biome.get("id", "")))
		_place_waterline_trees(chunk, occupied, req, str(center_biome.get("id", "")))

	# Drop skills that can't spawn here (e.g. fishing in a dry chunk).
	weights = weights.duplicate()
	if not _has_water(chunk):
		weights.erase("fishing")
	if weights.is_empty():
		return

	var richness := 1.0 + minf(float(req) / 200.0, 0.8)
	var jitter := 0.7 + 0.6 * WG.r01(world_seed, chunk.cx, chunk.cy, 61 + chunk.layer)
	var count := roundi(BASE_SITES_PER_CHUNK * density * richness * jitter)
	for i: int in count:
		var skill := WG.pick_weighted(weights, WG.r01(world_seed, chunk.cx, chunk.cy, 62 + i * 3 + chunk.layer * 97))
		if skill.is_empty() or not reg.node_table.has(skill):
			continue
		var cfg: Dictionary = reg.skill_cfg(skill)
		var water_edge := bool(cfg.get("waterEdge", false))
		var tile: Vector2i
		if skill == "woodcutting" and chunk.layer == 0 and not water_edge:
			var b: String = str(_center_biome(chunk).get("id", ""))
			tile = _pick_inland_biome_tile(chunk, occupied, b, 240 + i) if FOREST_BIOMES.has(b) else _pick_tile(chunk, occupied, i, false)
		else:
			tile = _pick_tile(chunk, occupied, i, water_edge)
		if tile.x < 0:
			continue
		var entry := _pick_node(chunk, skill, tile, req, i)
		if entry.is_empty():
			continue
		if skill == "woodcutting" and not _tree_spacing_ok(chunk, tile, str(entry["name"])):
			continue
		_add_site(chunk, occupied, skill, entry, tile, cfg)


func _place_forest_patches(chunk: RefCounted, occupied: Dictionary, req: int, biome_id: String) -> void:
	if not FOREST_BIOMES.has(biome_id):
		return
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var patch_count := 1 + (1 if WG.r01(world_seed, chunk.cx, chunk.cy, 168) < 0.35 else 0)
	var trees_per_patch := 5
	if biome_id == "dense_forest":
		patch_count = 2
		trees_per_patch = 6
	elif biome_id == "swamp":
		trees_per_patch = 3
	for p: int in patch_count:
		var anchor := _pick_inland_biome_tile(chunk, occupied, biome_id, 170 + p)
		if anchor.x < 0:
			continue
		var entry := _pick_forest_tree_node(chunk, biome_id, anchor, req, 172 + p)
		if entry.is_empty():
			continue
		var node_name := str(entry["name"])
		var rare_patch := _is_solitary_tree(node_name)
		var wanted := 1 if rare_patch else trees_per_patch
		var placed := 0
		for j: int in range(36):
			if placed >= wanted:
				break
			var t := anchor if j == 0 else _tree_patch_tile(anchor, chunk, p, j)
			if not _tile_ok(chunk, occupied, t, false):
				continue
			if _tile_biome_id(chunk, t) != biome_id:
				continue
			if not _tree_spacing_ok(chunk, t, node_name):
				continue
			_add_site(chunk, occupied, "woodcutting", entry, t, cfg)
			placed += 1


func _tree_patch_tile(anchor: Vector2i, chunk: RefCounted, patch_index: int, salt: int) -> Vector2i:
	var angle := WG.r01(world_seed, chunk.cx * 83 + anchor.x, chunk.cy * 89 + anchor.y, 250 + patch_index * 53 + salt) * TAU
	var radius_roll := WG.r01(world_seed, chunk.cx * 97 + anchor.x, chunk.cy * 101 + anchor.y, 251 + patch_index * 53 + salt)
	var radius := lerpf(3.4, 8.6, sqrt(radius_roll))
	var wobble := Vector2(
		WG.r01(world_seed, anchor.x, anchor.y, 252 + salt) - 0.5,
		WG.r01(world_seed, anchor.y, anchor.x, 253 + salt) - 0.5)
	var off := Vector2(cos(angle), sin(angle)) * radius + wobble * 1.9
	return Vector2i(anchor.x + roundi(off.x), anchor.y + roundi(off.y))


func _place_home_regular_trees(chunk: RefCounted, occupied: Dictionary) -> void:
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var entry := _regular_tree_entry()
	if entry.is_empty():
		return
	var placed := 0
	for t: Vector2i in [Vector2i(5, 11), Vector2i(10, 11), Vector2i(12, 6), Vector2i(4, 5)]:
		if not _tile_ok(chunk, occupied, t, false):
			continue
		if _near_water(chunk, t, 1):
			continue
		if not _tree_spacing_ok(chunk, t, str(entry["name"])):
			continue
		_add_site(chunk, occupied, "woodcutting", entry, t, cfg)
		placed += 1
		if placed >= 2:
			break


func _place_waterline_trees(chunk: RefCounted, occupied: Dictionary, req: int, biome_id: String) -> void:
	if not WATER_TREE_BIOMES.has(biome_id) or not _has_water(chunk):
		return
	if WG.r01(world_seed, chunk.cx, chunk.cy, 180) > 0.88:
		return
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var wanted := 2 + int(WG.hash_i(world_seed, chunk.cx, chunk.cy, 181) % 2)
	if biome_id == "forest" or biome_id == "swamp" or biome_id == "dense_forest":
		wanted += 1
	var placed := 0
	for i: int in range(wanted * 12):
		if placed >= wanted:
			break
		var tile := _pick_tile(chunk, occupied, 182 + i, true)
		if tile.x < 0:
			continue
		var entry := _pick_water_tree_node(chunk, tile, req, 183 + i)
		if entry.is_empty():
			continue
		if not _tree_spacing_ok(chunk, tile, str(entry["name"])):
			continue
		_add_site(chunk, occupied, "woodcutting", entry, tile, cfg)
		placed += 1


## Resource depots / fishing hotspots: a ring of one node type around the POI.
func _place_clusters(chunk: RefCounted, occupied: Dictionary, weights: Dictionary, req: int) -> void:
	const RING: Array = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1], [2, 0], [-2, 0]]
	for poi: Dictionary in chunk.pois:
		var n := int(poi.get("cluster_sites", 0))
		if n <= 0:
			continue
		var skill := str(poi.get("cluster_skill", ""))
		if skill.is_empty():
			skill = WG.pick_weighted(weights, WG.r01(world_seed, chunk.cx, chunk.cy, 71))
		if skill.is_empty() or not reg.node_table.has(skill):
			continue
		var cfg: Dictionary = reg.skill_cfg(skill)
		var anchor: Vector2i = poi["anchor"]
		var entry := _pick_node(chunk, skill, anchor, req, 71)
		if entry.is_empty():
			continue
		var placed := 0
		for off: Array in RING:
			if placed >= n:
				break
			var t := Vector2i(anchor.x + int(off[0]), anchor.y + int(off[1]))
			if not _tile_ok(chunk, occupied, t, bool(cfg.get("waterEdge", false))):
				continue
			_add_site(chunk, occupied, skill, entry, t, cfg)
			placed += 1


func _add_site(chunk: RefCounted, occupied: Dictionary, skill: String, entry: Dictionary, tile: Vector2i, cfg: Dictionary) -> void:
	occupied[Chunk.idx(tile.x, tile.y)] = true
	chunk.sites.append({
		"skill": skill,
		"node": entry["name"],
		"level": int(entry["level"]),
		"kind": str(cfg.get("kind", "bush")),
		"tx": tile.x, "ty": tile.y,
		"resources": int(cfg.get("resources", reg.site_defaults.get("resources", 8))),
		"remaining": int(cfg.get("resources", reg.site_defaults.get("resources", 8))),
		"respawn_sec": float(cfg.get("respawnSec", reg.site_defaults.get("respawnSec", 25.0))),
		"available": true,
		"respawn_at": 0.0,
	})


func _center_biome(chunk: RefCounted) -> Dictionary:
	var c := WG.CHUNK_TILES / 2
	var idx: int = chunk.biome_at(c, c)
	if idx == 255:
		return {}
	return reg.biomes[idx]


func _has_water(chunk: RefCounted) -> bool:
	for i: int in range(0, chunk.tiles.size(), 3):
		if reg.tile_def(chunk.tiles[i])["water"]:
			return true
	return false


func _pick_tile(chunk: RefCounted, occupied: Dictionary, salt: int, water_edge: bool) -> Vector2i:
	for attempt: int in PLACE_ATTEMPTS:
		var tx := 1 + WG.hash_i(world_seed, chunk.cx * 31 + salt, chunk.cy, 80 + attempt * 2 + chunk.layer * 13) % (WG.CHUNK_TILES - 2)
		var ty := 1 + WG.hash_i(world_seed, chunk.cx, chunk.cy * 31 + salt, 81 + attempt * 2 + chunk.layer * 13) % (WG.CHUNK_TILES - 2)
		var t := Vector2i(tx, ty)
		if _tile_ok(chunk, occupied, t, water_edge):
			return t
	return Vector2i(-1, -1)


func _pick_biome_tile(chunk: RefCounted, occupied: Dictionary, biome_id: String, salt: int, water_edge: bool) -> Vector2i:
	for attempt: int in PLACE_ATTEMPTS:
		var tx := 1 + WG.hash_i(world_seed, chunk.cx * 43 + salt, chunk.cy, 210 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var ty := 1 + WG.hash_i(world_seed, chunk.cx, chunk.cy * 43 + salt, 211 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var t := Vector2i(tx, ty)
		if _tile_ok(chunk, occupied, t, water_edge) and _tile_biome_id(chunk, t) == biome_id:
			return t
	return Vector2i(-1, -1)


func _pick_inland_biome_tile(chunk: RefCounted, occupied: Dictionary, biome_id: String, salt: int) -> Vector2i:
	for attempt: int in PLACE_ATTEMPTS * 2:
		var tx := 1 + WG.hash_i(world_seed, chunk.cx * 47 + salt, chunk.cy, 220 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var ty := 1 + WG.hash_i(world_seed, chunk.cx, chunk.cy * 47 + salt, 221 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var t := Vector2i(tx, ty)
		if _tile_ok(chunk, occupied, t, false) and _tile_biome_id(chunk, t) == biome_id and not _near_water(chunk, t, 1):
			return t
	return _pick_biome_tile(chunk, occupied, biome_id, salt, false)


func _tile_ok(chunk: RefCounted, occupied: Dictionary, t: Vector2i, water_edge: bool) -> bool:
	if t.x < 1 or t.y < 1 or t.x >= WG.CHUNK_TILES - 1 or t.y >= WG.CHUNK_TILES - 1:
		return false
	if occupied.has(Chunk.idx(t.x, t.y)):
		return false
	var td: Dictionary = reg.tile_def(chunk.tile_id(t.x, t.y))
	if not td["walkable"] or td["water"] or td["hazard"]:
		return false
	if water_edge:
		var found := false
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := t + off
			if n.x >= 0 and n.y >= 0 and n.x < WG.CHUNK_TILES and n.y < WG.CHUNK_TILES \
					and reg.tile_def(chunk.tile_id(n.x, n.y))["water"]:
				found = true
				break
		if not found:
			return false
	return true


func _tile_biome_id(chunk: RefCounted, t: Vector2i) -> String:
	if chunk.layer != 0:
		return ""
	var b_idx: int = chunk.biome_at(t.x, t.y)
	return "" if b_idx == 255 else str(reg.biomes[b_idx]["id"])


func _near_water(chunk: RefCounted, t: Vector2i, radius: int = 1) -> bool:
	for oy: int in range(-radius, radius + 1):
		for ox: int in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var nx := t.x + ox
			var ny := t.y + oy
			if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
				continue
			if reg.tile_def(chunk.tile_id(nx, ny))["water"]:
				return true
	return false


func _tree_spacing_ok(chunk: RefCounted, tile: Vector2i, node_name: String) -> bool:
	var min_dist := COMMON_TREE_SPACING
	if _is_solitary_tree(node_name):
		min_dist = SOLITARY_TREE_SPACING
	for s: Dictionary in chunk.sites:
		if str(s.get("kind", "")) != "tree":
			continue
		var other := Vector2(float(int(s["tx"])), float(int(s["ty"])))
		var dist := Vector2(float(tile.x), float(tile.y)).distance_to(other)
		var other_name := str(s.get("node", ""))
		var needed := maxf(min_dist, SOLITARY_TREE_SPACING if _is_solitary_tree(other_name) else COMMON_TREE_SPACING)
		if dist < needed:
			return false
	return true


func _is_solitary_tree(node_name: String) -> bool:
	var n := node_name.to_lower()
	return n.contains("imbued") or n.contains("magic") or n.contains("aether") or n.contains("lunarwood")


func _regular_tree_entry() -> Dictionary:
	for e: Dictionary in reg.node_table.get("woodcutting", []):
		if str(e["name"]) == "Regular Tree":
			return e
	return {}


func _pick_forest_tree_node(chunk: RefCounted, biome_id: String, tile: Vector2i, req: int, salt: int) -> Dictionary:
	var fitting := _fitting_nodes(chunk, "woodcutting", tile, req)
	if fitting.is_empty():
		return _pick_node(chunk, "woodcutting", tile, req, salt)
	var common: Array = []
	for e: Dictionary in fitting:
		var name := str(e["name"])
		if not _is_solitary_tree(name) and not name.to_lower().contains("willow"):
			common.append(e)
	if not common.is_empty():
		if req <= 1:
			for e: Dictionary in common:
				if str(e["name"]) == "Regular Tree":
					return e
		if biome_id == "forest":
			for e: Dictionary in common:
				if str(e["name"]) == "Oak Tree":
					return e
		return common[int(WG.hash_i(world_seed, chunk.cx * 31 + tile.x, chunk.cy * 31 + tile.y, 230 + salt) % common.size())]
	return fitting[int(WG.hash_i(world_seed, chunk.cx * 31 + tile.x, chunk.cy * 31 + tile.y, 231 + salt) % fitting.size())]


func _pick_water_tree_node(chunk: RefCounted, tile: Vector2i, req: int, salt: int) -> Dictionary:
	return _pick_node(chunk, "woodcutting", tile, req, salt)


func _fitting_nodes(chunk: RefCounted, skill: String, tile: Vector2i, req: int) -> Array:
	var entries: Array = reg.node_table.get(skill, [])
	var biome_id := _tile_biome_id(chunk, tile)
	var lvl_min := maxi(1, roundi(float(req) * 0.3))
	var lvl_max := req + 10
	var fitting: Array = []
	for e: Dictionary in entries:
		if chunk.layer == 0 and not Array(e["biomes"]).has(biome_id):
			continue
		if chunk.layer != 0 and not Array(e["cave_layers"]).has(chunk.layer):
			continue
		var lvl := int(e["level"])
		if lvl >= lvl_min and lvl <= lvl_max:
			fitting.append(e)
	return fitting


## Choose a gather node for this skill, biome/layer, and zone level band.
## Prefers nodes near the zone's requirement so far zones feel richer, while
## the band floor keeps a sprinkle of lower nodes for variety.
func _pick_node(chunk: RefCounted, skill: String, tile: Vector2i, req: int, salt: int) -> Dictionary:
	var entries: Array = reg.node_table.get(skill, [])
	if entries.is_empty():
		return {}
	var biome_id := ""
	if chunk.layer == 0:
		var b_idx: int = chunk.biome_at(tile.x, tile.y)
		if b_idx != 255:
			biome_id = str(reg.biomes[b_idx]["id"])
	var lvl_min := maxi(1, roundi(float(req) * 0.3))
	var lvl_max := req + 10
	var fitting: Array = []
	var fallback: Array = []
	for e: Dictionary in entries:
		var ok := Array(e["biomes"]).has(biome_id) if chunk.layer == 0 \
			else Array(e["cave_layers"]).has(chunk.layer)
		if not ok:
			continue
		fallback.append(e)
		var lvl := int(e["level"])
		if lvl >= lvl_min and lvl <= lvl_max:
			fitting.append(e)
	if fitting.is_empty():
		# No node in the band: take the highest-level allowed node still under
		# the zone cap. If even the cheapest node outlevels the zone (e.g.
		# swamp herbs in a level-1 zone), spawn nothing — low zones shouldn't
		# tease unreachable nodes.
		var best: Dictionary = {}
		for e: Dictionary in fallback:
			if int(e["level"]) <= lvl_max and (best.is_empty() or int(e["level"]) > int(best["level"])):
				best = e
		return best
	var total := 0.0
	var weights: Array = []
	for e: Dictionary in fitting:
		var w := 1.0 / (1.0 + absf(float(req) - float(e["level"])) * 0.12)
		weights.append(w)
		total += w
	var target := WG.r01(world_seed, chunk.cx * 17 + tile.x, chunk.cy * 17 + tile.y, 90 + salt) * total
	for i: int in fitting.size():
		target -= float(weights[i])
		if target <= 0.0:
			return fitting[i]
	return fitting.back()
