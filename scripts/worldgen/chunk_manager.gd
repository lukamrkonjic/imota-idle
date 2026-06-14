extends Node2D
## Keeps world streaming smooth by separating terrain visibility from gameplay
## activity. A large terrain ring is rendered so the camera sees far ahead, while
## only the smaller active ring emits spawn/path signals for entities.

signal chunk_loaded(chunk: RefCounted)
signal chunk_unloaded(chunk: RefCounted)

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var layer := 0
var view_radius := WG.VIEW_RADIUS
var active_radius := WG.ACTIVE_RADIUS
var detail_radius := WG.DETAIL_RADIUS
var unload_radius := WG.VIEW_RADIUS + 2
# WorkerThreadPool bakes can leave Godot with a non-zero process exit during
# headless validation/shutdown even when every assertion passes. The chunk bake
# is deliberately tiny (64x64 pixels), so synchronous baking is stable enough
# for now and keeps tests/game launch clean.
var use_threads := false

var _renderers: Dictionary = {}   # "cx:cy" -> renderer node
var _chunks: Dictionary = {}      # "cx:cy" -> Chunk
var _active: Dictionary = {}      # "cx:cy" -> true, has emitted chunk_loaded
var _seen: Dictionary = {}        # layer -> {"cx:cy": true}
var _center := Vector2i(2000000, 2000000)
var _tasks: Dictionary = {}       # task id -> chunk key
var _results: Dictionary = {}     # chunk key -> Image (worker -> main handoff)
var _results_mutex := Mutex.new()

# Incremental streaming: after the initial fill, new chunks are queued and loaded
# a few per frame instead of all at once on the crossing frame. This trades a
# slightly slower fill for no frame hiccup when the player walks into a new area.
const LOADS_PER_FRAME := 2
const LOAD_TIME_BUDGET_USEC := 2600
const ACTIVATIONS_PER_FRAME := 1
const DEACTIVATIONS_PER_FRAME := 3
var _load_queue: Array = []       # Array[Vector2i], nearest-first
var _queued: Dictionary = {}      # "cx:cy" -> true (dedupe what's already queued)
var _activate_queue: Array[String] = []
var _queued_activate: Dictionary = {}
var _deactivate_queue: Array[String] = []
var _queued_deactivate: Dictionary = {}


## Gameplay-active chunks only. Pathfinding/entities intentionally stay on this
## smaller set even though more terrain chunks are rendered in the distance.
func loaded_chunks() -> Array:
	var out: Array = []
	for key: String in _active.keys():
		if _chunks.has(key):
			out.append(_chunks[key])
	return out


func terrain_chunk_count() -> int:
	return _chunks.size()


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
	_activate_queue.clear()
	_queued_activate.clear()
	_deactivate_queue.clear()
	_queued_deactivate.clear()
	_active.clear()
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
				_unload(key)
	_update_renderer_detail()
	_sync_active_chunks()


func _load(coords: Vector2i, immediate_active: bool = false) -> void:
	var chunk: RefCounted = WorldGen.get_chunk(layer, coords.x, coords.y)
	WorldGen.snapshot_chunk_if_needed(chunk)
	if layer == 0:
		WorldGen.store.mark_explored(coords.x, coords.y)
	var key := "%d:%d" % [coords.x, coords.y]
	_chunks[key] = chunk
	if not _seen.has(layer):
		_seen[layer] = {}
	_seen[layer][key] = true
	var avg := ChunkRenderer.tile_color(WorldGen.reg, chunk.tile_id(WG.CHUNK_TILES / 2, WG.CHUNK_TILES / 2))
	var renderer: Node2D = ChunkRenderer.new(chunk, avg, _detail_for(coords))
	renderer.name = "Chunk_" + key.replace(":", "_").replace("-", "m")
	renderer.modulate.a = 0.0
	add_child(renderer)
	_renderers[key] = renderer
	_fade_in(renderer, 0.30)
	_redraw_loaded_neighbors(coords)
	if _within_radius(coords, _center, active_radius):
		if immediate_active:
			_activate(key, chunk)
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


func _update_renderer_detail() -> void:
	for key: String in _renderers.keys():
		var coord := _coord_from_key(key)
		if coord == Vector2i(999999, 999999):
			continue
		_renderers[key].call("set_detail_level", _detail_for(coord))


func _fade_in(node: CanvasItem, seconds: float) -> void:
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, seconds)


func _redraw_loaded_neighbors(coords: Vector2i) -> void:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key := "%d:%d" % [coords.x + dx, coords.y + dy]
			if _renderers.has(key):
				_renderers[key].queue_redraw()


func _process(_delta: float) -> void:
	# Stream queued chunks in a few per frame; skip any that are already loaded
	# or that the player has since walked out of range of.
	var budget := LOADS_PER_FRAME
	var started := Time.get_ticks_usec()
	while budget > 0 and not _load_queue.is_empty():
		if Time.get_ticks_usec() - started > LOAD_TIME_BUDGET_USEC:
			break
		var coord: Vector2i = _load_queue.pop_front()
		var key := "%d:%d" % [coord.x, coord.y]
		_queued.erase(key)
		if _renderers.has(key):
			continue
		if absi(coord.x - _center.x) > view_radius or absi(coord.y - _center.y) > view_radius:
			continue
		_load(coord)
		budget -= 1
	_process_deactivation_queue()
	_process_activation_queue()


func _unload(key: String) -> void:
	var chunk: RefCounted = _chunks.get(key)
	if _active.has(key):
		_deactivate(key, chunk)
	_queued_activate.erase(key)
	_queued_deactivate.erase(key)
	if _renderers.has(key):
		_renderers[key].queue_free()
	_renderers.erase(key)
	_chunks.erase(key)


func _sync_active_chunks() -> void:
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


func _activate(key: String, chunk: RefCounted) -> void:
	if chunk == null or _active.has(key):
		return
	_active[key] = true
	chunk_loaded.emit(chunk)


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
