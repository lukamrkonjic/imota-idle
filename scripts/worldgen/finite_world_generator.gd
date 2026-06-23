extends RefCounted
class_name FiniteWorldGenerator
## Bounded, finite-world generation service — the single home for compiling an
## authored WorldSpec into concrete chunk data. Used by BOTH the offline bake
## (tools/world_bake.gd) and the in-editor "Generate World" action, so they can
## never diverge.
##
## It reuses the existing infinite generator (world_generator.gd) per worker
## thread, then layers the authored, finite-level concerns on top:
##   • coastline — the outer chunk rings grade into open sea, so the continent
##     has an edge instead of tiling forever;
##   • roads / rivers / lakes — rasterized from the spec's polylines/discs;
##   • (difficulty/zone bands already come from the spec's regions + zone_map).
##
## generate_region() runs across all CPU threads (each worker owns a private
## generator → generation is a pure function of (cx, cy, seed)). The shared spec
## memo caches are pre-warmed single-threaded first, because letting threads
## trigger those lazy writes concurrently crashes the engine.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const WorldGenerator := preload("res://scripts/worldgen/world_generator.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")
const RoadBrush := preload("res://scripts/worldgen/road_brush.gd")

var reg: RefCounted
var spec: RefCounted
var seed: int
var bounds := Rect2i()
var overrides: Dictionary = {}     # water features (rivers / lakes): tile + flatten elev
var road_tiles: Dictionary = {}    # RoadBrush road body (incl. plank "bridge" decks): tile id
var road_elev: Dictionary = {}     # RoadBrush graded road elevation (Vector2i -> int), walkable ramps
var road_structs: Dictionary = {}  # "cx:cy" -> Array[part] (roadside decor)
var natural_only := false   ## true => terrain + natural life only, no man-made content

var _t_cobble: int
var _t_dirt: int
var _t_water: int
var _t_shallow: int
var _t_sand: int
var _t_deep: int
var _b_ocean: int
var _b_beach: int
var _has_land_mask := false   # authored mask owns the coast => skip the ring-coastline pass

# threading
var _results: Dictionary = {}
var _results_mutex := Mutex.new()
var _done := 0
var _done_mutex := Mutex.new()


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	spec = reg.spec
	seed = p_seed
	bounds = spec.bounds
	_t_cobble = int(reg.tile_index.get("cobble", 0))
	_t_dirt = int(reg.tile_index.get("dirt", 0))
	_t_water = int(reg.tile_index.get("water", 0))
	_t_shallow = int(reg.tile_index.get("shallow", 0))
	_t_sand = int(reg.tile_index.get("sand", 0))
	_t_deep = int(reg.tile_index.get("deep_water", 0))
	_b_ocean = int(reg.biome_index.get("ocean", 255))
	_b_beach = int(reg.biome_index.get("beach", _b_ocean))
	_has_land_mask = spec.active and spec.finite and FileAccess.file_exists(BiomeClassifier.land_mask_path(str(spec.id)))
	overrides = _build_overrides()
	# Roads/bridges compile through the RoadBrush (curves, variable width, feather,
	# elevation-following, auto-bridges). Built once here, single-threaded — it needs
	# a classifier to test where the centerline crosses water.
	if not spec.roads.is_empty():
		var brush := RoadBrush.new()
		# NOTE: roads are graded into walkable climbs when DRAWN in the world editor (it samples the
		# actual baked/edited chunk elevation and writes it straight to chunk.elev). The bake itself
		# leaves authored spec roads flat-following for now — the finite world's elevation is mask-
		# baked, not the procedural elevation_steps, so grading here would need the mask sampler.
		brush.build(reg, seed)
		road_tiles = brush.road_tiles
		road_elev = brush.road_elev
		road_structs = brush.structures


# --- structure collision (derived) --------------------------------------------
# Solid structures block their footprint so the player/pathfinder can't walk
# through them. This is DERIVED from chunk.structures (recomputed on bake / on
# editor save), so it never needs separate undo bookkeeping. Water/walls/hazards
# already block via tile flags, so this layer is only for placed entities.

const _PASSABLE_PROPS := {"lamp": true, "flowerbox": true, "hay": true}


## Footprint block-radius in tiles for a structure part (-1 = no entity collision).
##
## Buildings, houses and city walls are TILE-BACKED: the bake/structure_planner
## already paints non-walkable `building_wall` tiles for their walls while leaving
## interiors, doors and streets walkable, so the tile layer collides them
## correctly. Adding a square entity-footprint on top would wall off the very
## streets/interiors the tiles kept open (and break pathing through a city), so
## those kinds contribute NO entity collision. Only free-standing props that sit
## on otherwise-walkable ground block — and just their own tile, so you route
## around them rather than through them.
static func footprint_radius(part: Dictionary) -> int:
	match str(part.get("kind", "")):
		"building", "house", "bridge":
			return -1   # tile-backed: building walls are non-walkable tiles already
		"city_wall":
			# Ramparts sit on walkable cobble, so they need collision — except the
			# GATE piece (1), which is the road opening you walk through.
			return -1 if int(part.get("piece", 0)) == 1 else 0
		"city_prop":
			return -1 if _PASSABLE_PROPS.has(str(part.get("prop", ""))) else 0
		"fountain", "well", "burrow", "broken_statue", "obelisk", "altar", "anvil", \
		"chest", "ruin_arch", "ruin_pillar", "rubble_pile", "broken_wall", "cart", "meteor":
			return 0    # solid free-standing object — block its own tile
		_:
			return -1   # signs, campfires, tents, lamps… stay passable


## Recompute chunk.collision from its solid structures.
static func apply_structure_collision(chunk: RefCounted) -> void:
	chunk.collision.fill(0)
	var n: int = WG.CHUNK_TILES
	for p: Dictionary in chunk.structures:
		var r: int = footprint_radius(p)
		if r < 0:
			continue
		var lx: int = int(p.get("tx", -99))
		var ly: int = int(p.get("ty", -99))
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var x: int = lx + dx
				var y: int = ly + dy
				if x >= 0 and y >= 0 and x < n and y < n:
					chunk.collision[Chunk.idx(x, y)] = 1


## Default authored spawn: the safe central hub, nudged slightly off-centre (a
## little south) so players naturally expand without starting across rivers from
## the home camp. Keep this measured in tiles, not continent-scale chunks.
func default_spawn_tile() -> Vector2i:
	# Spawn at the home/spawn anchor (the (0,0) camp), not the geometric bounds centre —
	# the two differ when the world is recentred so the authored spawn maps to origin.
	var c: Vector2i = spec.anchor_by_id("spawn").get("chunk", Vector2i.ZERO) if spec != null else Vector2i.ZERO
	var cx := c.x * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
	var cy := c.y * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
	var off := clampi(int(round(float(WG.CHUNK_TILES) * 0.65)), 4, WG.CHUNK_TILES)
	return Vector2i(cx, cy + off)


## Generate every in-bounds chunk. Returns { "cx:cy": Chunk }. `host` is any Node
## used to await between progress polls; `progress_cb` (optional) is called as
## progress_cb.call(done, total).
func generate_region(host: Node, progress_cb := Callable()) -> Dictionary:
	_results.clear()
	_done = 0
	var b := bounds

	# Pre-warm shared spec memo caches single-threaded (writes from worker threads
	# would race and crash). 2-chunk margin covers fill_chunk's padding.
	for cy: int in range(b.position.y - 2, b.end.y + 2):
		for cx: int in range(b.position.x - 2, b.end.x + 2):
			spec.region_for_chunk(cx, cy)
			spec.anchor_for_chunk(cx, cy)

	var work: Array = []
	for cy: int in range(b.position.y, b.end.y):
		for cx: int in range(b.position.x, b.end.x):
			work.append(Vector2i(cx, cy))
	var total := work.size()
	var nthreads: int = clampi(OS.get_processor_count() - 1, 1, 16)
	var groups: Array = []
	for i: int in nthreads:
		groups.append([])
	for i: int in work.size():
		groups[i % nthreads].append(work[i])

	var task_ids: Array = []
	for g: Array in groups:
		task_ids.append(WorkerThreadPool.add_task(_gen_group.bind(g)))
	# Break on actual TASK completion, not on the progress counter: if a worker
	# aborts a chunk (a runtime error), the counter would never reach `total` and
	# a counter-based wait would hang forever. is_task_completed() can't hang.
	while true:
		var all_done := true
		for id: int in task_ids:
			if not WorkerThreadPool.is_task_completed(id):
				all_done = false
				break
		if progress_cb.is_valid():
			_done_mutex.lock()
			var done: int = _done
			_done_mutex.unlock()
			progress_cb.call(done, total)
		if all_done:
			break
		if host != null and host.is_inside_tree():
			await host.get_tree().create_timer(0.1).timeout
		else:
			OS.delay_msec(50)
	for id: int in task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	if _results.size() < total:
		push_warning("FiniteWorldGenerator: only %d/%d chunks generated — some workers failed." % [_results.size(), total])
	return _results


func _gen_group(group: Array) -> void:
	var gen: RefCounted = WorldGenerator.new()
	gen.setup(reg, seed)
	var local: Dictionary = {}
	for c: Vector2i in group:
		var chunk: RefCounted = gen.generate_natural(c.x, c.y) if natural_only else gen.generate(0, c.x, c.y)
		_apply_coastline(chunk, c.x, c.y)
		_apply_overrides(chunk)
		_apply_road_structs(chunk)
		apply_structure_collision(chunk)
		local["%d:%d" % [c.x, c.y]] = chunk
		_done_mutex.lock()
		_done += 1
		_done_mutex.unlock()
	_results_mutex.lock()
	_results.merge(local)
	_results_mutex.unlock()


# --- authored rasterization (roads / rivers / lakes / coastline) ---------------

func _build_overrides() -> Dictionary:
	# Water features only. Roads + bridges are compiled by the RoadBrush (see setup).
	var ov: Dictionary = {}
	for feat: Dictionary in spec.features:
		match str(feat.get("kind", "")):
			"river":
				_stamp_polyline(ov, feat.get("points", []), int(feat.get("width", 2)), _t_water, _t_shallow)
			"lake":
				_stamp_disc(ov, feat.get("tile", Vector2i.ZERO), int(feat.get("radius", 6)), _t_water, _t_shallow)
	return ov


func _stamp_polyline(ov: Dictionary, points: Array, width: int, core: int, rim: int) -> void:
	for i: int in range(points.size() - 1):
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		var steps := maxi(1, int(Vector2(b - a).length()))
		for s: int in range(steps + 1):
			var p := Vector2(a).lerp(Vector2(b), float(s) / float(steps))
			_stamp_disc(ov, Vector2i(roundi(p.x), roundi(p.y)), width, core, rim)


func _stamp_disc(ov: Dictionary, center: Vector2i, r: int, core: int, rim: int) -> void:
	var rr := r + (1 if rim >= 0 else 0)
	for dy: int in range(-rr, rr + 1):
		for dx: int in range(-rr, rr + 1):
			var d2 := dx * dx + dy * dy
			var key := center + Vector2i(dx, dy)
			if d2 <= r * r:
				ov[key] = core
			elif rim >= 0 and d2 <= rr * rr and not ov.has(key):
				ov[key] = rim


func _apply_overrides(chunk: RefCounted) -> void:
	if overrides.is_empty() and road_tiles.is_empty():
		return
	var bx: int = chunk.cx * WG.CHUNK_TILES
	var by: int = chunk.cy * WG.CHUNK_TILES
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			var key := Vector2i(bx + lx, by + ly)
			var i := Chunk.idx(lx, ly)
			# Water features (rivers / lakes): carve water and flatten.
			if overrides.has(key):
				chunk.tiles[i] = int(overrides[key])
				if chunk.elev.size() > i:
					chunk.elev[i] = 0
			# Road body (incl. plank "bridge" decks): repaint the tile, and where the brush
			# graded a walkable ramp, override the elevation so the road climbs smoothly.
			if road_tiles.has(key):
				chunk.tiles[i] = int(road_tiles[key])
				if road_elev.has(key) and chunk.elev.size() > i:
					chunk.elev[i] = int(road_elev[key])


## Append the RoadBrush's per-chunk structure parts (bridge rails, roadside decor)
## to this chunk. Local tile coords were already resolved when the brush built them.
func _apply_road_structs(chunk: RefCounted) -> void:
	var key := "%d:%d" % [chunk.cx, chunk.cy]
	if not road_structs.has(key):
		return
	for part: Dictionary in road_structs[key]:
		chunk.structures.append(part.duplicate())


func _apply_coastline(chunk: RefCounted, cx: int, cy: int) -> void:
	# With an authored land mask, the coast is already where the mask says (ocean
	# biome -> deep/shallow tiles per tile_at, sand ring on shore). Forcing the
	# outer bounds rings to sea here would cut any landmass that reaches the edge,
	# so let the mask own the entire coastline.
	if _has_land_mask:
		return
	var b := bounds
	var ring: int = min(
		min(cx - b.position.x, b.end.x - 1 - cx),
		min(cy - b.position.y, b.end.y - 1 - cy))
	if ring > 4:
		return

	var min_tx: int = b.position.x * WG.CHUNK_TILES
	var min_ty: int = b.position.y * WG.CHUNK_TILES
	var max_tx: int = b.end.x * WG.CHUNK_TILES - 1
	var max_ty: int = b.end.y * WG.CHUNK_TILES - 1
	var base_tx: int = cx * WG.CHUNK_TILES
	var base_ty: int = cy * WG.CHUNK_TILES
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			var gtx: int = base_tx + lx
			var gty: int = base_ty + ly
			var edge: float = float(min(
				min(gtx - min_tx, max_tx - gtx),
				min(gty - min_ty, max_ty - gty)))
			var coast_width: float = lerpf(8.0, 38.0, _edge_noise(gtx, gty))
			var i := Chunk.idx(lx, ly)
			if edge < coast_width:
				var depth: float = edge / maxf(coast_width, 1.0)
				var tid: int = _t_deep if depth < 0.24 else (_t_water if depth < 0.72 else _t_shallow)
				_set_coast_tile(chunk, i, tid, _b_ocean)
			elif edge < coast_width + 2.0:
				var td: Dictionary = reg.tile_def(chunk.tiles[i])
				if bool(td.get("walkable", false)) and not bool(td.get("water", false)) and not bool(td.get("hazard", false)):
					_set_coast_tile(chunk, i, _t_sand, _b_beach)


func _set_coast_tile(chunk: RefCounted, i: int, tid: int, biome_idx: int) -> void:
	chunk.tiles[i] = tid
	if biome_idx != 255:
		chunk.biomes_t[i] = biome_idx
		chunk.parent_biomes_t[i] = biome_idx
		chunk.sub_biomes_t[i] = 255
	if chunk.elev.size() > i:
		chunk.elev[i] = 0
	if chunk.collision.size() > i:
		chunk.collision[i] = 0


func _edge_noise(gtx: int, gty: int) -> float:
	var coarse := _smooth_hash_noise(gtx, gty, 30.0, 2401)
	var fine := _smooth_hash_noise(gtx + 173, gty - 91, 11.0, 2402)
	return clampf(coarse * 0.76 + fine * 0.24, 0.0, 1.0)


func _smooth_hash_noise(gtx: int, gty: int, scale: float, salt: int) -> float:
	var x: float = float(gtx) / scale
	var y: float = float(gty) / scale
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := _smooth_frac(x - float(x0))
	var fy := _smooth_frac(y - float(y0))
	var n00 := WG.r01(seed, x0, y0, salt)
	var n10 := WG.r01(seed, x0 + 1, y0, salt)
	var n01 := WG.r01(seed, x0, y0 + 1, salt)
	var n11 := WG.r01(seed, x0 + 1, y0 + 1, salt)
	return lerpf(lerpf(n00, n10, fx), lerpf(n01, n11, fx), fy)


func _smooth_frac(v: float) -> float:
	return v * v * (3.0 - 2.0 * v)
