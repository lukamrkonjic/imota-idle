extends RefCounted
class_name WorldRenderPreviewTools
## Verification / preview helpers (extracted from the WorldRender3D monolith): deterministic
## teleports to a forest or ocean-coast vista, the firemaking + prayer FX preview driver, the
## one-time smithy placement at spawn, and the headless screenshot capture. Not part of core
## rendering — gated behind command-line flags, so a normal run does nothing here.

const WG := preload("res://scripts/worldgen/wg.gd")
const SmithyProp := preload("res://scripts/render/smithy_prop.gd")

const FOREST_PREVIEW_ARG := "--forest-preview"
const WATER_PREVIEW_ARG := "--water-preview"   # verification: teleport to a deterministic ocean coast
const FX_PREVIEW_ARG := "--fx-preview"         # verification: light the fire + emit prayer bursts at spawn

var world: Node2D
var render: Node                  # the WorldRender3D coordinator (iso_to_3d/height_at/props_root)
var mesh_manager: TerrainMeshManager
var fx_presenter                  # WorldFx3D (untyped — only used to keep the API symmetric)

var _forest_preview_done := false
var _water_preview_done := false
var _smithy_done := false
var _fx_preview_lit := false
var smithy_node: Node3D = null
var _frames := 0
var _captured := false


func setup(w: Node2D, render_coordinator: Node, mgr: TerrainMeshManager, fx) -> void:
	world = w
	render = render_coordinator
	mesh_manager = mgr
	fx_presenter = fx


func update_if_enabled() -> void:
	_maybe_teleport_to_forest_preview()
	_maybe_teleport_to_water_preview()
	_maybe_fx_preview()
	_maybe_place_smithy()
	_frames += 1
	var capture_frame := 150 if (_forest_preview_enabled() or _water_preview_enabled()) else 90
	if _frames == capture_frame and not _captured:
		_capture()


## Place the imported smithy model at the spawn camp (once, after the spawn chunk's data is
## loaded so the ground height is real), then teleport the player there to see it.
func _maybe_place_smithy() -> void:
	if _smithy_done:
		return
	var spawn := WorldGen.spawn_position()
	var st := WG.world_to_tile(spawn)
	# Wait until the spawn chunk's data is present so height_at() returns the real ground.
	if not world.chunk_manager.data_chunks().any(func(c: RefCounted) -> bool:
			return c.cx == floori(float(st.x) / WG.CHUNK_TILES) and c.cy == floori(float(st.y) / WG.CHUNK_TILES)):
		return
	_smithy_done = true
	# Sit it a few tiles off the camp centre so it doesn't overlap the bank/campfire.
	var pos := WG.tile_to_world(st.x + 4, st.y - 2)
	var model_scale := SmithyProp.scale_for(4.0)   # ~4 tiles across
	var inst := SmithyProp.build()
	inst.scale = Vector3(model_scale, model_scale, model_scale)
	inst.position = render.iso_to_3d(pos, render.height_at(pos)) + Vector3(0.0, SmithyProp.bottom_offset(model_scale), 0.0)
	inst.rotation.y = PI * 0.15
	render.props_root.add_child(inst)
	smithy_node = inst
	# Teleport the player to the camp so the smithy is right there in view.
	world.teleport_to(spawn)
	render.invalidate_static_batches()
	print("[world3d] placed smithy at tile %s, teleported to spawn %s" % [WG.world_to_tile(pos), st])


func _maybe_teleport_to_forest_preview() -> void:
	if _forest_preview_done:
		return
	_forest_preview_done = true
	if not _forest_preview_enabled():
		return
	var pos := _forest_preview_position()
	if pos == Vector2.INF:
		push_warning("World3D forest preview: no forest landing found")
		return
	world.teleport_to(pos)
	render.invalidate_static_batches()
	print("[world3d] forest preview teleport to tile %s" % [WG.world_to_tile(pos)])


func _forest_preview_enabled() -> bool:
	return FOREST_PREVIEW_ARG in OS.get_cmdline_args() or FOREST_PREVIEW_ARG in OS.get_cmdline_user_args()


func _forest_preview_position() -> Vector2:
	var spawn_t := WG.world_to_tile(WorldGen.spawn_position())
	var targets := ["forest", "dense_forest", "grove", "boreal_forest"]
	for dx_chunk: int in range(-18, -96, -3):
		for dy_chunk: int in range(-16, 17, 2):
			var tx := spawn_t.x + dx_chunk * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
			var ty := spawn_t.y + dy_chunk * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
			var in_forest := false
			for biome: String in targets:
				if WorldGen.surface_biome_matches(tx, ty, biome):
					in_forest = true
					break
			if not in_forest:
				continue
			var pos := _verified_forest_landing(WG.tile_to_world(tx, ty), targets)
			if pos != Vector2.INF:
				return pos
	for biome: String in targets:
		var found: Dictionary = WorldGen.find_nearest_biome(WorldGen.spawn_position(), biome, 96)
		if found.is_empty():
			continue
		var landed := _verified_forest_landing(found["pos"], targets)
		if landed != Vector2.INF:
			return landed
	return Vector2.INF


func _verified_forest_landing(preferred: Vector2, targets: Array) -> Vector2:
	var center := WG.world_to_tile(preferred)
	for ring: int in range(0, 25):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if ring > 0 and maxi(absi(dx), absi(dy)) != ring:
					continue
				var pos := WG.tile_to_world(center.x + dx, center.y + dy)
				if not WorldGen.is_admin_teleport_floor(pos):
					continue
				var debug: Dictionary = WorldGen.tile_debug_at(pos, 0)
				if debug.is_empty():
					continue
				var tile_name := str(debug.get("tile_name", ""))
				if tile_name in ["sand", "sand_dune", "rock", "ash", "lava_rock", "snow", "shallow", "water", "deep_water"]:
					continue
				if _water_near_tile(center.x + dx, center.y + dy, 6):
					continue
				if str(debug.get("effective_biome", "")) in targets or str(debug.get("parent_biome", "")) in targets or str(debug.get("sub_biome", "")) in targets:
					return pos
	return Vector2.INF


func _water_near_tile(gtx: int, gty: int, radius: int) -> bool:
	for off: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
		if WorldGen.is_water_world(WG.tile_to_world(gtx + off.x, gty + off.y), 0):
			return true
	return false


# --- water-coast verification view -------------------------------------------
func _maybe_teleport_to_water_preview() -> void:
	if _water_preview_done:
		return
	_water_preview_done = true
	if not _water_preview_enabled():
		return
	var pos := _water_preview_position()
	if pos == Vector2.INF:
		push_warning("World3D water preview: no ocean coast found")
		return
	world.teleport_to(pos)
	if world._camera != null:
		world._camera.zoom = Vector2(1.05, 1.05)   # frame a good stretch of coast
	render.invalidate_static_batches()
	print("[world3d] water preview teleport to tile %s" % [WG.world_to_tile(pos)])


func _water_preview_enabled() -> bool:
	return WATER_PREVIEW_ARG in OS.get_cmdline_args() or WATER_PREVIEW_ARG in OS.get_cmdline_user_args()


# The nearest ocean BEACH (the finite world's edge coast). Falls back to any large water body.
func _water_preview_position() -> Vector2:
	var spawn := WorldGen.spawn_position()
	var beach: Dictionary = WorldGen.find_nearest_biome(spawn, "beach", 200)
	if not beach.is_empty():
		var bt := WG.world_to_tile(beach["pos"])
		# Step one tile inland onto firm ground if the beach tile itself is borderline.
		if WorldGen.is_admin_teleport_floor(beach["pos"]):
			return beach["pos"]
		for off: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var p := WG.tile_to_world(bt.x + off.x, bt.y + off.y)
			if WorldGen.is_admin_teleport_floor(p):
				return p
	return Vector2.INF


# Verification only: drive WorldFx3D from the spawn so a capture shows the campfire + a fresh
# prayer burst. Lights the fire once, then re-emits a prayer activation every ~0.4s.
func _maybe_fx_preview() -> void:
	if not (FX_PREVIEW_ARG in OS.get_cmdline_args() or FX_PREVIEW_ARG in OS.get_cmdline_user_args()):
		return
	if world.player == null:
		return
	if not _fx_preview_lit:
		_fx_preview_lit = true
		EventBus.activity_started.emit("craft", "Firemaking Oak Logs")
		EventBus.firemaking_log_burned.emit()
	if _frames % 24 == 0:
		EventBus.prayer_activated.emit("Steel Skin")


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("user://world3d_shot.png")
	print("[world3d] saved user://world3d_shot.png")
