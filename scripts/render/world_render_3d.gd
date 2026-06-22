extends Node
## 3D pixel-art renderer for the live world (committed port — replaces the 2D
## draw output, no toggle). Hosts a low-resolution SubViewport with a 3D world
## (iso ortho Camera3D, one key light, toon materials, OUR palette), presented at
## nearest-neighbour under the full-res HUD. The 2D nodes remain as the logic
## substrate (positions, pathing, picking) but their visuals are hidden.
##
## Stage A: 3D terrain from real chunk data + camera follow.  Stage C adds props.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const TOON_GROUND := preload("res://shaders/toon_ground.gdshader")
const TOON_WATER := preload("res://shaders/toon_water.gdshader")
const PALETTE_SNAP := preload("res://shaders/palette_snap.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const EquipLoadout := preload("res://scripts/render/equip_loadout.gd")
const SmithyProp := preload("res://scripts/render/smithy_prop.gd")

const INTERNAL := Vector2i(640, 360)   # internal render res (higher = finer/less chunky pixels)
const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := WG.ELEV_H           # height per elevation step (8px / 32px tile); single
                                    # source in wg.gd. Render alias kept for call-site brevity.
# Turn spring: a body accelerates into a turn and damps out of it (slightly
# underdamped for a snappy-but-physical settle), so facing changes are never instant.
const TURN_STIFFNESS := 62.0
const TURN_DAMPING := 14.0
const HURT_DUR := 0.2               # how long the take-a-hit red flash + shake lasts
const FOREST_PREVIEW_ARG := "--forest-preview"
const WATER_PREVIEW_ARG := "--water-preview"   # verification: teleport to a deterministic ocean coast
const FX_PREVIEW_ARG := "--fx-preview"         # verification: light the fire + emit prayer bursts at spawn

var world: Node2D
var sub: SubViewport
var world3d: Node3D
var cam: Camera3D
var present: TextureRect
var terrain_root: Node3D
var props_root: Node3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _snap_mat: ShaderMaterial
var _occ_cache: Dictionary = {}   # global tile -> is_water (deterministic; persists)
var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_nbr: Dictionary = {}      # chunk key -> neighbour-data count at last build (seam reconcile)
var _chunk_wait: Dictionary = {}     # chunk key -> frames waited for neighbour data (defer fallback)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (O(1) height lookup)
var batches_root: Node3D             # holds the per-(mesh,material) MultiMeshInstance3D
var _outlines_root: Node3D           # inverted-hull silhouette outlines for highlighted entities
var _outline_mat: ShaderMaterial     # shared white outline material (grown hull, cull_front)
var _outline_nodes: Dictionary = {}  # static entity id -> outline Node3D
var _outlined_movers: Dictionary = {} # mover id -> true (material_overlay applied)
var _fx: WorldFx3D                    # firemaking fire + prayer bursts (world_fx_3d.gd)
var _mover_nodes: Dictionary = {}    # moving entity id -> Node3D (player/enemies)
var _mover_prev: Dictionary = {}     # key -> last 3D pos (for walk detection)
var _mover_yaw: Dictionary = {}      # key -> facing yaw (turned with spring inertia)
var _mover_yaw_vel: Dictionary = {}  # key -> angular velocity for the turn spring
var _mover_walk: Dictionary = {}     # key -> smoothed walk amount 0..1
var _mover_sit: Dictionary = {}      # key -> smoothed sit amount 0..1 (player resting)
var _attack_t: Dictionary = {}       # key -> time (s) the last attack lunge started
var _hurt_t: Dictionary = {}         # key -> time (s) a body last took a hit (red flash + shake)
var _mover_death: Dictionary = {}    # key -> {t0, pos} while a defeated mover plays its death topple
var _shadow_nodes: Dictionary = {}   # key -> blob-shadow MeshInstance3D pinned to ground
var fx_layer: CanvasLayer            # screen-space overlay for hitsplats over the 3D world
var _env: Environment                # kept so the view-distance slider can retune the fog
var _sun: DirectionalLight3D         # kept so the slider can scale shadow distance
var _terrain_cull := 34.0            # visible terrain radius (tiles), driven by view_distance
var _prop_cull := 30.0               # visible prop/decor radius (tiles)
# The 3D terrain BUILD ring (chunks): how far full-detail terrain meshes are generated
# around the player. The view-distance slider scales this between MIN and MAX so it
# genuinely extends how far the world renders (the old code pinned terrain to the tiny
# 3-chunk nav ring, so the slider could only shrink — never extend — the visible world).
const TERRAIN_RING_MIN := 3
const TERRAIN_RING_MAX := 10          # slider's max FLOOR (~160 tiles)
const TERRAIN_RING_HARD_MAX := 14     # absolute cap incl. zoom-out coverage (perf bound, ~224 tiles)
var terrain_ring := TERRAIN_RING_MIN  # public: world._update_stream_radius streams data to match
var _view_ring_floor := TERRAIN_RING_MIN   # slider-driven minimum; the live ring also grows to fit zoom
var _player_node: Node3D
var _cam_yaw := PI / 4.0          # orbit angle around the player (Left/Right arrows)
var _cam_pitch := 0.413           # elevation above horizon (Up/Down arrows); matches old iso
const CAM_FOLLOW_SPEED := 12.0   # eased-follow rate, matches the 2D Camera2D position_smoothing_speed
var _cam_follow := Vector2.INF    # smoothed follow target (iso); INF = uninitialised (snap on first use)
var editor_cam_target = null      # world editor: Vector2 to pin the camera to (overrides player follow); null = off
var editor_hide_player := false   # world editor: don't render the player rig (clean world-building canvas)
var _pixel_scale := 3             # INTEGER display px per internal px (nearest-neighbour, no fractional stretch)
# How the low-res image is placed on the window: an exact integer scale + centred offset.
# Kept here so screen<->internal-pixel picking math accounts for the integer presentation.
const PRESENT_OVERSCAN := 1   # internal-px margin per side, for the sub-pixel residual shift
var _present_scale := 1.0
var _present_off := Vector2.ZERO
var _present_base_off := Vector2.ZERO
var _static_sig := ""
var _ti_cache: Dictionary = {}       # per-frame memo: Vector2i tile -> tile info (cleared each frame)
var _cc_cache: Dictionary = {}       # per-frame memo: Vector2i corner -> corner colour
var _cb_cache: Dictionary = {}       # per-frame memo: Vector2i corner -> beach fraction
var _vfh_cache: Dictionary = {}      # per-frame memo: Vector2i tile -> visual floor height
var _ccl_cache: Dictionary = {}      # per-frame memo: Vector2i corner -> Array of height clusters
var _batch_xf: Dictionary = {}       # static prop instance_id -> cached world Transform3D
const _IDENTITY_XF := Transform3D()  # sentinel for "not yet cached" (props never sit at identity)
var _terrain_built := false          # did a chunk mesh build this frame (stagger batch rebuild off it)
var _batch_rebuild_t := 0.0          # last static-batch rebuild START time (throttle)
const BATCH_REBUILD_MIN := 0.35      # min seconds between static-batch rebuilds
# Staged (time-sliced) batch rebuild: the full rebuild is O(all visible props) and spiked to
# ~70ms at close zoom. We spread it over frames — collect a slice of props, then emit a few
# MultiMesh groups per frame into a HIDDEN staging node — and swap it in only when complete,
# so the old batch stays visible meanwhile (no gap) and no single frame does the whole rebuild.
const RB_COLLECT_PER_FRAME := 150     # props collected per frame (caps height_at samples/frame)
const RB_EMIT_INSTANCES_PER_FRAME := 500  # instances buffered per frame (caps a giant group's fill)
var _rb_active := false
var _rb_phase := 0                   # 0 = collecting, 1 = emitting
var _rb_list: Array = []             # snapshot [[kind:int 0=decor/1=water/2=ent, node], …]
var _rb_i := 0                       # phase 0: list index;  phase 1: group-key index
var _rb_groups: Dictionary = {}
var _rb_xf: Dictionary = {}
var _rb_keys: Array = []
var _rb_sig := ""
var _rb_staging: Node3D = null
var _rb_g: Dictionary = {}           # group currently being emitted (filled incrementally)
var _rb_gbuf := PackedFloat32Array() # its instance buffer, filled across frames
var _rb_gi := 0                      # instance index within the current group
var _forest_preview_done := false
var _water_preview_done := false
var _smithy_done := false
var smithy_node: Node3D = null   # the placed smithy model (kept so it persists at spawn)
var _frames := 0
var _captured := false
var _active := false


func setup(w: Node2D) -> void:
	world = w
	if DisplayServer.get_name() == "headless":
		return   # tests run headless; keep the 2D path, no 3D build
	_active = true
	_build()
	_hide_2d()


func _build() -> void:
	_setup_viewport()
	_setup_environment()
	_setup_sun()
	_setup_camera()
	_setup_scene_roots()
	_setup_materials()
	_setup_present()
	# Pixelation is controlled from the Settings menu (GameSettings.pixelation).
	_pixel_scale = _scale_from_setting(GameSettings.pixelation)
	GameSettings.changed.connect(_on_settings_changed)


func _setup_viewport() -> void:
	sub = SubViewport.new()
	sub.size = INTERNAL
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub.use_taa = false
	sub.use_debanding = false
	sub.positional_shadow_atlas_size = 0
	add_child(sub)
	PropMeshes.warm_static_caches()

	world3d = Node3D.new()
	sub.add_child(world3d)


func _setup_environment() -> void:
	# Soft warm HAZE sky (A Short Hike-ish): a low-contrast warm wash, no cool blue
	# top, so wherever the terrain edge lands it meets a matching sky and dissolves
	# instead of forming a seam. The horizon colour is shared with the distance fog.
	var horizon_col := PixelPalette.pal("snow_a").lerp(PixelPalette.pal("gold"), 0.34)
	var sky_hi := PixelPalette.pal("snow_a").lerp(PixelPalette.pal("gold"), 0.22)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_hi
	sky_mat.sky_horizon_color = horizon_col
	sky_mat.ground_horizon_color = horizon_col
	sky_mat.ground_bottom_color = horizon_col
	sky_mat.sky_curve = 0.32   # wide, soft horizon band: the warm haze fills most of the sky
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# A muted, slightly cool earth-green fill so shaded grass/foliage stays a deep
	# mossy green (not near-black, not lime) — moody-cozy forest, not bright neon.
	env.ambient_light_color = Color(0.5, 0.56, 0.47)
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Stylized atmospheric perspective (A Short Hike), NOT volumetric fog: a depth
	# fog in the SAME colour as the sky horizon, ramping from the middle distance to
	# 100% before the camera reaches the streamed terrain's edge — so the edge is
	# never seen, the world just fades into the sky. The smoothstep curve keeps the
	# near/mid ground crisp and only hazes the far field.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = horizon_col
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_begin = 24.0
	env.fog_depth_end = 48.0      # full opacity before the streamed terrain's edge depth
	env.fog_depth_curve = 2.0     # > 1 = hold the mid distance clear, then ramp hard at the end
	# Bleed the fog into the lower sky too, so the fogged terrain and the sky behind
	# it are the SAME haze — no seam at the horizon, and the sky itself reads foggy.
	env.fog_sky_affect = 0.5
	env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world3d.add_child(we)
	_env = env


func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)   # lower afternoon sun -> longer soft shadows
	sun.light_color = Color(1.0, 0.95, 0.8)    # warm afternoon daylight
	sun.light_energy = 1.0                     # softer key light for a moodier, earthy look
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.9
	sun.shadow_blur = 0.7   # tighter edge: the wide 1.5 blur shimmered ("fuzzy") in motion;
	                        # the pixel-snapped camera keeps the now-crisper edge stable
	world3d.add_child(sun)
	_sun = sun
	_apply_view_distance()   # set terrain cull / fog distance / shadow distance from the slider
	GameSettings.changed.connect(func(p: StringName) -> void:
		if p == &"view_distance":
			_apply_view_distance())


func _setup_camera() -> void:
	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.8
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)


func _setup_scene_roots() -> void:
	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)
	batches_root = Node3D.new()
	world3d.add_child(batches_root)
	_outlines_root = Node3D.new()
	world3d.add_child(_outlines_root)
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("outline_color", Color(1.0, 1.0, 1.0, 1.0))
	_outline_mat.set_shader_parameter("width", 0.045)


func _setup_materials() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("grass_dark"))   # deeper mossy shade so cast shadows read
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("hike_grass_light"))
	_ground_mat.set_shader_parameter("cold_shadow_tint", Color(0.48, 0.51, 0.74))
	_ground_mat.set_shader_parameter("cold_light_tint", Color(0.88, 0.89, 1.0))
	_ground_mat.set_shader_parameter("ambient", 0.26)
	_ground_mat.set_shader_parameter("softness", 0.03)
	# Beach sand: warm golden tones + world-space macro/speckle variation (toon_ground
	# applies these only where a vertex is flagged as sand via UV.y; wetness via UV.x).
	# Paler/less-saturated than the target hexes so the WARM toon sun lands them back at a
	# soft sandy yellow (full-sat yellows go orange under the warm light).
	_ground_mat.set_shader_parameter("sand_dry", Color(0.835, 0.768, 0.566))   # soft tan
	_ground_mat.set_shader_parameter("sand_hi", Color(0.890, 0.835, 0.650))    # pale highlight
	_ground_mat.set_shader_parameter("sand_wet", Color(0.737, 0.660, 0.486))   # wet sand
	_ground_mat.set_shader_parameter("sand_macro_scale", 0.045)
	_ground_mat.set_shader_parameter("sand_detail_scale", 0.6)
	_ground_mat.set_shader_parameter("sand_speckle", 0.045)
	_ground_mat.set_shader_parameter("sand_noise", _make_water_noise(0.8, 3, 5))

	_water_mat = ShaderMaterial.new()
	_water_mat.shader = TOON_WATER
	# wf-driven water on a FINELY TESSELLATED plane: the smoothed coast field (UV.x), sampled
	# bicubically per sub-vertex, gives a pixel-smooth 0.5 contour decoupled from the coarse
	# terrain mesh — no per-tile triangulation teeth. Shallows / foam / illustrated contour
	# loops all key off that one field. World-space sampled (camera-stable).
	_water_mat.set_shader_parameter("deep_color", Color(0.067, 0.380, 0.498))     # #11617F deep ocean
	_water_mat.set_shader_parameter("shallow_color", Color(0.420, 0.780, 0.760))  # #6BC7C2 lit shallow
	_water_mat.set_shader_parameter("line_color", Color(0.290, 0.588, 0.655))     # #4A96A7 contour
	_water_mat.set_shader_parameter("foam_color", Color(0.886, 0.953, 0.965))     # #E2F3F6 sea foam
	_water_mat.set_shader_parameter("sd_scale", SHORE_SD_SCALE)   # (wf-0.5) -> signed cells
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
	_water_mat.set_shader_parameter("foam_speed", 0.05)
	_water_mat.set_shader_parameter("foam_tex", _make_water_noise(0.7, 3, 6))
	_water_mat.set_shader_parameter("noise_tex", _make_water_noise(0.9, 2, 1))
	_water_mat.set_shader_parameter("warp_tex", _make_water_noise(0.35, 2, 2))
	_apply_view_distance()   # now that _water_mat exists, push the detail-fade range for the view slider


func _setup_present() -> void:
	# Present the low-res 3D world at nearest-neighbour, under the HUD (layer 1).
	var layer := CanvasLayer.new()
	layer.layer = 0
	world.add_child(layer)
	present = TextureRect.new()
	# Sized/positioned explicitly in _apply_pixelation to an EXACT integer scale (centred,
	# slight overscan) so every internal texel becomes a uniform block — no fractional
	# stretch (the root cause of pixel crawl). Nearest-neighbour, no mipmaps.
	present.set_anchors_preset(Control.PRESET_TOP_LEFT)
	present.texture = sub.get_texture()
	present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	present.stretch_mode = TextureRect.STRETCH_SCALE
	# Let clicks / scroll-wheel fall through to the 2D world (movement, picking,
	# zoom all still run on the hidden 2D substrate).
	present.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_mat = ShaderMaterial.new()
	_snap_mat.shader = PALETTE_SNAP
	_snap_mat.set_shader_parameter("palette_tex", _palette_texture())
	_snap_mat.set_shader_parameter("palette_count", PixelPalette.PAL.size())
	_snap_mat.set_shader_parameter("enabled", 1.0)
	_snap_mat.set_shader_parameter("strength", 0.8)
	_snap_mat.set_shader_parameter("contrast", 1.08)
	_snap_mat.set_shader_parameter("saturation", 1.03)   # muted, earthy — not punchy lime
	_snap_mat.set_shader_parameter("brightness", 0.92)   # moodier, slightly darker
	present.material = _snap_mat
	layer.add_child(present)
	# Screen-space overlay for combat hitsplats: sits above the world image (added
	# after `present` in the same layer 0) and below the HUD (layer 1). Splats are
	# projected onto here through the 3D camera so they land over the right body.
	fx_layer = CanvasLayer.new()
	fx_layer.name = "FxOverlay"
	fx_layer.layer = 0
	world.add_child(fx_layer)
	# Combat HP bars (player + target) drawn on the overlay during a fight.
	var bars := preload("res://scripts/world/combat_bars.gd").new()
	bars.name = "CombatBars"
	bars.world = world
	bars.render_3d = self
	fx_layer.add_child(bars)
	# Drive attack lunges off the combat ticks: each hit splat is one swing landing.
	EventBus.combat_hit_splat.connect(_on_combat_swing)
	EventBus.combat_ranged_shot.connect(func(_a: int, _m: bool) -> void: _mark_attack("player"))
	# Firemaking fire + prayer-activation bursts: WorldFx3D listens to EventBus itself.
	_fx = WorldFx3D.new()
	_fx.setup(self)


## React to the Settings-menu pixelation slider (0 = native, 1 = really crunchy),
## mapped to a 1x..8x render-pixel size relative to the window.
func _on_settings_changed(prop: StringName) -> void:
	if prop == &"pixelation":
		_pixel_scale = _scale_from_setting(GameSettings.pixelation)


# Discrete INTEGER pixel scales the slider snaps to. Godot recommends integer viewport
# scaling for pixel art — fractional scales give texels uneven displayed sizes, which is
# exactly what crawls during motion. Each level is an exact display:internal ratio.
const PIXEL_LEVELS := [1, 2, 3, 4, 5, 6, 8]

func _scale_from_setting(v: float) -> int:
	# Verification override: `-- --crisp` renders near-native so detail is legible in shots.
	if "--crisp" in OS.get_cmdline_args() or "--crisp" in OS.get_cmdline_user_args():
		return 1
	var idx := int(round(clampf(v, 0.0, 1.0) * float(PIXEL_LEVELS.size() - 1)))
	return PIXEL_LEVELS[clampi(idx, 0, PIXEL_LEVELS.size() - 1)]


## Size the SubViewport to an INTEGER fraction of the window and present it at that exact
## integer scale (centred, slight overscan so the integer-scaled image always covers the
## window — no black bars, no fractional stretch). This is the stable pixel grid: every
## internal texel maps to a uniform `scale x scale` block of display pixels.
func _apply_pixelation() -> void:
	if sub == null or present == null:
		return
	var win: Vector2 = world.get_viewport().get_visible_rect().size
	if win.x < 1.0 or win.y < 1.0:
		return
	var scale: int = _pixel_scale
	# Overscan (ceil + a 1px margin on every side) so display = internal*scale comfortably
	# covers the window AND leaves room for the sub-pixel residual shift below to slide the
	# image without revealing an empty edge. Both dims are integers.
	var internal := Vector2i(
		maxi(8, int(ceil(win.x / float(scale))) + 2 * PRESENT_OVERSCAN),
		maxi(8, int(ceil(win.y / float(scale))) + 2 * PRESENT_OVERSCAN))
	if internal != sub.size:
		sub.size = internal
	var displayed := internal * scale
	_present_scale = float(scale)
	_present_base_off = Vector2(floor((win.x - float(displayed.x)) * 0.5), floor((win.y - float(displayed.y)) * 0.5))
	present.size = Vector2(displayed)
	# Base position now; _snap_camera adds the sub-pixel residual shift after the follow.
	present.position = _present_base_off
	_present_off = _present_base_off


## Hide the 2D world visuals — every CanvasItem child of the world root — while
## the nodes stay alive as the logic substrate (positions, pathing, picking).
func _hide_2d() -> void:
	# The 3D renderer is the display; stop the chunk substrate from baking 2D ground meshes
	# that are never shown (saves CPU per streamed chunk), then hide the 2D canvas.
	ChunkRenderer.build_meshes = false
	for node: Node in world.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false


# ----------------------------------------------------------------- runtime ----

func _process(delta: float) -> void:
	if not _active or world.player == null:
		return
	_maybe_teleport_to_forest_preview()
	_maybe_teleport_to_water_preview()
	_maybe_fx_preview()
	_maybe_place_smithy()
	# Per-frame memo for tile-info/corner-colour sampling (terrain build + every mover
	# height sample hit the same tiles thousands of times in a frame).
	_ti_cache.clear()
	_cc_cache.clear()
	_cb_cache.clear()
	_occ_cache.clear()
	_vfh_cache.clear()
	_ccl_cache.clear()
	_apply_pixelation()   # keeps render res matched to the window + pixelation slider
	_update_camera_input(delta)
	_sync_camera()
	_refresh_view_extent()   # grow the loaded terrain to cover the current zoom/tilt footprint
	_sync_terrain()
	_sync_movers()
	_sync_static_batches()
	_sync_outlines()
	_fx.update(delta)
	_frames += 1
	var capture_frame := 150 if (_forest_preview_enabled() or _water_preview_enabled()) else 90
	if _frames == capture_frame and not _captured:
		_capture()


## Place the imported smithy model at the spawn camp (once, after the spawn chunk's data is
## loaded so the ground height is real), then teleport the player there to see it. Static prop —
## parented under props_root and kept for the session.
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
	inst.position = iso_to_3d(pos, height_at(pos)) + Vector3(0.0, SmithyProp.bottom_offset(model_scale), 0.0)
	inst.rotation.y = PI * 0.15
	props_root.add_child(inst)
	smithy_node = inst
	# Teleport the player to the camp so the smithy is right there in view.
	world.teleport_to(spawn)
	_static_sig = ""
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
	_static_sig = ""
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
# Deterministic teleport to a dry beach tile that overlooks open ocean, so coastline
# tweaks can be eyeballed at the SAME spot every run (the save position drifts).
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
	_static_sig = ""
	print("[world3d] water preview teleport to tile %s" % [WG.world_to_tile(pos)])


func _water_preview_enabled() -> bool:
	return WATER_PREVIEW_ARG in OS.get_cmdline_args() or WATER_PREVIEW_ARG in OS.get_cmdline_user_args()


# Verification only: drive WorldFx3D from the spawn so a capture shows the campfire + a fresh
# prayer burst (the FX never trigger at idle spawn otherwise). Lights the fire once, then
# re-emits a prayer activation every ~0.4s so a burst is always live when the shot is taken.
var _fx_preview_lit := false
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


# The nearest ocean BEACH (the finite world's edge coast). A beach tile is dry,
# walkable land directly against open ocean — the long diagonal coastline where the
# per-tile triangulation is most exposed. Falls back to any large water body.
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


const CAM_SIZE_BASE := 19.5   # ortho size at the default 1.65 zoom
const CAM_DIST := 31.0
const CAM_YAW_SPEED := 1.7    # rad/sec — Left/Right orbit (full 360°)
const CAM_PITCH_SPEED := 1.1  # rad/sec — Up/Down tilt
const CAM_PITCH_MIN := 0.16   # near the horizon — low cinematic tilt; the bottom-edge stays on the
                              # ground via the frustum lift in _sync_camera (not a pitch limit)
const CAM_PITCH_MAX := 1.40   # near top-down (kept off the gimbal pole)


## Arrow keys orbit the camera around the player: Left/Right spin the yaw a full
## 360°, Up/Down tilt the pitch (clamped). Picking adapts automatically because
## screen_to_iso casts through the live camera.
func _update_camera_input(delta: float) -> void:
	var spd: float = GameSettings.cam_rotate_speed   # user-tunable orbit/tilt multiplier
	if Input.is_key_pressed(KEY_LEFT):
		_cam_yaw -= CAM_YAW_SPEED * spd * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_yaw += CAM_YAW_SPEED * spd * delta
	if Input.is_key_pressed(KEY_UP):
		_cam_pitch = clampf(_cam_pitch + CAM_PITCH_SPEED * spd * delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
	if Input.is_key_pressed(KEY_DOWN):
		_cam_pitch = clampf(_cam_pitch - CAM_PITCH_SPEED * spd * delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
	_cam_yaw = wrapf(_cam_yaw, -PI, PI)


# Radians of yaw/pitch per pixel of middle-mouse drag (before the cam_rotate_speed
# multiplier). Tuned so a ~full-window horizontal drag sweeps most of a 360° orbit and
# a vertical drag covers the pitch clamp — the drag equivalent of the arrow-key orbit.
const CAM_DRAG_YAW := 0.006
const CAM_DRAG_PITCH := 0.004


## Middle-mouse drag orbit: rotate the camera by a screen-pixel mouse delta. Drag
## moves the world WITH the cursor (grab-and-drag feel) on both axes: dragging right
## spins the view so the scene follows, dragging down tilts toward top-down.
func orbit_drag(rel: Vector2) -> void:
	var spd: float = GameSettings.cam_rotate_speed
	_cam_yaw = wrapf(_cam_yaw - rel.x * CAM_DRAG_YAW * spd, -PI, PI)
	_cam_pitch = clampf(_cam_pitch + rel.y * CAM_DRAG_PITCH * spd, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _sync_camera() -> void:
	# Eased follow (the "snappier follow-cam" from main): the 2D Camera2D uses
	# position_smoothing, but the 3D render camera is what's visible here, so replicate it.
	# Smoothly chase the player's iso position instead of hard-locking to it, which absorbs
	# any unevenness in the walk and reads as a calm, steady glide.
	# The world editor pins the camera to a fixed authoring point so the live (and
	# possibly wandering/fighting) player never drifts the view. null = follow the player.
	var follow: Vector2 = editor_cam_target if editor_cam_target != null else world.player.position
	if _cam_follow == Vector2.INF:
		_cam_follow = follow   # first frame / teleport: snap, don't ease across the world
	elif _cam_follow.distance_to(follow) > 600.0:
		_cam_follow = follow   # big jump (teleport) — snap, never ease across a long gap
	else:
		_cam_follow = _cam_follow.lerp(follow, clampf(CAM_FOLLOW_SPEED * get_process_delta_time(), 0.0, 1.0))
	var c := iso_to_3d(_cam_follow, height_at(_cam_follow))
	# Mouse-wheel zoom still drives the 2D camera (the logic substrate); mirror it
	# to the 3D ortho size so zoom works like before.
	var zoom: float = float(world._camera.zoom.x) if world._camera != null and world._camera.zoom.x > 0.01 else 1.65
	cam.size = CAM_SIZE_BASE / zoom
	# Orbit direction from the arrow-key yaw/pitch (default = the original iso angle).
	var dir := Vector3(cos(_cam_pitch) * sin(_cam_yaw), sin(_cam_pitch), cos(_cam_pitch) * cos(_cam_yaw))
	cam.position = c + dir * CAM_DIST
	cam.look_at(c + Vector3(0, 0.75, 0), Vector3.UP)
	# An ORTHOGRAPHIC frustum dips its lower edge BELOW the ground plane when tilted low and zoomed
	# out, so the bottom of the screen shows bare sky ("fog under the player") — no terrain loading
	# can fill it (there's no ground along those rays). Rather than forbid the low angle, SLIDE the
	# camera up its own up-axis so the bottom edge rides on the ground: the view shifts up (player
	# sits a little lower on screen, like a real low-angle shot) instead of revealing the void.
	var up := cam.global_transform.basis.y
	if up.y > 0.01:
		var bottom_y := cam.position.y - (cam.size * 0.5) * up.y   # world Y of the frustum's lower edge
		var deficit := (c.y + 0.5) - bottom_y                      # how far it sits below ground (+0.5 margin)
		if deficit > 0.0:
			var lift := minf(deficit / up.y, cam.size * 0.46 / up.y)  # cap so the player stays on screen
			cam.position += up * lift
	_snap_camera()


## Pixel-snapped RENDER camera + sub-pixel residual offset ("Stable Pixel Motion").
##
## The follow above is the smooth LOGICAL transform. We SNAP the render camera's
## screen-plane translation to the internal pixel grid so coast edges / contour lines /
## sprites land on the SAME internal texels frame to frame (no crawl). But snapping alone
## makes the world jump in whole-internal-pixel steps as you walk — visible micro-stutter,
## worse at stronger pixelation. So we also take the RESIDUAL we snapped away and shift the
## final presented image by it, rounded to whole DISPLAY pixels: the apparent motion is
## then smooth to display-pixel precision while every internal texel stays a clean block.
## The 2D gameplay world, player position and camera orientation are untouched.
func _snap_camera() -> void:
	if sub == null or sub.size.y <= 0:
		return
	var wupp := cam.size / float(sub.size.y)   # world units per internal pixel (KEEP_HEIGHT)
	if wupp <= 0.0:
		return
	var b := cam.global_transform.basis
	var right := b.x   # camera screen-right (orthonormal)
	var up := b.y      # camera screen-up
	var fwd := -b.z    # camera forward (depth) — left unsnapped
	var logical := cam.position
	var r: float = round(logical.dot(right) / wupp) * wupp
	var u: float = round(logical.dot(up) / wupp) * wupp
	var f: float = logical.dot(fwd)
	cam.position = right * r + up * u + fwd * f   # snapped render position
	# Residual we snapped away (< half a pixel along each screen axis), as a fraction of an
	# internal pixel. Re-add it by sliding the presented image — content moves OPPOSITE to a
	# rightward camera nudge, and screen-Y is inverted vs camera-up. Rounded to whole display
	# pixels so texels never resample/blur.
	if present != null:
		var res_right := (logical.dot(right) - r) / wupp   # internal px, [-0.5, 0.5]
		var res_up := (logical.dot(up) - u) / wupp
		var shift := Vector2(round(-res_right * _present_scale), round(res_up * _present_scale))
		present.position = _present_base_off + shift
		_present_off = present.position


## Build/free per-chunk terrain meshes to match the currently loaded chunks.
const DEFER_MAX_WAIT := 24   # frames a chunk may wait for neighbour data before force-building

func _sync_terrain() -> void:
	var live := {}   # the build set: every loaded chunk within the view-distance terrain ring
	for chunk: RefCounted in world.chunk_manager.terrain_chunks(terrain_ring):
		live[chunk.key()] = true
	# APRON / HALO: index EVERY chunk with loaded data (a ring larger than the build set),
	# so building a chunk can sample its neighbour tiles one ring out and compute complete,
	# matching shared-border corners on the FIRST build — no later seam, no rebuild heal.
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.data_chunks():
		_chunk_by_key[chunk.key()] = chunk
	# Pass 2 (DEFER): build at most one mesh per frame (each SurfaceTool build is a few ms),
	# and ONLY a chunk whose 8 neighbours' data is already present, so its borders are
	# seamless the first time. If nothing qualifies for a while (a world-edge chunk whose
	# neighbour will never load), fall back to the longest-waiting chunk so terrain still
	# appears; such a partial build is reconciled by the rebuild pass once data arrives.
	var pick := ""
	for key2: String in live:
		if not _chunk_meshes.has(key2) and _data_nbr_count(key2) == 8:
			pick = key2
			break
	if pick == "":
		var best_w := DEFER_MAX_WAIT
		for key2: String in live:
			if _chunk_meshes.has(key2):
				continue
			var w := int(_chunk_wait.get(key2, 0)) + 1
			_chunk_wait[key2] = w
			if w > best_w:
				best_w = w
				pick = key2
	_terrain_built = false
	if pick != "":
		var node := _build_chunk_terrain(_chunk_by_key[pick])
		terrain_root.add_child(node)
		_chunk_meshes[pick] = node
		_chunk_nbr[pick] = _data_nbr_count(pick)
		_chunk_wait.erase(pick)
		_terrain_built = true
		# CATCH-UP: when many chunks are missing at once (just zoomed out / view grew), build a
		# few extra neighbour-complete chunks this frame so the new, larger ring fills in within
		# a fraction of a second instead of crawling in one-per-frame with the edge exposed.
		var missing := 0
		for k: String in live:
			if not _chunk_meshes.has(k):
				missing += 1
		if missing > 24:
			var extra := 0
			for k2: String in live:
				if extra >= TERRAIN_CATCHUP_BUILDS:
					break
				if not _chunk_meshes.has(k2) and _data_nbr_count(k2) == 8:
					var n2 := _build_chunk_terrain(_chunk_by_key[k2])
					terrain_root.add_child(n2)
					_chunk_meshes[k2] = n2
					_chunk_nbr[k2] = _data_nbr_count(k2)
					_chunk_wait.erase(k2)
					extra += 1
	else:
		# Pass 2b: nothing new to build this frame -> reconcile any chunk that was
		# force-built with partial neighbour data once more of its neighbours have loaded.
		for key2: String in _chunk_meshes.keys():
			if not live.has(key2):
				continue
			var nc := _data_nbr_count(key2)
			if nc > int(_chunk_nbr.get(key2, -1)):
				var old: Node = _chunk_meshes[key2]
				if is_instance_valid(old):
					old.queue_free()
				var node := _build_chunk_terrain(_chunk_by_key[key2])
				terrain_root.add_child(node)
				_chunk_meshes[key2] = node
				_chunk_nbr[key2] = nc
				_terrain_built = true
				break
	# Persist built terrain ("load once"): meshes are NOT freed when the player walks away, so
	# revisiting an area never re-streams or flickers — the radial cull just hides the far ones.
	# Only evict when over budget, dropping the chunks farthest from the player first, so memory
	# stays bounded on a long trek.
	if _chunk_meshes.size() > MAX_TERRAIN_MESHES:
		_evict_far_terrain(_chunk_meshes.size() - MAX_TERRAIN_MESHES)
	_update_terrain_visibility()


const MAX_TERRAIN_MESHES := 1400   # persisted terrain budget; ~radius-21-chunk explored area
const TERRAIN_CATCHUP_BUILDS := 5  # extra chunk meshes built in one frame while the ring is filling

func _evict_far_terrain(count: int) -> void:
	var g := _world_to_grid(world.player.position)
	var ranked: Array = []
	for key: String in _chunk_meshes.keys():
		var parts := key.split(":")
		if parts.size() < 3:
			continue
		var ct := Vector2(float(int(parts[1]) * WG.CHUNK_TILES), float(int(parts[2]) * WG.CHUNK_TILES))
		ranked.append([ct.distance_squared_to(g), key])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])   # farthest first
	for i: int in mini(count, ranked.size()):
		var key: String = ranked[i][1]
		var mi: Node = _chunk_meshes.get(key)
		if is_instance_valid(mi):
			mi.queue_free()
		_chunk_meshes.erase(key)
		_chunk_nbr.erase(key)
		_chunk_wait.erase(key)


## Editor hook (world editor's live 3D view): discard the built terrain mesh for a chunk
## and its 8 neighbours, so the per-frame _sync_terrain build loop re-meshes them from the
## now-edited (shared) chunk data — borders re-stitch because the neighbours rebuild too.
## No-op in headless. Terrain/biome/water tile edits show up within a few frames.
func rebuild_chunk(cx: int, cy: int) -> void:
	if not _active:
		return
	var layer: int = world.current_layer
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var k := WG.key(layer, cx + dx, cy + dy)
			if _chunk_meshes.has(k):
				var n: Node = _chunk_meshes[k]
				if is_instance_valid(n):
					n.queue_free()
				_chunk_meshes.erase(k)
				_chunk_nbr.erase(k)
				_chunk_wait.erase(k)


# How many of a chunk's 8 neighbours currently have their DATA loaded (indexed in the
# apron). 8 => the chunk can be built with fully complete, seamless shared borders.
func _data_nbr_count(key: String) -> int:
	var parts := key.split(":")
	if parts.size() < 3:
		return 0
	var layer := int(parts[0])
	var cx := int(parts[1])
	var cy := int(parts[2])
	var c := 0
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if _chunk_by_key.has(WG.key(layer, cx + dx, cy + dy)):
				c += 1
	return c


func _update_terrain_visibility() -> void:
	var g := _world_to_grid(world.player.position)
	for key: String in _chunk_meshes.keys():
		var node: Node3D = _chunk_meshes[key]
		if not is_instance_valid(node):
			continue
		var parts := key.split(":")
		if parts.size() < 3:
			node.visible = true
			continue
		var cx := int(parts[1])
		var cy := int(parts[2])
		var center := Vector2(float(cx * WG.CHUNK_TILES + WG.CHUNK_TILES / 2), float(cy * WG.CHUNK_TILES + WG.CHUNK_TILES / 2))
		# RADIAL cull (a disc, not a square): a square's corners reach the cull distance x1.41,
		# and at the default 45° camera yaw those corners sit straight ahead/behind — so they
		# rendered as a big fully-hazed cream band ("fog under the player"). A disc ends at the
		# same radius in every direction, so it dissolves uniformly into the matching sky haze.
		node.visible = center.distance_squared_to(g) <= _terrain_cull * _terrain_cull


## Map the view-distance setting (0..1) to a visible terrain radius, then retune
## everything that scales with it: prop culling, the fog ramp (so the fogged edge
## still hides the terrain boundary), and the shadow distance (capped — shadows
## past the fogged range are invisible, so keeping them short is a free perf win).
func _apply_view_distance() -> void:
	# The slider sets the FLOOR for the terrain ring; the live ring (in _refresh_view_extent,
	# every frame) also grows to cover the camera's actual ground footprint when zoomed out or
	# tilted, so the loaded edge is never visible as a bare band under the player.
	_view_ring_floor = int(round(lerpf(float(TERRAIN_RING_MIN), float(TERRAIN_RING_MAX),
		clampf(GameSettings.view_distance, 0.0, 1.0))))
	_refresh_view_extent()


## Per-frame: size the loaded terrain to COVER the camera's real ground footprint (zoom + tilt
## aware), never below the slider floor and capped for perf. Then retune everything that scales
## with the resulting radius (prop cull, the atmospheric fog ramp, shadow distance). This is the
## "loaded distance = camera view + margin" rule: zooming out grows the loaded disc to match, so
## you never see the bare loaded edge under the player.
func _refresh_view_extent() -> void:
	terrain_ring = clampi(maxi(_view_ring_floor, _required_terrain_ring()),
		TERRAIN_RING_MIN, TERRAIN_RING_HARD_MAX)
	var vt := float(terrain_ring * WG.CHUNK_TILES)
	_terrain_cull = vt
	_prop_cull = vt - 4.0
	if _env != null:
		# Long, gradual distance haze (atmospheric depth, not a hard beige band): crisp around
		# the player, fully dissolved into the matching sky by the terrain's visible edge.
		_env.fog_depth_end = vt
		_env.fog_depth_begin = maxf(vt * 0.5, CAM_DIST + 12.0)
	if _water_mat != null:
		_water_mat.set_shader_parameter("detail_fade_begin", vt - 20.0)
		_water_mat.set_shader_parameter("detail_fade_end", vt - 2.0)
	if _sun != null:
		_sun.directional_shadow_max_distance = clampf(vt * 0.85, 30.0, 60.0)


## The terrain ring (in chunks) needed to cover what the camera actually sees: project the four
## viewport corners onto the ground plane and take the farthest from the player. Grows with
## zoom-out and low tilt; quantised to chunks (which also damps frame-to-frame jitter).
func _required_terrain_ring() -> int:
	if cam == null or sub == null or sub.size.y <= 0:
		return _view_ring_floor
	var vp := Vector2(sub.size)
	var pg := _world_to_grid(world.player.position)
	var py := height_at(world.player.position)
	var max_d2 := 0.0
	for c: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0.0), Vector2(0.0, vp.y), vp]:
		var o := cam.project_ray_origin(c)
		var n := cam.project_ray_normal(c)
		if absf(n.y) < 0.0001:
			continue
		var t := (py - o.y) / n.y
		if t < 0.0:
			continue
		var hit := o + n * t
		var g := Vector2(hit.x / TILE_S, hit.z / TILE_S)
		max_d2 = maxf(max_d2, g.distance_squared_to(pg))
	return ceili(sqrt(max_d2) / float(WG.CHUNK_TILES)) + 1


# Water basin model. The surface rides the LOCAL sea-level rolling baseline minus
# WATER_SINK, so it follows the meadow swells and is always WATER_SINK below the dry
# shore (no flat sheet floating on a pedestal). The lakebed dips further: a shallow
# clearance at the shore ramping to the full interior drop in open water.
const WATER_SINK := 0.16        # surface below the local dry-land baseline
const WATER_SHORE_DEPTH := 0.12 # lakebed clearance just under the surface at the shore
const WATER_DEEP_DROP := 0.62   # extra interior lakebed depth (deep_water) below the surface
const SHORE := Color(0.80, 0.75, 0.58)  # sandy shore tone under/at water edges
# Tile categories + terrain colour live in scripts/render/terrain_style.gd (TerrainStyle).

## Smooth, continuous, SEAMLESS terrain: each grid corner's height/normal/color
## is averaged from the tiles around it (sampled globally so chunk borders match),
## giving rolling sculpted land instead of flat terraced diamonds. Water tiles dip
## the floor into a basin and get a separate animated water surface on top.
func _build_chunk_terrain(chunk: RefCounted) -> Node3D:
	var n := WG.CHUNK_TILES
	var cx0: int = int(chunk.cx) * n
	var cy0: int = int(chunk.cy) * n
	var wfc := {}  # memoized corner water-fraction (the ONE shared coastline field)
	var wlc := {}  # memoized corner water-surface level (watertight, calm sheet)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false
	for ty: int in n:
		for tx: int in n:
			var gtx := cx0 + tx
			var gty := cy0 + ty
			var info := _tile_info(gtx, gty)
			# Plateau the tile sits on: gameplay floor (terraced, noise-free). Each corner is
			# emitted on THIS plateau so cliffs stay vertical (see _corner_height_for).
			var ref_top := float(info["top"]) if not info.is_empty() else 0.0
			# Four shared corners (continuous across cells -> one smooth surface). Steep
			# terrace risers come through as steep smooth slopes (no axis-aligned vertical
			# faces, which would staircase into sawtooth teeth along diagonal contours).
			_emit_corner(st, gtx, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty + 1, ref_top, wfc, wlc)
			_emit_corner(st, gtx, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty + 1, ref_top, wfc, wlc)
			_emit_corner(st, gtx, gty + 1, ref_top, wfc, wlc)
			# The water sheet covers the water bodies + a small coastal margin and is FINELY
			# TESSELLATED. Each sub-vertex bakes the smoothed coast field (UV.x), sampled
			# BICUBICALLY, so the shader's 0.5 contour (the shoreline) is a smooth curve at
			# sub-tile resolution — decoupled from the coarse terrain mesh, so the coast can
			# never staircase into per-tile teeth.
			if _water_plane_tile(gtx, gty):
				has_water = true
				_emit_water_tile(wst, gtx, gty, wfc, wlc)
	var root := Node3D.new()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	if has_water:
		var water := MeshInstance3D.new()
		water.mesh = wst.commit()
		water.material_override = _water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
	return root


# A tile the continuous water plane covers: any water tile, or dry land within a few
# tiles of water (the coastal margin the sheet dips into so the depth shader can carve
# the shoreline per-pixel). Cheap-gated by the per-frame water occupancy cache.
const WATER_PLANE_MARGIN := 3
func _water_plane_tile(gtx: int, gty: int) -> bool:
	for dy: int in range(-WATER_PLANE_MARGIN, WATER_PLANE_MARGIN + 1):
		for dx: int in range(-WATER_PLANE_MARGIN, WATER_PLANE_MARGIN + 1):
			if _coast_water(gtx + dx, gty + dy):
				return true
	return false



func _emit_corner(st: SurfaceTool, ci: int, cj: int, ref_top: float, wfc: Dictionary, wlc: Dictionary) -> void:
	var h := _corner_height_for(ci, cj, ref_top)
	# Smooth normal from the height field (central differences over the corners). Sampled on
	# THIS tile's plateau (ref_top) so a corner at a cliff lip stays flat-shaded on top rather
	# than tilting toward the drop.
	var hx := _corner_height_for(ci + 1, cj, ref_top) - _corner_height_for(ci - 1, cj, ref_top)
	var hz := _corner_height_for(ci, cj + 1, ref_top) - _corner_height_for(ci, cj - 1, ref_top)
	# If this ground corner sits UNDER the water sheet, push it safely below the sheet so a
	# terrain facet can never poke through and clip the shader's smooth waterline contour.
	if _corner_touches_water(ci, cj):
		h = minf(h, _water_corner_level(ci, cj, wlc) - WATER_BED_CLEARANCE)
	st.set_normal(Vector3(-hx, 2.0 * TILE_S, -hz).normalized())
	st.set_color(_corner_color(ci, cj))
	# UV carries beach data for toon_ground: y = beach fraction (sand vs other, smoothed
	# over the corner so the sand/grass edge can be dithered), x = wetness from the shared
	# coast field (sand darkens/saturates near the waterline).
	var beach := _corner_beach(ci, cj)
	var wet: float = clampf((_coast_wf(ci, cj, wfc) - 0.30) / 0.16, 0.0, 1.0) if beach > 0.0 else 0.0
	st.set_uv(Vector2(wet, beach))
	st.set_uv2(Vector2(_corner_snow(ci, cj), 0.0))
	st.add_vertex(Vector3(float(ci) * TILE_S, h, float(cj) * TILE_S))


# Beach fraction at a grid corner: how many of the 4 touching tiles are sand (0..1). A
# fractional value near the biome edge lets the shader dither the sand/grass boundary.
func _corner_beach(ci: int, cj: int) -> float:
	var ck := Vector2i(ci, cj)
	if _cb_cache.has(ck):
		return _cb_cache[ck]
	var cnt := 0
	var sand := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if info.is_empty():
			continue
		cnt += 1
		if str(info["tile"]) in ["sand", "sand_dune"]:
			sand += 1
	var b: float = float(sand) / float(cnt) if cnt > 0 else 0.0
	_cb_cache[ck] = b
	return b


# Snow fraction at a shared corner, used by the toon shader to swap the mossy grass
# lighting ramp for slate/periwinkle alpine lighting without a hard tile seam.
func _corner_snow(ci: int, cj: int) -> float:
	var cnt := 0
	var frozen := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if info.is_empty():
			continue
		cnt += 1
		if str(info["tile"]) in TerrainStyle.SNOW_TILES:
			frozen += 1
	return float(frozen) / float(cnt) if cnt > 0 else 0.0


## Smooth visual corner height: average of the up-to-4 tiles touching the grid corner.
## ref_top is unused now (kept in the signature so terrace/mover/prop callers share one
## entry point). Continuous across cells, so terrace risers render as steep smooth slopes
## rather than vertical faces that would staircase into sawtooth along diagonal contours.
func _corner_height_for(ci: int, cj: int, _ref_top: float) -> float:
	var ck := Vector2i(ci, cj)
	if _ccl_cache.has(ck):
		return _ccl_cache[ck]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			sum += _visual_floor_height(ci + off.x, cj + off.y, info)
			cnt += 1
	var h: float = sum / float(cnt) if cnt > 0 else 0.0
	_ccl_cache[ck] = h
	return h


func _corner_color(ci: int, cj: int) -> Color:
	var ck := Vector2i(ci, cj)
	if _cc_cache.has(ck):
		return _cc_cache[ck]
	var col := _corner_color_compute(ci, cj)
	_cc_cache[ck] = col
	return col


func _corner_color_compute(ci: int, cj: int) -> Color:
	var infos := []
	var families := {}
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			infos.append(info)
			var family := _surface_family(str(info["tile"]))
			families[family] = int(families.get(family, 0)) + 1
	if infos.is_empty():
		return PixelPalette.pal("grass_a")
	var family := ""
	var best := 0
	for f: String in families:
		if int(families[f]) > best:
			best = int(families[f])
			family = f
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var cnt := 0
	for info: Dictionary in infos:
		if best < 3 or _surface_family(str(info["tile"])) == family:
			var c: Color = info["col"]
			r += c.r
			g += c.g
			b += c.b
			cnt += 1
	return Color(r / float(cnt), g / float(cnt), b / float(cnt))


## Per-global-tile info {top, water, tile, col}, or {} if the chunk isn't loaded.
## Memoised for the frame: the terrain build + every mover's height sample hit the
## same tiles thousands of times, and grading the colour (_grade_ground) is not free.
func _tile_info(gtx: int, gty: int) -> Dictionary:
	var cache_key := Vector2i(gtx, gty)
	if _ti_cache.has(cache_key):
		return _ti_cache[cache_key]
	var info := _tile_info_compute(gtx, gty)
	_ti_cache[cache_key] = info
	return info


func _tile_info_compute(gtx: int, gty: int) -> Dictionary:
	var ck := WG.tile_to_chunk(Vector2i(gtx, gty))
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk == null:
		return {}
	var lx: int = gtx - ck.x * WG.CHUNK_TILES
	var ly: int = gty - ck.y * WG.CHUNK_TILES
	var tid: int = chunk.tile_id(lx, ly)
	var tdef: Dictionary = WorldGen.reg.tile_def(tid)
	var tile_name := str(WorldGen.reg.tile_order[tid])
	var biome_idx: int = chunk.parent_biome_at(lx, ly)
	var biome_id := "" if biome_idx == 255 or biome_idx >= WorldGen.reg.biomes.size() else str(WorldGen.reg.biomes[biome_idx]["id"])
	var water := bool(tdef.get("water", false))
	var elev: int = chunk.elev[ly * WG.CHUNK_TILES + lx]
	var top: float = float(elev) * ELEV_H
	var slope: int = _tile_slope_steps(gtx, gty, elev) if (not water and elev > 0) else 0
	var curve: int = _tile_curvature_steps(gtx, gty, elev) if (not water and elev > 0) else 0
	var col: Color = SHORE if water else TerrainStyle.grade(tdef["colors"][0], tile_name, gtx, gty, elev, slope, curve)
	return {
		"top": top,
		"water": water,
		"tile": tile_name,
		"biome": biome_id,
		"col": col,
	}


func _visual_floor_height(gtx: int, gty: int, info: Dictionary) -> float:
	# Per-frame memo: each tile's floor height is sampled ~4x per chunk build (once per
	# touching corner) plus by mover height queries — all with the same deterministic result.
	var fk := Vector2i(gtx, gty)
	if _vfh_cache.has(fk):
		return _vfh_cache[fk]
	var top := float(info["top"])
	var tile := str(info["tile"])
	var h: float
	if bool(info["water"]):
		# Lakebed rides the SAME sea-level rolling baseline as the water surface, dipped
		# below it: a shallow clearance at the rim ramping to a deeper bed under open
		# water, keyed off the tile depth (shallow -> water -> deep_water). Parallel to
		# the surface, so narrow rivers and broad lakes both nestle without a flat floor.
		var depth := WATER_SHORE_DEPTH
		if tile == "water":
			depth += WATER_DEEP_DROP * 0.45
		elif tile == "deep_water":
			depth += WATER_DEEP_DROP
		h = _rolling_hill(gtx, gty) - WATER_SINK - depth
	elif top > 0.0:
		# Elevation is authoritative for the mountain surface. Biome/structure passes
		# can leave gravel, snow, or another gameplay tile on a raised cell; all of
		# them must share the same smoothed geometry or visible seams reappear.
		h = _smoothed_elevation_height(gtx, gty) + _rolling_hill(gtx, gty) * 0.42 + _rocky_lift(gtx, gty) * 0.35
	elif _is_path(tile):
		h = top + _rolling_hill(gtx, gty) * 0.28 - 0.055
	elif _is_rock(tile):
		h = _smoothed_elevation_height(gtx, gty) + _rolling_hill(gtx, gty) * 0.42 + _rocky_lift(gtx, gty) * 0.35
	else:
		h = top + _rolling_hill(gtx, gty)
	_vfh_cache[fk] = h
	return h


func _smoothed_elevation_height(gtx: int, gty: int) -> float:
	var sum := float(_elev_raw(gtx, gty)) * 4.0
	var weight := 4.0
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		sum += float(_elev_raw(gtx + off.x, gty + off.y)) * 2.0
		weight += 2.0
	for off: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		sum += float(_elev_raw(gtx + off.x, gty + off.y))
		weight += 1.0
	return sum / weight * ELEV_H


# Water-surface level at a grid CORNER. The sheet rides the LOCAL sea-level rolling
# baseline (water is always elev 0) minus WATER_SINK. We average ONLY the WATER tiles
# touching the corner, so high land on the shore never lifts the sheet up its flank — a
# mountain tarn stays at the bottom of its basin. Memoised over shared corners (wlc) so
# neighbouring water tiles agree exactly: the surface is watertight and calm.
func _water_corner_level(ci: int, cj: int, wlc: Dictionary) -> float:
	var key := Vector2i(ci, cj)
	if wlc.has(key):
		return wlc[key]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty() and bool(info["water"]):
			sum += _rolling_hill(ci + off.x, cj + off.y)
			cnt += 1
	var base: float = sum / float(cnt) if cnt > 0 else _rolling_hill(ci, cj)
	var lvl := base - WATER_SINK
	wlc[key] = lvl
	return lvl


# Water-surface height at a tile CENTRE (for movers/decor/fish that ride the sheet).
# Matches the mesh: the sheet rides the sea-level rolling baseline minus WATER_SINK.
func _water_surface_at(gtx: int, gty: int) -> float:
	return _rolling_hill(gtx, gty) - WATER_SINK


# True if any of the four tiles touching this grid corner is water (cheap occupancy read).
func _corner_touches_water(ci: int, cj: int) -> bool:
	return _coast_water(ci - 1, cj - 1) or _coast_water(ci, cj - 1) \
		or _coast_water(ci - 1, cj) or _coast_water(ci, cj)


# Emit ONE water tile as a finely tessellated patch. Each sub-vertex bakes the smoothed
# coast field (UV.x) sampled BICUBICALLY, so the shader's 0.5 contour is smooth at sub-tile
# resolution. Heights bilerp the four watertight corner levels (the sheet is near-flat).
const WATER_SUBDIV := 5            # sub-quads per tile edge (25 quads / tile near the coast)
const WATER_BED_CLEARANCE := 0.07  # how far submerged ground sits below the sheet
func _emit_water_tile(wst: SurfaceTool, gtx: int, gty: int, wfc: Dictionary, wlc: Dictionary) -> void:
	var lA := _water_corner_level(gtx, gty, wlc)
	var lB := _water_corner_level(gtx + 1, gty, wlc)
	var lC := _water_corner_level(gtx + 1, gty + 1, wlc)
	var lD := _water_corner_level(gtx, gty + 1, wlc)
	# Only the COASTAL RING needs tessellation (that's where the 0.5 contour lives). Open
	# deep water (every corner well offshore) and far-inland margin (every corner on land)
	# are flat in wf — emit them as a cheap 2-tri quad so the subdivision cost stays tiny.
	var c00 := _coast_wf(gtx, gty, wfc)
	var c10 := _coast_wf(gtx + 1, gty, wfc)
	var c11 := _coast_wf(gtx + 1, gty + 1, wfc)
	var c01 := _coast_wf(gtx, gty + 1, wfc)
	var lo: float = minf(minf(c00, c10), minf(c11, c01))
	var hi: float = maxf(maxf(c00, c10), maxf(c11, c01))
	if lo >= 0.9 or hi <= 0.12:
		var x0 := float(gtx) * TILE_S
		var z0 := float(gty) * TILE_S
		var x1 := x0 + TILE_S
		var z1 := z0 + TILE_S
		var qa := [[Vector3(x0, lA, z0), c00], [Vector3(x1, lB, z0), c10], [Vector3(x1, lC, z1), c11],
			[Vector3(x0, lA, z0), c00], [Vector3(x1, lC, z1), c11], [Vector3(x0, lD, z1), c01]]
		for v: Array in qa:
			wst.set_normal(Vector3.UP)
			wst.set_uv(Vector2(float(v[1]), 0.0))
			wst.add_vertex(v[0])
		return
	var s := WATER_SUBDIV
	var pos := []        # (s+1)x(s+1) sub-vertex positions
	var wfv := []        # matching bicubic water-fraction
	for j: int in range(s + 1):
		var fz := float(j) / float(s)
		var prow := []
		var wrow := []
		for i: int in range(s + 1):
			var fx := float(i) / float(s)
			var hy := lerpf(lerpf(lA, lB, fx), lerpf(lD, lC, fx), fz)
			var wx := float(gtx) + fx
			var wz := float(gty) + fz
			prow.append(Vector3(wx * TILE_S, hy, wz * TILE_S))
			wrow.append(_wf_cubic(wx, wz, wfc))
		pos.append(prow)
		wfv.append(wrow)
	for j: int in range(s):
		for i: int in range(s):
			var quad := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1),
				Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for c: Vector2i in quad:
				wst.set_normal(Vector3.UP)
				wst.set_uv(Vector2(float(wfv[c.y][c.x]), 0.0))
				wst.add_vertex(pos[c.y][c.x])


# Catmull-Rom cubic through p1,p2 (p0,p3 are the outer tangents), t in [0,1].
func _cubic1(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))


# Bicubic sample of the smoothed coast field at a fractional world position. Built on the
# memoised integer-corner _coast_wf grid, so it's smooth (C1) and exact at integer corners
# (no cracks between neighbouring water tiles). This is what makes the coastline curve.
func _wf_cubic(fx: float, fz: float, wfc: Dictionary) -> float:
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var rows := []
	for dz: int in range(-1, 3):
		rows.append(_cubic1(
			_coast_wf(x0 - 1, z0 + dz, wfc), _coast_wf(x0, z0 + dz, wfc),
			_coast_wf(x0 + 1, z0 + dz, wfc), _coast_wf(x0 + 2, z0 + dz, wfc), tx))
	return clampf(_cubic1(rows[0], rows[1], rows[2], rows[3], tz), 0.0, 1.0)


## Gentle rolling-hill undulation laid over ALL land (an "A Short Hike / Swiss
## meadow" swell). Long wavelengths + low slope so it's pretty and always walkable —
## it's visual only (the 2D walk grid ignores it), so it never blocks movement; it
## just lifts the ground the player/props/enemies stand on into soft rolling hills.
func _rolling_hill(gtx: int, gty: int) -> float:
	var x := float(gtx)
	var y := float(gty)
	# Layered swells (periods ~30-90 tiles) give real, light-catching rolling hills:
	# enough relief that the toon shading paints lit/shaded flanks, but long enough
	# wavelengths that the slopes stay gentle and natural — never bumpy. Visual only,
	# so however tall it rolls it never blocks walking.
	var broad := sin(x * 0.072 + 0.7) * cos(y * 0.063 - 1.2)
	var roll := sin((x * 0.7 + y * 0.7) * 0.085 + 1.8)
	var mid := sin(x * 0.155 - 0.4) * cos(y * 0.138 + 0.9)
	var fine := sin((x - y) * 0.21 + 2.3)
	return broad * 0.52 + roll * 0.28 + mid * 0.2 + fine * 0.09


func _rocky_lift(gtx: int, gty: int) -> float:
	var chip := sin(float(gtx) * 0.91 + float(gty) * 0.37)
	return maxf(chip, 0.0) * 0.08


# Tile classification + terrain colour live in TerrainStyle (one swappable art module);
# these thin wrappers keep the render-side call sites unchanged.
func _surface_family(tile: String) -> String:
	return TerrainStyle.surface_family(tile)


func _is_path(tile: String) -> bool:
	return TerrainStyle.is_path(tile)


func _is_rock(tile: String) -> bool:
	return TerrainStyle.is_rock(tile)


func _is_snow(tile: String) -> bool:
	return TerrainStyle.is_snow(tile)


## Raw baked elevation step at a global tile (0 if the chunk/apron isn't loaded). Cheap
## array read — used for slope (no noise re-eval).
func _elev_raw(gtx: int, gty: int) -> int:
	var ck := WG.tile_to_chunk(Vector2i(gtx, gty))
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk == null or chunk.elev.size() == 0:
		return 0
	var lx: int = gtx - ck.x * WG.CHUNK_TILES
	var ly: int = gty - ck.y * WG.CHUNK_TILES
	return chunk.elev[ly * WG.CHUNK_TILES + lx]


## Local terrain steepness in elevation steps: the largest drop to a 4-neighbour. Flat
## shelves read ~0-1; steep cliff risers read high. Drives slope-aware materials/snow.
func _tile_slope_steps(gtx: int, gty: int, e: int) -> int:
	var m := 0
	m = maxi(m, absi(_elev_raw(gtx + 1, gty) - e))
	m = maxi(m, absi(_elev_raw(gtx - 1, gty) - e))
	m = maxi(m, absi(_elev_raw(gtx, gty + 1) - e))
	m = maxi(m, absi(_elev_raw(gtx, gty - 1) - e))
	return m


## Signed local curvature: positive on convex shelf lips/crests, negative in bowls.
## This breaks material regions away from simple elevation rings.
func _tile_curvature_steps(gtx: int, gty: int, e: int) -> int:
	var neighbours := _elev_raw(gtx + 1, gty) + _elev_raw(gtx - 1, gty) \
		+ _elev_raw(gtx, gty + 1) + _elev_raw(gtx, gty - 1)
	return e * 4 - neighbours


# Build one seamless tiling noise texture for the water shader. `freq_mul` scales the
# feature size, `oct` the fractal detail, `seed` decorrelates the layers. Generated once
# at setup; seamless+normalized so it tiles across the whole world without visible seams.
func _make_water_noise(freq_mul: float, oct: int, seed: int) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.seed = seed
	fnl.frequency = 0.012 * freq_mul
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = oct
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.normalize = true
	tex.noise = fnl
	return tex


# Water occupancy for the coastline field — read straight from the LOADED chunk tile (the
# same source the water mesh uses), NOT the classifier. surface_tile_def_at() re-runs the
# biome-noise eval per tile and was the single biggest chunk-build cost (tens of ms on a
# fresh region); the loaded tile id is a cheap array read and, thanks to the apron index,
# is available for the chunk + its margin. Tiles outside the loaded data read as land.
# Cached per session (a loaded tile's water-ness is deterministic).
func _coast_water(gtx: int, gty: int) -> bool:
	var key := Vector2i(gtx, gty)
	if _occ_cache.has(key):   # per-frame cache (cleared each frame) -> never stale across load/layer
		return _occ_cache[key]
	var w := false
	var ck := WG.tile_to_chunk(key)
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk != null:
		var lx: int = gtx - ck.x * WG.CHUNK_TILES
		var ly: int = gty - ck.y * WG.CHUNK_TILES
		w = bool(WorldGen.reg.tile_def(chunk.tile_id(lx, ly)).get("water", false))
	_occ_cache[key] = w
	return w


# Low-passed water fraction (0 land .. 1 open water) at a grid CORNER. A DISTANCE-WEIGHTED
# (triangular) kernel over a radius-3 neighbourhood: this is THE one authoritative coastline
# field. The weighting (centre tiles count most) gives a smooth, rounded 0.5 iso-line — broad
# stylized bends instead of tile staircases — while keeping the contour within ~half a cell
# of the true boundary (so bays/peninsulas are preserved). Both the water mesh and the shore
# overlay read this same field, so their layers can never disagree. Memoized over shared
# corners so neighbouring tiles agree exactly (no cracks).
const SHORE_SMOOTH := 4
const SHORE_RADIUS := 4.0       # kernel reach in cells (round, Euclidean — NOT square)
const SHORE_SD_SCALE := 5.2     # maps (wf - 0.5) -> signed distance to coast, in cells
func _coast_wf(ci: int, cj: int, wfc: Dictionary) -> float:
	var key := Vector2i(ci, cj)
	if wfc.has(key):
		return wfc[key]
	var sum := 0.0
	var wsum := 0.0
	for dy: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
		for dx: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
			# Tile (ci+dx, cj+dy) sits with its centre 0.5 off the corner. Weight by a
			# ROUND (Euclidean) smooth falloff: a square/Chebyshev kernel makes the 0.5
			# iso-line diamond-shaped, which reads as an angular sawtooth coast. The radial
			# bump rounds the contour so bays and headlands curve smoothly.
			var rx := float(dx) + 0.5
			var ry := float(dy) + 0.5
			var d := sqrt(rx * rx + ry * ry)
			var w := smoothstep(SHORE_RADIUS, 0.0, d)   # 1 at centre -> 0 at the reach
			if w <= 0.0:
				continue
			if _coast_water(ci + dx, cj + dy):
				sum += w
			wsum += w
	var wf: float = sum / wsum if wsum > 0.0 else 0.0
	wfc[key] = wf
	return wf


## A vertical riser quad from the top edge (p0->p1 at height top_y) down to bot_y.
func _riser(st: SurfaceTool, p0: Vector3, p1: Vector3, bot_y: float, normal: Vector3, col: Color) -> void:
	var a := p0
	var b := p1
	var c := Vector3(p1.x, bot_y, p1.z)
	var d := Vector3(p0.x, bot_y, p0.z)
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(normal)
		st.add_vertex(v)


## White contour outlines for entities flagged highlight_outline (Alt-hold) or hovered.
## Enemies (movers) get a material_overlay on their rig; static interactables get a parts-
## built inverted-hull node. Both trace the silhouette with a thin white stroke. Pooled by
## entity id and rebuilt only when the highlighted set changes.
func _sync_outlines() -> void:
	var want := {}
	for e: Node2D in world.entities:
		if is_instance_valid(e) and (e.highlight_outline or e.hovered):
			want[e.get_instance_id()] = e
	for id: int in _outline_nodes.keys():
		if not want.has(id):
			_outline_nodes[id].queue_free()
			_outline_nodes.erase(id)
	for id: int in _outlined_movers.keys():
		if not want.has(id):
			var rig: Node3D = _mover_nodes.get(id)
			if rig != null:
				_set_rig_outline(rig, false)
			_outlined_movers.erase(id)
	for id: int in want:
		var e: Node2D = want[id]
		if PropMeshes.is_moving(e):
			var rig: Node3D = _mover_nodes.get(id)
			if rig != null and not _outlined_movers.has(id):
				_set_rig_outline(rig, true)
				_outlined_movers[id] = true
		else:
			var node: Node3D = _outline_nodes.get(id)
			if node == null:
				node = _build_outline_node(e)
				if node == null:
					continue
				_outlines_root.add_child(node)
				_outline_nodes[id] = node
			node.transform = Transform3D(Basis.IDENTITY, iso_to_3d(e.position, height_at(e.position)))


func _build_outline_node(e: Node2D) -> Node3D:
	var parts: Array = PropMeshes.entity_parts(e)
	if parts.is_empty():
		return null
	var node := Node3D.new()
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = _outline_mat
		mi.transform = Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node


func _set_rig_outline(rig: Node3D, on: bool) -> void:
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_overlay = _outline_mat if on else null
		for c: Node in n.get_children():
			stack.append(c)


## Movers (player + enemies) stay individual nodes — few of them, and they move.
func _sync_movers() -> void:
	var dt := get_process_delta_time()
	var t := Time.get_ticks_msec() / 1000.0
	if editor_hide_player:
		if _player_node != null:
			_player_node.visible = false
			var psh: Node3D = _shadow_nodes.get("player")
			if psh != null:
				psh.visible = false
	else:
		if _player_node == null:
			_player_node = PropMeshes.player_rig(PixelPalette.pal("skin_a"))
			_prep_mover(_player_node, "player")
			_apply_player_equipment()
			EventBus.equipment_changed.connect(_apply_player_equipment)
		_animate_mover(_player_node, "player", world.player.position, t, dt)
	var live := {}
	for e: Node in world.entities:
		if not is_instance_valid(e) or not PropMeshes.is_moving(e):
			continue
		var id := e.get_instance_id()
		live[id] = true
		var n: Node3D = _mover_nodes.get(id)
		if n == null:
			n = PropMeshes.enemy_rig(e)
			_prep_mover(n, str(id))
			_mover_nodes[id] = n
		# A defeated enemy (dimmed) plays its death topple instead of the normal gait.
		_animate_mover(n, str(id), e.position, t, dt, bool(e.get("dimmed")))
	for id: int in _mover_nodes.keys():
		if not live.has(id):
			var n: Node = _mover_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			_mover_nodes.erase(id)
			_mover_prev.erase(id); _mover_yaw.erase(id); _mover_yaw_vel.erase(id); _mover_walk.erase(id)
			_mover_death.erase(str(id)); _hurt_t.erase(str(id))
			_free_shadow(str(id))


## Add a mover rig to the scene, drop a blob shadow under it, and turn off its
## real cast shadow (the blob replaces it for the clean A Short Hike look).
func _prep_mover(node: Node3D, key: String) -> void:
	props_root.add_child(node)
	_disable_cast_shadows(node)
	# Measure the rig's true head height ONCE here, in its built rest pose (before any gait
	# animation), so floating HP bars sit a consistent distance above every body.
	node.set_meta("rig_top_y", _rig_top_y(node))
	var shadow := PropMeshes.blob_shadow()
	props_root.add_child(shadow)
	_shadow_nodes[key] = shadow


## (Re)build the player's visible gear from GameState.equipment — on spawn and
## whenever equipment changes.
func _apply_player_equipment(_a := "", _b := "") -> void:
	if _player_node == null:
		return
	var loadout := EquipLoadout.for_player(GameState.equipment)
	PropMeshes.apply_equipment(_player_node, loadout)
	# Grip a planted staff when one is wielded (else stand normally).
	var mainhand: Dictionary = loadout.get("mainhand", {})
	_player_node.set_meta("pose", "staff" if str(mainhand.get("kind", "")) in ["staff", "raven_staff", "wand"] else "")
	_disable_cast_shadows(_player_node)


func _disable_cast_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c: Node in node.get_children():
		_disable_cast_shadows(c)


func _free_shadow(key: String) -> void:
	var s: Node = _shadow_nodes.get(key)
	if is_instance_valid(s):
		s.queue_free()
	_shadow_nodes.erase(key)


## A Short Hike-style walk feel: gentle bob + squash-stretch while moving, body
## turns to face travel. The pose itself is per body template (humanoid stride,
## quadruped trot, bird waddle) so a cow walks like an animal and a chicken like
## a bird — read from the rig's "body3d" meta.
func _animate_mover(node: Node3D, key: String, pos2d: Vector2, t: float, dt: float, dying := false) -> void:
	var pos3 := iso_to_3d(pos2d, height_at(pos2d))
	var btype0 := str(node.get_meta("body3d", "humanoid"))
	# A defeated enemy topples and settles where it fell (its own death per body type),
	# then holds until it respawns; skip the normal gait + the drift-home slide.
	if dying:
		_death_anim(node, key, pos3, t, float(node.get_meta("base_scale", 1.0)), btype0)
		return
	if _mover_death.has(key):
		_mover_death.erase(key)            # respawned — clear so it stands back up
		_mover_prev[key] = pos3            # don't read the death->home jump as a walk
	var prev: Vector3 = _mover_prev.get(key, pos3)
	var vel := pos3 - prev
	_mover_prev[key] = pos3
	var speed := vel.length() / maxf(dt, 0.0001)
	var target_walk := clampf(speed / 3.0, 0.0, 1.0)
	var walk: float = lerpf(float(_mover_walk.get(key, 0.0)), target_walk, clampf(dt * 10.0, 0.0, 1.0))
	_mover_walk[key] = walk
	# Desired heading: face where you're moving; in a fight the foe's bearing wins —
	# an enemy keeps facing you, while the PLAYER only squares up to the foe when
	# standing its ground, so walking/running away turns it to its travel direction.
	# The turn itself is driven by a spring (angular accel + damping) so every body
	# rotates with real inertia and is always animated turning — never an instant snap.
	var yaw: float = float(_mover_yaw.get(key, 0.0))
	var moving := speed > 0.35
	var desired := yaw
	var want := false
	if moving:
		desired = atan2(vel.x, vel.z)
		want = true
	var face: Variant = _combat_face_pos(key, moving)
	if face != null:
		var f3 := iso_to_3d(face, 0.0)
		desired = atan2(f3.x - pos3.x, f3.z - pos3.z)
		want = true
	if want:
		var sdt := minf(dt, 0.04)                 # clamp so a frame spike can't blow up the spring
		var yvel: float = float(_mover_yaw_vel.get(key, 0.0))
		var diff := wrapf(desired - yaw, -PI, PI)
		yvel += (diff * TURN_STIFFNESS - yvel * TURN_DAMPING) * sdt
		yaw = wrapf(yaw + yvel * sdt, -PI, PI)
		_mover_yaw_vel[key] = yvel
		_mover_yaw[key] = yaw
	var phase := float(absi(hash(key)) % 1000) * 0.006283
	var base: float = float(node.get_meta("base_scale", 1.0))
	var atk := _attack_progress(key, t)
	var btype := str(node.get_meta("body3d", "humanoid"))
	match btype:
		"bird":
			MoverRig._pose_bird(node, pos3, yaw, walk, t, phase, base, atk)
		"humanoid":
			# Goblins and gnolls get their own lore-flavoured gaits; everyone else
			# (player, skeletons, generic humanoids) uses the upright human pose.
			match str(node.get_meta("gait", "")):
				"goblin":
					MoverRig._pose_goblin(node, pos3, yaw, walk, t, phase, base, atk)
				"gnoll":
					MoverRig._pose_gnoll(node, pos3, yaw, walk, t, phase, base, atk)
				_:
					MoverRig._pose_humanoid(node, pos3, yaw, walk, t, phase, base, atk)
		_:
			MoverRig._pose_quadruped(node, pos3, yaw, walk, t, phase, base, atk)
	# Resting: the player folds down to sit on the ground (right-click the run orb).
	# Eased in/out and applied over the idle pose; moving cancels it.
	var sit_target := 1.0 if (key == "player" and GameState.resting and not moving) else 0.0
	var sit: float = lerpf(float(_mover_sit.get(key, 0.0)), sit_target, clampf(dt * 7.0, 0.0, 1.0))
	_mover_sit[key] = sit
	MoverRig.pose_sit(node, sit, base)
	# A swing steps the body into the target — the lunge that sells the hit.
	if atk > 0.0:
		node.position += Vector3(sin(yaw), 0.0, cos(yaw)) * (sin(atk * PI) * 0.22)
	# Pin the blob shadow to the ground under the mover (it never bobs), oriented with
	# the body, sized to its footprint, and pushed in the direction the sunlight
	# travels so it falls down-light like a real cast shadow (sun upper-right ->
	# shadow down-left), staying consistent with the static props' real shadows.
	var shadow: Node3D = _shadow_nodes.get(key)
	if shadow != null:
		var off := _shadow_push() * base
		shadow.position = Vector3(pos3.x + off.x, pos3.y + 0.04, pos3.z + off.y)
		shadow.rotation.y = yaw
		var fp := _shadow_footprint(btype)
		shadow.scale = Vector3(fp.x * base * 1.12, 1.0, fp.y * base * 1.12)
	MoverRig._flow_cloth(node, walk, t, phase)
	MoverRig._sway_hair(node, walk, t, phase)
	_apply_hurt(node, key, t, base)


## Death topple: a defeated mover crumples where it fell and settles to the ground
## over DEATH_DUR, then holds the corpse pose until it respawns. The fall is flavoured
## per enemy type — goblins faceplant forward, gnolls topple back, four-legged beasts
## roll onto their side, birds flop over — and the blob shadow shrinks away with it.
const DEATH_DUR := 0.65
func _death_anim(node: Node3D, key: String, pos3: Vector3, t: float, base: float, btype: String) -> void:
	var d: Dictionary = _mover_death.get(key, {})
	if d.is_empty():
		d = {"t0": t, "pos": pos3}                       # freeze where it died
		_mover_death[key] = d
	var raw := clampf((t - float(d["t0"])) / DEATH_DUR, 0.0, 1.0)
	var p := ease(raw, 0.35)                              # quick drop, then settle
	var dpos: Vector3 = d["pos"]
	var yaw := float(_mover_yaw.get(key, 0.0))
	var fall := p * 1.5
	var tilt := 0.0
	var roll := 0.0
	match btype:
		"bird":
			roll = fall                                  # flops onto its side, legs up
		"humanoid":
			match str(node.get_meta("gait", "")):
				"goblin":
					tilt = fall                          # crumples forward (faceplant)
				"gnoll":
					tilt = -fall * 1.05                  # heavy backward topple
				_:
					tilt = -fall                         # falls onto its back
		_:
			roll = fall                                  # quadruped collapses sideways
	# Limbs relax out of their gait into a loose sprawl as it goes limp.
	for pv: String in ["leg_l", "leg_r", "arm_l", "arm_r"]:
		MoverRig._set_pivot(node, pv, lerpf(0.0, 0.25, p))
	var spine: Node3D = MoverRig._pivot(node, "spine")
	if spine != null:
		spine.rotation = spine.rotation.lerp(Vector3.ZERO, clampf(p, 0.0, 1.0))
	node.rotation = Vector3(tilt, yaw, roll)
	node.position = dpos + Vector3(0, 0.04 - p * 0.06 * base, 0)
	node.scale = Vector3(base, base, base)
	# The blob shadow sinks and shrinks away under the corpse.
	var shadow: Node3D = _shadow_nodes.get(key)
	if shadow != null:
		var fp := _shadow_footprint(btype)
		var ss := base * (1.0 - 0.55 * p)
		shadow.position = Vector3(dpos.x, dpos.y + 0.04, dpos.z)
		shadow.rotation.y = yaw
		shadow.scale = Vector3(fp.x * ss, 1.0, fp.y * ss)
	_apply_hurt(node, key, t, base)   # the killing blow's red flash carries into the topple


## Take-a-hit feedback: a subtle red wash (per-instance shader flash) plus a tiny
## positional shake on the struck body, decaying over HURT_DUR. Adds to whatever the
## pose set, so it layers on the walk/idle without overriding it.
func _apply_hurt(node: Node3D, key: String, t: float, base: float) -> void:
	if not _hurt_t.has(key):
		return
	var p := clampf(1.0 - (t - float(_hurt_t[key])) / HURT_DUR, 0.0, 1.0)
	if p <= 0.0:
		_set_hurt_flash(node, 0.0)   # one final clear, then stop touching it
		_hurt_t.erase(key)
		return
	_set_hurt_flash(node, p * 0.35)  # subtle: a brief light-red wash that fades out
	var sh := p * 0.03 * base        # small jitter, scaled to body size
	node.position += Vector3(sin(t * 94.0) * sh, 0.0, cos(t * 86.0) * sh)


## Push the per-instance `hurt` flash onto every toon mesh under the rig (materials
## that don't use the uniform just ignore it).
func _set_hurt_flash(node: Node, v: float) -> void:
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).set_instance_shader_parameter(&"hurt", v)
		if c.get_child_count() > 0:
			_set_hurt_flash(c, v)



## Ground-plane (x,z) offset a blob shadow is pushed, matching the direction the
## sunlight travels — so shadows fall away from the sun (down-left on screen).
func _shadow_push() -> Vector2:
	if _sun == null:
		return Vector2(0.32, 0.18)
	var travel := -_sun.global_transform.basis.z   # light shines along -Z of its basis
	var h := Vector2(travel.x, travel.z)
	if h.length() < 0.001:
		return Vector2(0.32, 0.18)
	return h.normalized() * 0.42


## Footprint (x = width, y = length-along-Z) of the blob shadow per body type.
func _shadow_footprint(btype: String) -> Vector2:
	match btype:
		"bird":
			return Vector2(0.58, 0.64)
		"humanoid":
			return Vector2(0.78, 0.86)
		_:
			return Vector2(1.05, 1.62)  # four-legged: a longer oval along the spine



const ATTACK_DUR := 0.42  # seconds one swing lunge plays over


## A hit splat means a swing just landed: lunge the attacker. on_player = the enemy
## hit us (so the enemy lunges); otherwise the player's swing landed.
func _on_combat_swing(_amount: int, miss: bool, on_player: bool) -> void:
	var tgt: Node = world.combat_target_entity
	if on_player:
		# The enemy swung at the player: enemy lunges, and the PLAYER took the hit.
		if is_instance_valid(tgt):
			_mark_attack(str(tgt.get_instance_id()))
		if not miss:
			_mark_hurt("player")
	else:
		# The player swung at the enemy: player lunges, the ENEMY took the hit.
		_mark_attack("player")
		if not miss and is_instance_valid(tgt):
			_mark_hurt(str(tgt.get_instance_id()))


func _mark_attack(key: String) -> void:
	_attack_t[key] = Time.get_ticks_msec() / 1000.0


## Flag a body as just-hit so it flashes red and shakes for HURT_DUR (the model that
## TOOK the damage — the player on an enemy hit, the enemy on a player hit).
func _mark_hurt(key: String) -> void:
	_hurt_t[key] = Time.get_ticks_msec() / 1000.0


func _attack_progress(key: String, t: float) -> float:
	var p := (t - float(_attack_t.get(key, -99.0))) / ATTACK_DUR
	return p if p >= 0.0 and p <= 1.0 else 0.0


## The iso position a mover should face mid-fight, or null when not in combat:
## the player faces its target, the target faces the player.
func _combat_face_pos(key: String, moving: bool) -> Variant:
	if not CombatSim.active:
		return null
	var tgt: Node = world.combat_target_entity
	if not is_instance_valid(tgt):
		return null
	if key == "player":
		# Square up to the foe only while holding position — if we're walking/running
		# (away or anywhere) face the travel direction instead of the enemy.
		return null if moving else tgt.position
	if key == str(tgt.get_instance_id()):
		return world.player.position
	return null


## Batch all static decor + props into per-(mesh,material) MultiMeshes, merged across the
## whole visible set (draw calls stay minimal — important for low-end GPUs). The rebuild is
## TIME-SLICED across frames (see RB_* state) so no single frame does the full O(all props)
## work; the old batch stays visible until the new one is fully built, then swaps in.
func _sync_static_batches() -> void:
	if not _rb_active:
		var sig := "%s:%d:%d:%d" % [str(world.current_layer), int(world._decor_nodes.size()), int(world._water_decor_nodes.size()), int(world.entities.size())]
		if sig == _static_sig:
			return
		var now := Time.get_ticks_msec() / 1000.0
		if now - _batch_rebuild_t < BATCH_REBUILD_MIN:
			return                              # throttle: let a streaming burst settle
		_batch_rebuild_t = now
		_start_staged_rebuild(sig)
	if _terrain_built:
		return                                  # stagger: don't run a slice on a chunk-build frame
	_advance_staged_rebuild()


## Snapshot the current static-prop set for a fresh staged rebuild.
func _start_staged_rebuild(sig: String) -> void:
	_rb_active = true
	_rb_phase = 0
	_rb_i = 0
	_rb_groups = {}
	_rb_xf = {}
	_rb_sig = sig
	_rb_list = []
	for d: Node in world._decor_nodes:
		_rb_list.append([0, d])
	for d: Node in world._water_decor_nodes:
		_rb_list.append([1, d])
	for e: Node in world.entities:
		if is_instance_valid(e) and not PropMeshes.is_moving(e):
			_rb_list.append([2, e])


func _advance_staged_rebuild() -> void:
	if _rb_phase == 0:
		# Collect a slice of props into groups. Cached transforms (the costly per-prop terrain
		# height sample) are reused for props that persisted from the last build.
		var processed := 0
		while _rb_i < _rb_list.size() and processed < RB_COLLECT_PER_FRAME:
			var item: Array = _rb_list[_rb_i]
			_rb_i += 1
			processed += 1
			var kind: int = item[0]
			var d = item[1]   # UNTYPED: nodes can be freed between snapshot and processing
			                  # (chunk unloads mid-build); a typed assign would error pre-guard.
			if not is_instance_valid(d):
				continue
			var id: int = d.get_instance_id()
			var pl: Transform3D = _batch_xf.get(id, _IDENTITY_XF)
			if kind == 0:
				if pl == _IDENTITY_XF:
					pl = Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.131), iso_to_3d(d.position, height_at(d.position)))
				_rb_xf[id] = pl
				_collect(PropMeshes.decor_parts(str(d.kind)), pl, _rb_groups)
			elif kind == 1:
				if pl == _IDENTITY_XF:
					pl = Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.17), iso_to_3d(d.position, height_at(d.position) + 0.04))
				_rb_xf[id] = pl
				_collect(PropMeshes.water_decor_parts(str(d.kind)), pl, _rb_groups)
			else:
				var parts: Array = PropMeshes.entity_parts(d)
				if parts.is_empty():
					continue
				if pl == _IDENTITY_XF:
					pl = Transform3D(Basis.IDENTITY, iso_to_3d(d.position, height_at(d.position)))
				_rb_xf[id] = pl
				_collect(parts, pl, _rb_groups)
		if _rb_i >= _rb_list.size():
			_rb_phase = 1
			_rb_keys = _rb_groups.keys()
			_rb_i = 0
			_rb_staging = Node3D.new()
			_rb_staging.visible = false         # hidden until fully built — old batch stays up
			batches_root.add_child(_rb_staging)
	else:
		# Emit into the hidden staging node, budgeted by INSTANCES so even one giant group
		# (e.g. all grass) fills across several frames instead of spiking a single frame.
		var budget := RB_EMIT_INSTANCES_PER_FRAME
		while budget > 0 and _rb_i < _rb_keys.size():
			if _rb_g.is_empty():
				_rb_g = _rb_groups[_rb_keys[_rb_i]]
				_rb_gbuf = PackedFloat32Array()
				_rb_gbuf.resize((_rb_g["xf"] as Array).size() * 12)
				_rb_gi = 0
			var xf: Array = _rb_g["xf"]
			while _rb_gi < xf.size() and budget > 0:
				var t: Transform3D = xf[_rb_gi]
				var b := t.basis
				var o := t.origin
				var j := _rb_gi * 12
				_rb_gbuf[j] = b.x.x;     _rb_gbuf[j + 1] = b.y.x;  _rb_gbuf[j + 2] = b.z.x;   _rb_gbuf[j + 3] = o.x
				_rb_gbuf[j + 4] = b.x.y; _rb_gbuf[j + 5] = b.y.y;  _rb_gbuf[j + 6] = b.z.y;   _rb_gbuf[j + 7] = o.y
				_rb_gbuf[j + 8] = b.x.z; _rb_gbuf[j + 9] = b.y.z;  _rb_gbuf[j + 10] = b.z.z;  _rb_gbuf[j + 11] = o.z
				_rb_gi += 1
				budget -= 1
			if _rb_gi >= xf.size():
				_finish_group_mmi(_rb_g, _rb_gbuf, _rb_staging)
				_rb_g = {}
				_rb_i += 1
		if _rb_i >= _rb_keys.size() and _rb_g.is_empty():
			# Done: reveal the new batch and drop the old one (hide first to avoid a 1-frame
			# double-draw while queue_free is deferred).
			for c: Node in batches_root.get_children():
				if c != _rb_staging:
					(c as Node3D).visible = false
					c.queue_free()
			_rb_staging.visible = true
			_batch_xf = _rb_xf
			_static_sig = _rb_sig
			_rb_active = false
			_rb_groups = {}
			_rb_list = []
			_rb_keys = []
			_rb_staging = null
			_rb_gbuf = PackedFloat32Array()


## Create a MultiMeshInstance3D for a group from a pre-filled transform buffer.
func _finish_group_mmi(g: Dictionary, buf: PackedFloat32Array, root: Node3D) -> void:
	var n := (g["xf"] as Array).size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = g["mesh"]
	mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = g["mat"]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi)


func _collect(parts: Array, placement: Transform3D, groups: Dictionary) -> void:
	for p: Dictionary in parts:
		var key := str(p["mesh"].get_instance_id()) + "|" + str(p["mat"].get_instance_id())
		if not groups.has(key):
			groups[key] = {"mesh": p["mesh"], "mat": p["mat"], "xf": []}
		var local := Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		groups[key]["xf"].append(placement * local)


## Map a 2D iso-pixel position to a 3D world position (Y from elevation/height).
func iso_to_3d(pos: Vector2, y: float) -> Vector3:
	var g := WG.iso_to_grid(pos)
	return Vector3(g.x * TILE_S, y, g.y * TILE_S)


func _world_to_grid(pos: Vector2) -> Vector2:
	return WG.iso_to_grid(pos)


func _near_visual_grid(pos: Vector2, radius_tiles: float) -> bool:
	var g := _world_to_grid(pos)
	var p := _world_to_grid(world.player.position)
	return absf(g.x - p.x) <= radius_tiles and absf(g.y - p.y) <= radius_tiles


func _tile_center_pos(gtx: int, gty: int, lift := 0.0) -> Vector3:
	var info := _tile_info(gtx, gty)
	var h := 0.0
	if not info.is_empty() and bool(info["water"]):
		h = _water_surface_at(gtx, gty)
	elif not info.is_empty():
		var rt := float(info["top"])
		h = (_corner_height_for(gtx, gty, rt) + _corner_height_for(gtx + 1, gty, rt) + _corner_height_for(gtx, gty + 1, rt) + _corner_height_for(gtx + 1, gty + 1, rt)) * 0.25
	return Vector3((float(gtx) + 0.5) * TILE_S, h + lift, (float(gty) + 0.5) * TILE_S)


## Terrain height (3D Y) at a 2D iso position, sampled from the loaded chunk.
func height_at(pos: Vector2) -> float:
	var g := WG.iso_to_grid(pos)
	return _grid_height(g.x, g.y)


## Terrain height (3D Y) at fractional grid coordinates (gx,gy = 3D x/z over TILE_S).
func _grid_height(gx: float, gy: float) -> float:
	var t := Vector2i(floori(gx), floori(gy))
	var info := _tile_info(t.x, t.y)
	if not info.is_empty() and bool(info["water"]):
		return _water_surface_at(t.x, t.y)
	# Sample on this tile's plateau so a mover near a cliff lip rides its own flat top, not a
	# corner-average sagging toward the drop.
	var ref_top := float(info["top"]) if not info.is_empty() else 0.0
	var fx := gx - floorf(gx)
	var fy := gy - floorf(gy)
	var h00 := _corner_height_for(t.x, t.y, ref_top)
	var h10 := _corner_height_for(t.x + 1, t.y, ref_top)
	var h01 := _corner_height_for(t.x, t.y + 1, ref_top)
	var h11 := _corner_height_for(t.x + 1, t.y + 1, ref_top)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


## --- Picking: map a screen pixel to the 2D iso world position it visually points
## at, by casting through the 3D camera onto the terrain. The 2D substrate still
## owns movement/picking, but its Camera2D no longer matches what's on screen
## (the 3D camera does), so clicks must be projected through THIS camera instead.
func is_active() -> bool:
	return _active and cam != null


## Current camera orbit angle (radians). PI/4 is the default iso framing; the
## minimap reads this to rotate with the view when north-lock is off.
func cam_yaw() -> float:
	return _cam_yaw


func screen_to_iso(screen: Vector2) -> Vector2:
	var win: Vector2 = world.get_viewport().get_visible_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return world.get_global_mouse_position()
	# Window pixel -> SubViewport pixel. The present rect is an exact integer scale placed
	# at `_present_off`, so invert that affine mapping (subtract offset, divide by scale)
	# rather than assuming it fills the window proportionally.
	var sub_px := (screen - _present_off) / _present_scale
	var origin := cam.project_ray_origin(sub_px)
	var dir := cam.project_ray_normal(sub_px)
	var hit := _ray_to_ground(origin, dir)
	# 3D (x,z) -> grid -> iso world position (inverse of iso_to_3d / WG.tile_to_world).
	return WG.grid_to_iso(Vector2(hit.x / TILE_S, hit.z / TILE_S))


## Inverse of screen_to_iso: where an entity at iso position `pos` (lifted `lift`
## world units above the terrain) lands on screen, in window pixels. Picking the
## 3D billboards correctly has to happen in screen space — the ground-plane
## projection foreshortens differently at every elevation/pitch, so comparing the
## cursor to each entity's projected body avoids the vertical offset a flat iso
## comparison produces.
func iso_to_screen(pos: Vector2, lift := 0.0) -> Vector2:
	var p3 := iso_to_3d(pos, height_at(pos) + lift)
	var sub_px: Vector2 = cam.unproject_position(p3)
	# Internal pixel -> window pixel: the inverse of screen_to_iso's mapping (integer
	# scale + centred offset), so picking stays aligned with the presented image.
	return sub_px * _present_scale + _present_off


## World-Y to anchor a hitsplat at, scaled to the mover's size so the splat sits ON
## the body — low on a chicken, high on a cow — instead of a fixed height.
func mover_lift(entity: Node) -> float:
	if entity == world.player and _player_node != null:
		return float(_player_node.get_meta("base_scale", 1.0)) * 1.0
	var n: Node3D = _mover_nodes.get(entity.get_instance_id())
	if n != null:
		return float(n.get_meta("base_scale", 1.0)) * 0.95
	return 0.95


## Constant world-unit gap the HP bar floats above EVERY head — so the bar reads the same
## distance over a chicken, a wolf and the player, never "too high" on the animal rigs (whose
## old hardcoded height over-estimated their back, floating the bar ~0.6 too high). 0.30 keeps
## the previously-correct humanoid gap and brings every other body down to match it.
const BAR_CLEARANCE := 0.30

## World-Y just above the model's head for floating UI (HP bars). Uses the rig's MEASURED top
## (cached at build from its mesh AABBs, held weapons excluded) scaled by its size, plus one
## constant clearance — so the gap above the head is identical for every entity, instead of a
## hardcoded per-body guess that floated too high on some rigs.
func mover_top(entity: Node) -> float:
	var n: Node3D = _player_node if entity == world.player else _mover_nodes.get(entity.get_instance_id())
	if n == null:
		return 2.4
	var base := float(n.get_meta("base_scale", 1.0))
	var top_local := float(n.get_meta("rig_top_y", 2.0))
	return base * top_local + BAR_CLEARANCE


## Highest point of a mover rig in its OWN local space (feet ≈ y 0), measured from the mesh
## AABBs so floating UI clears the ACTUAL head — not a per-body guess. Held weapons/tools
## (socket_mainhand/offhand subtrees) are skipped so a tall staff never lifts the bar.
func _rig_top_y(root: Node3D) -> float:
	var top := _accumulate_top_y(root, Transform3D.IDENTITY, -1.0e9)
	return top if top > 0.01 else 2.0


func _accumulate_top_y(node: Node, xform: Transform3D, best: float) -> float:
	for child: Node in node.get_children():
		if not (child is Node3D):
			continue
		var nm := String(child.name)
		if nm.contains("socket_mainhand") or nm.contains("socket_offhand"):
			continue   # held weapon/tool — tracks the body, not the staff tip
		var cx: Transform3D = xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var ab: AABB = (child as MeshInstance3D).mesh.get_aabb()
			for i in 8:
				var corner: Vector3 = cx * (ab.position + Vector3(
					ab.size.x if (i & 1) != 0 else 0.0,
					ab.size.y if (i & 2) != 0 else 0.0,
					ab.size.z if (i & 4) != 0 else 0.0))
				best = maxf(best, corner.y)
		best = _accumulate_top_y(child, cx, best)
	return best


## Window pixels per world unit (orthographic, vertical) — turns a world-space
## pick radius into a screen-space one so tolerance is consistent at any zoom.
func world_px_per_unit() -> float:
	if cam == null or cam.size <= 0.0 or sub == null:
		return 1.0
	# Display px per world unit = (internal px per world unit) * integer present scale.
	return float(sub.size.y) * _present_scale / cam.size


## First (nearest) intersection of a ray with the terrain height field. We march forward
## from where the ray enters the terrain's vertical band and stop at the FIRST sample that
## dips below the sampled surface, then bisect. This returns the actual clicked face — a
## click on a tall mountain returns that mountain, not the distant low ground the ray would
## eventually cross (the old plane-iteration converged to that far surface, which put the
## click marker "on the ground" instead of where the user clicked).
const _TERR_MAX_Y := 14.0   # generous ceiling above the tallest summit (ELEV_MAX*ELEV_H + relief)
const _TERR_MIN_Y := -3.0   # below the deepest water basin
func _ray_to_ground(origin: Vector3, dir: Vector3) -> Vector3:
	if dir.y > -0.00001:
		# Ray parallel or pointing up — fall back to the flat ground plane.
		var tp := (0.0 - origin.y) / dir.y if absf(dir.y) > 0.00001 else 0.0
		return origin + dir * maxf(tp, 0.0)
	# Restrict the march to the slab the terrain occupies (enter at the top, exit at the floor).
	var t_enter: float = maxf((_TERR_MAX_Y - origin.y) / dir.y, 0.0)
	var t_exit: float = (_TERR_MIN_Y - origin.y) / dir.y
	if t_exit <= t_enter:
		var tp2 := (0.0 - origin.y) / dir.y
		return origin + dir * maxf(tp2, 0.0)
	var steps := 96
	var dt := (t_exit - t_enter) / float(steps)
	var prev_t := t_enter
	for i: int in steps + 1:
		var t := t_enter + dt * float(i)
		var p := origin + dir * t
		var h := _grid_height(p.x / TILE_S, p.z / TILE_S)
		if p.y <= h:
			# Crossed below the surface between prev_t and t — bisect for the precise hit.
			var lo := prev_t
			var hi := t
			for _b: int in 8:
				var mt := (lo + hi) * 0.5
				var mp := origin + dir * mt
				if mp.y <= _grid_height(mp.x / TILE_S, mp.z / TILE_S):
					hi = mt
				else:
					lo = mt
			return origin + dir * hi
		prev_t = t
	# Ray passed over all terrain (e.g. pointing at open sky/sea) — flat plane fallback.
	var tp3 := (0.0 - origin.y) / dir.y
	return origin + dir * maxf(tp3, 0.0)


func _palette_texture() -> ImageTexture:
	var keys := PixelPalette.PAL.keys()
	var img := Image.create(keys.size(), 1, false, Image.FORMAT_RGBA8)
	for i: int in keys.size():
		img.set_pixel(i, 0, PixelPalette.pal(keys[i]))
	return ImageTexture.create_from_image(img)


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world3d_shot.png")
	print("[world3d] saved user://world3d_shot.png")
