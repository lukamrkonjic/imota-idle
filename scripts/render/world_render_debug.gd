extends RefCounted
class_name WorldRenderDebug
## Diagnostic readout for the terrain coverage / fog / cutoff model (new — supports the spec's
## fog-band investigation). Gated behind `--render-debug`; when on, it periodically logs the live
## state so it's obvious WHY a beige/fog band appears (or doesn't):
##   A. data chunk not loaded   B. terrain mesh not built   C. mesh hidden by visibility cull
##   D. fog too aggressive      E. camera pitch exceeds the terrain budget
## Pure logger (no scene nodes), so it is safe to leave wired in a normal build.

const WG := preload("res://scripts/worldgen/wg.gd")
const LOG_EVERY := 45   # frames between log lines (~0.75s at 60fps)

var world: Node2D
var camera_rig: WorldCameraRig3D
var stream_view: TerrainStreamView
var mesh_manager: TerrainMeshManager
var atmosphere: WorldAtmosphere
var _frames := 0


func setup(w: Node2D, rig: WorldCameraRig3D, sv: TerrainStreamView, mgr: TerrainMeshManager, atmo: WorldAtmosphere) -> void:
	world = w
	camera_rig = rig
	stream_view = sv
	mesh_manager = mgr
	atmosphere = atmo


func enabled() -> bool:
	return "--render-debug" in OS.get_cmdline_args() or "--render-debug" in OS.get_cmdline_user_args()


func update_if_enabled() -> void:
	if not enabled():
		return
	_frames += 1
	if _frames % LOG_EVERY != 0:
		return
	var pc := WG.world_to_chunk(world.player.position)
	var loaded: int = world.chunk_manager.data_chunks().size()
	var demand: Dictionary = world.chunk_manager.terrain_demand_status()
	var poly := camera_rig.get_ground_footprint_polygon()
	var fog_begin := 0.0
	var fog_end := 0.0
	var env := atmosphere.get_environment() if atmosphere != null else null
	if env != null:
		fog_begin = env.fog_depth_begin
		fog_end = env.fog_depth_end
	print("[render-debug] player_chunk=%s pitch=%.3f (min=%.3f) yaw=%.2f ortho=%.1f cover=%.2f | data=%d built=%d | visible=%d margin=%d keep=%d | ring=%d extent=%.0f | fog=[%.0f..%.0f] | footprint=%s" % [
		str(pc),
		camera_rig.get_pitch(), camera_rig.effective_min_pitch(), camera_rig.get_yaw(), camera_rig.get_ortho_size(), camera_rig.get_cover_zoom(),
		loaded, mesh_manager.built_count(),
		stream_view.visible_chunks().size(), stream_view.margin_chunks().size(), stream_view.keep_chunks().size(),
		stream_view.terrain_data_ring(), stream_view.approx_visual_extent_tiles(),
		fog_begin, fog_end,
		_poly_str(poly),
	])
	print("[render-debug] terrain-demand total=%d real=%d placeholders=%d queued=%d" % [
		int(demand.get("demand", 0)), int(demand.get("real", 0)),
		int(demand.get("placeholders", 0)), int(demand.get("queued", 0)),
	])


func _poly_str(poly: PackedVector2Array) -> String:
	var parts: Array = []
	for p: Vector2 in poly:
		parts.append("(%.0f,%.0f)" % [p.x, p.y])
	return "[" + ", ".join(parts) + "]"
