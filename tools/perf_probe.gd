extends Node
## perf_probe — loads the real world scene (NOT --headless) at a few play zooms,
## lets it settle, then prints the actual rendering stats so we can target the
## real bottleneck (draw calls vs primitives vs node count) instead of guessing.
##   godot --path . res://tools/perf_probe.tscn

const WG := preload("res://scripts/worldgen/wg.gd")

var _world: Node2D


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_run()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.position_smoothing_enabled = false

	var samples: Array = [
		{"name": "spawn z0.95", "chunk": Vector2i(0, 0), "zoom": 0.95},
		{"name": "spawn z1.40", "chunk": Vector2i(0, 0), "zoom": 1.40},
		{"name": "north_peaks z0.85", "chunk": Vector2i(-3, -24), "zoom": 0.85},
	]
	print("\n=== PERF PROBE ===")
	for s: Dictionary in samples:
		await _probe(s)
	get_tree().quit(0)


func _probe(s: Dictionary) -> void:
	var c: Vector2i = s["chunk"]
	var pos := WG.tile_to_world(c.x * WG.CHUNK_TILES + 8, c.y * WG.CHUNK_TILES + 8)
	_world.player.position = pos
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(float(s["zoom"]), float(s["zoom"]))
		cam.reset_smoothing()
	_world.chunk_manager.update_center(pos)
	for i: int in 320:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var fps := Engine.get_frames_per_second()

	var entities: Array = _world.get("entities")
	var decor: Array = _world.get("_decor_nodes")
	var water: Array = _world.get("_water_decor_nodes")
	var terrain_total := int(_world.chunk_manager.call("terrain_chunk_count"))
	var renderers: Dictionary = _world.chunk_manager.get("_renderers")
	var terrain_visible := 0
	for k: String in renderers.keys():
		if is_instance_valid(renderers[k]) and renderers[k].visible:
			terrain_visible += 1
	var total_nodes := _count_nodes(_world)

	print(JSON.stringify({
		"sample": s["name"],
		"fps": fps,
		"view_r": _world.chunk_manager.get("view_radius"),
		"active_r": _world.chunk_manager.get("active_radius"),
		"draw_calls": draw_calls,
		"primitives": prims,
		"objects": objs,
		"nodes_in_world": total_nodes,
		"terrain_chunks_loaded": terrain_total,
		"terrain_chunks_visible": terrain_visible,
		"entities": entities.size(),
		"ground_decor": decor.size(),
		"water_decor": water.size(),
	}))


func _count_nodes(n: Node) -> int:
	var total := 1
	for c: Node in n.get_children():
		total += _count_nodes(c)
	return total
