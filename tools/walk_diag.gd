extends Node
## walk_diag — reproduces the real fullscreen walking case and attributes the
## WORST frames to a subsystem, so we fix the actual stutter cause instead of
## guessing. Runs the real world at a high resolution, walks fast across fresh
## chunks, and prints the worst frames with their per-step breakdown.
##   godot --path . res://tools/walk_diag.tscn

const WG := preload("res://scripts/worldgen/wg.gd")
const CR := preload("res://scripts/worldgen/chunk_renderer.gd")

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
	await _click_walk(0.95)
	get_tree().quit(0)


## REAL click-to-walk: drives the player through the actual path system (A* find_path,
## avatar movement at 230px/s, debounced nav rebuilds on chunk crossings, waypoint
## arrivals) instead of teleporting position. Camera smoothing left ON like real play.
## Attributes the worst frames to a subsystem so we catch the click-walk-only culprit.
func _click_walk(zoom: float) -> void:
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.position_smoothing_enabled = true
		cam.reset_smoothing()
	var vp_rid := _world.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	# Settle at spawn, then walk outward into fresh land along a diagonal.
	for _i: int in 120:
		await get_tree().process_frame
	var dir := Vector2(0.80, 0.60).normalized()
	var bake: Node = _world.get_node("BakeQueue")
	var worst: Array = []
	var drops := 0
	var big := 0
	# correlation counts: of the slow (>13ms) frames, how many coincided with each event
	var slow := 0
	var with_apply := 0
	var with_bake := 0
	var with_spawn := 0
	var with_mesh := 0
	var with_activate := 0
	var clean := 0  # slow frames with NONE of the above
	var prev_applies: int = CR.debug_applies
	var prev_kept: int = (bake.get("_kept_viewports") as Array).size()
	var prev_ents: int = (_world.get("entities") as Array).size()
	var frames := 3200
	var stuck := 0
	for i: int in frames:
		var p: Node2D = _world.player
		if not bool(p.get("walking")):
			# Steer: aim a few chunks ahead; if that's unreachable (water/cliffs),
			# rotate until we find walkable land so the avatar keeps moving.
			var moved := false
			for attempt: int in 8:
				var target: Vector2 = p.position + dir * (WG.CHUNK_SIZE * 4.0)
				if bool(_world.call("walk_to_pos", target)):
					moved = true
					break
				dir = dir.rotated(deg_to_rad(50.0))
			if not moved:
				stuck += 1
				dir = dir.rotated(randf_range(-PI, PI))
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var applies: int = CR.debug_applies - prev_applies
		prev_applies = CR.debug_applies
		var bakes: int = (bake.get("_kept_viewports") as Array).size() - prev_kept
		prev_kept += bakes
		var spawned: int = (_world.get("entities") as Array).size() - prev_ents
		prev_ents += spawned
		var cm: Dictionary = _world.chunk_manager.get("last_timings")
		if ms > 16.7:
			drops += 1
		if ms > 25.0:
			big += 1
		if ms > 13.0:
			slow += 1
			var had := false
			if applies > 0: with_apply += 1; had = true
			if bakes > 0: with_bake += 1; had = true
			if spawned > 0: with_spawn += 1; had = true
			if int(cm.get("mesh", 0)) > 200: with_mesh += 1; had = true
			if int(cm.get("activate", 0)) > 200: with_activate += 1; had = true
			if not had: clean += 1
			var wf: Dictionary = _world.get("last_frame_timings")
			worst.append({"ms": snappedf(ms, 0.1), "appl": applies, "bake": bakes, "spawn": spawned,
				"rcpu": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid), 0.2),
				"rgpu": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), 0.2),
				"draw": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
				"objs": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
				"cm": cm.duplicate(), "w": wf.duplicate()})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms"] > b["ms"])
	print("\n=== CLICK-WALK (zoom %.2f, %d frames, stuck=%d) ===" % [zoom, frames, stuck])
	print("frames >16.7ms: %d   >25ms: %d   slow>13ms: %d" % [drops, big, slow])
	print("of %d slow frames: apply=%d bake=%d spawn=%d mesh=%d activate=%d NONE=%d" % [
		slow, with_apply, with_bake, with_spawn, with_mesh, with_activate, clean])
	for w: Dictionary in worst.slice(0, 12):
		print(JSON.stringify(w))


func _ab_test(zoom: float) -> void:
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.reset_smoothing()
	print("\n=== A/B fresh-vs-warm corridor (zoom %.2f) ===" % zoom)
	var start := WG.tile_to_world(-472, -472)  # chunk (-30,-30): in-bounds, far from spawn, unvisited
	for pass_i: int in 2:
		var pos := start
		_world.player.position = pos
		_world.chunk_manager.call("update_center", pos)
		for _i: int in 60:
			await get_tree().process_frame
		var spikes := 0
		var worst_ms := 0.0
		var frames := 320
		for i: int in frames:
			pos += Vector2(WG.CHUNK_SIZE * 0.02, WG.CHUNK_SIZE * 0.012)
			_world.player.position = pos
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			worst_ms = maxf(worst_ms, ms)
			if ms > 16.0:
				spikes += 1
		print("pass %d (%s): spikes>16ms = %d / %d, worst = %.1fms" % [
			pass_i + 1, "FRESH" if pass_i == 0 else "WARM (same path)", spikes, frames, worst_ms])


func _walk(zoom: float) -> void:
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(zoom, zoom)
		cam.reset_smoothing()
	var pos := WG.tile_to_world(8, 8)
	_world.player.position = pos
	_world.chunk_manager.call("update_center", pos)
	var vp_rid := _world.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	for _i: int in 90:
		await get_tree().process_frame

	# Collect the worst frames with their breakdown.
	var worst: Array = []
	var frames := 500
	for i: int in frames:
		# Brisk run that keeps crossing fresh chunk boundaries.
		pos += Vector2(WG.CHUNK_SIZE * 0.02, WG.CHUNK_SIZE * 0.012)
		_world.player.position = pos
		var ents_before: int = (_world.get("entities") as Array).size()
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > 16.0:
			var cm: Dictionary = (_world.chunk_manager.get("last_timings") as Dictionary).duplicate()
			var wf: Dictionary = (_world.get("last_frame_timings") as Dictionary).duplicate()
			var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			var rgpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			var ents_added: int = (_world.get("entities") as Array).size() - ents_before
			worst.append({"ms": snappedf(ms, 0.1), "rcpu": snappedf(rcpu, 0.2),
				"rgpu": snappedf(rgpu, 0.2), "ents+": ents_added, "world_us": wf, "cm_us": cm})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms"] > b["ms"])
	print("\n--- zoom %.2f  view_r=%d  spikes>16ms: %d / %d ---" % [
		zoom, int(_world.chunk_manager.get("view_radius")), worst.size(), frames])
	for w: Dictionary in worst.slice(0, 6):
		print(JSON.stringify(w))
