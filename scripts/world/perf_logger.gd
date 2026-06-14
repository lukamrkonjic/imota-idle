extends Node
class_name PerfLogger
## Lightweight in-game performance logger. Samples the engine perf monitors plus
## world-specific counts (entities/decor drawn, terrain visible, stream radii) and
## the per-subsystem _process timings, and appends a line to a log file a few
## times a second so a laggy session can be diagnosed after the fact.
##
## Output: user://perf_log.txt — absolute path is printed on start. Disabled in
## release; toggle with `enabled`.

const WG := preload("res://scripts/worldgen/wg.gd")

var world: Node2D
var enabled := OS.is_debug_build()

var _file: FileAccess
var _accum := 0.0
const SAMPLE_INTERVAL := 0.5

# Per-subsystem time (usec) recorded by world._process each frame; averaged over
# the sample window.
var _timings: Dictionary = {}
var _timing_frames := 0
var _worst_frame_ms := 0.0


func setup(w: Node2D) -> void:
	world = w


func _ready() -> void:
	if not enabled:
		return
	var path := "user://perf_log.txt"
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("PerfLogger: could not open %s" % path)
		return
	var abs := ProjectSettings.globalize_path(path)
	print("\n=== PERF LOG -> %s ===\n" % abs)
	_file.store_line("# Imota perf log  device=%s  renderer=%s" % [
		RenderingServer.get_video_adapter_name(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")])
	_file.store_line("# t  fps  frame_ms  worst_ms  proc_ms  phys_ms  draw_calls  prims  objs  nodes  "
		+ "ent_total  ent_vis  decor_total  decor_vis  water  terr_load  terr_vis  view_r  active_r  nav_r  "
		+ "| sub_us: chunk stream path visual hover activity "
		+ "| cm_us: load redraw mesh deact unload act detail total q_load q_mesh q_act q_unload "
		+ "| bake_us: total jobs q inflight kept")
	_file.flush()


## Called by world._process with the per-subsystem microsecond timings for the
## frame: {"chunk":us, "stream":us, "path":us, "visual":us, "hover":us, "activity":us}.
func record(delta: float, frame_timings: Dictionary) -> void:
	if _file == null:
		return
	for k: String in frame_timings:
		_timings[k] = float(_timings.get(k, 0.0)) + float(frame_timings[k])
	_timing_frames += 1
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_write_sample()
	_accum = 0.0
	_timings.clear()
	_timing_frames = 0
	_worst_frame_ms = 0.0


func _write_sample() -> void:
	var ent_total := 0
	var ent_vis := 0
	var decor_total := 0
	var decor_vis := 0
	var water := 0
	if world != null:
		var ents: Array = world.entities
		ent_total = ents.size()
		for e: Node2D in ents:
			if is_instance_valid(e) and e.is_visible_in_tree():
				ent_vis += 1
		var dec: Array = world._decor_nodes
		decor_total = dec.size()
		for d: Node2D in dec:
			if is_instance_valid(d) and d.is_visible_in_tree():
				decor_vis += 1
		water = world._water_decor_nodes.size()

	var terr_load := 0
	var terr_vis := 0
	var view_r := 0
	var active_r := 0
	var nav_r := 0
	if world != null and world.chunk_manager != null:
		var cm: Node2D = world.chunk_manager
		terr_load = int(cm.call("terrain_chunk_count"))
		var renderers: Dictionary = cm.get("_renderers")
		for k: String in renderers.keys():
			if is_instance_valid(renderers[k]) and renderers[k].visible:
				terr_vis += 1
		view_r = int(cm.get("view_radius"))
		active_r = int(cm.get("active_radius"))
		nav_r = int(cm.get("nav_radius"))

	var n := maxi(1, _timing_frames)
	var sub := "%d %d %d %d %d %d" % [
		int(float(_timings.get("chunk", 0.0)) / n),
		int(float(_timings.get("stream", 0.0)) / n),
		int(float(_timings.get("path", 0.0)) / n),
		int(float(_timings.get("visual", 0.0)) / n),
		int(float(_timings.get("hover", 0.0)) / n),
		int(float(_timings.get("activity", 0.0)) / n),
	]
	var cm_sub := "0 0 0 0 0 0 0 0 0 0 0 0"
	if world != null and world.chunk_manager != null and world.chunk_manager.has_method("consume_perf_timings"):
		var cm_perf: Dictionary = world.chunk_manager.call("consume_perf_timings")
		cm_sub = "%d %d %d %d %d %d %d %d %d %d %d %d" % [
			int(cm_perf.get("load", 0)),
			int(cm_perf.get("redraw", 0)),
			int(cm_perf.get("mesh", 0)),
			int(cm_perf.get("deactivate", 0)),
			int(cm_perf.get("unload", 0)),
			int(cm_perf.get("activate", 0)),
			int(cm_perf.get("detail", 0)),
			int(cm_perf.get("total", 0)),
			int(cm_perf.get("load_q", 0)),
			int(cm_perf.get("mesh_q", 0)),
			int(cm_perf.get("activate_q", 0)),
			int(cm_perf.get("unload_q", 0)),
		]
	var bake_sub := "0 0 0 0 0"
	if world != null:
		var bake := world.get_node_or_null("BakeQueue")
		if bake != null and bake.has_method("consume_perf_timings"):
			var bake_perf: Dictionary = bake.call("consume_perf_timings")
			bake_sub = "%d %d %d %d %d" % [
				int(bake_perf.get("total", 0)),
				int(bake_perf.get("jobs", 0)),
				int(bake_perf.get("queue", 0)),
				int(bake_perf.get("in_flight", 0)),
				int(bake_perf.get("kept", 0)),
			]

	var line := "%.1f  %d  %.1f  %.1f  %.1f  %.1f  %d  %d  %d  %d  %d %d  %d %d  %d  %d %d  %d %d %d  | %s | %s | %s" % [
		Time.get_ticks_msec() / 1000.0,
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		_worst_frame_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		ent_total, ent_vis, decor_total, decor_vis, water,
		terr_load, terr_vis, view_r, active_r, nav_r, sub, cm_sub, bake_sub,
	]
	_file.store_line(line)
	_file.flush()


func _exit_tree() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
