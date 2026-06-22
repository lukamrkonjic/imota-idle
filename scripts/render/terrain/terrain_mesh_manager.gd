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
const TERRAIN_CATCHUP_BUILDS := 5   # extra chunk meshes built in one frame while the ring is filling

var world: Node2D
var terrain_root: Node3D
var mesher: TerrainChunkMesher

var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_nbr: Dictionary = {}      # chunk key -> neighbour-data count at last build (seam reconcile)
var _chunk_wait: Dictionary = {}     # chunk key -> frames waited for neighbour data (defer fallback)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (apron index; shared w/ mesher)
var _terrain_built := false          # did a chunk mesh build this frame (stagger batch rebuild off it)
var _chunk_used_ms: Dictionary = {}  # chunk key -> last ms it was kept-visible (eviction tie-break)


func setup(w: Node2D, root: Node3D, m: TerrainChunkMesher) -> void:
	world = w
	terrain_root = root
	mesher = m
	mesher.set_chunk_lookup(_chunk_by_key)   # share the apron index (same object, refilled each frame)


## Build/free per-chunk terrain meshes to match the camera's visual coverage (stream_view).
func update(stream_view: TerrainStreamView) -> void:
	var now := Time.get_ticks_msec()
	var live := stream_view.keep_chunks()   # the build/keep set: camera-footprint visual coverage
	# APRON / HALO: index EVERY chunk with loaded data (a ring larger than the build set), so
	# building a chunk can sample its neighbour tiles one ring out and compute complete, matching
	# shared-border corners on the FIRST build — no later seam, no rebuild heal.
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.data_chunks():
		_chunk_by_key[chunk.key()] = chunk
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
	if pick != "":
		_build_into(pick)
		# CATCH-UP: when many chunks are missing at once (just zoomed out / view grew), build a
		# few extra neighbour-complete chunks this frame so the new, larger ring fills in within a
		# fraction of a second instead of crawling in one-per-frame with the edge exposed.
		var missing := 0
		for k: String in live:
			if not _chunk_meshes.has(k):
				missing += 1
		if missing > 24:
			var extra := 0
			for k2: String in live:
				if extra >= TERRAIN_CATCHUP_BUILDS:
					break
				if _chunk_meshes.has(k2) or not _chunk_by_key.has(k2):
					continue
				if _data_nbr_count(k2) == 8:
					_build_into(k2)
					extra += 1
	else:
		# Pass 2b: nothing new to build this frame -> reconcile any chunk that was force-built with
		# partial neighbour data once more of its neighbours have loaded.
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
	_update_terrain_visibility(stream_view, now)


# Build the mesh for a loaded chunk and register it.
func _build_into(key: String) -> void:
	var node := mesher.build_chunk_terrain(_chunk_by_key[key])
	terrain_root.add_child(node)
	_chunk_meshes[key] = node
	_chunk_nbr[key] = _data_nbr_count(key)
	_chunk_wait.erase(key)
	_terrain_built = true


## Editor hook (world editor's live 3D view): discard the built terrain mesh for a chunk and its
## 8 neighbours, so the per-frame update build loop re-meshes them from the now-edited (shared)
## chunk data — borders re-stitch because the neighbours rebuild too.
func rebuild_chunk(cx: int, cy: int) -> void:
	var layer: int = world.current_layer
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var k := WG.key(layer, cx + dx, cy + dy)
			if _chunk_meshes.has(k):
				var n: Node = _chunk_meshes[k]
				if is_instance_valid(n):
					n.queue_free()
				_chunk_meshes.erase(k)
				_chunk_nbr.erase(k)
				_chunk_wait.erase(k)


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
