extends Node
## perf_bisect — FPS bottleneck bisection UNDER MOTION. Loads the REAL world windowed (vsync OFF so
## frame time reflects true CPU/GPU cost, not the refresh cap), lets the sim-player crowd spawn, then
## WALKS the player continuously (streaming chunks / spawning entities / following camera — the real
## play stress) while toggling ONE system off at a time, so we can see what each costs in motion.
##   godot --path . res://tools/perf_bisect.tscn -- --perf-probe
## (--perf-probe also prints the per-subsystem _process CPU breakdown, captured WHILE walking.)

const WG := preload("res://scripts/worldgen/wg.gd")

var _world: Node2D
var _rend: Node
var _sun: Node
var _sub: SubViewport
var _hud_kids: Array = []        # CanvasItem children of the HUD CanvasLayer (toggled to ablate HUD)
var _walk: Vector2               # current player position, advanced every measured frame
var _step: Vector2               # per-frame walk advance (running pace)
var _start: Vector2              # fixed path start (every measurement teleports here first)


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_rend = _world.get("render_3d")
	if _rend != null:
		_sun = _rend.atmosphere.get_sun() if _rend.get("atmosphere") != null else null
		_sub = _rend.presenter.sub if _rend.get("presenter") != null else null
	var hud: Node = _world.get_node_or_null("HUD")
	if hud != null:
		for c: Node in hud.get_children():
			if c is CanvasItem:
				_hud_kids.append(c)

	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(0.55, 0.55)   # zoomed-OUT play view (the jank-heavy case)
		cam.position_smoothing_enabled = false
		cam.reset_smoothing()

	# Fixed start + step: EVERY measurement re-teleports here and walks the identical path, so the
	# per-ablation deltas are comparable (not confounded by walking into different terrain density).
	_start = _world.player.position
	_walk = _start
	_step = Vector2(WG.CHUNK_SIZE * 0.015, WG.CHUNK_SIZE * 0.008)

	print("\n=== PERF BISECT (motion, same-path) — settling 400 frames ===")
	for i: int in 400:
		await get_tree().process_frame

	await _report_counts("baseline (walking)")
	var base := await _measure_path()
	print("BASELINE walking: %.1f fps  avg %.2f ms  worst %.1f ms  jank(>16ms) %d/%d  movers=%d  hover=%.0f us" % [
		1000.0 / base["avg"], base["avg"], base["worst"], base["jank"], base["n"], _mover_count(), base["hover_us"]])
	await _dump_render_cpu()

	var tests: Array = [
		["3D viewport render OFF (all 3D GPU)", _ab_view_off, _ab_view_on],
		["terrain hidden", _ab_terrain_off, _ab_terrain_on],
		["props/decor batches hidden", _ab_props_off, _ab_props_on],
		["movers/rigs hidden (player+enemies+sims)", _ab_movers_off, _ab_movers_on],
		["directional shadow OFF", _ab_shadow_off, _ab_shadow_on],
		["sims/AI calc OFF (sims_enabled)", _ab_sims_off, _ab_sims_on],
		["gameplay OFF (sims+AI+collision)", _ab_gameplay_off, _ab_gameplay_on],
		["HUD hidden", _ab_hud_off, _ab_hud_on],
	]

	print("\n--- ablations while WALKING same path (saved = ms/frame that system costs) ---")
	for t: Array in tests:
		var apply: Callable = t[1]
		var restore: Callable = t[2]
		apply.call()
		var r := await _measure_path()
		restore.call()
		print(JSON.stringify({
			"ablation": t[0],
			"fps": snappedf(1000.0 / r["avg"], 0.1),
			"avg_ms": snappedf(r["avg"], 0.01),
			"worst_ms": snappedf(r["worst"], 0.1),
			"saved_ms": snappedf(base["avg"] - r["avg"], 0.01),
			"gain_pct": snappedf((base["avg"] - r["avg"]) / base["avg"] * 100.0, 0.1),
		}))

	get_tree().quit(0)


# --- ablation toggles -------------------------------------------------------
func _ab_view_off() -> void:
	if _sub != null: _sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
func _ab_view_on() -> void:
	if _sub != null: _sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
func _ab_terrain_off() -> void:
	_rend.terrain_root.visible = false
func _ab_terrain_on() -> void:
	_rend.terrain_root.visible = true
func _ab_props_off() -> void:
	_rend.batches_root.visible = false
func _ab_props_on() -> void:
	_rend.batches_root.visible = true
func _ab_movers_off() -> void:
	_rend.props_root.visible = false
func _ab_movers_on() -> void:
	_rend.props_root.visible = true
func _ab_shadow_off() -> void:
	if _sun != null: _sun.shadow_enabled = false
func _ab_shadow_on() -> void:
	if _sun != null: _sun.shadow_enabled = true
func _ab_sims_off() -> void:
	_world.set("sims_enabled", false)
func _ab_sims_on() -> void:
	_world.set("sims_enabled", true)
func _ab_gameplay_off() -> void:
	_world.set("gameplay_active", false)
func _ab_gameplay_on() -> void:
	_world.set("gameplay_active", true)
func _ab_hud_off() -> void:
	for c: CanvasItem in _hud_kids:
		if is_instance_valid(c): c.visible = false
func _ab_hud_on() -> void:
	for c: CanvasItem in _hud_kids:
		if is_instance_valid(c): c.visible = true


# --- motion + measurement ---------------------------------------------------
## Advance the walk one frame: move the player + re-center streaming (emulates real movement).
func _advance() -> void:
	_walk += _step
	_world.player.position = _walk
	_world.chunk_manager.update_center(_walk)


## Walk N frames without measuring (settle after toggling a system).
func _walk_only(frames: int) -> void:
	for i: int in frames:
		_advance()
		await get_tree().process_frame


## Teleport back to the fixed start, let streaming settle, then walk + time the IDENTICAL path.
## Same path every call => clean per-ablation deltas.
func _measure_path() -> Dictionary:
	_walk = _start
	_world.player.position = _walk
	_world.chunk_manager.update_center(_walk)
	await _walk_only(45)         # re-stream the start area (this spike is NOT measured)
	return await _walk_measure(150)


func _mover_count() -> int:
	if _rend != null and _rend.get("mover_renderer") != null:
		var d: Variant = _rend.mover_renderer.get("_mover_nodes")
		if d is Dictionary:
			return (d as Dictionary).size()
	return 0


## Walk `frames` frames, timing each; return {avg, worst, jank, n} in ms. Vsync off => real cost.
func _walk_measure(frames: int) -> Dictionary:
	for i: int in 8:
		_advance()
		await get_tree().process_frame
	var total := 0.0
	var worst := 0.0
	var jank := 0
	var hover := 0.0
	for i: int in frames:
		_advance()
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		if ms > 16.0:
			jank += 1
		hover += float(_world.get("last_hover_us"))
	return {"avg": total / float(frames), "worst": worst, "jank": jank, "n": frames,
		"hover_us": hover / float(frames)}


func _report_counts(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ents: Array = _world.get("entities")
	var decor: Array = _world.get("_decor_nodes")
	print(JSON.stringify({
		"at": label,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"entities": ents.size(),
		"ground_decor": decor.size(),
		"total_nodes": _count_nodes(_world),
	}))


## Per-subsystem _process CPU (usec) — only populated when run with `-- --perf-probe`. Captured while
## walking so it reflects motion cost (streaming/meshing/props), not a static frame.
func _dump_render_cpu() -> void:
	if _rend == null or not _rend.has_method("consume_render_timings"):
		return
	await _walk_only(140)
	var t: Dictionary = _rend.call("consume_render_timings")
	if int(t.get("frames", 0)) > 0:
		print("RENDER CPU usec/frame (mean, walking): %s" % JSON.stringify(t))


func _count_nodes(n: Node) -> int:
	var total := 1
	for c: Node in n.get_children():
		total += _count_nodes(c)
	return total
