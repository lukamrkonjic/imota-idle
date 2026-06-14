extends Node2D
## Keeps the chunks around the player loaded: pulls chunk data from the
## WorldGen cache (generating on demand), creates a ground renderer per chunk,
## bakes ground images on the worker thread pool so loading never blocks a
## frame, and tells the world (via signals) when to spawn entities.
##
## Chunks within view_radius load eagerly; chunks beyond unload_radius are freed
## so explored areas do not accumulate forever and tank frame time.

signal chunk_loaded(chunk: RefCounted)
signal chunk_unloaded(chunk: RefCounted)

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var layer := 0
var view_radius := WG.VIEW_RADIUS
var unload_radius := WG.VIEW_RADIUS + 2
# WorkerThreadPool bakes can leave Godot with a non-zero process exit during
# headless validation/shutdown even when every assertion passes. The chunk bake
# is deliberately tiny (64x64 pixels), so synchronous baking is stable enough
# for now and keeps tests/game launch clean.
var use_threads := false

var _renderers: Dictionary = {}   # "cx:cy" -> renderer node
var _chunks: Dictionary = {}      # "cx:cy" -> Chunk
var _seen: Dictionary = {}        # layer -> {"cx:cy": true}
var _center := Vector2i(2000000, 2000000)
var _tasks: Dictionary = {}       # task id -> chunk key
var _results: Dictionary = {}     # chunk key -> Image (worker -> main handoff)
var _results_mutex := Mutex.new()

# Incremental streaming: after the initial fill, new chunks are queued and loaded
# a few per frame instead of all at once on the crossing frame. This trades a
# slightly slower fill for no frame hiccup when the player walks into a new area.
const LOADS_PER_FRAME := 1
var _load_queue: Array = []       # Array[Vector2i], nearest-first
var _queued: Dictionary = {}      # "cx:cy" -> true (dedupe what's already queued)


func loaded_chunks() -> Array:
	return _chunks.values()


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
	_center = Vector2i(2000000, 2000000)


## Call whenever the player moves; loads new chunks only on chunk crossings.
func update_center(world_pos: Vector2) -> void:
	var c := WG.world_to_chunk(world_pos)
	if c == _center:
		return
	# The very first centering loads its whole ring synchronously (a one-time
	# load cost), so the player never sees a blank world at spawn. Every later
	# crossing streams new chunks in over several frames to avoid a hiccup.
	var first_fill: bool = _center.x == 2000000
	_center = c
	var needed: Dictionary = {}
	for dy: int in range(-view_radius, view_radius + 1):
		for dx: int in range(-view_radius, view_radius + 1):
			needed["%d:%d" % [c.x + dx, c.y + dy]] = Vector2i(c.x + dx, c.y + dy)
	for key: String in needed:
		if _renderers.has(key) or _queued.has(key):
			continue
		if first_fill:
			_load(needed[key])
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


func _load(coords: Vector2i) -> void:
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
	var renderer: Node2D = ChunkRenderer.new(chunk, avg)
	renderer.name = "Chunk_" + key.replace(":", "_").replace("-", "m")
	add_child(renderer)
	_renderers[key] = renderer
	chunk_loaded.emit(chunk)


func _closer_to_center(a: Vector2i, b: Vector2i) -> bool:
	var da := absi(a.x - _center.x) + absi(a.y - _center.y)
	var db := absi(b.x - _center.x) + absi(b.y - _center.y)
	return da < db


func _process(_delta: float) -> void:
	# Stream queued chunks in a few per frame; skip any that are already loaded
	# or that the player has since walked out of range of.
	var budget := LOADS_PER_FRAME
	while budget > 0 and not _load_queue.is_empty():
		var coord: Vector2i = _load_queue.pop_front()
		var key := "%d:%d" % [coord.x, coord.y]
		_queued.erase(key)
		if _renderers.has(key):
			continue
		if absi(coord.x - _center.x) > view_radius or absi(coord.y - _center.y) > view_radius:
			continue
		_load(coord)
		budget -= 1


func _unload(key: String) -> void:
	var chunk: RefCounted = _chunks.get(key)
	_renderers[key].queue_free()
	_renderers.erase(key)
	_chunks.erase(key)
	if chunk != null:
		chunk_unloaded.emit(chunk)


func _exit_tree() -> void:
	# Don't leave bake tasks running against a dying scene.
	for task: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	_results_mutex.lock()
	_results.clear()
	_results_mutex.unlock()
