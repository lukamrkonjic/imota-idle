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
const SpawnDressingSpecs := preload("res://scripts/render/spawn_dressing_specs.gd")

const INTERNAL := Vector2i(640, 360)   # internal render res (higher = finer/less chunky pixels)
const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := WG.ELEV_H           # height per elevation step (8px / 32px tile); single
                                    # source in wg.gd. Render alias kept for call-site brevity.
# Turn spring: a body accelerates into a turn and damps out of it (slightly
# underdamped for a snappy-but-physical settle), so facing changes are never instant.
const TURN_STIFFNESS := 62.0
const TURN_DAMPING := 14.0
const HURT_DUR := 0.2               # how long the take-a-hit red flash + shake lasts
const DRESSING_ANCHOR := 4          # visual set dressing snaps to this tile grid
const SPAWN_LAYER := 0              # overworld layer the home-campsite dressing lives on
const DRESSING_SPREAD := 1.7        # fan the camp pieces apart so nothing is squished
const FOREST_PREVIEW_ARG := "--forest-preview"
const WATER_PREVIEW_ARG := "--water-preview"   # verification: teleport to a deterministic ocean coast

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
var dressing_root: Node3D            # visual-only hiking-diorama silhouettes near camera
var _outlines_root: Node3D           # inverted-hull silhouette outlines for highlighted entities
var _outline_mat: ShaderMaterial     # shared white outline material (grown hull, cull_front)
var _outline_nodes: Dictionary = {}  # static entity id -> outline Node3D
var _outlined_movers: Dictionary = {} # mover id -> true (material_overlay applied)
var _fire: Node3D                    # the single firemaking fire (one per burning session)
var _fire_flames: Node3D             # the flame meshes (flickered/flared separately)
var _fire_phase := ""                 # "" | "burn" | "decay"
var _fire_t := 0.0                    # flicker clock
var _fire_decay := 0.0                # seconds since the player stopped feeding it
var _fire_flare := 0.0                # brief flame boost when a log is fed
var _kneel_t := 0.0                   # seconds left of the player's kneel-to-feed crouch
var _fx_bursts: Array = []            # transient effects {node, t, dur, kind, mat?, from?, to?}
var _mover_nodes: Dictionary = {}    # moving entity id -> Node3D (player/enemies)
var _mover_prev: Dictionary = {}     # key -> last 3D pos (for walk detection)
var _mover_yaw: Dictionary = {}      # key -> facing yaw (turned with spring inertia)
var _mover_yaw_vel: Dictionary = {}  # key -> angular velocity for the turn spring
var _mover_walk: Dictionary = {}     # key -> smoothed walk amount 0..1
var _attack_t: Dictionary = {}       # key -> time (s) the last attack lunge started
var _hurt_t: Dictionary = {}         # key -> time (s) a body last took a hit (red flash + shake)
var _mover_death: Dictionary = {}    # key -> {t0, pos} while a defeated mover plays its death topple
var _shadow_nodes: Dictionary = {}   # key -> blob-shadow MeshInstance3D pinned to ground
var fx_layer: CanvasLayer            # screen-space overlay for hitsplats over the 3D world
var _env: Environment                # kept so the view-distance slider can retune the fog
var _sun: DirectionalLight3D         # kept so the slider can scale shadow distance
var _terrain_cull := 34.0            # visible terrain radius (tiles), driven by view_distance
var _prop_cull := 30.0               # visible prop/decor radius (tiles)
var _player_node: Node3D
var _cam_yaw := PI / 4.0          # orbit angle around the player (Left/Right arrows)
var _cam_pitch := 0.413           # elevation above horizon (Up/Down arrows); matches old iso
const CAM_FOLLOW_SPEED := 12.0   # eased-follow rate, matches the 2D Camera2D position_smoothing_speed
var _cam_follow := Vector2.INF    # smoothed follow target (iso); INF = uninitialised (snap on first use)
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
var _dressing_sig := ""
var _spawn_placed := -1               # how many camp-dressing pieces have ground so far
var _spawn_stable := 0                # frames the placed count has held steady
var _spawn_dressing_built := false    # latched true once the whole camp scene is placed
var _forest_preview_done := false
var _water_preview_done := false
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
	dressing_root = Node3D.new()
	world3d.add_child(dressing_root)
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
	# Firemaking fire + prayer-activation bursts (world FX).
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.activity_stopped.connect(_on_activity_stopped)
	EventBus.prayer_activated.connect(_on_prayer_activated)
	EventBus.firemaking_log_burned.connect(_on_firemaking_burned)


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
	_sync_terrain()
	_sync_movers()
	_sync_static_batches()
	_sync_outlines()
	_update_fx(delta)
	# Compose the cozy A Short Hike camp ONCE around the spawn tile (the home
	# campsite). Anchored to spawn, NOT the camera — so it's a finished place you
	# arrive at, not canned props that follow you everywhere (the old failure mode).
	_sync_spawn_dressing()
	_frames += 1
	var capture_frame := 150 if (_forest_preview_enabled() or _water_preview_enabled()) else 90
	if _frames == capture_frame and not _captured:
		_capture()


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
	_dressing_sig = ""
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
	_dressing_sig = ""
	print("[world3d] water preview teleport to tile %s" % [WG.world_to_tile(pos)])


func _water_preview_enabled() -> bool:
	return WATER_PREVIEW_ARG in OS.get_cmdline_args() or WATER_PREVIEW_ARG in OS.get_cmdline_user_args()


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
const CAM_PITCH_MIN := 0.16   # near the horizon
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


func _sync_camera() -> void:
	# Eased follow (the "snappier follow-cam" from main): the 2D Camera2D uses
	# position_smoothing, but the 3D render camera is what's visible here, so replicate it.
	# Smoothly chase the player's iso position instead of hard-locking to it, which absorbs
	# any unevenness in the walk and reads as a calm, steady glide.
	var follow: Vector2 = world.player.position
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
	var live := {}   # the build set: chunks that should have a terrain mesh (nav ring)
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
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
	for key: String in _chunk_meshes.keys():
		if not live.has(key):
			var mi: Node = _chunk_meshes[key]
			if is_instance_valid(mi):
				mi.queue_free()
			_chunk_meshes.erase(key)
			_chunk_nbr.erase(key)
			_chunk_wait.erase(key)
	_update_terrain_visibility()


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
		node.visible = absf(center.x - g.x) <= _terrain_cull and absf(center.y - g.y) <= _terrain_cull


## Map the view-distance setting (0..1) to a visible terrain radius, then retune
## everything that scales with it: prop culling, the fog ramp (so the fogged edge
## still hides the terrain boundary), and the shadow distance (capped — shadows
## past the fogged range are invisible, so keeping them short is a free perf win).
func _apply_view_distance() -> void:
	var vt := lerpf(34.0, 64.0, clampf(GameSettings.view_distance, 0.0, 1.0))
	_terrain_cull = vt
	_prop_cull = vt - 4.0
	if _env != null:
		_env.fog_depth_end = vt + 14.0     # camera-depth ≈ CAM_DIST + tiles; full haze past the edge
		_env.fog_depth_begin = vt - 10.0
	if _sun != null:
		_sun.directional_shadow_max_distance = clampf(vt * 0.85, 30.0, 52.0)


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


# ---- world FX: firemaking fire + prayer-activation bursts -------------------
func _on_activity_started(kind: String, detail: String) -> void:
	if kind == "craft" and detail.begins_with("Firemaking"):
		_light_fire()


func _on_activity_stopped(_reason: String) -> void:
	# Player stopped feeding logs — let the fire burn down to embers and vanish.
	if _fire != null and _fire_phase == "burn":
		_fire_phase = "decay"
		_fire_decay = 0.0


func _light_fire() -> void:
	if _fire == null or not is_instance_valid(_fire):
		_fire = _build_campfire()
		_fire.position = _fire_spot()
		props_root.add_child(_fire)
		_fire_flames = _fire.get_node_or_null("flames")
	_fire_phase = "burn"   # resumes if it was decaying


## Ground spot a short step IN FRONT of the player (toward the camera, so it reads as set
## down before them rather than under their feet).
func _fire_spot() -> Vector3:
	var ppos := iso_to_3d(world.player.position, height_at(world.player.position))
	var fwd := cam.global_position - ppos
	fwd.y = 0.0
	if fwd.length() > 0.01:
		ppos += fwd.normalized() * 1.1
	return ppos


## A small campfire: a ring of stones, charred logs, and emissive flames (self-lit — no
## dynamic light, which washed out the toon-shaded world). The "flames" child is animated.
func _build_campfire() -> Node3D:
	var node := Node3D.new()
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.46, 0.46, 0.50)
	for i: int in 7:
		var a := TAU * float(i) / 7.0
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.22
		s.mesh = sm
		s.material_override = stone_mat
		s.position = Vector3(cos(a) * 0.36, 0.06, sin(a) * 0.36)
		s.scale = Vector3(1.0, 0.7, 1.0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(s)
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.22, 0.14, 0.09)
	for j: int in 2:
		var lg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.05
		lm.bottom_radius = 0.05
		lm.height = 0.5
		lg.mesh = lm
		lg.material_override = log_mat
		lg.position = Vector3(0.0, 0.06, 0.0)
		lg.rotation = Vector3(PI / 2.0, float(j) * 1.4, 0.0)
		lg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lg)
	var flames := Node3D.new()
	flames.name = "flames"
	for f: Array in [[0.0, 0.55, Color(1.0, 0.5, 0.14)], [0.07, 0.4, Color(1.0, 0.82, 0.3)]]:
		var fm := CylinderMesh.new()
		fm.top_radius = 0.005
		fm.bottom_radius = 0.16 - float(f[0])
		fm.height = float(f[1])
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = f[2]
		fmat.emission_enabled = true
		fmat.emission = f[2]
		fmat.emission_energy_multiplier = 2.6
		var fi := MeshInstance3D.new()
		fi.mesh = fm
		fi.material_override = fmat
		fi.position = Vector3(float(f[0]), 0.12 + float(f[1]) * 0.5, 0.0)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.add_child(fi)
	node.add_child(flames)
	return node


## Player feeds a log: kneel-crouch + a log tossed into the fire + a flame flare.
func _on_firemaking_burned() -> void:
	if _fire == null or not is_instance_valid(_fire):
		return
	_fire_flare = 0.5
	_kneel_t = 0.5
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.34, 0.22, 0.12)
	var lm := CylinderMesh.new()
	lm.top_radius = 0.05
	lm.bottom_radius = 0.05
	lm.height = 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = lm
	mi.material_override = log_mat
	mi.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node := Node3D.new()
	node.add_child(mi)
	var from := iso_to_3d(world.player.position, height_at(world.player.position) + 0.7)
	props_root.add_child(node)
	node.position = from
	_fx_bursts.append({"node": node, "t": 0.0, "dur": 0.4, "kind": "log",
		"from": from, "to": _fire.position + Vector3(0.0, 0.2, 0.0)})


func _on_prayer_activated(prayer_name: String) -> void:
	if world.player == null:
		return
	var col := _prayer_color(prayer_name)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node := Node3D.new()
	node.add_child(mi)
	node.position = iso_to_3d(world.player.position, height_at(world.player.position) + 1.2)
	props_root.add_child(node)
	_fx_bursts.append({"node": node, "mat": mat, "t": 0.0, "dur": 0.8, "kind": "burst"})


func _update_fx(delta: float) -> void:
	_fire_flare = maxf(_fire_flare - delta, 0.0)
	if _fire != null and is_instance_valid(_fire):
		_fire_t += delta
		var flare := 1.0 + _fire_flare * 1.2
		if _fire_phase == "burn" and _fire_flames != null:
			var f := (1.0 + 0.12 * sin(_fire_t * 11.0) + 0.06 * sin(_fire_t * 23.0)) * flare
			_fire_flames.scale = Vector3(1.0, f, 1.0)
		elif _fire_phase == "decay":
			_fire_decay += delta
			var k := clampf(1.0 - _fire_decay / 5.0, 0.0, 1.0)   # embers over ~5s
			if _fire_flames != null:
				_fire_flames.scale = Vector3(k, k, k)
			if _fire_decay >= 5.0:
				_fire.queue_free()
				_fire = null
				_fire_flames = null
				_fire_phase = ""
	# Kneel-to-feed: briefly lower the player rig (re-applied each frame after _sync_movers).
	if _kneel_t > 0.0 and _player_node != null:
		_kneel_t = maxf(_kneel_t - delta, 0.0)
		_player_node.position.y -= 0.22
	for i: int in range(_fx_bursts.size() - 1, -1, -1):
		var b: Dictionary = _fx_bursts[i]
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			_fx_bursts.remove_at(i)
			continue
		b["t"] += delta
		var p: float = clampf(b["t"] / float(b["dur"]), 0.0, 1.0)
		if str(b.get("kind", "burst")) == "log":
			# Arc the log from the player into the fire.
			var from: Vector3 = b["from"]
			var to: Vector3 = b["to"]
			node.position = from.lerp(to, p) + Vector3(0.0, sin(p * PI) * 0.6, 0.0)
			node.rotate_x(delta * 8.0)
		else:
			node.scale = Vector3.ONE * (0.4 + p * 1.4)
			node.position.y += delta * 1.1
			(b["mat"] as StandardMaterial3D).albedo_color.a = (1.0 - p) * 0.85
		if p >= 1.0:
			node.queue_free()
			_fx_bursts.remove_at(i)


func _build_parts_node(parts: Array) -> Node3D:
	var node := Node3D.new()
	for pt: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pt["mesh"]
		mi.material_override = pt["mat"]
		mi.transform = Transform3D(Basis.from_euler(pt.get("rot", Vector3.ZERO)).scaled(pt.get("scl", Vector3.ONE)), pt.get("off", Vector3.ZERO))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node


## Distinct colour per prayer: a base hue by its group, nudged by the prayer name so each
## reads a little differently (a unique-ish activation flash without bespoke art per prayer).
func _prayer_color(prayer_name: String) -> Color:
	var group := str(DataRegistry.prayers.get(prayer_name, {}).get("group", ""))
	var base: Color
	match group:
		"defence": base = Color(0.40, 0.62, 1.0)
		"damage": base = Color(1.0, 0.42, 0.20)
		"accuracy": base = Color(1.0, 0.88, 0.30)
		"protect": base = Color(0.72, 0.42, 1.0)
		_: base = Color(0.75, 1.0, 0.78)
	var h := float(absi(hash(prayer_name)) % 1000) / 1000.0
	return base.lerp(Color.from_hsv(h, 0.5, 1.0), 0.18)


## Movers (player + enemies) stay individual nodes — few of them, and they move.
func _sync_movers() -> void:
	var dt := get_process_delta_time()
	var t := Time.get_ticks_msec() / 1000.0
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
			_pose_bird(node, pos3, yaw, walk, t, phase, base, atk)
		"humanoid":
			# Goblins and gnolls get their own lore-flavoured gaits; everyone else
			# (player, skeletons, generic humanoids) uses the upright human pose.
			match str(node.get_meta("gait", "")):
				"goblin":
					_pose_goblin(node, pos3, yaw, walk, t, phase, base, atk)
				"gnoll":
					_pose_gnoll(node, pos3, yaw, walk, t, phase, base, atk)
				_:
					_pose_humanoid(node, pos3, yaw, walk, t, phase, base, atk)
		_:
			_pose_quadruped(node, pos3, yaw, walk, t, phase, base, atk)
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
	_flow_cloth(node, walk, t, phase)
	_sway_hair(node, walk, t, phase)
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
		_set_pivot(node, pv, lerpf(0.0, 0.25, p))
	var spine: Node3D = _pivot(node, "spine")
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


## Cheap "hair physics": any hair/beard/mane/tuft pivot on a rig gets a soft sway —
## bouncing and leaning back as the character moves, drifting on a light idle wind.
## Pure procedural (a rotation per pivot), no real physics. Rigs opt in by parenting
## their soft bits under a pivot named hair/beard/mane/tuft.
func _sway_hair(node: Node3D, walk: float, t: float, phase: float) -> void:
	for hp: String in ["hair", "beard", "mane"]:
		var p: Node3D = node.get_node_or_null(NodePath(hp))
		if p == null:
			p = _pivot(node, hp)
		if p == null:
			continue
		var amp := 0.5 + walk * 1.4
		p.rotation = Vector3(
			-walk * 0.16 + sin(t * 5.2 + phase) * 0.05 * amp,   # lift/lean back when moving
			sin(t * 3.4 + phase) * 0.03 * amp,
			sin(t * 2.7 + phase * 1.4) * 0.04 * amp)


## Cheap cloth "sim" for worn robes/capes: pure procedural secondary motion — no
## physics, no per-vertex work. The skirt (socket_legs) and cape (socket_back)
## pivot at the waist/shoulders, trailing back as you move and rippling on a soft
## wind oscillation, so robes flow instead of standing rigid.
func _flow_cloth(node: Node3D, walk: float, t: float, phase: float) -> void:
	for sock_name: String in ["socket_legs", "socket_back"]:
		var sock: Node = node.get_node_or_null(NodePath(sock_name))
		if sock == null:
			sock = _pivot(node, sock_name)
		if sock == null:
			continue
		var eq: Node3D = sock.get_node_or_null(^"equip")
		if eq == null or not bool(eq.get_meta("cloth", false)):
			continue
		if int(eq.get_meta("cape_segments", 0)) > 0:
			_flow_cape(eq, walk, t, phase)
			continue
		var amp := 0.45 + walk * 1.7
		eq.rotation = Vector3(
			-walk * 0.24 + sin(t * 4.2 + phase) * 0.07 * amp,
			sin(t * 3.1 + phase) * 0.04 * amp,
			sin(t * 2.6 + phase * 1.7) * 0.06 * amp)


## A fixed per-link drape curve (radians of backward tilt added at each link). It
## stays near-vertical down the back, then folds toward horizontal at the hem, so
## the chain falls under "gravity" to the floor and the last links POOL/drag behind
## the heels — a long, heavy, majestic cape rather than a stiff board.
const CAPE_DRAPE := [0.03, 0.05, 0.08, 0.13, 0.42, 0.82]

## Cheap cape "cloth sim": hold the drape curve (so the cape hangs down and drags on
## the ground), then add only a slow, low-amplitude undulation rolled down the chain
## — a heavy fabric sway, never an upward billow. ~12 sin() calls, no physics.
func _flow_cape(eq: Node3D, walk: float, t: float, phase: float) -> void:
	var amp := 0.02 + walk * 0.06         # small: heavy cloth barely lifts when moving
	var seg: Node3D = eq.get_node_or_null(^"cape_seg0")
	var d := 0
	while seg != null:
		var base_x: float = CAPE_DRAPE[d] if d < CAPE_DRAPE.size() else 0.12
		var lag := float(d) * 0.55
		# Gentle ripple (kept below the drape so it undulates without lifting), plus a
		# slow side-to-side sway that grows a touch toward the trailing hem.
		var ripple := sin(t * 1.7 + phase - lag) * amp
		var sway := sin(t * 1.25 + phase * 1.2 - lag) * amp * (1.0 + 0.3 * float(d))
		seg.rotation = Vector3(base_x + maxf(ripple, -base_x * 0.5), 0.0, sway)
		seg = seg.get_node_or_null(NodePath("cape_seg%d" % (d + 1)))
		d += 1


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


## Jointed biped: knees and elbows flex for a natural bent-leg walk, and a `crouch`
## meta gives a bent-kneed standing stance (goblins stoop, the gnoll sneaks low).
## `lean` hunches the body, `arm_rest` keeps arms a touch forward (never ramrod).
func _pose_humanoid(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var lean: float = float(node.get_meta("lean", 0.04))
	# `hunch` curves the upper back forward at the spine pivot (an old-lady stoop) —
	# legs/hips stay vertical, so it reads as a natural bent back, NOT a whole-body
	# forward lean (the Michael-Jackson tilt we want to avoid).
	var hunch: float = float(node.get_meta("hunch", 0.0))
	var arm_rest: float = float(node.get_meta("arm_rest", 0.08))
	var crouch: float = float(node.get_meta("crouch", 0.1))
	var holds_staff: bool = str(node.get_meta("pose", "")) == "staff"
	var breathe := rest * sin(t * 1.9 + phase) * 0.03
	var sway := rest * sin(t * 1.15 + phase) * 0.05
	var stride := t * 6.0 + phase
	# The life of the walk is in the BODY, not just the limbs: it rocks side-to-side
	# toward the planted foot (the `roll`, once per stride), bobs up and settles on
	# each footfall (twice per stride — the little "shake" on every step), and leans
	# a touch into the stride. This carries the walk; the limbs stay understated.
	var roll := sin(stride) * 0.09 * walk
	var bob := absf(sin(stride)) * 0.055 * walk
	var settle := absf(sin(stride)) * 0.045 * walk
	# Idle sway is upward-only so it never sinks the feet below the ground; GROUND_LIFT
	# compensates for the boot mesh sitting a touch below the rig origin + the crouch.
	var idle_bob := rest * (0.5 + 0.5 * sin(t * 2.0 + phase)) * 0.02
	node.rotation = Vector3(lean + walk * 0.06 + breathe * 0.4, yaw, sway + roll)
	# Curl the upper back forward (head leads, shoulders round) — the spine pivot
	# carries everything above the hips; a touch more curl while walking.
	_set_pivot(node, "spine", hunch + walk * 0.05)
	node.position = pos3 + Vector3(0, bob + idle_bob + 0.09 - crouch * 0.14, 0)
	node.scale = Vector3(base * (1.0 - settle * 0.4), base * (1.0 + breathe + settle), base * (1.0 - settle * 0.4))
	# Legs: a natural stride — moderate hip swing, the knee lifting in its swing phase
	# to clear the ground (not a deep squat, not a stiff post).
	var hip := sin(stride) * 0.42 * walk
	var hip_crouch := -crouch * 0.42                 # thighs forward to sit into the crouch
	var knee_base := 0.16 + crouch * 0.95            # standing knee bend
	var knee_l := knee_base + walk * (0.1 + 0.45 * maxf(0.0, sin(stride + 1.1)))
	var knee_r := knee_base + walk * (0.1 + 0.45 * maxf(0.0, sin(stride + PI + 1.1)))
	_set_pivot(node, "leg_l", hip + hip_crouch)
	_set_pivot(node, "leg_r", -hip + hip_crouch)
	_set_pivot(node, "leg_l/knee_l", knee_l)   # knees are nested under the hip pivots
	_set_pivot(node, "leg_r/knee_r", knee_r)
	# Arms: a relaxed counter-swing to the legs; ELBOWS fold FORWARD (negative — the
	# forearm comes up toward the front like a real arm, never bent backward), with a
	# soft constant crook so the arms read as relaxed, not stiff or flailing.
	var idle_arm := rest * sin(t * 1.5 + phase) * 0.1
	var arm_l := arm_rest + sin(stride + PI) * 0.4 * walk + idle_arm
	var arm_r := arm_rest + sin(stride) * 0.4 * walk - idle_arm
	var elbow_base := -(0.2 + crouch * 0.25)
	var elbow_l := elbow_base - walk * 0.22 * maxf(0.0, sin(stride + PI + 0.5))
	var elbow_r := elbow_base - walk * 0.22 * maxf(0.0, sin(stride + 0.5))
	if holds_staff:
		arm_r = 0.12 + idle_arm * 0.3   # rest the hand on a side-planted staff
		elbow_r = -0.16
	if atk > 0.0:
		var strike := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.5, strike)   # lead arm chops overarm
		elbow_r = lerpf(elbow_r, -1.0, strike)  # forearm folds in for the chop
		arm_l = lerpf(arm_l, 0.4, strike)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", elbow_l)   # elbows are nested under the shoulder pivots
	_set_pivot(node, "arm_r/elbow_r", elbow_r)


## Goblin stance — stands UPRIGHT but cocky and twitchy (a nimble medieval-game
## goblin, not a hunchback): a slightly coiled wide stance on bent knees, the torso
## near-vertical with just a hint of forward attitude, weight shifting, the head
## darting to glance around, and clawed hands held ready at the waist. The walk is a
## fast, light, bouncy scamper.
func _pose_goblin(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var holds_staff: bool = str(node.get_meta("pose", "")) == "staff"
	var crouch := 0.24                                               # bent knees, but STANDING
	var stride := t * 8.4 + phase                                    # fast little legs
	var bob := absf(sin(stride)) * 0.08 * walk
	var skip := absf(sin(stride * 0.5 + 0.4)) * 0.045 * walk
	# Idle life: shifty side-weight, glancing around, sudden nervous twitches.
	var shift := rest * sin(t * 2.3 + phase) * 0.08
	var glance := rest * sin(t * 0.85 + phase) * 0.4
	var twitch := rest * maxf(0.0, sin(t * 1.3 + phase * 2.0) - 0.6) * 0.6
	var roll := sin(stride) * 0.12 * walk
	node.rotation = Vector3(0.03, yaw, shift + roll)
	node.position = pos3 + Vector3(0, bob + skip + 0.09 - crouch * 0.14, 0)
	# Spine: near-vertical (just a hint of forward attitude) that twists to glance +
	# a quick scheming jitter — upright, never toppling.
	var spine: Node3D = _pivot(node, "spine")
	if spine != null:
		spine.rotation = Vector3(0.12 + walk * 0.05 + twitch, glance, rest * sin(t * 3.0 + phase) * 0.05)
	# Legs: a fast, light, high-knee scamper from a wide bent-knee stance.
	var hip := sin(stride) * 0.5 * walk
	var hipc := -crouch * 0.42
	var kbase := 0.2 + crouch * 0.95
	_set_pivot(node, "leg_l", hip + hipc)
	_set_pivot(node, "leg_r", -hip + hipc)
	_set_pivot(node, "leg_l/knee_l", kbase + walk * (0.22 + 0.62 * maxf(0.0, sin(stride + 1.1))))
	_set_pivot(node, "leg_r/knee_r", kbase + walk * (0.22 + 0.62 * maxf(0.0, sin(stride + PI + 1.1))))
	# Arms: clawed hands held ready at the waist (a small idle fidget), pumping when
	# scampering; a staff-goblin grips its planted staff with the right hand instead.
	var fidget := rest * sin(t * 4.8 + phase) * 0.12
	var arm_l := 0.46 + sin(stride + PI) * 0.42 * walk
	var arm_r := 0.46 + sin(stride) * 0.42 * walk
	var elbow_r := -0.82 + fidget
	if holds_staff:
		arm_r = 0.16
		elbow_r = -0.18
	if atk > 0.0:
		var st := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.4, st)                              # a quick stabby swipe
		elbow_r = lerpf(elbow_r, -0.9, st)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", -0.82 - fidget)
	_set_pivot(node, "arm_r/elbow_r", elbow_r)


## Gnoll gait — a heavy hyena-beast prowl (predatory, not a tidy walk): the head is
## carried low and forward, shoulders rolling, a slow menacing weight-sway, broken by
## a sudden cackling snout-up jerk. The walk is a powerful, lurching, long-stride lope.
func _pose_gnoll(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var stride := t * 5.2 + phase                                    # slow, heavy strides
	var bob := absf(sin(stride)) * 0.06 * walk
	# Idle: slow heavy sway, breathing shoulders, an occasional cackle head-jerk.
	var sway := rest * sin(t * 1.3 + phase) * 0.1
	var breathe := rest * (0.5 + 0.5 * sin(t * 1.8 + phase)) * 0.05
	var cackle := rest * maxf(0.0, sin(t * 0.9 + phase) - 0.78) * 0.9
	var roll := sin(stride) * 0.15 * walk                           # heavy shoulder roll
	node.rotation = Vector3(0.04, yaw, sway + roll)
	node.position = pos3 + Vector3(0, bob + 0.04, 0)
	# Spine: stands UPRIGHT and imposing — chest up, only a slight forward set (ready,
	# not falling). The snout already juts from the rig; the head dips a touch on each
	# footfall and snaps up to cackle. Heavy breathing rocks the shoulders.
	var spine: Node3D = _pivot(node, "spine")
	if spine != null:
		var dip := absf(sin(stride)) * 0.1 * walk
		spine.rotation = Vector3(0.15 + breathe + dip - cackle, sway * 0.5, 0)
	# Legs: a powerful digitigrade stance/lope — stands tall on bent hocks, long push.
	var hip := sin(stride) * 0.44 * walk
	var hipc := -0.14
	var kbase := 0.5
	_set_pivot(node, "leg_l", hip + hipc)
	_set_pivot(node, "leg_r", -hip + hipc)
	_set_pivot(node, "leg_l/knee_l", kbase + walk * (0.15 + 0.5 * maxf(0.0, sin(stride + 1.1))))
	_set_pivot(node, "leg_r/knee_r", kbase + walk * (0.15 + 0.5 * maxf(0.0, sin(stride + PI + 1.1))))
	# Arms: long and heavy, hanging at the sides with a slight ready set, swinging on
	# the lope; a big overhead claw-rake on attack.
	var idle_arm := rest * sin(t * 1.4 + phase) * 0.1
	var arm_l := 0.16 + sin(stride + PI) * 0.46 * walk + idle_arm
	var arm_r := 0.16 + sin(stride) * 0.46 * walk - idle_arm
	var elbow := -0.42
	if atk > 0.0:
		var st := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.7, st)
		elbow = lerpf(elbow, -1.1, st)
		arm_l = lerpf(arm_l, 0.5, st)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", elbow)
	_set_pivot(node, "arm_r/elbow_r", elbow)


## Four-legged trot: diagonal leg pairs swing together (FL+BR vs FR+BL), low body
## bob, the back dips a touch on each push, and the tail wags. A swing leans the
## whole body in for a headbutt/bite.
func _pose_quadruped(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	# Idle life: slow breathing, a gentle side-to-side weight shift, and a periodic
	# head-down graze dip so a standing beast never just freezes.
	var breathe := rest * sin(t * 1.5 + phase) * 0.022
	var sway := rest * sin(t * 0.85 + phase) * 0.035
	var graze := rest * maxf(0.0, sin(t * 0.45 + phase) - 0.4) * 0.32
	node.rotation = Vector3(-0.28 * sin(atk * PI) + graze, yaw, sway)
	var stride := t * 7.6 + phase
	# A clear up/down body bob while moving + a gentle idle breathing sway at rest;
	# a small ground lift so the hooves sit on the floor, not through it.
	var bob := absf(sin(stride)) * 0.06 * walk + rest * (0.5 + 0.5 * sin(t * 2.0 + phase)) * 0.02
	node.position = pos3 + Vector3(0, bob + 0.07, 0)
	var sq := sin(stride * 2.0) * 0.03 * walk
	node.scale = Vector3(base * (1.0 + sq * 0.4), base * (1.0 - sq * 0.5 + breathe), base * (1.0 + sq * 0.4))
	# Diagonal trot: FL+BR swing together, FR+BL opposite. Each knee folds through
	# its swing so the legs articulate (lift + reach) instead of swinging as posts.
	var swing := sin(stride) * 0.7 * walk
	var idle_leg := rest * sin(t * 1.1 + phase) * 0.04
	var knee_a := 0.12 + walk * (0.18 + 0.5 * maxf(0.0, sin(stride + 1.1)))
	var knee_b := 0.12 + walk * (0.18 + 0.5 * maxf(0.0, sin(stride + PI + 1.1)))
	_set_pivot(node, "leg_fl", swing + idle_leg)
	_set_pivot(node, "leg_br", swing - idle_leg)
	_set_pivot(node, "leg_fr", -swing - idle_leg)
	_set_pivot(node, "leg_bl", -swing + idle_leg)
	_set_pivot(node, "leg_fl/knee_fl", knee_a)
	_set_pivot(node, "leg_br/knee_br", knee_a)
	_set_pivot(node, "leg_fr/knee_fr", knee_b)
	_set_pivot(node, "leg_bl/knee_bl", knee_b)
	var tail: Node3D = node.get_node_or_null(^"tail")
	if tail != null:
		tail.rotation = Vector3(0.18 * sin(stride * 0.5) * walk, 0.5 * sin(t * 2.0 + phase), 0)


## Bird waddle: quick alternating steps, a side-to-side roll, and a brisk bob —
## smaller and twitchier than the beasts. A swing is a sharp forward peck.
func _pose_bird(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var stride := t * 9.0 + phase
	# Idle life: a constant little body bob plus a sharp periodic peck-and-look,
	# and a slight head-cock sway — birds are never still.
	var idle_bob := rest * absf(sin(t * 2.2 + phase)) * 0.02
	var peck := rest * maxf(0.0, sin(t * 1.4 + phase) - 0.3) * 0.5
	var look := rest * sin(t * 0.7 + phase) * 0.12
	var bob := absf(sin(stride)) * 0.05 * walk + idle_bob
	node.position = pos3 + Vector3(0, bob + 0.03, 0)
	var roll := sin(stride) * 0.18 * walk
	node.rotation = Vector3(-0.35 * sin(atk * PI) - peck, yaw + look, roll)
	node.scale = Vector3(base, base, base)
	var swing := sin(stride) * 0.7 * walk
	_set_pivot(node, "leg_l", swing)
	_set_pivot(node, "leg_r", -swing)


# --- combat animation: lunges driven by the tick-combat hit splats -------------

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


func _set_pivot(node: Node3D, pivot_name: String, angle: float) -> void:
	var p := _pivot(node, pivot_name)
	if p != null:
		p.rotation.x = angle


## Resolve a named rig pivot, CACHED per rig. Pivots like "arm_l" now sit under the
## `spine` pivot, so a plain path lookup misses and needs a recursive search — doing
## that every frame for every mover was the dominant per-frame cost. We resolve once
## (path, then recursive fallback for nested names) and cache the node (incl. nulls)
## on the rig, so subsequent frames are a dictionary hit.
func _pivot(node: Node3D, pivot_name: String) -> Node3D:
	var cache: Dictionary
	if node.has_meta("pivot_cache"):
		cache = node.get_meta("pivot_cache")
	else:
		cache = {}
		node.set_meta("pivot_cache", cache)
	if cache.has(pivot_name):
		var c: Variant = cache[pivot_name]
		if c == null or is_instance_valid(c):
			return c
	var p: Node3D = node.get_node_or_null(NodePath(pivot_name))
	if p == null:
		var segs := pivot_name.split("/")
		var cur: Node = node.find_child(segs[0], true, false)
		for i: int in range(1, segs.size()):
			if cur == null:
				break
			cur = cur.get_node_or_null(NodePath(segs[i]))
		p = cur as Node3D
	cache[pivot_name] = p
	return p


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


func _sync_style_dressing() -> void:
	var g := _world_to_grid(world.player.position)
	var anchor := Vector2i(roundi(g.x / float(DRESSING_ANCHOR)) * DRESSING_ANCHOR, roundi(g.y / float(DRESSING_ANCHOR)) * DRESSING_ANCHOR)
	var sig := "%s:%d,%d" % [str(world.current_layer), anchor.x, anchor.y]
	if sig == _dressing_sig:
		return
	_dressing_sig = sig
	for c: Node in dressing_root.get_children():
		c.queue_free()
	var groups := {}
	for spec: Dictionary in SpawnDressingSpecs.specs():
		var off: Vector2i = spec["off"]
		var gtx := anchor.x + off.x
		var gty := anchor.y + off.y
		var info := _tile_info(gtx, gty)
		if info.is_empty():
			continue
		if bool(info["water"]) and str(spec["kind"]) != "hike_pool":
			continue
		var angle := float(spec.get("angle", 0.0))
		var scale := float(spec.get("scale", 1.0))
		var lift := float(spec.get("lift", 0.0))
		var pos := _tile_center_pos(gtx, gty, lift)
		var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
		var parts := PropMeshes.dressing_parts(str(spec["kind"]), int(spec.get("variant", 0)))
		_collect(parts, Transform3D(basis, pos), groups)
	_emit_groups(groups, dressing_root)


## Build the composed hiking-camp diorama anchored to the spawn tile, ONE time.
## Rebuilt only while chunks stream in (more pieces find ground each pass), then
## latched. Hidden when the player is on another layer (caves), shown on the
## overworld where the home campsite lives.
func _sync_spawn_dressing() -> void:
	dressing_root.visible = (world.current_layer == SPAWN_LAYER)
	if _spawn_dressing_built or world.current_layer != SPAWN_LAYER:
		return
	var specs := SpawnDressingSpecs.specs()
	var sg := _world_to_grid(WorldGen.spawn_position())
	var anchor := Vector2(roundi(sg.x), roundi(sg.y))
	# Cheap pre-pass: which pieces currently have loaded ground under them. Pieces
	# are fanned out from the anchor by DRESSING_SPREAD so nothing overlaps. This
	# count grows as the spawn chunks finish streaming, then settles.
	var placeable := []
	for spec: Dictionary in specs:
		var off: Vector2i = spec["off"]
		var cgx := anchor.x + float(off.x) * DRESSING_SPREAD + 0.5
		var cgy := anchor.y + float(off.y) * DRESSING_SPREAD + 0.5
		var info := _tile_info(floori(cgx), floori(cgy))
		if info.is_empty():
			continue
		if bool(info["water"]) and str(spec["kind"]) != "hike_pool":
			continue
		placeable.append(spec)
	# Latch once the placed set holds steady (all reachable ground has loaded), so
	# we stop re-evaluating every frame even if a far backdrop tile never streams.
	if placeable.size() == _spawn_placed:
		_spawn_stable += 1
		if _spawn_stable > 90 or placeable.size() >= specs.size():
			_spawn_dressing_built = true
		return
	_spawn_placed = placeable.size()
	_spawn_stable = 0
	var groups := {}
	for spec: Dictionary in placeable:
		var off: Vector2i = spec["off"]
		var cgx := anchor.x + float(off.x) * DRESSING_SPREAD + 0.5
		var cgy := anchor.y + float(off.y) * DRESSING_SPREAD + 0.5
		var angle := float(spec.get("angle", 0.0))
		var scale := float(spec.get("scale", 1.0))
		var lift := float(spec.get("lift", 0.0))
		var pos := Vector3(cgx * TILE_S, _grid_height(cgx, cgy) + lift, cgy * TILE_S)
		var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
		var parts := PropMeshes.dressing_parts(str(spec["kind"]), int(spec.get("variant", 0)))
		_collect(parts, Transform3D(basis, pos), groups)
	for c: Node in dressing_root.get_children():
		c.queue_free()
	_emit_groups(groups, dressing_root)


func _emit_groups(groups: Dictionary, root: Node3D) -> void:
	for key: String in groups:
		_emit_one_group(groups[key], root)


## Emit one (mesh,material) group as a MultiMeshInstance3D under `root`.
func _emit_one_group(g: Dictionary, root: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = g["mesh"]
	var xf: Array = g["xf"]
	var n := xf.size()
	mm.instance_count = n
	# Bulk-upload all instance transforms via the buffer in one call. The per-instance
	# set_instance_transform() loop was far slower; filling a flat PackedFloat32Array
	# (12 floats = the 3x4 affine, row-major) and assigning it once is cheaper. Layout
	# per Godot MultiMesh TRANSFORM_3D.
	var buf := PackedFloat32Array()
	buf.resize(n * 12)
	for i: int in n:
		var t: Transform3D = xf[i]
		var b := t.basis
		var o := t.origin
		var j := i * 12
		buf[j] = b.x.x;   buf[j + 1] = b.y.x;   buf[j + 2] = b.z.x;   buf[j + 3] = o.x
		buf[j + 4] = b.x.y; buf[j + 5] = b.y.y;  buf[j + 6] = b.z.y;   buf[j + 7] = o.y
		buf[j + 8] = b.x.z; buf[j + 9] = b.y.z;  buf[j + 10] = b.z.z;  buf[j + 11] = o.z
	if n > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = g["mat"]
	# A Short Hike-style soft drop shadows: props/trees/buildings cast onto the
	# ground (the toon shaders fold the cast region into their shadow band).
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


## World-Y just ABOVE the model's head, scaled to its size and body type — for
## floating UI (HP bars) that must clear the body, never sit inside it.
func mover_top(entity: Node) -> float:
	var n: Node3D = _player_node if entity == world.player else _mover_nodes.get(entity.get_instance_id())
	if n == null:
		return 2.4
	var base := float(n.get_meta("base_scale", 1.0))
	var h := 2.05   # humanoid rig top (head/hair ~2.0 local units)
	match str(n.get_meta("body3d", "humanoid")):
		"quadruped", "wolf": h = 1.4
		"bird": h = 1.05
	return base * h + 0.3


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
