extends Node2D
## Keeps world streaming smooth by separating terrain visibility from gameplay
## activity. A large terrain ring is rendered so the camera sees far ahead, while
## only the smaller active ring emits spawn/path signals for entities.

signal chunk_loaded(chunk: RefCounted, immediate: bool)
signal chunk_unloaded(chunk: RefCounted)

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var layer := 0
var view_radius := WG.VIEW_RADIUS
var active_radius := WG.ACTIVE_RADIUS
var editor_view_cap := 0           # world editor: raise the data-ring hard cap (chunks); 0 = gameplay MAX_VIEW_RADIUS
var nav_radius := WG.NAV_RADIUS
var detail_radius := WG.DETAIL_RADIUS
var unload_radius := WG.VIEW_RADIUS + 2
# WorkerThreadPool bakes can leave Godot with a non-zero process exit during
# headless validation/shutdown even when every assertion passes. The chunk bake
# is deliberately tiny (64x64 pixels), so synchronous baking is stable enough
# for now and keeps tests/game launch clean.
var use_threads := false

var _renderers: Dictionary = {}   # "cx:cy" -> renderer node
var _chunks: Dictionary = {}      # "cx:cy" -> Chunk
var _visual_only: Dictionary = {} # "cx:cy" -> true, cheap terrain placeholder only
var _active: Dictionary = {}      # "cx:cy" -> true, has emitted chunk_loaded
var _seen: Dictionary = {}        # layer -> {"cx:cy": true}
var _center := Vector2i(2000000, 2000000)
var _tasks: Dictionary = {}       # task id -> chunk key
var _results: Dictionary = {}     # chunk key -> Image (worker -> main handoff)
var _results_mutex := Mutex.new()

# Incremental streaming: after the initial fill, new chunks are queued and loaded
# a few per frame instead of all at once on the crossing frame. This trades a
# slightly slower fill for no frame hiccup when the player walks into a new area.
const LOADS_PER_FRAME := 1
const LOAD_TIME_BUDGET_USEC := 1400
const ACTIVATIONS_PER_FRAME := 1
const DEACTIVATIONS_PER_FRAME := 1
const UNLOADS_PER_FRAME := 1
const TERRAIN_REDRAWS_PER_FRAME := 2
const MESH_REBUILDS_PER_FRAME := 1
const MESH_REBUILD_TIME_BUDGET_USEC := 1800
const MESH_REBUILD_IDLE_MSEC := 180
const DETAIL_UPDATE_IDLE_MSEC := 350
const UNLOAD_IDLE_MSEC := 500
var _load_queue: Array = []       # Array[Vector2i], nearest-first
var _queued: Dictionary = {}      # "cx:cy" -> true (dedupe what's already queued)
var _unload_queue: Array[String] = []
var _queued_unload: Dictionary = {}
# Seam re-draws after a neighbour loads are expensive (a full chunk _draw), so
# they are coalesced and flushed a few per frame instead of all-at-once on load.
var _redraw_queue: Array = []     # Array[String] keys, FIFO
var _redraw_pending: Dictionary = {}  # "cx:cy" -> true (dedupe)
var _activate_queue: Array[String] = []
var _queued_activate: Dictionary = {}
var _deactivate_queue: Array[String] = []
var _queued_deactivate: Dictionary = {}
var _mesh_queue: Array[String] = []
var _queued_mesh: Dictionary = {}
var _mesh_queue_dirty := false
var _last_center_change_msec := 0
var _detail_update_pending := false
const PERF_KEYS := ["load", "redraw", "mesh", "deactivate", "unload", "activate", "detail", "total"]
var _perf_accum: Dictionary = {}
var _perf_frames := 0


## Gameplay-active chunks only. Pathfinding/entities intentionally stay on this
## smaller set even though more terrain chunks are rendered in the distance.
## Active chunks the NAV graph should cover — only the small ring around the
## player, not the (possibly large, zoom-driven) entity ring. Keeps the A*
## rebuild cheap regardless of how far out entities/terrain stream.
func loaded_chunks() -> Array:
	var out: Array = []
	for key: String in _active.keys():
		if _chunks.has(key) and _within_radius(_coord_from_key(key), _center, nav_radius):
			out.append(_chunks[key])
	return out


## Data chunks within `radius` chunks of the player — the 3D terrain BUILD ring, sized by
## the view-distance slider (independent of the small nav ring). Each needs its neighbours'
## data to mesh seamlessly, which the streaming radius (kept >= radius + 1) guarantees.
func terrain_chunks(radius: int) -> Array:
	var out: Array = []
	# A disc (Euclidean), not a square — matches the renderer's radial terrain cull so we
	# don't build corner chunks that would only be hidden. +1 chunk margin keeps the visible
	# disc fully meshed at its edge.
	var r2 := float((radius + 1) * (radius + 1))
	for key: String in _chunks.keys():
		var c := _coord_from_key(key)
		var dx := float(c.x - _center.x)
		var dy := float(c.y - _center.y)
		if dx * dx + dy * dy <= r2:
			out.append(_chunks[key])
	return out


## Every chunk with loaded DATA — the larger streaming ring, a superset of loaded_chunks().
## Renderers index this so they can sample a built chunk's NEIGHBOUR tiles (one ring out)
## and produce seamless shared borders on the first build (the apron / halo pattern).
func data_chunks() -> Array:
	return _chunks.values()


func terrain_chunk_count() -> int:
	return _renderers.size()


func set_visible_rect(world_rect: Rect2) -> void:
	for key: String in _renderers.keys():
		var renderer: Node2D = _renderers[key]
		var chunk: RefCounted = renderer.get("chunk")
		renderer.visible = world_rect.intersects(WG.chunk_aabb(chunk.cx, chunk.cy))


func set_layer(new_layer: int) -> void:
	if new_layer == layer:
		return
	layer = new_layer
	clear_all()


func clear_all() -> void:
	for key: String in _renderers.keys():
		_unload(key)
	_load_queue.clear()
	_queued.clear()
	_unload_queue.clear()
	_queued_unload.clear()
	_activate_queue.clear()
	_queued_activate.clear()
	_deactivate_queue.clear()
	_queued_deactivate.clear()
	_mesh_queue.clear()
	_queued_mesh.clear()
	_mesh_queue_dirty = false
	_detail_update_pending = false
	_active.clear()
	_visual_only.clear()
	_center = Vector2i(2000000, 2000000)


## Call whenever the player moves; loads new chunks only on chunk crossings.
func update_center(world_pos: Vector2) -> void:
	var c := WG.world_to_chunk(world_pos)
	if c == _center:
		return
	# First centering loads the active gameplay ring plus one visual buffer
	# synchronously. Farther visual chunks stream in over following frames.
	var first_fill: bool = _center.x == 2000000
	_center = c
	_last_center_change_msec = Time.get_ticks_msec()
	_refresh(first_fill)


## Zoom-aware streaming: the world recomputes these every frame from the camera
## zoom so the loaded ring always covers the view (plus margin). Re-streams when
## the radius grows and unloads when it shrinks.
func set_radii(p_view: int, p_active: int) -> void:
	# Gameplay caps the data ring at WG.MAX_VIEW_RADIUS; the world editor raises it (editor_view_cap)
	# so a far-zoom aerial view can load DATA all the way out (terrain only meshes where data exists).
	var view_hard: int = editor_view_cap if editor_view_cap > 0 else WG.MAX_VIEW_RADIUS
	var v := clampi(p_view, WG.VIEW_RADIUS, view_hard)
	var a := clampi(p_active, WG.NAV_RADIUS, mini(WG.MAX_ACTIVE_RADIUS, v - 1))
	if v == view_radius and a == active_radius:
		return
	view_radius = v
	active_radius = a
	unload_radius = view_radius + 2
	if _center.x != 2000000:
		_refresh(false)


func _refresh(first_fill: bool) -> void:
	var c := _center
	var needed: Dictionary = {}
	for dy: int in range(-view_radius, view_radius + 1):
		for dx: int in range(-view_radius, view_radius + 1):
			needed["%d:%d" % [c.x + dx, c.y + dy]] = Vector2i(c.x + dx, c.y + dy)
	for key: String in needed:
		if _renderers.has(key) or _queued.has(key):
			continue
		if first_fill and _within_radius(needed[key], c, active_radius + 1):
			_load(needed[key], true)
		else:
			_load_queue.append(needed[key])
			_queued[key] = true
	if not _load_queue.is_empty():
		_load_queue.sort_custom(_closer_to_center)
	for key: String in _renderers.keys():
		if not needed.has(key):
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 2:
				continue
			var dx: int = absi(int(parts[0]) - c.x)
			var dy: int = absi(int(parts[1]) - c.y)
			if dx > unload_radius or dy > unload_radius:
				_queue_unload(key)
	_request_renderer_detail_update(first_fill)
	_sync_active_chunks()


func _load(coords: Vector2i, immediate_active: bool = false) -> void:
	var key := "%d:%d" % [coords.x, coords.y]
	if _visual_only.has(key):
		_hydrate_visual_placeholder(coords, immediate_active)
		return
	var chunk: RefCounted = WorldGen.get_chunk(layer, coords.x, coords.y)
	WorldGen.snapshot_chunk_if_needed(chunk)
	if layer == 0:
		WorldGen.store.mark_explored(coords.x, coords.y)
	_chunks[key] = chunk
	if not _seen.has(layer):
		_seen[layer] = {}
	_seen[layer][key] = true
	var avg := ChunkRenderer.tile_color(WorldGen.reg, chunk.tile_id(WG.CHUNK_TILES / 2, WG.CHUNK_TILES / 2))
	var detail := _detail_for(coords)
	if not immediate_active and detail == ChunkRenderer.DETAIL_FULL and not _detail_updates_allowed():
		detail = ChunkRenderer.DETAIL_LOW
	var renderer: Node2D = ChunkRenderer.new(chunk, avg, detail)
	renderer.name = "Chunk_" + key.replace(":", "_").replace("-", "m")
	# No fade: terrain loads well outside the view (large radius), so it is simply
	# present when it scrolls on screen — fading introduced the visible "pop".
	add_child(renderer)
	_renderers[key] = renderer
	_queue_mesh_rebuild(key)
	_redraw_loaded_neighbors(coords)
	if _within_radius(coords, _center, active_radius):
		if immediate_active:
			_activate(key, chunk, true)
		else:
			_queue_activate(key)


func _load_visual_placeholder(coords: Vector2i) -> void:
	var key := "%d:%d" % [coords.x, coords.y]
	if _renderers.has(key):
		return
	var tid := WorldGen.surface_tile_id(coords.x * WG.CHUNK_TILES + WG.CHUNK_TILES / 2, coords.y * WG.CHUNK_TILES + WG.CHUNK_TILES / 2)
	if tid < 0 or tid >= WorldGen.reg.tile_order.size():
		tid = int(WorldGen.reg.tile_index.get("grass", 0))
	var chunk := Chunk.new()
	chunk.setup(layer, coords.x, coords.y)
	var avg := ChunkRenderer.tile_color(WorldGen.reg, tid)
	var renderer: Node2D = ChunkRenderer.new(chunk, avg, ChunkRenderer.DETAIL_LOW)
	renderer.name = "Chunk_" + key.replace(":", "_").replace("-", "m")
	add_child(renderer)
	_renderers[key] = renderer
	_visual_only[key] = true


func _hydrate_visual_placeholder(coords: Vector2i, immediate_active: bool = false) -> void:
	var key := "%d:%d" % [coords.x, coords.y]
	if not _visual_only.has(key):
		return
	var chunk: RefCounted = WorldGen.get_chunk(layer, coords.x, coords.y)
	WorldGen.snapshot_chunk_if_needed(chunk)
	if layer == 0:
		WorldGen.store.mark_explored(coords.x, coords.y)
	_chunks[key] = chunk
	if not _seen.has(layer):
		_seen[layer] = {}
	_seen[layer][key] = true
	_visual_only.erase(key)
	if _renderers.has(key):
		var renderer: Node2D = _renderers[key]
		renderer.set("chunk", chunk)
		renderer.call("set_detail_level", _detail_for(coords))
		_queue_mesh_rebuild(key)
	_redraw_loaded_neighbors(coords)
	if _within_radius(coords, _center, active_radius):
		if immediate_active:
			_activate(key, chunk, true)
		else:
			_queue_activate(key)


func _closer_to_center(a: Vector2i, b: Vector2i) -> bool:
	var ca := maxi(absi(a.x - _center.x), absi(a.y - _center.y))
	var cb := maxi(absi(b.x - _center.x), absi(b.y - _center.y))
	if ca != cb:
		return ca < cb
	var da := absi(a.x - _center.x) + absi(a.y - _center.y)
	var db := absi(b.x - _center.x) + absi(b.y - _center.y)
	return da < db


func _closer_key_to_center(a: String, b: String) -> bool:
	return _closer_to_center(_coord_from_key(a), _coord_from_key(b))


func _detail_for(coords: Vector2i) -> int:
	return ChunkRenderer.DETAIL_FULL if _within_radius(coords, _center, detail_radius) else ChunkRenderer.DETAIL_LOW


## Frustum-cull the terrain renderers to the camera view (with a generous
## per-chunk margin so a chunk becomes visible just before it scrolls on screen
## and stays until it is fully off screen). Without this, every loaded terrain
## chunk in the wide stream radius is drawn every frame even far off screen.
func set_view_rect(rect: Rect2) -> void:
	for key: String in _renderers.keys():
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999):
			continue
		var aabb := WG.chunk_aabb(coord.x, coord.y).grow(WG.CHUNK_SIZE * 0.5)
		_renderers[key].visible = aabb.intersects(rect)


func _update_renderer_detail() -> void:
	for key: String in _renderers.keys():
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999):
			continue
		if _visual_only.has(key):
			continue
		var renderer: Node2D = _renderers[key]
		renderer.call("set_detail_level", _detail_for(coord))
		if renderer.has_method("needs_mesh_rebuild") and renderer.call("needs_mesh_rebuild"):
			_queue_mesh_rebuild(key)


func _redraw_loaded_neighbors(coords: Vector2i) -> void:
	# Enqueue the existing neighbours for a seam refresh (the just-created chunk
	# already draws fresh on entering the tree, so skip its own centre). The queue
	# is drained a few per frame in _process so a load never triggers a burst of
	# full chunk redraws on the same frame.
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var key := "%d:%d" % [coords.x + dx, coords.y + dy]
			if _renderers.has(key) and not _redraw_pending.has(key):
				_redraw_pending[key] = true
				_redraw_queue.append(key)


func _process(_delta: float) -> void:
	# Stream queued chunks in a few per frame; skip any that are already loaded
	# or that the player has since walked out of range of.
	var p0 := Time.get_ticks_usec()
	var budget := LOADS_PER_FRAME
	var started := Time.get_ticks_usec()
	while budget > 0 and not _load_queue.is_empty():
		if Time.get_ticks_usec() - started > LOAD_TIME_BUDGET_USEC:
			break
		var coord: Vector2i = _load_queue.pop_front()
		var key := "%d:%d" % [coord.x, coord.y]
		_queued.erase(key)
		if _renderers.has(key) and not _visual_only.has(key):
			continue
		if absi(coord.x - _center.x) > view_radius or absi(coord.y - _center.y) > view_radius:
			continue
		if _visual_only.has(key):
			if not _should_load_real_chunk(coord):
				continue
			_load(coord)
		elif _should_load_real_chunk(coord):
			_load(coord)
		else:
			_load_visual_placeholder(coord)
		budget -= 1
	var p1 := Time.get_ticks_usec()
	_process_redraw_queue()
	var p2 := Time.get_ticks_usec()
	_process_mesh_rebuild_queue()
	var p3 := Time.get_ticks_usec()
	_process_deactivation_queue()
	var p4 := Time.get_ticks_usec()
	_process_unload_queue()
	var p5 := Time.get_ticks_usec()
	_process_activation_queue()
	var p6 := Time.get_ticks_usec()
	if _detail_update_pending and _detail_updates_allowed():
		_detail_update_pending = false
		_update_renderer_detail()
	var p7 := Time.get_ticks_usec()
	_record_perf_timings({
		"load": p1 - p0,
		"redraw": p2 - p1,
		"mesh": p3 - p2,
		"deactivate": p4 - p3,
		"unload": p5 - p4,
		"activate": p6 - p5,
		"detail": p7 - p6,
		"total": p7 - p0,
	})


func _record_perf_timings(times: Dictionary) -> void:
	for k: String in PERF_KEYS:
		_perf_accum[k] = float(_perf_accum.get(k, 0.0)) + float(times.get(k, 0))
	_perf_frames += 1


func consume_perf_timings() -> Dictionary:
	var n := maxi(1, _perf_frames)
	var out: Dictionary = {}
	for k: String in PERF_KEYS:
		out[k] = int(float(_perf_accum.get(k, 0.0)) / float(n))
	out["frames"] = _perf_frames
	out["load_q"] = _load_queue.size()
	out["mesh_q"] = _mesh_queue.size()
	out["activate_q"] = _activate_queue.size()
	out["unload_q"] = _unload_queue.size()
	_perf_accum.clear()
	_perf_frames = 0
	return out


func _request_renderer_detail_update(force: bool = false) -> void:
	if force or _detail_updates_allowed():
		_detail_update_pending = false
		_update_renderer_detail()
	else:
		_detail_update_pending = true


func _detail_updates_allowed() -> bool:
	return Time.get_ticks_msec() - _last_center_change_msec >= DETAIL_UPDATE_IDLE_MSEC


func _should_load_real_chunk(coord: Vector2i) -> bool:
	return _within_radius(coord, _center, active_radius + 1) or _detail_updates_allowed()


func _queue_unload(key: String) -> void:
	if not _renderers.has(key) or _queued_unload.has(key):
		return
	_queued_unload[key] = true
	_unload_queue.append(key)


func _process_unload_queue() -> void:
	if not _unloads_allowed():
		return
	var budget := UNLOADS_PER_FRAME
	while budget > 0 and not _unload_queue.is_empty():
		var key: String = _unload_queue.pop_front()
		_queued_unload.erase(key)
		if not _renderers.has(key):
			continue
		var coord := _coord_from_key(key)
		if coord != Vector2i(999999, 999999) and _within_radius(coord, _center, unload_radius):
			continue
		_unload(key)
		budget -= 1


func _process_redraw_queue() -> void:
	var budget := TERRAIN_REDRAWS_PER_FRAME
	while budget > 0 and not _redraw_queue.is_empty():
		var key: String = _redraw_queue.pop_front()
		_redraw_pending.erase(key)
		if _renderers.has(key) and not _visual_only.has(key):
			_renderers[key].mark_dirty()  # rebuild the chunk mesh (seam/shadow may have changed)
			_queue_mesh_rebuild(key)
			budget -= 1


func _queue_mesh_rebuild(key: String) -> void:
	if not _renderers.has(key) or _queued_mesh.has(key):
		return
	_queued_mesh[key] = true
	_mesh_queue.append(key)
	_mesh_queue_dirty = true


func _process_mesh_rebuild_queue() -> void:
	if not _mesh_rebuilds_allowed():
		return
	if _mesh_queue_dirty:
		_mesh_queue.sort_custom(_closer_key_to_center)
		_mesh_queue_dirty = false
	var budget := MESH_REBUILDS_PER_FRAME
	var rebuilt := 0
	var started := Time.get_ticks_usec()
	while budget > 0 and not _mesh_queue.is_empty():
		if rebuilt > 0 and Time.get_ticks_usec() - started > MESH_REBUILD_TIME_BUDGET_USEC:
			break
		var key: String = _mesh_queue.pop_front()
		_queued_mesh.erase(key)
		if not _renderers.has(key):
			continue
		var renderer: Node2D = _renderers[key]
		if renderer.has_method("needs_mesh_rebuild") and renderer.call("needs_mesh_rebuild"):
			renderer.call("rebuild_mesh")
			rebuilt += 1
			budget -= 1


func _mesh_rebuilds_allowed() -> bool:
	return Time.get_ticks_msec() - _last_center_change_msec >= MESH_REBUILD_IDLE_MSEC


func _unload(key: String) -> void:
	var chunk: RefCounted = _chunks.get(key)
	if _active.has(key):
		_deactivate(key, chunk)
	_queued_activate.erase(key)
	_queued_deactivate.erase(key)
	_queued_unload.erase(key)
	if _renderers.has(key):
		_renderers[key].queue_free()
	_renderers.erase(key)
	_visual_only.erase(key)
	_queued_mesh.erase(key)
	_chunks.erase(key)


func _sync_active_chunks() -> void:
	for key: String in _visual_only.keys():
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999) or not _should_load_real_chunk(coord):
			continue
		if _queued.has(key):
			continue
		_queued[key] = true
		if _within_radius(coord, _center, active_radius + 1):
			_load_queue.push_front(coord)
		else:
			_load_queue.append(coord)
	for key: String in _active.keys():
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999) or not _within_radius(coord, _center, active_radius):
			_queue_deactivate(key)
	for key: String in _chunks.keys():
		if _active.has(key):
			continue
		var coord := _coord_from_key(key)
		if coord != Vector2i(999999, 999999) and _within_radius(coord, _center, active_radius):
			_queue_activate(key)


func _queue_activate(key: String) -> void:
	if _active.has(key) or _queued_activate.has(key):
		return
	_queued_activate[key] = true
	_activate_queue.append(key)
	_activate_queue.sort_custom(_closer_key_to_center)


func _queue_deactivate(key: String) -> void:
	if not _active.has(key) or _queued_deactivate.has(key):
		return
	_queued_deactivate[key] = true
	_deactivate_queue.append(key)


func _process_activation_queue() -> void:
	var budget := ACTIVATIONS_PER_FRAME
	while budget > 0 and not _activate_queue.is_empty():
		var key: String = _activate_queue.pop_front()
		_queued_activate.erase(key)
		if _active.has(key) or not _chunks.has(key):
			continue
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999) or not _within_radius(coord, _center, active_radius):
			continue
		_activate(key, _chunks[key])
		budget -= 1


func _process_deactivation_queue() -> void:
	var budget := DEACTIVATIONS_PER_FRAME
	while budget > 0 and not _deactivate_queue.is_empty():
		var key: String = _deactivate_queue.pop_front()
		_queued_deactivate.erase(key)
		if not _active.has(key):
			continue
		var coord := _coord_from_key(key)
		if coord != Vector2i(999999, 999999) and _within_radius(coord, _center, active_radius):
			continue
		_deactivate(key, _chunks.get(key))
		budget -= 1


func _unloads_allowed() -> bool:
	return Time.get_ticks_msec() - _last_center_change_msec >= UNLOAD_IDLE_MSEC


func _activate(key: String, chunk: RefCounted, immediate: bool = false) -> void:
	if chunk == null or _active.has(key):
		return
	_active[key] = true
	chunk_loaded.emit(chunk, immediate)


func _deactivate(key: String, chunk: RefCounted) -> void:
	if not _active.has(key):
		return
	_active.erase(key)
	if chunk != null:
		chunk_unloaded.emit(chunk)


static func _within_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	return absi(coord.x - center.x) <= radius and absi(coord.y - center.y) <= radius


static func _coord_from_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		return Vector2i(999999, 999999)
	return Vector2i(int(parts[0]), int(parts[1]))


func _exit_tree() -> void:
	# Don't leave bake tasks running against a dying scene.
	for task: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	_results_mutex.lock()
	_results.clear()
	_results_mutex.unlock()
