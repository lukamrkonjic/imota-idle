extends Node
class_name WorldRender3D
## 3D pixel-art renderer for the live world — now a thin COORDINATOR over focused subsystems
## (was a ~2.3k-line god-object). It hosts a low-resolution SubViewport with a 3D world (iso
## ortho Camera3D, one key light, toon materials, OUR palette), presented at nearest-neighbour
## under the full-res HUD. The 2D nodes remain the logic substrate (positions, pathing, picking,
## chunk data) but their visuals are hidden.
##
## Architecture (see the spec): gameplay streaming stays PLAYER-centred, while VISUAL terrain
## coverage is CAMERA-FOOTPRINT-centred (TerrainStreamView) — the separation that fixes the
## low-pitch beige fog/cutoff band. This node only: builds the roots + shared materials, creates
## and wires the subsystems, drives them in _process, and exposes a small compatibility API to
## the rest of the game (which still talks to `world.render_3d`).
##
## Subsystems:
##   RenderViewportPresenter  — SubViewport / present TextureRect / pixelation / residual shift
##   WorldCameraRig3D         — Camera3D follow / orbit / zoom / pixel-snap / ground footprint
##   TerrainChunkMesher       — terrain + water mesh emission and the height field
##   TerrainMeshManager       — terrain mesh lifecycle, build queue, visibility, eviction
##   TerrainStreamView        — camera-footprint visual chunk sets (visible/margin/keep)
##   WorldAtmosphere          — WorldEnvironment + sun; fog/shadow tuned from the visual extent
##   StaticPropBatcher        — time-sliced static-prop MultiMesh batching
##   MoverRenderer3D          — player/enemy rigs, animation, combat FX, shadows, outlines
##   PickingProjector3D       — screen<->world projection through the live camera
##   WorldFx3D                — firemaking fire + prayer bursts
##   WorldRenderDebug / WorldRenderPreviewTools — diagnostics + verification helpers

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")
const TOON_GROUND := preload("res://shaders/toon_ground.gdshader")
const TOON_WATER := preload("res://shaders/toon_water.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const CombatBars := preload("res://scripts/world/combat_bars.gd")

var world: Node2D
var cam: Camera3D                    # the live render camera (kept for WorldFx3D)
var fx_layer: CanvasLayer            # screen-space overlay for hitsplats over the 3D world
var terrain_ring := TerrainStreamView.TERRAIN_RING_MIN   # public: world streams DATA to match
var props_root: Node3D
var batches_root: Node3D
var terrain_root: Node3D
var _outlines_root: Node3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _active := false

# Subsystems.
var presenter: RenderViewportPresenter
var camera_rig: WorldCameraRig3D
var terrain_mesher: TerrainChunkMesher
var mesh_manager: TerrainMeshManager
var stream_view: TerrainStreamView
var atmosphere: WorldAtmosphere
var static_prop_batcher: StaticPropBatcher
var mover_renderer: MoverRenderer3D
var picking: PickingProjector3D
var fx: WorldFx3D
var debug: WorldRenderDebug
var preview_tools: WorldRenderPreviewTools

# Editor / FX compatibility properties (the editor + WorldFx3D set/read these via the coordinator;
# they delegate to the owning subsystem so external call sites don't change).
var editor_cam_target:
	get:
		return camera_rig.editor_cam_target if camera_rig != null else null
	set(value):
		if camera_rig != null:
			camera_rig.editor_cam_target = value

var editor_hide_player := false:
	get:
		return mover_renderer.editor_hide_player if mover_renderer != null else false
	set(value):
		if mover_renderer != null:
			mover_renderer.set_editor_hide_player(value)

var editor_plain_player := false:
	get:
		return mover_renderer.editor_plain_player if mover_renderer != null else false
	set(value):
		if mover_renderer != null:
			mover_renderer.set_editor_plain_player(value)

var editor_no_fog := false:
	get:
		return atmosphere.editor_no_fog if atmosphere != null else false
	set(value):
		if atmosphere != null:
			atmosphere.editor_no_fog = value

var editor_view_radius := 0:
	get:
		return stream_view.editor_radius_cap if stream_view != null else 0
	set(value):
		if stream_view != null:
			stream_view.editor_radius_cap = value
		if camera_rig != null:
			camera_rig.editor_footprint_chunks = value   # extend the camera footprint to match

var _cam_pitch: float:
	get:
		return camera_rig.get_pitch() if camera_rig != null else 0.413
	set(value):
		if camera_rig != null:
			camera_rig.set_pitch(value)

var _static_sig: String:
	get:
		return ""
	set(value):
		if static_prop_batcher != null:
			static_prop_batcher.invalidate()

var _player_node: Node3D:
	get:
		return mover_renderer.get_player_node() if mover_renderer != null else null
	set(value):
		pass


func setup(w: Node2D) -> void:
	world = w
	# Tests run headless and keep the 2D path (no 3D build). `-- --force3d` opts a headless run
	# INTO the full 3D pipeline against the dummy renderer — a smoke test for the renderer wiring
	# (subsystem build + the _process pipeline) that the normal headless path skips entirely.
	if DisplayServer.get_name() == "headless" and not ("--force3d" in OS.get_cmdline_user_args()):
		return
	_active = true
	_build()
	_hide_2d()


func _build() -> void:
	PropMeshes.warm_static_caches()
	presenter = RenderViewportPresenter.new()
	presenter.setup(world)
	var world3d := presenter.get_world3d()
	_setup_scene_roots(world3d)
	_setup_materials()
	# Terrain geometry + height field.
	terrain_mesher = TerrainChunkMesher.new()
	terrain_mesher.setup(world, _ground_mat, _water_mat)
	mesh_manager = TerrainMeshManager.new()
	mesh_manager.setup(world, terrain_root, terrain_mesher)
	# Camera (needs the height field to follow the ground + project the footprint).
	camera_rig = WorldCameraRig3D.new()
	camera_rig.setup(world, world3d, presenter, Callable(terrain_mesher, "height_at_iso"))
	camera_rig.set_coverage_query(_terrain_loaded_at)
	cam = camera_rig.get_camera()
	# Atmosphere (owns the sun the movers read for shadow direction).
	atmosphere = WorldAtmosphere.new()
	atmosphere.setup(world3d, _water_mat)
	# Visual coverage (camera-footprint chunk sets).
	stream_view = TerrainStreamView.new()
	stream_view.setup(world)
	# Props + movers + picking, wired through shared providers.
	var height_iso := Callable(terrain_mesher, "height_at_iso")
	var iso_to_3d_cb := Callable(terrain_mesher, "iso_to_3d")
	static_prop_batcher = StaticPropBatcher.new()
	static_prop_batcher.setup(world, batches_root, height_iso, iso_to_3d_cb)
	mover_renderer = MoverRenderer3D.new()
	mover_renderer.setup(world, props_root, _outlines_root, height_iso, iso_to_3d_cb, Callable(atmosphere, "get_sun"))
	picking = PickingProjector3D.new()
	picking.setup(world, camera_rig, presenter, height_iso, Callable(terrain_mesher, "height_at_grid"), iso_to_3d_cb)
	_setup_overlay()
	# FX + diagnostics + verification helpers.
	fx = WorldFx3D.new()
	fx.setup(self)
	debug = WorldRenderDebug.new()
	debug.setup(world, camera_rig, stream_view, mesh_manager, atmosphere)
	preview_tools = WorldRenderPreviewTools.new()
	preview_tools.setup(world, self, mesh_manager, fx)


func _setup_scene_roots(world3d: Node3D) -> void:
	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)
	batches_root = Node3D.new()
	world3d.add_child(batches_root)
	_outlines_root = Node3D.new()
	world3d.add_child(_outlines_root)


func _setup_materials() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("grass_dark"))   # deeper mossy shade so cast shadows read
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("hike_grass_light"))
	# Snow/ice surfaces: cool light grey, NOT periwinkle — snowy mountains should read white.
	_ground_mat.set_shader_parameter("cold_shadow_tint", Color(0.66, 0.71, 0.78))
	_ground_mat.set_shader_parameter("cold_light_tint", Color(0.94, 0.96, 0.99))
	_ground_mat.set_shader_parameter("ambient", 0.26)
	_ground_mat.set_shader_parameter("softness", 0.03)
	# Beach sand: warm golden tones + world-space macro/speckle variation (toon_ground applies
	# these only where a vertex is flagged as sand via UV.y; wetness via UV.x).
	_ground_mat.set_shader_parameter("sand_dry", Color(0.835, 0.768, 0.566))   # soft tan
	_ground_mat.set_shader_parameter("sand_hi", Color(0.890, 0.835, 0.650))    # pale highlight
	_ground_mat.set_shader_parameter("sand_wet", Color(0.737, 0.660, 0.486))   # wet sand
	_ground_mat.set_shader_parameter("sand_macro_scale", 0.045)
	_ground_mat.set_shader_parameter("sand_detail_scale", 0.6)
	_ground_mat.set_shader_parameter("sand_speckle", 0.045)
	_ground_mat.set_shader_parameter("sand_noise", TerrainChunkMesher.make_water_noise(0.8, 3, 5))

	_water_mat = ShaderMaterial.new()
	_water_mat.shader = TOON_WATER
	# wf-driven water on a FINELY TESSELLATED plane: the smoothed coast field (UV.x), sampled
	# bicubically per sub-vertex, gives a pixel-smooth 0.5 contour decoupled from the coarse
	# terrain mesh. World-space sampled (camera-stable).
	_water_mat.set_shader_parameter("deep_color", Color(0.067, 0.380, 0.498))     # #11617F deep ocean
	_water_mat.set_shader_parameter("shallow_color", Color(0.420, 0.780, 0.760))  # #6BC7C2 lit shallow
	_water_mat.set_shader_parameter("line_color", Color(0.290, 0.588, 0.655))     # #4A96A7 contour
	_water_mat.set_shader_parameter("foam_color", Color(0.886, 0.953, 0.965))     # #E2F3F6 sea foam
	_water_mat.set_shader_parameter("sd_scale", TerrainChunkMesher.SHORE_SD_SCALE)   # (wf-0.5) -> signed cells
	_water_mat.set_shader_parameter("shore_aa", 0.10)            # AA width of the waterline (cells)
	_water_mat.set_shader_parameter("shallow_cells", 0.9)        # shallow band before the deep ramp
	_water_mat.set_shader_parameter("pattern_scale", 0.072)       # mid features (dense 0.105 .. sparse 0.032)
	_water_mat.set_shader_parameter("contour_count", 3.5)         # medium line density / spacing
	_water_mat.set_shader_parameter("line_width", 0.038)
	_water_mat.set_shader_parameter("line_opacity", 0.6)
	_water_mat.set_shader_parameter("domain_warp_strength", 0.6)
	_water_mat.set_shader_parameter("secondary_strength", 0.28)   # weak secondary detail only
	_water_mat.set_shader_parameter("secondary_scale", 1.7)
	_water_mat.set_shader_parameter("primary_speed", Vector2(0.006, 0.003))
	_water_mat.set_shader_parameter("secondary_speed", Vector2(-0.003, 0.005))
	_water_mat.set_shader_parameter("contour_fade_in", 0.7)       # cells: contours start returning
	_water_mat.set_shader_parameter("contour_fade_out", 1.6)      # cells: contours fully back
	_water_mat.set_shader_parameter("foam_cells", 0.55)          # foam band width at the shore (cells)
	_water_mat.set_shader_parameter("foam_scale", 0.17)
	_water_mat.set_shader_parameter("foam_speed", 0.14)        # faster scroll -> visibly animated foam
	_water_mat.set_shader_parameter("foam_tex", TerrainChunkMesher.make_water_noise(0.7, 3, 6))
	_water_mat.set_shader_parameter("noise_tex", TerrainChunkMesher.make_water_noise(0.9, 2, 1))
	_water_mat.set_shader_parameter("warp_tex", TerrainChunkMesher.make_water_noise(0.35, 2, 2))


## Screen-space overlay for combat hitsplats (sits above the world image, below the HUD) plus
## the combat HP bars drawn on it. Splats are projected through the 3D camera onto here.
func _setup_overlay() -> void:
	fx_layer = CanvasLayer.new()
	fx_layer.name = "FxOverlay"
	fx_layer.layer = 0
	world.add_child(fx_layer)
	var bars := CombatBars.new()
	bars.name = "CombatBars"
	bars.world = world
	bars.render_3d = self
	fx_layer.add_child(bars)


## Hide the 2D world visuals — every CanvasItem child of the world root — while the nodes stay
## alive as the logic substrate (positions, pathing, picking).
func _hide_2d() -> void:
	# The 3D renderer is the display; stop the chunk substrate from baking 2D ground meshes that
	# are never shown (saves CPU per streamed chunk), then hide the 2D canvas.
	ChunkRenderer.build_meshes = false
	for node: Node in world.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false


# ----------------------------------------------------------------- runtime ----

func _process(delta: float) -> void:
	if not _active or world.player == null:
		return
	preview_tools.update_if_enabled()
	# Per-frame memo for tile-info/corner sampling (terrain build + every height sample hit the
	# same tiles thousands of times in a frame). Cleared once here, owned by the mesher.
	terrain_mesher.clear_frame_caches()
	presenter.update_pixelation()
	camera_rig.update_input(delta)
	camera_rig.sync_camera(delta)
	stream_view.update(camera_rig)
	terrain_ring = stream_view.terrain_data_ring()
	atmosphere.update(camera_rig, stream_view)
	mesh_manager.update(stream_view)
	mover_renderer.update(delta)
	static_prop_batcher.update(mesh_manager.is_terrain_built_this_frame())
	mover_renderer.update_outlines()
	fx.update(delta)
	debug.update_if_enabled()


# --------------------------------------------------- compatibility API (delegating) ----

func is_active() -> bool:
	return _active and cam != null


## Current camera orbit angle (radians). The minimap reads this to rotate with the view.
func cam_yaw() -> float:
	return camera_rig.get_yaw()


func orbit_drag(rel: Vector2) -> void:
	camera_rig.orbit_drag(rel)


func screen_to_iso(screen: Vector2) -> Vector2:
	return picking.screen_to_iso(screen)


func iso_to_screen(pos: Vector2, lift := 0.0) -> Vector2:
	return picking.iso_to_screen(pos, lift)


func world_px_per_unit() -> float:
	return picking.world_px_per_unit()


## Terrain height (3D Y) at a 2D iso position.
func height_at(pos: Vector2) -> float:
	return terrain_mesher.height_at_iso(pos)


## Map a 2D iso-pixel position to a 3D world position (Y from elevation/height).
func iso_to_3d(pos: Vector2, y: float) -> Vector3:
	return terrain_mesher.iso_to_3d(pos, y)


## World-Y to anchor a hitsplat at, scaled to the mover's size.
func mover_lift(entity: Node) -> float:
	return mover_renderer.mover_lift(entity)


## World-Y just above the model's head for floating UI (HP bars).
func mover_top(entity: Node) -> float:
	return mover_renderer.mover_top(entity)


## Editor hook: re-mesh a chunk + its 8 neighbours after a terrain/biome/water edit.
func rebuild_chunk(cx: int, cy: int) -> void:
	if not _active:
		return
	mesh_manager.rebuild_chunk(cx, cy)


## Editor live-brush hook: re-mesh just this chunk in place (fast, flicker-free) while dragging.
func rebuild_chunk_instant(cx: int, cy: int) -> void:
	if not _active:
		return
	mesh_manager.rebuild_chunk_instant(cx, cy)


## Force the static-prop batch to rebuild (preview teleports / placed props / editor edits).
func invalidate_static_batches() -> void:
	if static_prop_batcher != null:
		static_prop_batcher.invalidate()


## Editor: after an elevation/terrain edit, drop cached prop transforms in the edited world-space rect
## so the next batch re-samples their terrain height — otherwise the clutter floats above (or sinks
## into) the lowered/raised ground.
func reset_prop_transforms_in_rect(world_rect: Rect2) -> void:
	if static_prop_batcher != null:
		static_prop_batcher.reset_transforms_in_rect(world_rect)


## Rebuild the static-prop batch IMMEDIATELY (a tree felled to a stump / regrown) so the swap is
## instant — no momentary double of the old and new prop.
func force_static_batches() -> void:
	if static_prop_batcher != null:
		static_prop_batcher.force_rebuild()


## Is terrain DATA loaded at this grid point? The camera rig's coverage auto-zoom probes this so
## the view tightens before its footprint reaches past loaded terrain (world edge / streaming).
func _terrain_loaded_at(grid: Vector2) -> bool:
	var cx := floori(grid.x / float(WG.CHUNK_TILES))
	var cy := floori(grid.y / float(WG.CHUNK_TILES))
	return mesh_manager.data_chunk_by_key(WG.key(world.current_layer, cx, cy)) != null
