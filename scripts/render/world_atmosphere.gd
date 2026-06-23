extends RefCounted
class_name WorldAtmosphere
## Owns the WorldEnvironment (warm haze sky + atmospheric depth fog) and the key DirectionalLight
## (extracted from the WorldRender3D monolith). Each frame it retunes the fog ramp, shadow
## distance and water detail-fade from the camera's VISUAL extent (TerrainStreamView) instead of
## a player-centred radius — so the fog is pushed OUTSIDE the comfortable camera footprint and
## never enters the foreground as a flat beige band, while still hiding the streamed terrain edge.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const CAM_DIST := WorldCameraRig3D.CAM_DIST

var world3d: Node3D
var _water_mat: ShaderMaterial
var _env: Environment
var _sun: DirectionalLight3D
# Clear-weather baselines, captured at setup so the per-frame weather grade lerps from a fixed
# reference instead of drifting. See _apply_weather().
var _sky_mat: ProceduralSkyMaterial
var _base_sky_hi: Color
var _base_sky_horizon: Color
var _base_ambient: Color
var _base_ambient_energy: float
var _base_fog: Color
var _base_sun_energy: float
var _base_sun_color: Color


func setup(w3d: Node3D, water_mat: ShaderMaterial) -> void:
	world3d = w3d
	_water_mat = water_mat
	_setup_environment()
	_setup_sun()
	GameSettings.changed.connect(func(p: StringName) -> void:
		if p == &"view_distance":
			apply_view_distance())


func _setup_environment() -> void:
	# Soft warm HAZE sky (A Short Hike-ish): a low-contrast warm wash, no cool blue top, so
	# wherever the terrain edge lands it meets a matching sky and dissolves instead of seaming.
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
	env.ambient_light_color = Color(0.5, 0.56, 0.47)
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Stylized atmospheric perspective (A Short Hike), NOT volumetric fog: a depth fog in the
	# SAME colour as the sky horizon. The per-frame update() pushes the ramp out past the
	# comfortable footprint; these are just the pre-first-frame defaults.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = horizon_col
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	# Safe far defaults so frame 1 (before the first update() retune) never flashes foreground fog.
	env.fog_depth_begin = 110.0
	env.fog_depth_end = 165.0
	env.fog_depth_curve = 2.0     # > 1 = hold the mid distance clear, then ramp hard at the end
	env.fog_sky_affect = 0.5
	env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world3d.add_child(we)
	_env = env
	# Capture clear-weather baselines for the per-frame weather grade.
	_sky_mat = sky_mat
	_base_sky_hi = sky_hi
	_base_sky_horizon = horizon_col
	_base_ambient = env.ambient_light_color
	_base_ambient_energy = env.ambient_light_energy
	_base_fog = horizon_col


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
	world3d.add_child(sun)
	_sun = sun
	_base_sun_energy = sun.light_energy
	_base_sun_color = sun.light_color


## Retune the fog ramp, shadow distance and water detail-fade from the camera's VISUAL extent.
## The fog START is pushed out near the far comfortable footprint (so the near/mid ground around
## the player stays crisp — no foreground beige band) and the END lands just past the streamed
## terrain edge (so the edge is still hidden, fading into the matching sky haze).
func update(_camera_rig: WorldCameraRig3D, stream_view: TerrainStreamView) -> void:
	if _env == null:
		return
	var vt := stream_view.approx_visual_extent_tiles()
	# Push fog out of the foreground: begin at ~74% of the visual extent (was 50%), end just past
	# the meshed edge so the boundary is hazed away into the same-colour sky.
	_env.fog_depth_begin = maxf(vt * 0.74, CAM_DIST + 16.0)
	_env.fog_depth_end = maxf(vt * 1.05, _env.fog_depth_begin + 8.0)
	if _water_mat != null:
		_water_mat.set_shader_parameter("detail_fade_begin", maxf(vt - 20.0, CAM_DIST))
		_water_mat.set_shader_parameter("detail_fade_end", maxf(vt - 2.0, CAM_DIST + 8.0))
	if _sun != null:
		# Shadows past the fogged range are invisible, so keeping them short is a free perf win.
		_sun.directional_shadow_max_distance = clampf(vt * 0.85, 30.0, 60.0)
	_apply_weather()


## Wash the sky / fog / ambient / sun toward the current weather: snow = cool white + brighter, flatter
## light; rain = cool blue-grey + dimmer, moodier light. Lerps from the clear-weather baselines so it's
## reversible and never accumulates. Reads the global Weather autoload.
func _apply_weather() -> void:
	var t: Color = Weather.tint
	var a: float = t.a
	var wash := Color(t.r, t.g, t.b)
	_env.ambient_light_color = _base_ambient.lerp(wash, a * 0.6)
	_env.ambient_light_energy = _base_ambient_energy * (1.0 + Weather.snow * 0.22 - Weather.rain * 0.22)
	_env.fog_light_color = _base_fog.lerp(wash, a * 0.7)
	_env.fog_sky_affect = 0.5 + (Weather.snow + Weather.rain) * 0.35   # precip thickens the haze
	if _sky_mat != null:
		var horizon := _base_sky_horizon.lerp(wash, a * 0.6)
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = horizon
		_sky_mat.ground_bottom_color = horizon
		_sky_mat.sky_top_color = _base_sky_hi.lerp(wash, a * 0.45)
	if _sun != null:
		_sun.light_energy = _base_sun_energy * (1.0 - Weather.rain * 0.42 - Weather.snow * 0.12)
		_sun.light_color = _base_sun_color.lerp(wash, a * 0.4)


## View-distance slider hook. The per-frame update() is the actual driver (it reads the live
## visual extent, which already scales with the slider), so this only exists for API/compat.
func apply_view_distance() -> void:
	pass


func get_environment() -> Environment:
	return _env


func get_sun() -> DirectionalLight3D:
	return _sun
