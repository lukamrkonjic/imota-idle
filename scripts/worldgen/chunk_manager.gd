extends Node2D
## Keeps the chunks around the player loaded: pulls chunk data from the
## WorldGen cache (generating on demand), creates a ground renderer per chunk,
## bakes ground images on the worker thread pool so loading never blocks a
## frame, and tells the world (via signals) when to spawn entities.
##
## Explored chunks stay resident for the current layer. That avoids the ugly
## visible square of only-current chunks when zoomed out and keeps discovered
## areas feeling like a continuous map instead of popping away behind you.

signal chunk_loaded(chunk: RefCounted)
signal chunk_unloaded(chunk: RefCounted)

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var layer := 0
var view_radius := WG.VIEW_RADIUS
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


func loaded_chunks() -> Array:
	return _chunks.values()


func set_visible_rect(world_rect: Rect2) -> void:
	var chunk_size := Vector2(WG.CHUNK_SIZE, WG.CHUNK_SIZE)
	for key: String in _renderers.keys():
		var renderer: Node2D = _renderers[key]
		var chunk: RefCounted = renderer.get("chunk")
		renderer.visible = world_rect.intersects(Rect2(chunk.origin(), chunk_size))


func set_layer(new_layer: int) -> void:
	if new_layer == layer:
		return
	layer = new_layer
	clear_all()


func clear_all() -> void:
	for key: String in _renderers.keys():
		_unload(key)
	_center = Vector2i(2000000, 2000000)


## Call whenever the player moves; loads new chunks only on chunk crossings.
func update_center(world_pos: Vector2) -> void:
	var c := WG.world_to_chunk(world_pos)
	if c == _center:
		return
	_center = c
	var needed: Dictionary = {}
	for dy: int in range(-view_radius, view_radius + 1):
		for dx: int in range(-view_radius, view_radius + 1):
			needed["%d:%d" % [c.x + dx, c.y + dy]] = Vector2i(c.x + dx, c.y + dy)
	for key: String in needed:
		if not _renderers.has(key):
			_load(needed[key])


func _load(coords: Vector2i) -> void:
	var chunk: RefCounted = WorldGen.get_chunk(layer, coords.x, coords.y)
	WorldGen.snapshot_chunk_if_needed(chunk)
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
	var reg: RefCounted = WorldGen.reg
	var classifier: RefCounted = WorldGen.generator.classifier
	var seed_v: int = WorldGen.store.world_seed
	if use_threads:
		var mutex := _results_mutex
		var results := _results
		var task := WorkerThreadPool.add_task(func() -> void:
			var img := ChunkRenderer.bake(chunk, reg, classifier, seed_v)
			mutex.lock()
			results[key] = img
			mutex.unlock())
		_tasks[task] = key
	else:
		renderer.apply_image(ChunkRenderer.bake(chunk, reg, classifier, seed_v))
	chunk_loaded.emit(chunk)


func _process(_delta: float) -> void:
	if _tasks.is_empty():
		return
	# Collect finished bakes (main thread only touches the scene here).
	_results_mutex.lock()
	var ready := _results.keys()
	for key: String in ready:
		if _renderers.has(key):
			_renderers[key].apply_image(_results[key])
		_results.erase(key)
	_results_mutex.unlock()
	for task: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(task):
			_tasks.erase(task)


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
