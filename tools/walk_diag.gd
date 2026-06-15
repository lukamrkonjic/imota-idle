extends Node
## walk_diag — reproduces the real fullscreen walking case and attributes the
## WORST frames to a subsystem, so we fix the actual stutter cause instead of
## guessing. Runs the real world at a high resolution, walks fast across fresh
## chunks, and prints the worst frames with their per-step breakdown.
##   godot --path . res://tools/walk_diag.tscn

const WG := preload("res://scripts/worldgen/wg.gd")

var _world: Node2D


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	_run()


func _run() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.position_smoothing_enabled = false
	print("\n=== WALK DIAG (2560x1440) ===")
	for zoom: float in [1.0, 0.7, 0.5]:
		await _walk(zoom)
	get_tree().quit(0)


func _walk(zoom: float) -> void:
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.reset_smoothing()
	var pos := WG.tile_to_world(8, 8)
	_world.player.position = pos
	_world.chunk_manager.call("update_center", pos)
	for _i: int in 90:
		await get_tree().process_frame

	# Collect the worst frames with their breakdown.
	var worst: Array = []
	var frames := 500
	for i: int in frames:
		# Brisk run that keeps crossing fresh chunk boundaries.
		pos += Vector2(WG.CHUNK_SIZE * 0.02, WG.CHUNK_SIZE * 0.012)
		_world.player.position = pos
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > 16.0:
			var cm: Dictionary = (_world.chunk_manager.get("last_timings") as Dictionary).duplicate()
			var wf: Dictionary = (_world.get("last_frame_timings") as Dictionary).duplicate()
			worst.append({"ms": snappedf(ms, 0.1), "world_us": wf, "cm_us": cm})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms"] > b["ms"])
	print("\n--- zoom %.2f  view_r=%d  spikes>16ms: %d / %d ---" % [
		zoom, int(_world.chunk_manager.get("view_radius")), worst.size(), frames])
	for w: Dictionary in worst.slice(0, 6):
		print(JSON.stringify(w))
