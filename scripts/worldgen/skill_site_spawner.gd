extends RefCounted
## Populates chunks with gather sites (trees, rocks, fishing spots, bushes...).
## Which node spawns where is decided by data: biome skillWeights pick the
## skill, then data/world/skill_sites.json rules + the zone's level requirement
## pick a node from the Bloobs export. Richer, higher-level nodes appear in
## higher-tier zones; cave layers shift the band up via oreLevelBonus.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const BASE_SITES_PER_CHUNK := 1.6
const PLACE_ATTEMPTS := 28
const TREE_GRID := 7
const ORE_GRID := 9
const FOREST_BIOMES := ["forest", "dense_forest", "swamp", "jungle", "boreal_forest", "grove", "bamboo_thicket"]
const WATER_TREE_BIOMES := ["plains", "forest", "dense_forest", "swamp", "jungle", "boreal_forest", "savanna"]
const TREE_GROUND_TILES := ["grass", "grass_dark", "marsh", "mud", "frozen_grass", "dirt"]
const WATER_SURFACE_TILES := ["deep_water", "water", "shallow"]
const SAND_TILES := ["sand", "sand_dune"]
const ROCKY_TILES := ["rock", "cobble", "lava_rock"]
var reg: RefCounted
var world_seed: int = 0
var _tree_cells: Dictionary = {}  # global tree-slot key -> true
var _ore_cells: Dictionary = {}  # global ore-slot key -> true


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed
	_tree_cells.clear()
	_ore_cells.clear()


func populate(chunk: RefCounted, occupied: Dictionary, _placement_grid: RefCounted = null) -> void:
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
	var rocky_bonus := _rocky_tile_count(chunk)
	if rocky_bonus > 0:
		weights["mining"] = float(weights.get("mining", 0.0)) * (1.0 + float(rocky_bonus) * 0.14)
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
			tile = _pick_tree_tile(chunk, occupied, b if FOREST_BIOMES.has(b) else "", 240 + i)
		elif skill == "mining":
			tile = _pick_rocky_tile(chunk, occupied, i)
			if tile.x < 0:
				continue
			if not _claim_ore_slot(chunk, tile):
				continue
		else:
			tile = _pick_tile(chunk, occupied, i, water_edge)
		if tile.x < 0:
			continue
		var entry := _pick_node(chunk, skill, tile, req, i)
		if entry.is_empty():
			continue
		if skill == "woodcutting":
			if not _place_tree_site(chunk, occupied, entry, tile, cfg, false):
				continue
		else:
			_add_site(chunk, occupied, skill, entry, tile, cfg)


func _place_forest_patches(chunk: RefCounted, occupied: Dictionary, req: int, biome_id: String) -> void:
	if not FOREST_BIOMES.has(biome_id):
		return
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var patch_count := 1 if WG.r01(world_seed, chunk.cx, chunk.cy, 168) < 0.55 else 0
	var trees_per_patch := 2
	if biome_id in ["dense_forest", "jungle", "bamboo_thicket"]:
		patch_count = 1 + (1 if WG.r01(world_seed, chunk.cx, chunk.cy, 169) < 0.25 else 0)
		trees_per_patch = 3
	elif biome_id == "swamp":
		trees_per_patch = 2
	for p: int in patch_count:
		var candidates := _tree_slot_candidates(chunk, occupied, biome_id, 170 + p)
		if candidates.is_empty():
			continue
		var entry := _pick_forest_tree_node(chunk, biome_id, candidates[0]["tile"], req, 172 + p)
		if entry.is_empty():
			continue
		var node_name := str(entry["name"])
		var rare_patch := _is_solitary_tree(node_name)
		var wanted := 1 if rare_patch else mini(trees_per_patch, candidates.size())
		var placed := 0
		for slot: Dictionary in candidates:
			if placed >= wanted:
				break
			if _place_tree_site(chunk, occupied, entry, slot["tile"], cfg):
				placed += 1


func _tree_cell_key(gtx: int, gty: int) -> String:
	return "%d:%d" % [floori(float(gtx) / float(TREE_GRID)), floori(float(gty) / float(TREE_GRID))]


func _tree_cell_for_global(gtx: int, gty: int) -> Vector2i:
	return Vector2i(floori(float(gtx) / float(TREE_GRID)), floori(float(gty) / float(TREE_GRID)))


func _tree_tile_in_cell(chunk: RefCounted, cell: Vector2i, salt: int) -> Vector2i:
	for attempt: int in TREE_GRID * TREE_GRID:
		var jx: int = WG.hash_i(world_seed, cell.x, cell.y, 300 + salt + attempt) % TREE_GRID
		var jy: int = WG.hash_i(world_seed, cell.y, cell.x, 301 + salt + attempt) % TREE_GRID
		var gtx: int = cell.x * TREE_GRID + jx
		var gty: int = cell.y * TREE_GRID + jy
		var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
		var ly: int = gty - chunk.cy * WG.CHUNK_TILES
		if lx >= 1 and ly >= 1 and lx < WG.CHUNK_TILES - 1 and ly < WG.CHUNK_TILES - 1:
			return Vector2i(lx, ly)
	return Vector2i(-1, -1)


func _tree_slot_free(gtx: int, gty: int) -> bool:
	return not _tree_cells.has(_tree_cell_key(gtx, gty))


func _claim_tree_slot(gtx: int, gty: int) -> void:
	_tree_cells[_tree_cell_key(gtx, gty)] = true


func _ore_cell_key(gtx: int, gty: int) -> String:
	return "%d:%d" % [floori(float(gtx) / float(ORE_GRID)), floori(float(gty) / float(ORE_GRID))]


func _claim_ore_slot(chunk: RefCounted, tile: Vector2i) -> bool:
	var gtx: int = chunk.cx * WG.CHUNK_TILES + tile.x
	var gty: int = chunk.cy * WG.CHUNK_TILES + tile.y
	var key := _ore_cell_key(gtx, gty)
	if _ore_cells.has(key):
		return false
	_ore_cells[key] = true
	return true


func _place_tree_site(
		chunk: RefCounted,
		occupied: Dictionary,
		entry: Dictionary,
		tile: Vector2i,
		cfg: Dictionary,
		water_edge: bool = false) -> bool:
	if tile.x < 0:
		return false
	var gtx: int = chunk.cx * WG.CHUNK_TILES + tile.x
	var gty: int = chunk.cy * WG.CHUNK_TILES + tile.y
	if not _tree_slot_free(gtx, gty):
		return false
	if not _tree_tile_ok(chunk, occupied, tile, water_edge):
		return false
	_claim_tree_slot(gtx, gty)
	_add_site(chunk, occupied, "woodcutting", entry, tile, cfg)
	return true


func _tree_slot_candidates(
		chunk: RefCounted,
		occupied: Dictionary,
		biome_id: String,
		salt: int,
		water_edge_only: bool = false) -> Array:
	var cells: Array = _cells_overlapping_chunk(chunk)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return WG.hash_i(world_seed, a.x, a.y, salt) < WG.hash_i(world_seed, b.x, b.y, salt))
	var out: Array = []
	for i: int in cells.size():
		var cell: Vector2i = cells[i]
		if _tree_cells.has(_tree_cell_key(cell.x * TREE_GRID, cell.y * TREE_GRID)):
			continue
		var t := _tree_tile_in_cell(chunk, cell, salt + i)
		if t.x < 0:
			continue
		if not _tree_tile_ok(chunk, occupied, t, water_edge_only):
			continue
		if biome_id != "" and _tile_biome_id(chunk, t) != biome_id:
			continue
		if water_edge_only:
			if not _adjacent_water(chunk, t):
				continue
		elif _adjacent_water(chunk, t):
			continue
		out.append({"cell": cell, "tile": t})
	return out


func _cells_overlapping_chunk(chunk: RefCounted) -> Array:
	var gx0: int = chunk.cx * WG.CHUNK_TILES
	var gy0: int = chunk.cy * WG.CHUNK_TILES
	var gx1: int = gx0 + WG.CHUNK_TILES - 1
	var gy1: int = gy0 + WG.CHUNK_TILES - 1
	var cx0: int = floori(float(gx0) / float(TREE_GRID))
	var cy0: int = floori(float(gy0) / float(TREE_GRID))
	var cx1: int = floori(float(gx1) / float(TREE_GRID))
	var cy1: int = floori(float(gy1) / float(TREE_GRID))
	var out: Array = []
	for cy: int in range(cy0, cy1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			out.append(Vector2i(cx, cy))
	return out


func _pick_tree_tile(
		chunk: RefCounted,
		occupied: Dictionary,
		biome_id: String,
		salt: int) -> Vector2i:
	var candidates := _tree_slot_candidates(chunk, occupied, biome_id, salt)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[int(WG.hash_i(world_seed, chunk.cx, chunk.cy, 260 + salt) % candidates.size())]["tile"]


func _is_rocky_tile_id(byte_id: int) -> bool:
	if byte_id < 0 or byte_id >= reg.tile_order.size():
		return false
	return ROCKY_TILES.has(reg.tile_order[byte_id])


func _rocky_tile_count(chunk: RefCounted) -> int:
	var n := 0
	for ty: int in WG.CHUNK_TILES:
		for tx: int in WG.CHUNK_TILES:
			if _is_rocky_tile_id(chunk.tile_id(tx, ty)):
				n += 1
	return n


func _pick_rocky_tile(chunk: RefCounted, occupied: Dictionary, salt: int) -> Vector2i:
	for attempt: int in PLACE_ATTEMPTS * 2:
		var tx := 1 + WG.hash_i(world_seed, chunk.cx * 53 + salt, chunk.cy, 280 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var ty := 1 + WG.hash_i(world_seed, chunk.cx, chunk.cy * 53 + salt, 281 + attempt * 2) % (WG.CHUNK_TILES - 2)
		var t := Vector2i(tx, ty)
		if not _tile_ok(chunk, occupied, t, false):
			continue
		if _is_rocky_tile_id(chunk.tile_id(tx, ty)):
			return t
	for attempt: int in PLACE_ATTEMPTS:
		var t := _pick_tile(chunk, occupied, salt + attempt, false)
		if t.x >= 0:
			return t
	return Vector2i(-1, -1)


func _place_home_regular_trees(chunk: RefCounted, occupied: Dictionary) -> void:
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var entry := _regular_tree_entry()
	if entry.is_empty():
		return
	var placed := 0
	for t: Vector2i in [Vector2i(5, 11), Vector2i(10, 11), Vector2i(12, 6), Vector2i(4, 5)]:
		if not _tree_tile_ok(chunk, occupied, t, false):
			continue
		if _place_tree_site(chunk, occupied, entry, t, cfg, false):
			placed += 1
		if placed >= 2:
			break


func _place_waterline_trees(chunk: RefCounted, occupied: Dictionary, req: int, biome_id: String) -> void:
	if not WATER_TREE_BIOMES.has(biome_id) or not _has_water(chunk):
		return
	if WG.r01(world_seed, chunk.cx, chunk.cy, 180) > 0.92:
		return
	var cfg: Dictionary = reg.skill_cfg("woodcutting")
	if cfg.is_empty():
		return
	var wanted := 1 + int(WG.hash_i(world_seed, chunk.cx, chunk.cy, 181) % 2)
	if biome_id in ["forest", "swamp", "dense_forest", "jungle", "bamboo_thicket", "boreal_forest"]:
		wanted += 1
	var placed := 0
	for i: int in range(wanted * 8):
		if placed >= wanted:
			break
		var candidates := _tree_slot_candidates(chunk, occupied, "", 182 + i, true)
		if candidates.is_empty():
			continue
		var slot: Dictionary = candidates[int(WG.hash_i(world_seed, chunk.cx, chunk.cy, 184 + i) % candidates.size())]
		var tile: Vector2i = slot["tile"]
		var entry := _pick_water_tree_node(chunk, tile, req, 183 + i)
		if entry.is_empty():
			continue
		if _place_tree_site(chunk, occupied, entry, tile, cfg, true):
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
			if skill == "woodcutting":
				if not _tree_tile_ok(chunk, occupied, t, false):
					continue
			elif not _tile_ok(chunk, occupied, t, bool(cfg.get("waterEdge", false))):
				continue
			if skill == "mining" and not _claim_ore_slot(chunk, t):
				continue
			_add_site(chunk, occupied, skill, entry, t, cfg)
			placed += 1


func _add_site(chunk: RefCounted, occupied: Dictionary, skill: String, entry: Dictionary, tile: Vector2i, cfg: Dictionary) -> void:
	occupied[Chunk.idx(tile.x, tile.y)] = true
	var site := {
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
	}
	if skill == "fishing":
		var water := _water_tile_beside(chunk, tile)
		if water.x >= 0:
			site["fish_tx"] = water.x
			site["fish_ty"] = water.y
	chunk.sites.append(site)


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
	var td: Dictionary = _tile_def_at(chunk, t.x, t.y)
	if td.is_empty() or not td["walkable"] or td["water"] or td["hazard"]:
		return false
	if water_edge and not _adjacent_water(chunk, t):
		return false
	return true


func _tree_tile_ok(chunk: RefCounted, occupied: Dictionary, t: Vector2i, water_edge: bool) -> bool:
	if not _tile_ok(chunk, occupied, t, water_edge):
		return false
	return _is_tree_ground_tile(chunk, t.x, t.y)


func _tile_name_at(chunk: RefCounted, lx: int, ly: int) -> String:
	if lx >= 0 and ly >= 0 and lx < WG.CHUNK_TILES and ly < WG.CHUNK_TILES:
		var tid: int = chunk.tile_id(lx, ly)
		if tid >= 0 and tid < reg.tile_order.size():
			return reg.tile_order[tid]
	if chunk.layer != 0:
		return ""
	var gtx: int = chunk.cx * WG.CHUNK_TILES + lx
	var gty: int = chunk.cy * WG.CHUNK_TILES + ly
	var tid: int = WorldGen.surface_tile_id(gtx, gty)
	if tid >= 0 and tid < reg.tile_order.size():
		return reg.tile_order[tid]
	return ""


func _tile_def_at(chunk: RefCounted, lx: int, ly: int) -> Dictionary:
	var tname: String = _tile_name_at(chunk, lx, ly)
	if tname.is_empty() or not reg.tile_index.has(tname):
		return {}
	return reg.tile_def(int(reg.tile_index[tname]))


func _is_tree_ground_tile(chunk: RefCounted, tx: int, ty: int) -> bool:
	var tname: String = _tile_name_at(chunk, tx, ty)
	if tname.is_empty() or not TREE_GROUND_TILES.has(tname):
		return false
	if WATER_SURFACE_TILES.has(tname) or SAND_TILES.has(tname):
		return false
	var td: Dictionary = _tile_def_at(chunk, tx, ty)
	return not td.is_empty() and bool(td.get("walkable", false)) \
		and not bool(td.get("water", false)) and not bool(td.get("hazard", false))


func _adjacent_water(chunk: RefCounted, t: Vector2i) -> bool:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var tname: String = _tile_name_at(chunk, t.x + off.x, t.y + off.y)
		if WATER_SURFACE_TILES.has(tname):
			return true
	return false


func _water_tile_beside(chunk: RefCounted, shore: Vector2i) -> Vector2i:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var w := Vector2i(shore.x + off.x, shore.y + off.y)
		var tname: String = _tile_name_at(chunk, w.x, w.y)
		if WATER_SURFACE_TILES.has(tname):
			return w
	return Vector2i(-1, -1)


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
	var fitting := _fitting_nodes(chunk, "woodcutting", tile, req)
	var willows: Array = []
	for e: Dictionary in fitting:
		if str(e["name"]).to_lower().contains("willow"):
			willows.append(e)
	if willows.is_empty():
		return {}
	return willows[int(WG.hash_i(world_seed, chunk.cx * 31 + tile.x, chunk.cy * 31 + tile.y, 232 + salt) % willows.size())]


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
