extends Node
## 3D pixel-art renderer for the live world (committed port — replaces the 2D
## draw output, no toggle). Hosts a low-resolution SubViewport with a 3D world
## (iso ortho Camera3D, one key light, toon materials, OUR palette), presented at
## nearest-neighbour under the full-res HUD. The 2D nodes remain as the logic
## substrate (positions, pathing, picking) but their visuals are hidden.
##
## Stage A: 3D terrain from real chunk data + camera follow.  Stage C adds props.

const WG := preload("res://scripts/worldgen/wg.gd")
const TOON_GROUND := preload("res://shaders/toon_ground.gdshader")
const TOON_WATER := preload("res://shaders/toon_water.gdshader")
const TOON_SHORE := preload("res://shaders/toon_shore.gdshader")
const PALETTE_SNAP := preload("res://shaders/palette_snap.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const EquipLoadout := preload("res://scripts/render/equip_loadout.gd")

const INTERNAL := Vector2i(640, 360)   # internal render res (higher = finer/less chunky pixels)
const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := 0.25                # height per elevation step (8px / 32px tile)
# Turn spring: a body accelerates into a turn and damps out of it (slightly
# underdamped for a snappy-but-physical settle), so facing changes are never instant.
const TURN_STIFFNESS := 62.0
const TURN_DAMPING := 14.0
const HURT_DUR := 0.2               # how long the take-a-hit red flash + shake lasts
const DRESSING_ANCHOR := 4          # visual set dressing snaps to this tile grid
const SPAWN_LAYER := 0              # overworld layer the home-campsite dressing lives on
const DRESSING_SPREAD := 1.7        # fan the camp pieces apart so nothing is squished
const FOREST_PREVIEW_ARG := "--forest-preview"

var world: Node2D
var sub: SubViewport
var world3d: Node3D
var cam: Camera3D
var present: TextureRect
var terrain_root: Node3D
var props_root: Node3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _shore_mat: ShaderMaterial
var _snap_mat: ShaderMaterial
var _occ_cache: Dictionary = {}   # global tile -> is_water (deterministic; persists)
var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_nbr: Dictionary = {}      # chunk key -> neighbour-data count at last build (seam reconcile)
var _chunk_wait: Dictionary = {}     # chunk key -> frames waited for neighbour data (defer fallback)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (O(1) height lookup)
var batches_root: Node3D             # holds the per-(mesh,material) MultiMeshInstance3D
var dressing_root: Node3D            # visual-only hiking-diorama silhouettes near camera
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
var _pixel_scale := 3             # INTEGER display px per internal px (nearest-neighbour, no fractional stretch)
# How the low-res image is placed on the window: an exact integer scale + centred offset.
# Kept here so screen<->internal-pixel picking math accounts for the integer presentation.
const PRESENT_OVERSCAN := 1   # internal-px margin per side, for the sub-pixel residual shift
var _present_scale := 1.0
var _present_off := Vector2.ZERO
var _present_base_off := Vector2.ZERO
var _static_sig := ""
var _ti_cache: Dictionary = {}       # per-frame memo: "gtx,gty" -> tile info (cleared each frame)
var _cc_cache: Dictionary = {}       # per-frame memo: "ci,cj" -> corner colour
var _batch_rebuild_t := 0.0          # last static-batch rebuild time (throttle)
const BATCH_REBUILD_MIN := 0.35      # min seconds between static-batch rebuilds
var _dressing_sig := ""
var _spawn_placed := -1               # how many camp-dressing pieces have ground so far
var _spawn_stable := 0                # frames the placed count has held steady
var _spawn_dressing_built := false    # latched true once the whole camp scene is placed
var _forest_preview_done := false
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

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)   # lower afternoon sun -> longer soft shadows
	sun.light_color = Color(1.0, 0.95, 0.8)    # warm afternoon daylight
	sun.light_energy = 1.0                     # softer key light for a moodier, earthy look
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.9
	sun.shadow_blur = 1.5   # soft A Short Hike shadow edge (low-res render keeps it crisp)
	world3d.add_child(sun)
	_sun = sun
	_apply_view_distance()   # set terrain cull / fog distance / shadow distance from the slider
	GameSettings.changed.connect(func(p: StringName) -> void:
		if p == &"view_distance":
			_apply_view_distance())

	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.8
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)

	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)
	batches_root = Node3D.new()
	world3d.add_child(batches_root)
	dressing_root = Node3D.new()
	world3d.add_child(dressing_root)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("grass_dark"))   # deeper mossy shade so cast shadows read
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("hike_grass_light"))
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
	# Deep-blue ocean with MID-scale domain-warped contour loops (between the old dense
	# version and the over-large one): clear medium/large irregular loops, plenty of dark
	# negative space. World-space sampled (camera-stable). The visible shallow band is the
	# separate shore overlay below — this just fades its own contours out near the coast.
	_water_mat.set_shader_parameter("base_color", Color(0.067, 0.380, 0.498))      # #11617F deep
	_water_mat.set_shader_parameter("secondary_color", Color(0.090, 0.431, 0.537)) # #176E89 subtle var
	_water_mat.set_shader_parameter("line_color", Color(0.290, 0.588, 0.655))      # #4A96A7 lines
	_water_mat.set_shader_parameter("pattern_scale", 0.072)       # mid features (dense 0.105 .. sparse 0.032)
	_water_mat.set_shader_parameter("contour_count", 3.5)         # medium line density / spacing
	_water_mat.set_shader_parameter("line_width", 0.038)
	_water_mat.set_shader_parameter("line_opacity", 0.6)
	_water_mat.set_shader_parameter("domain_warp_strength", 0.6)
	_water_mat.set_shader_parameter("secondary_strength", 0.28)   # weak secondary detail only
	_water_mat.set_shader_parameter("secondary_scale", 1.7)
	_water_mat.set_shader_parameter("primary_speed", Vector2(0.006, 0.003))
	_water_mat.set_shader_parameter("secondary_speed", Vector2(-0.003, 0.005))
	_water_mat.set_shader_parameter("sd_scale", SHORE_SD_SCALE)
	_water_mat.set_shader_parameter("coast_cut", -0.1)            # deep water laps slightly under overlay
	_water_mat.set_shader_parameter("contour_fade_in", 0.55)      # cells: contours start returning
	_water_mat.set_shader_parameter("contour_fade_out", 1.15)     # cells: contours fully back
	_water_mat.set_shader_parameter("noise_tex", _make_water_noise(0.9, 2, 1))
	_water_mat.set_shader_parameter("warp_tex", _make_water_noise(0.35, 2, 2))

	# Render-only coastal overlay: wet-sand + two-tone aqua bands hiding the coastline
	# teeth. Driven by the SAME smoothed water-fraction field (UV.x) as the water mesh.
	_shore_mat = ShaderMaterial.new()
	_shore_mat.shader = TOON_SHORE
	_shore_mat.set_shader_parameter("wet_sand_color", Color(0.788, 0.678, 0.451)) # #C9AD73
	_shore_mat.set_shader_parameter("inner_color", Color(0.510, 0.820, 0.796))    # #82D1CB light aqua
	_shore_mat.set_shader_parameter("outer_color", Color(0.263, 0.682, 0.698))    # #43AEB2 turquoise
	_shore_mat.set_shader_parameter("sd_scale", SHORE_SD_SCALE)
	_shore_mat.set_shader_parameter("wet_cells", 0.26)
	_shore_mat.set_shader_parameter("inner_cells", 0.30)
	_shore_mat.set_shader_parameter("outer_cells", 0.50)
	_shore_mat.set_shader_parameter("fade_cells", 0.22)
	_shore_mat.set_shader_parameter("width_var", 0.22)
	_shore_mat.set_shader_parameter("var_scale", 0.05)
	_shore_mat.set_shader_parameter("var_noise", _make_water_noise(0.5, 2, 4))

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
	# Pixelation is controlled from the Settings menu (GameSettings.pixelation).
	_pixel_scale = _scale_from_setting(GameSettings.pixelation)
	GameSettings.changed.connect(_on_settings_changed)


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
	for node: Node in world.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false


# ----------------------------------------------------------------- runtime ----

func _process(delta: float) -> void:
	if not _active or world.player == null:
		return
	_maybe_teleport_to_forest_preview()
	# Per-frame memo for tile-info/corner-colour sampling (terrain build + every mover
	# height sample hit the same tiles thousands of times in a frame).
	_ti_cache.clear()
	_cc_cache.clear()
	_apply_pixelation()   # keeps render res matched to the window + pixelation slider
	_update_camera_input(delta)
	_sync_camera()
	_sync_terrain()
	_sync_movers()
	_sync_static_batches()
	# Compose the cozy A Short Hike camp ONCE around the spawn tile (the home
	# campsite). Anchored to spawn, NOT the camera — so it's a finished place you
	# arrive at, not canned props that follow you everywhere (the old failure mode).
	_sync_spawn_dressing()
	_frames += 1
	var capture_frame := 150 if _forest_preview_enabled() else 90
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
	if Input.is_key_pressed(KEY_LEFT):
		_cam_yaw -= CAM_YAW_SPEED * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_yaw += CAM_YAW_SPEED * delta
	if Input.is_key_pressed(KEY_UP):
		_cam_pitch = clampf(_cam_pitch + CAM_PITCH_SPEED * delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
	if Input.is_key_pressed(KEY_DOWN):
		_cam_pitch = clampf(_cam_pitch - CAM_PITCH_SPEED * delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
	_cam_yaw = wrapf(_cam_yaw, -PI, PI)


func _sync_camera() -> void:
	var c := iso_to_3d(world.player.position, height_at(world.player.position))
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
	if pick != "":
		var node := _build_chunk_terrain(_chunk_by_key[pick])
		terrain_root.add_child(node)
		_chunk_meshes[pick] = node
		_chunk_nbr[pick] = _data_nbr_count(pick)
		_chunk_wait.erase(pick)
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


const WATER_DROP := 0.45   # how far the ground floor dips under water (shore basin)
const SHORE := Color(0.80, 0.75, 0.58)  # sandy shore tone under/at water edges
const PATH_TILES := ["dirt", "cobble", "mud", "gravel", "badland_clay"]
const ROCK_TILES := ["rock", "lava_rock", "ash"]

## Smooth, continuous, SEAMLESS terrain: each grid corner's height/normal/color
## is averaged from the tiles around it (sampled globally so chunk borders match),
## giving rolling sculpted land instead of flat terraced diamonds. Water tiles dip
## the floor into a basin and get a separate animated water surface on top.
func _build_chunk_terrain(chunk: RefCounted) -> Node3D:
	var n := WG.CHUNK_TILES
	var cx0: int = int(chunk.cx) * n
	var cy0: int = int(chunk.cy) * n
	var hc := {}  # memoized corner heights
	var wfc := {}  # memoized corner water-fraction (the ONE shared coastline field)
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
			# Four shared corners (continuous across cells -> smooth surface).
			_emit_corner(st, gtx, gty, hc, wfc)
			_emit_corner(st, gtx + 1, gty, hc, wfc)
			_emit_corner(st, gtx + 1, gty + 1, hc, wfc)
			_emit_corner(st, gtx, gty, hc, wfc)
			_emit_corner(st, gtx + 1, gty + 1, hc, wfc)
			_emit_corner(st, gtx, gty + 1, hc, wfc)
			var info := _tile_info(gtx, gty)
			if not info.is_empty() and bool(info["water"]):
				has_water = true
				var wy: float = _water_surface_height(info)
				var x0 := float(gtx) * TILE_S
				var z0 := float(gty) * TILE_S
				var x1 := x0 + TILE_S
				var z1 := z0 + TILE_S
				# Bake the SHARED smoothed water-fraction field at each corner into UV.x
				# (same field the shore overlay uses), so the deep-mesh coast discard and
				# the overlay bands derive from ONE source and can never open a seam.
				var fA := _coast_wf(gtx, gty, wfc)
				var fB := _coast_wf(gtx + 1, gty, wfc)
				var fC := _coast_wf(gtx + 1, gty + 1, wfc)
				var fD := _coast_wf(gtx, gty + 1, wfc)
				var quad := [
					[Vector3(x0, wy, z0), fA], [Vector3(x1, wy, z0), fB], [Vector3(x1, wy, z1), fC],
					[Vector3(x0, wy, z0), fA], [Vector3(x1, wy, z1), fC], [Vector3(x0, wy, z1), fD],
				]
				for p: Array in quad:
					wst.set_normal(Vector3.UP)
					wst.set_uv(Vector2(float(p[1]), 0.0))
					wst.add_vertex(p[0])
	# Coastal overlay: a smooth two-tone aqua band draped just above the coast that hides
	# the ground mesh's per-tile triangulation teeth. Covers any tile straddling/near the
	# smoothed coastline; the shader (driven by the per-vertex smoothed water-fraction in
	# UV.x) decides where it's land (transparent), inner aqua, outer turquoise, or deep.
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_shore := false
	for ty: int in n:
		for tx: int in n:
			var gtx := cx0 + tx
			var gty := cy0 + ty
			var w00 := _coast_wf(gtx, gty, wfc)
			var w10 := _coast_wf(gtx + 1, gty, wfc)
			var w11 := _coast_wf(gtx + 1, gty + 1, wfc)
			var w01 := _coast_wf(gtx, gty + 1, wfc)
			var wmax: float = maxf(maxf(w00, w10), maxf(w11, w01))
			var wmin: float = minf(minf(w00, w10), minf(w11, w01))
			if wmax <= 0.08 or wmin >= 0.98:
				continue   # fully dry inland (no band) or open deep water (deep mesh only)
			has_shore = true
			var x0 := float(gtx) * TILE_S
			var z0 := float(gty) * TILE_S
			var x1 := x0 + TILE_S
			var z1 := z0 + TILE_S
			var yA := _coast_corner_height(gtx, gty, hc)
			var yB := _coast_corner_height(gtx + 1, gty, hc)
			var yC := _coast_corner_height(gtx + 1, gty + 1, hc)
			var yD := _coast_corner_height(gtx, gty + 1, hc)
			var quad := [
				[Vector3(x0, yA, z0), w00], [Vector3(x1, yB, z0), w10], [Vector3(x1, yC, z1), w11],
				[Vector3(x0, yA, z0), w00], [Vector3(x1, yC, z1), w11], [Vector3(x0, yD, z1), w01],
			]
			for p: Array in quad:
				sst.set_normal(Vector3.UP)
				sst.set_uv(Vector2(float(p[1]), 0.0))
				sst.add_vertex(p[0])
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
	if has_shore:
		var shore := MeshInstance3D.new()
		shore.mesh = sst.commit()
		shore.material_override = _shore_mat
		shore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shore)
	return root


func _emit_corner(st: SurfaceTool, ci: int, cj: int, hc: Dictionary, wfc: Dictionary) -> void:
	var h := _corner_height(ci, cj, hc)
	# Smooth normal from the height field (central differences over the corners).
	var hx := _corner_height(ci + 1, cj, hc) - _corner_height(ci - 1, cj, hc)
	var hz := _corner_height(ci, cj + 1, hc) - _corner_height(ci, cj - 1, hc)
	st.set_normal(Vector3(-hx, 2.0 * TILE_S, -hz).normalized())
	st.set_color(_corner_color(ci, cj))
	# UV carries beach data for toon_ground: y = beach fraction (sand vs other, smoothed
	# over the corner so the sand/grass edge can be dithered), x = wetness from the shared
	# coast field (sand darkens/saturates near the waterline).
	var beach := _corner_beach(ci, cj)
	var wet: float = clampf((_coast_wf(ci, cj, wfc) - 0.30) / 0.16, 0.0, 1.0) if beach > 0.0 else 0.0
	st.set_uv(Vector2(wet, beach))
	st.add_vertex(Vector3(float(ci) * TILE_S, h, float(cj) * TILE_S))


# Beach fraction at a grid corner: how many of the 4 touching tiles are sand (0..1). A
# fractional value near the biome edge lets the shader dither the sand/grass boundary.
func _corner_beach(ci: int, cj: int) -> float:
	var cnt := 0
	var sand := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if info.is_empty():
			continue
		cnt += 1
		if str(info["tile"]) in ["sand", "sand_dune"]:
			sand += 1
	return float(sand) / float(cnt) if cnt > 0 else 0.0


func _corner_height(ci: int, cj: int, hc: Dictionary) -> float:
	var key := "%d,%d" % [ci, cj]
	if hc.has(key):
		return hc[key]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			sum += _visual_floor_height(ci + off.x, cj + off.y, info)
			cnt += 1
	var h: float = sum / float(cnt) if cnt > 0 else 0.0
	hc[key] = h
	return h


func _corner_color(ci: int, cj: int) -> Color:
	var ck := "%d,%d" % [ci, cj]
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
	var cache_key := "%d,%d" % [gtx, gty]
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
	var water := bool(tdef.get("water", false))
	var top: float = float(chunk.elev[ly * WG.CHUNK_TILES + lx]) * ELEV_H
	var col: Color = SHORE if water else _grade_ground(tdef["colors"][0], tile_name, gtx, gty)
	return {
		"top": top,
		"water": water,
		"tile": tile_name,
		"col": col,
	}


func _visual_floor_height(gtx: int, gty: int, info: Dictionary) -> float:
	var top := float(info["top"])
	var tile := str(info["tile"])
	if bool(info["water"]):
		var extra := 0.18 if tile == "deep_water" else (0.08 if tile == "water" else 0.0)
		return top - WATER_DROP - extra
	var hill := _rolling_hill(gtx, gty)
	if _is_path(tile):
		return top + hill * 0.28 - 0.055
	if _is_rock(tile):
		return top + hill * 0.78 + _rocky_lift(gtx, gty)
	return top + hill


func _water_surface_height(info: Dictionary) -> float:
	return float(info["top"]) - 0.035


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


func _surface_family(tile: String) -> String:
	if tile in ["deep_water", "water", "shallow"]:
		return "water"
	if _is_path(tile):
		return "path"
	if _is_rock(tile):
		return "rock"
	if tile in ["sand", "sand_dune"]:
		return "sand"
	if tile == "snow" or tile == "frozen_grass":
		return "snow"
	return "grass"


func _is_path(tile: String) -> bool:
	return tile in PATH_TILES


func _is_rock(tile: String) -> bool:
	return tile in ROCK_TILES


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


# Deterministic water occupancy for ANY global tile (no chunk load needed), so the
# coastline overlay is identical regardless of streaming order -> seamless across chunk
# borders. Cached for the whole session (the worldgen result never changes).
func _coast_water(gtx: int, gty: int) -> bool:
	var key := Vector2i(gtx, gty)
	if _occ_cache.has(key):
		return _occ_cache[key]
	var td := WorldGen.surface_tile_def_at(gtx, gty)
	var w := not td.is_empty() and bool(td.get("water", false))
	_occ_cache[key] = w
	return w


# Low-passed water fraction (0 land .. 1 open water) at a grid CORNER. A DISTANCE-WEIGHTED
# (triangular) kernel over a radius-3 neighbourhood: this is THE one authoritative coastline
# field. The weighting (centre tiles count most) gives a smooth, rounded 0.5 iso-line — broad
# stylized bends instead of tile staircases — while keeping the contour within ~half a cell
# of the true boundary (so bays/peninsulas are preserved). Both the water mesh and the shore
# overlay read this same field, so their layers can never disagree. Memoized over shared
# corners so neighbouring tiles agree exactly (no cracks).
const SHORE_SMOOTH := 3
const SHORE_SD_SCALE := 4.0   # maps (wf - 0.5) -> signed distance to coast, in cells
func _coast_wf(ci: int, cj: int, wfc: Dictionary) -> float:
	var key := Vector2i(ci, cj)
	if wfc.has(key):
		return wfc[key]
	var sum := 0.0
	var wsum := 0.0
	for dy: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
		for dx: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
			# Tile (ci+dx, cj+dy) sits with its centre 0.5 off the corner; weight by a
			# triangular falloff so the centre dominates (smooth, low displacement).
			var rx := absf(float(dx) + 0.5)
			var ry := absf(float(dy) + 0.5)
			var w: float = maxf(0.0, float(SHORE_SMOOTH) - maxf(rx, ry))
			if w <= 0.0:
				continue
			if _coast_water(ci + dx, cj + dy):
				sum += w
			wsum += w
	var wf: float = sum / wsum if wsum > 0.0 else 0.0
	wfc[key] = wf
	return wf


# Drape height for the coastal overlay at a grid corner: sit just above BOTH the local
# terrain and the water surface so the aqua reliably covers the tan teeth and never
# z-fights. Over water corners the terrain floor is the basin (below sea) so the sea
# level wins; over the low beach the terrain wins.
const COAST_LIFT := 0.06
func _coast_corner_height(ci: int, cj: int, hc: Dictionary) -> float:
	var g := _corner_height(ci, cj, hc)
	var sea := -1.0e9
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty() and bool(info["water"]):
			sea = maxf(sea, _water_surface_height(info))
	if sea < -1.0e8:
		return g + COAST_LIFT
	return maxf(sea, g) + COAST_LIFT


## Warm + enrich a terrain tile color and add BROAD low-frequency variation
## (large painted regions, not noise) so the ground reads painterly, not as flat
## monotone diamonds. Original warm grading — our palette, A Short Hike vibe.
func _grade_ground(col: Color, tile: String, gtx: int, gty: int) -> Color:
	var c := col
	var fx := float(gtx)
	var fz := float(gty)
	# Three broad low-frequency bands (no noise) -> painterly sunlit/shaded
	# gradients across the ground like A Short Hike.
	var bright := 0.5 + 0.5 * sin(fx * 0.07) * cos(fz * 0.06)
	var band2 := 0.5 + 0.5 * sin(fx * 0.13 + 1.2) * cos(fz * 0.115 - 0.7)
	var warm := clampf(sin((fx + fz) * 0.045 + 1.3), 0.0, 1.0)
	if _is_path(tile):
		var path_col := PixelPalette.pal("path_orange").lerp(PixelPalette.pal("path_light"), bright * 0.42)
		c = c.lerp(path_col, 0.94)
	elif _is_rock(tile):
		c = c.lerp(PixelPalette.pal("cliff_warm").lerp(PixelPalette.pal("cliff_light"), bright * 0.34), 0.78)
	elif tile in ["sand", "sand_dune"]:
		c = c.lerp(PixelPalette.pal("warm_stone"), 0.5)
	else:
		# Deep-forest grass gradient: mid foliage -> sunlit grass across the broad
		# bright band, drifting toward leaf-green/forest-green in shaded regions and
		# a moss highlight in others. No lime.
		var grass := PixelPalette.pal("mid_foliage").lerp(PixelPalette.pal("sunlit_grass"), bright)
		grass = grass.lerp(PixelPalette.pal("leaf_green"), (1.0 - band2) * 0.45)
		grass = grass.lerp(PixelPalette.pal("forest_green"), (1.0 - bright) * 0.2)
		grass = grass.lerp(PixelPalette.pal("moss_hi"), warm * 0.18)
		c = c.lerp(grass, 0.82)
	return c


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


## Batch all static decor + props into per-(mesh,material) MultiMeshes. Rebuilt
## only when the static set changes (or a periodic safety pass), not every frame.
## Static props are batched into MultiMeshes ONCE per change of the prop SET — NOT
## per player move. The old trigger keyed on the player's chunk + a per-prop distance
## cull, so crossing any chunk boundary rebuilt every batch (an 8-18ms hitch on every
## few steps). Now the trigger is just the loaded prop counts (which change only when
## chunks stream in/out or async decor finishes spawning), the props are gated by
## chunk-load not player distance (instanced rendering makes the extra props ~free),
## and rebuilds are throttled so a burst of streaming can't hitch every frame.
func _sync_static_batches() -> void:
	var sig := "%s:%d:%d:%d" % [str(world.current_layer), int(world._decor_nodes.size()), int(world._water_decor_nodes.size()), int(world.entities.size())]
	if sig == _static_sig:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _batch_rebuild_t < BATCH_REBUILD_MIN:
		return                                  # throttle: let a streaming burst settle
	_static_sig = sig
	_batch_rebuild_t = now
	for c: Node in batches_root.get_children():
		c.queue_free()
	var groups := {}
	for d: Node in world._decor_nodes:
		if not is_instance_valid(d):
			continue
		var pl := Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.131), iso_to_3d(d.position, height_at(d.position)))
		_collect(PropMeshes.decor_parts(str(d.kind)), pl, groups)
	for d: Node in world._water_decor_nodes:
		if not is_instance_valid(d):
			continue
		var pl := Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.17), iso_to_3d(d.position, height_at(d.position) + 0.04))
		_collect(PropMeshes.water_decor_parts(str(d.kind)), pl, groups)
	for e: Node in world.entities:
		if not is_instance_valid(e) or PropMeshes.is_moving(e):
			continue
		var parts: Array = PropMeshes.entity_parts(e)
		if parts.is_empty():
			continue
		_collect(parts, Transform3D(Basis.IDENTITY, iso_to_3d(e.position, height_at(e.position))), groups)
	_emit_groups(groups, batches_root)


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
	for spec: Dictionary in _hike_dressing_specs():
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
	var specs := _hike_dressing_specs()
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
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		var xf: Array = g["xf"]
		mm.instance_count = xf.size()
		for i: int in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		# A Short Hike-style soft drop shadows: props/trees/buildings cast onto the
		# ground (the toon shaders fold the cast region into their shadow band).
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)


## The composed home-camp diorama, laid out in concentric rings around spawn so
## it reads like a real A Short Hike clearing from any zoom: an OPEN middle
## (campfire, sign, low props), the hero buildings set just back, a vivid autumn
## color band, then a dense conifer + layered-cliff backdrop framing the bowl.
## Camera looks from +X/+Z, so −X/−Z is the visible "back wall"; big trees live
## there and on the wings, never in the foreground covering the camp.
func _hike_dressing_specs() -> Array:
	var specs := []

	# --- Paths: two soft trails meeting at the camp, then out to the trailhead.
	var path := [
		# trailhead coming in from the front-left, curving up to the cabin door
		Vector2i(-2, 5), Vector2i(-2, 4), Vector2i(-3, 3), Vector2i(-3, 2),
		Vector2i(-4, 1), Vector2i(-4, 0), Vector2i(-4, -1),
		# spur across the clearing to the lodge on the right
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(3, -1), Vector2i(4, -2)]
	for i: int in path.size():
		specs.append({"kind": "hike_path", "off": path[i], "angle": -0.55 + float(i % 5) * 0.14, "scale": 0.92 + float(i % 4) * 0.06, "lift": 0.035, "variant": i})

	# --- Hero structures + the open central clearing (campfire & seating).
	specs.append_array([
		{"kind": "hike_cabin", "off": Vector2i(-4, -2), "angle": -0.58, "scale": 1.0, "variant": 0},
		{"kind": "hike_lodge", "off": Vector2i(4, -2), "angle": -0.72, "scale": 0.96, "variant": 1},
		{"kind": "hike_campfire", "off": Vector2i(-1, 0), "angle": 0.2, "scale": 1.3, "lift": 0.04, "variant": 1},
		{"kind": "hike_sign", "off": Vector2i(-2, 4), "angle": -0.35, "scale": 1.08, "variant": 0},
		{"kind": "hike_bench", "off": Vector2i(0, 1), "angle": -0.7, "scale": 1.12, "variant": 0},
		{"kind": "hike_bench", "off": Vector2i(-2, -1), "angle": 0.55, "scale": 1.05, "variant": 1},
		{"kind": "hike_log", "off": Vector2i(1, 1), "angle": 0.5, "scale": 1.3, "variant": 1},
		{"kind": "hike_log", "off": Vector2i(-2, 2), "angle": -0.25, "scale": 1.0, "variant": 2},
		{"kind": "hike_stump", "off": Vector2i(2, 1), "angle": 0.0, "scale": 1.05, "variant": 0},
		{"kind": "hike_stump", "off": Vector2i(-5, 1), "angle": 0.0, "scale": 0.95, "variant": 1},
		# a teal hiking pool tucked into the front-left, foam-edged by the terrain
		{"kind": "hike_pool", "off": Vector2i(-6, 5), "angle": 0.24, "scale": 1.8, "lift": 0.02, "variant": 0},
	])

	# --- Boulders: a few big warm slabs bedding the camp into the slope.
	for b: Dictionary in [
			{"off": Vector2i(3, 2), "angle": 0.4, "scale": 1.2},
			{"off": Vector2i(-6, -1), "angle": -0.2, "scale": 1.05},
			{"off": Vector2i(5, 1), "angle": 0.9, "scale": 0.95},
			{"off": Vector2i(-5, 3), "angle": 0.1, "scale": 0.85}]:
		specs.append({"kind": "hike_boulder", "off": b["off"], "angle": b["angle"], "scale": b["scale"], "variant": int(b["off"].x) & 1})

	# --- Autumn color band: the vivid red/orange/gold canopies ringing the bowl
	#     (mid radius). Kept out of the near-foreground so they frame, not cover.
	var leaves := [
		Vector2i(-7, 2), Vector2i(-7, 0), Vector2i(-6, -3), Vector2i(-4, -4),
		Vector2i(-1, -4), Vector2i(2, -4), Vector2i(5, -4), Vector2i(7, -2),
		Vector2i(7, 0), Vector2i(6, 2), Vector2i(-8, 4), Vector2i(8, 3),
		Vector2i(-3, -3), Vector2i(3, -3)]
	for i: int in leaves.size():
		specs.append({"kind": "hike_deciduous", "off": leaves[i], "angle": float(i) * 0.29, "scale": 0.95 + float(i % 4) * 0.13, "variant": i})

	# --- Conifer backdrop: a dense pine wall behind and along the wings (image 2).
	var conifers := [
		Vector2i(-10, -3), Vector2i(-9, -5), Vector2i(-8, -7), Vector2i(-6, -6),
		Vector2i(-5, -5), Vector2i(-3, -6), Vector2i(-1, -7), Vector2i(1, -7),
		Vector2i(3, -6), Vector2i(5, -6), Vector2i(6, -5), Vector2i(8, -5),
		Vector2i(9, -3), Vector2i(10, -1), Vector2i(9, 1), Vector2i(-9, 1),
		Vector2i(-10, 3), Vector2i(10, 2), Vector2i(-7, -8), Vector2i(7, -7)]
	for i: int in conifers.size():
		specs.append({"kind": "hike_conifer", "off": conifers[i], "angle": float(i) * 0.37, "scale": 1.12 + float(i % 4) * 0.12, "variant": i})

	# --- Layered cliff back-wall: warm stone slabs across the deep background.
	var cliffs := [
		Vector2i(-10, -8), Vector2i(-8, -9), Vector2i(-6, -9), Vector2i(-4, -9),
		Vector2i(-2, -10), Vector2i(0, -10), Vector2i(2, -9), Vector2i(4, -9),
		Vector2i(6, -8), Vector2i(8, -8), Vector2i(9, -6), Vector2i(-10, -6),
		Vector2i(-11, -3), Vector2i(10, -4)]
	for i: int in cliffs.size():
		specs.append({"kind": "hike_cliff", "off": cliffs[i], "angle": 0.08 + float(i) * 0.14, "scale": 1.3 - float(i % 3) * 0.08, "variant": i})

	# --- Split-rail fence arcing around the front edge of the clearing.
	var fences := [
		{"off": Vector2i(-4, 4), "angle": 0.55}, {"off": Vector2i(-2, 5), "angle": -0.12},
		{"off": Vector2i(0, 5), "angle": 0.0}, {"off": Vector2i(2, 4), "angle": 0.2},
		{"off": Vector2i(4, 3), "angle": 0.7}, {"off": Vector2i(5, 2), "angle": 0.88},
		{"off": Vector2i(-6, 2), "angle": 0.78}, {"off": Vector2i(-6, 0), "angle": 0.88}]
	for i: int in fences.size():
		var f: Dictionary = fences[i]
		specs.append({"kind": "hike_fence", "off": f["off"], "angle": f["angle"], "scale": 1.08, "variant": i})

	# --- Flower beds and mushrooms freshening the clearing edges.
	var flowers := [
		Vector2i(-3, 1), Vector2i(-1, 2), Vector2i(0, 3), Vector2i(2, 2),
		Vector2i(-4, 3), Vector2i(1, 3), Vector2i(3, 1), Vector2i(-5, 0),
		Vector2i(-3, 3), Vector2i(2, 3), Vector2i(-2, 3), Vector2i(4, 2)]
	for i: int in flowers.size():
		specs.append({"kind": "hike_flower", "off": flowers[i], "angle": float(i) * 0.2, "scale": 1.0 + float(i % 2) * 0.2, "lift": 0.02, "variant": i})
	specs.append_array([
		{"kind": "hike_mushroom", "off": Vector2i(-5, 4), "angle": 0.2, "scale": 1.05, "variant": 0},
		{"kind": "hike_mushroom", "off": Vector2i(3, 3), "angle": -0.3, "scale": 0.92, "variant": 1},
	])

	# --- Scattered ground clutter (leaf litter, grass tufts, pebbles), thinned
	#     out of the central clearing so the camp stays readable.
	var clutter := ["hike_leaf_litter", "hike_grass", "hike_pebbles", "hike_grass", "hike_leaf_litter", "hike_mushroom"]
	for i: int in range(58):
		var ox := int((i * 5) % 21) - 10
		var oy := int((i * 7 + int(i / 3)) % 19) - 9
		if absi(ox) <= 2 and absi(oy) <= 2:
			continue
		var kind: String = clutter[i % clutter.size()]
		var scale := 0.72 + float((i * 3) % 5) * 0.09
		specs.append({"kind": kind, "off": Vector2i(ox, oy), "angle": float(i) * 0.41, "scale": scale, "lift": 0.018, "variant": i})
	return specs


func _collect(parts: Array, placement: Transform3D, groups: Dictionary) -> void:
	for p: Dictionary in parts:
		var key := str(p["mesh"].get_instance_id()) + "|" + str(p["mat"].get_instance_id())
		if not groups.has(key):
			groups[key] = {"mesh": p["mesh"], "mat": p["mat"], "xf": []}
		var local := Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		groups[key]["xf"].append(placement * local)


## Map a 2D iso-pixel position to a 3D world position (Y from elevation/height).
func iso_to_3d(pos: Vector2, y: float) -> Vector3:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	return Vector3(gx * TILE_S, y, gy * TILE_S)


func _world_to_grid(pos: Vector2) -> Vector2:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	return Vector2(gx, gy)


func _near_visual_grid(pos: Vector2, radius_tiles: float) -> bool:
	var g := _world_to_grid(pos)
	var p := _world_to_grid(world.player.position)
	return absf(g.x - p.x) <= radius_tiles and absf(g.y - p.y) <= radius_tiles


func _tile_center_pos(gtx: int, gty: int, lift := 0.0) -> Vector3:
	var info := _tile_info(gtx, gty)
	var h := 0.0
	if not info.is_empty() and bool(info["water"]):
		h = _water_surface_height(info)
	elif not info.is_empty():
		var hc := {}
		h = (_corner_height(gtx, gty, hc) + _corner_height(gtx + 1, gty, hc) + _corner_height(gtx, gty + 1, hc) + _corner_height(gtx + 1, gty + 1, hc)) * 0.25
	return Vector3((float(gtx) + 0.5) * TILE_S, h + lift, (float(gty) + 0.5) * TILE_S)


## Terrain height (3D Y) at a 2D iso position, sampled from the loaded chunk.
func height_at(pos: Vector2) -> float:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	return _grid_height(gx, gy)


## Terrain height (3D Y) at fractional grid coordinates (gx,gy = 3D x/z over TILE_S).
func _grid_height(gx: float, gy: float) -> float:
	var t := Vector2i(floori(gx), floori(gy))
	var info := _tile_info(t.x, t.y)
	if not info.is_empty() and bool(info["water"]):
		return _water_surface_height(info)
	var hc := {}
	var fx := gx - floorf(gx)
	var fy := gy - floorf(gy)
	var h00 := _corner_height(t.x, t.y, hc)
	var h10 := _corner_height(t.x + 1, t.y, hc)
	var h01 := _corner_height(t.x, t.y + 1, hc)
	var h11 := _corner_height(t.x + 1, t.y + 1, hc)
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
	var gx := hit.x / TILE_S
	var gy := hit.z / TILE_S
	return Vector2((gx - gy) * WG.ISO_HW, (gx + gy) * WG.ISO_HH)


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


## Intersect a ray with the terrain height field. The surface isn't flat, so we
## intersect a horizontal plane, sample the ground height there, and re-intersect
## a couple of times — converges fast on the gentle hike terrain.
func _ray_to_ground(origin: Vector3, dir: Vector3) -> Vector3:
	if absf(dir.y) < 0.00001:
		return origin
	var y := 0.0
	var hit := origin
	for _i: int in 4:
		var t: float = (y - origin.y) / dir.y
		if t < 0.0:
			t = 0.0
		hit = origin + dir * t
		y = _grid_height(hit.x / TILE_S, hit.z / TILE_S)
	return hit


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
