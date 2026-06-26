extends RefCounted
class_name TerrainMeshManager
## Terrain mesh LIFECYCLE (extracted from the WorldRender3D monolith): builds per-chunk meshes
## incrementally (a few per frame, neighbour-data-aware so borders are seamless on first build),
## reconciles seams when more neighbour data arrives, keeps the loaded-data apron index in sync,
## drives VISIBILITY off the camera-footprint visual set (NOT a player-centred radius — the fog/
## cutoff fix), and evicts only when over the persisted-mesh budget.
##
## It owns the chunk_by_key apron index and shares it (by reference) with the mesher so height
## sampling sees the live data. Mesh GENERATION itself lives in TerrainChunkMesher.

const WG := preload("res://scripts/worldgen/wg.gd")

const DEFER_MAX_WAIT := 24          # frames a chunk may wait for neighbour data before force-building
const MAX_TERRAIN_MESHES := 1400    # persisted terrain budget; ~radius-21-chunk explored area
const TERRAIN_CATCHUP_BUILDS := 1   # one extra only after the camera settles; avoids zoom-time mesh spikes
const TERRAIN_CATCHUP_BUDGET_USEC := 3500
const ZOOM_SETTLE_MS := 220          # wheel/pinch pauses this long before detailed terrain catches up

var world: Node2D
var terrain_root: Node3D
var mesher: TerrainChunkMesher

var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_nbr: Dictionary = {}      # chunk key -> neighbour-data count at last build (seam reconcile)
var _chunk_wait: Dictionary = {}     # chunk key -> frames waited for neighbour data (defer fallback)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (apron index; shared w/ mesher)
var _terrain_built := false          # did a chunk mesh build this frame (stagger batch rebuild off it)
var _chunk_used_ms: Dictionary = {}  # chunk key -> last ms it was kept-visible (eviction tie-break)
var _last_camera_zoom := -1.0
var _last_zoom_change_ms := -ZOOM_SETTLE_MS

# Opt-in sub-phase timing (set by WorldRender3D when `-- --perf-probe`).
var probe := false
var _sub: Dictionary = {}
var _sub_frames := 0
var _nbuild_total := 0


func consume_sub() -> Dictionary:
	var n := maxi(1, _sub_frames)
	var out: Dictionary = {}
	for k: String in ["apron", "scan", "build_pick", "reconcile", "vis"]:
		out["mesh_" + k] = int(float(_sub.get(k, 0.0)) / float(n))
	out["mesh_nbuilds_total"] = int(_sub.get("nbuilds", 0.0))   # SUM, not mean
	var nb := maxf(1.0, _sub.get("nbuilds", 0.0))
	out["mesh_us_per_build"] = int(float(_sub.get("build_us_sum", 0.0)) / nb)   # true single-build cost
	out["mesh_us_loop"] = int(float(_sub.get("loop_us_sum", 0.0)) / nb)        # sampling+add_vertex
	out["mesh_us_commit"] = int(float(_sub.get("commit_us_sum", 0.0)) / nb)    # SurfaceTool.commit
	out["mesh_water_builds"] = int(_sub.get("water_builds", 0.0))
	_sub.clear()
	_sub_frames = 0
	return out


func _sub_add(k: String, v: float) -> void:
	_sub[k] = float(_sub.get(k, 0.0)) + v


func setup(w: Node2D, root: Node3D, m: TerrainChunkMesher) -> void:
	world = w
	terrain_root = root
	mesher = m
	mesher.set_chunk_lookup(_chunk_by_key)   # share the apron index (same object, refilled each frame)


## Build/free per-chunk terrain meshes to match the camera's visual coverage (stream_view).
func update(stream_view: TerrainStreamView) -> void:
	var now := Time.get_ticks_msec()
	var zoom_interacting := _is_zoom_interacting(now)
	var live := stream_view.keep_chunks()   # the build/keep set: camera-footprint visual coverage
	var _ta := Time.get_ticks_usec()
	# APRON / HALO: index EVERY chunk with loaded data (a ring larger than the build set), so
	# building a chunk can sample its neighbour tiles one ring out and compute complete, matching
	# shared-border corners on the FIRST build — no later seam, no rebuild heal.
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.data_chunks():
		_chunk_by_key[chunk.key()] = chunk
	var _tb := Time.get_ticks_usec()
	# Pass 2 (DEFER): build at most one mesh per frame (each SurfaceTool build is a few ms), and
	# prefer the highest-priority (camera-visible) chunk whose 8 neighbours' data is already
	# present, so its borders are seamless the first time. Only chunks whose OWN data is loaded
	# are buildable (footprint chunks still streaming in are skipped until their data arrives).
	var pick := ""
	var pick_pri := 99
	for key2: String in live:
		if _chunk_meshes.has(key2) or not _chunk_by_key.has(key2):
			continue
		if _data_nbr_count(key2) != 8:
			continue
		var pri := stream_view.priority_for_chunk(key2)
		if pri < pick_pri:
			pick_pri = pri
			pick = key2
			if pri == 0:
				break   # camera-visible + seamless — can't do better
	if pick == "":
		# Nothing seamless ready: fall back to the longest-waiting loaded chunk so terrain still
		# appears (a world-edge chunk whose neighbour will never load); reconciled later.
		var best_w := DEFER_MAX_WAIT
		for key2: String in live:
			if _chunk_meshes.has(key2) or not _chunk_by_key.has(key2):
				continue
			var w := int(_chunk_wait.get(key2, 0)) + 1
			_chunk_wait[key2] = w
			if w > best_w:
				best_w = w
				pick = key2
	_terrain_built = false
	var _tc := Time.get_ticks_usec()
	var _nb0 := _nbuild_total
	# Zooming out can expose dozens of chunks at once. The hybrid underlay already covers the
	# temporary gap, so defer expensive detailed mesh construction until the wheel/pinch settles
	# rather than stacking several SurfaceTool builds into every input frame.
	var _t_recon0 := 0
	if pick != "" and not zoom_interacting:
		var build_started := Time.get_ticks_usec()
		_build_into(pick)
		# CATCH-UP: when many chunks are missing at once (just zoomed out / view grew), build a
		# single additional neighbour-complete chunk in the same frame, only while inside a small
		# CPU budget. This settles far more smoothly than the former five-build burst.
		var missing := 0
		for k: String in live:
			if not _chunk_meshes.has(k):
				missing += 1
		if missing > 24:
			var extra := 0
			for k2: String in live:
				if extra >= TERRAIN_CATCHUP_BUILDS or Time.get_ticks_usec() - build_started > TERRAIN_CATCHUP_BUDGET_USEC:
					break
				if _chunk_meshes.has(k2) or not _chunk_by_key.has(k2):
					continue
				if _data_nbr_count(k2) == 8:
					_build_into(k2)
					extra += 1
	elif not zoom_interacting:
		# Pass 2b: nothing new to build this frame -> reconcile any chunk that was force-built with
		# partial neighbour data once more of its neighbours have loaded.
		_t_recon0 = Time.get_ticks_usec()
		for key2: String in _chunk_meshes.keys():
			if not live.has(key2) or not _chunk_by_key.has(key2):
				continue
			var nc := _data_nbr_count(key2)
			if nc > int(_chunk_nbr.get(key2, -1)):
				var old: Node = _chunk_meshes[key2]
				if is_instance_valid(old):
					old.queue_free()
				_build_into(key2)
				_chunk_nbr[key2] = nc
				break
	# Persist built terrain ("load once"): meshes are NOT freed when the player walks away, so
	# revisiting an area never re-streams or flickers. Only evict when over budget.
	if _chunk_meshes.size() > MAX_TERRAIN_MESHES:
		_evict_far_terrain(_chunk_meshes.size() - MAX_TERRAIN_MESHES, stream_view)
	var _td := Time.get_ticks_usec()
	_update_terrain_visibility(stream_view, now)
	if probe:
		var _te := Time.get_ticks_usec()
		_sub_add("apron", float(_tb - _ta))
		_sub_add("scan", float(_tc - _tb))
		# reconcile branch (_t_recon0 set) vs the pick-build branch are mutually exclusive.
		if _t_recon0 > 0:
			_sub_add("reconcile", float(_td - _t_recon0))
			_sub_add("build_pick", float(_t_recon0 - _tc))
		else:
			_sub_add("build_pick", float(_td - _tc))
		_sub_add("vis", float(_te - _td))
		_sub_add("nbuilds", float(_nbuild_total - _nb0))
		_sub_frames += 1


## Wheel and pinch events update the logic Camera2D immediately. Keep the expensive detailed-mesh
## path dormant for a short settling interval; low-detail terrain remains visible via the hybrid
## fallback, so this is a responsiveness improvement rather than a coverage reduction.
func _is_zoom_interacting(now: int) -> bool:
	if world == null or world._camera == null:
		return false
	var zoom := float(world._camera.zoom.x)
	if _last_camera_zoom < 0.0 or not is_equal_approx(zoom, _last_camera_zoom):
		_last_camera_zoom = zoom
		_last_zoom_change_ms = now
	return now - _last_zoom_change_ms < ZOOM_SETTLE_MS


# Build the mesh for a loaded chunk and register it.
func _build_into(key: String) -> void:
	_nbuild_total += 1
	var _bs := Time.get_ticks_usec()
	var node := mesher.build_chunk_terrain(_chunk_by_key[key])
	if probe:
		_sub_add("build_us_sum", float(Time.get_ticks_usec() - _bs))
		_sub_add("loop_us_sum", float(mesher.dbg_loop_us))
		_sub_add("commit_us_sum", float(mesher.dbg_commit_us))
		if mesher.dbg_had_water:
			_sub_add("water_builds", 1.0)
	terrain_root.add_child(node)
	_chunk_meshes[key] = node
	_chunk_nbr[key] = _data_nbr_count(key)
	_chunk_wait.erase(key)
	_terrain_built = true


## Editor hook (world editor's live 3D view): discard the built terrain mesh for a chunk and its
## 8 neighbours, so the per-frame update build loop re-meshes them from the now-edited (shared)
## chunk data — borders re-stitch because the neighbours rebuild too.
func rebuild_chunk(cx: int, cy: int) -> void:
	# Re-mesh the edited chunk AND its 8 neighbours so shared borders re-stitch. Each is an
	# IN-PLACE swap (build new mesh → add → free old), so a chunk is never missing for a frame.
	# The old code freed all 9 and let the one-per-frame streamer rebuild them, which flashed the
	# terrain as "loading" while brushing — this version stays flicker-free.
	_reindex_data()
	var layer: int = world.current_layer
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			_swap_chunk_mesh(WG.key(layer, cx + dx, cy + dy))


## Fast editor live-brush hook: re-mesh ONLY this chunk in place (no neighbours), so a drag
## updates at interactive rates. Border seams with neighbours are reconciled by the full
## rebuild_chunk() that runs once on stroke commit.
func rebuild_chunk_instant(cx: int, cy: int) -> void:
	_reindex_data()
	_swap_chunk_mesh(WG.key(world.current_layer, cx, cy))


## Refresh the data index so the mesher samples the just-edited tiles (plus the apron ring).
func _reindex_data() -> void:
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.data_chunks():
		_chunk_by_key[chunk.key()] = chunk


## Build a fresh mesh for one already-meshed chunk and swap it in without ever leaving a gap.
func _swap_chunk_mesh(k: String) -> void:
	if not _chunk_meshes.has(k) or not _chunk_by_key.has(k):
		return
	var old: Node = _chunk_meshes[k]
	var node := mesher.build_chunk_terrain(_chunk_by_key[k])
	node.visible = (not is_instance_valid(old)) or old.visible
	terrain_root.add_child(node)
	_chunk_meshes[k] = node
	_chunk_nbr[k] = _data_nbr_count(k)
	_chunk_wait.erase(k)
	if is_instance_valid(old):
		old.queue_free()


# How many of a chunk's 8 neighbours currently have their DATA loaded (indexed in the apron).
func _data_nbr_count(key: String) -> int:
	var parts := key.split(":")
	if parts.size() < 3:
		return 0
	var layer := int(parts[0])
	var cx := int(parts[1])
	var cy := int(parts[2])
	var c := 0
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if _chunk_by_key.has(WG.key(layer, cx + dx, cy + dy)):
				c += 1
	return c


## Visibility is the camera-footprint visual KEEP set, not a player-centred circle: a chunk is
## shown iff its rect is inside the footprint (+margin+hysteresis). This is the actual fog/cutoff
## fix — a low-pitch ortho camera sees an asymmetric ground footprint, so a radial disc was wrong.
func _update_terrain_visibility(stream_view: TerrainStreamView, now: int) -> void:
	for key: String in _chunk_meshes.keys():
		var node: Node3D = _chunk_meshes[key]
		if not is_instance_valid(node):
			continue
		var kept := stream_view.is_chunk_kept(key)
		node.visible = kept
		if kept:
			_chunk_used_ms[key] = now


## Evict ranking: chunks NOT in the visual keep set first, then farthest from the player, then
## oldest used. Never drops a currently-kept near chunk while a far stale one survives.
func _evict_far_terrain(count: int, stream_view: TerrainStreamView) -> void:
	var g := WG.iso_to_grid(world.player.position)
	var ranked: Array = []
	for key: String in _chunk_meshes.keys():
		var parts := key.split(":")
		if parts.size() < 3:
			continue
		var ct := WG.CHUNK_TILES
		var center := Vector2(float(int(parts[1]) * ct + ct / 2), float(int(parts[2]) * ct + ct / 2))
		var kept := 1 if stream_view.is_chunk_kept(key) else 0
		ranked.append([kept, center.distance_squared_to(g), int(_chunk_used_ms.get(key, 0)), key])
	# not-kept first (kept asc); then farthest first (dist desc); then oldest used (ms asc).
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[2] < b[2])
	for i: int in mini(count, ranked.size()):
		var key: String = ranked[i][3]
		var mi: Node = _chunk_meshes.get(key)
		if is_instance_valid(mi):
			mi.queue_free()
		_chunk_meshes.erase(key)
		_chunk_nbr.erase(key)
		_chunk_wait.erase(key)
		_chunk_used_ms.erase(key)


# ---------------------------------------------------------------------- queries ----

func is_terrain_built_this_frame() -> bool:
	return _terrain_built


func data_chunk_by_key(key: String) -> RefCounted:
	return _chunk_by_key.get(key)


func built_count() -> int:
	return _chunk_meshes.size()


func height_at_iso(pos: Vector2) -> float:
	return mesher.height_at_iso(pos)


func height_at_grid(gx: float, gy: float) -> float:
	return mesher.height_at_grid(gx, gy)
