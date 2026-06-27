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
var _ground_mat: ShaderMaterial      # terrain ground: only its uniform `terrain_mood` is driven here
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
var editor_no_fog := false      # world editor: kill depth fog so the aerial view shows the whole map


func setup(w3d: Node3D, water_mat: ShaderMaterial, ground_mat: ShaderMaterial = null) -> void:
	world3d = w3d
	_water_mat = water_mat
	_ground_mat = ground_mat
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
	# Colour-grade post pass (used by the day/night grade to richen dusk; 1.0 = neutral otherwise).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
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


## Sun direction (pitch, yaw, roll). Steady angle so shadows never slide as the day/night cycle
## advances — only the sun's colour/energy change with time (see _apply_grade). DEFAULT is a lower
## afternoon sun; tunable live via set_sun_direction (admin slider) to dial in the look.
const SUN_DIR_DEG := Vector3(-38, 40, 0)   # lower afternoon sun -> longer soft shadows
var sun_dir_deg := SUN_DIR_DEG


## Set the (fixed) sun pitch/yaw live — used by the admin "Sun direction" sliders to find a look.
func set_sun_direction(pitch: float, yaw: float) -> void:
	sun_dir_deg = Vector3(pitch, yaw, 0.0)
	if _sun != null:
		_sun.rotation_degrees = sun_dir_deg


func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_dir_deg
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
	# Editor aerial view: no distance fog — show all the streamed terrain crisply to the edge.
	if editor_no_fog:
		_env.fog_enabled = false
		# CRITICAL: with no fog AND the aerial camera pulled far back, every water vertex sits past
		# the water shader's default detail-LOD cutoff (16..34), which would collapse the whole sea
		# to the flat muted "distant" tone (the bug: uniform teal, no shallows/foam/shoreline). Push
		# the detail fade out beyond the entire aerial view so the shallow→deep gradient, illustrated
		# contours and shoreline foam render across the map — i.e. water that looks like the game.
		if _water_mat != null:
			_water_mat.set_shader_parameter("detail_fade_begin", 1.0e6)
			_water_mat.set_shader_parameter("detail_fade_end", 1.0e6 + 1.0)
			# But at AERIAL scale the bright cyan shallow band reads as a halo tracing every coast
			# across the whole map. Mute the shallow tone toward the deep ocean and tighten the band
			# so the FOAM line alone marks the shoreline — no light-blue rim. (Editor material only;
			# the player-height game view keeps its lit shallows — its mat never hits this branch.)
			_water_mat.set_shader_parameter("shallow_color", Color(0.11, 0.43, 0.53))
			_water_mat.set_shader_parameter("shallow_cells", 0.4)
		_apply_grade()
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
	_apply_grade()


# Night sky / ambient endpoints (the day endpoints are the clear-weather baselines captured at setup).
const _AMB_NIGHT := Color(0.26, 0.30, 0.46)        # moonlit blue — dim but still navigable
const _AMB_NIGHT_ENERGY := 0.26
const _SKY_NIGHT := Color(0.10, 0.13, 0.24)
const _SUN_HIGH := Color(1.0, 0.95, 0.80)          # warm daylight
const _SUN_LOW := Color(1.0, 0.60, 0.34)           # orange dawn/dusk
const _DUSK := Color(0.86, 0.52, 0.40)             # warm horizon bloom at sunrise/sunset


## Drive the whole sky from the DAY/NIGHT cycle (sun arc + colour + energy, ambient, sky tint), then
## wash the current WEATHER over the top (snow = cool white + brighter; rain = blue-grey + dimmer).
## Lerps from the clear-weather baselines (= the day endpoints) so it's reversible and never drifts.
func _apply_grade() -> void:
	var dl := DayNight.daylight()         # 0 night .. 1 noon
	var glow := DayNight.horizon_glow()   # 1 when the sun is near/below the horizon
	# Sun DIRECTION is fixed (a steady afternoon angle), so cast shadows and the toon lit/shadow
	# bands stay put. Arcing the sun made those bands creep across the open ground all day — on
	# near-flat grass the soft threshold is so light-angle-sensitive it read as "moving cloud
	# shadows". The day/night cycle still drives the sun's COLOUR + ENERGY (and ambient/sky/fog)
	# below, so dawn/day/dusk/night still look right — only the shadows no longer slide.
	if _sun != null:
		_sun.rotation_degrees = sun_dir_deg
	# Day/night base palette.
	var ambient := _AMB_NIGHT.lerp(_base_ambient, dl)
	var amb_energy := lerpf(_AMB_NIGHT_ENERGY, _base_ambient_energy, dl)
	var sun_color := _SUN_HIGH.lerp(_SUN_LOW, glow * 0.8)
	var sun_energy := _base_sun_energy * clampf(dl, 0.0, 1.0)
	var horizon := _SKY_NIGHT.lerp(_base_sky_horizon, dl).lerp(_DUSK, glow * dl * 0.7)
	var sky_hi := _SKY_NIGHT.lerp(_base_sky_hi, dl)
	var fog := horizon
	# Weather wash over the day/night base.
	var t: Color = Weather.tint
	var a: float = t.a
	var wash := Color(t.r, t.g, t.b)
	ambient = ambient.lerp(wash, a * 0.5)
	amb_energy *= 1.0 + Weather.snow * 0.22 - Weather.rain * 0.18
	horizon = horizon.lerp(wash, a * 0.55)
	sky_hi = sky_hi.lerp(wash, a * 0.4)
	fog = fog.lerp(wash, a * 0.6)
	sun_energy *= 1.0 - Weather.rain * 0.42 - Weather.snow * 0.12
	sun_color = sun_color.lerp(wash, a * 0.35)
	# Apply.
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = amb_energy
	_env.fog_light_color = fog
	_env.fog_sky_affect = 0.5 + (Weather.snow + Weather.rain) * 0.35   # precip thickens the haze
	if _sky_mat != null:
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = horizon
		_sky_mat.ground_bottom_color = horizon
		_sky_mat.sky_top_color = sky_hi
	if _sun != null:
		_sun.light_color = sun_color
		_sun.light_energy = sun_energy
	# Dusk: richer, warmer colour. A little extra saturation + contrast as the sun sets (not at dawn —
	# dawn instead gets the misty haze). Rain/snow desaturate slightly so storms read cooler/flatter.
	var dusk := DayNight.dusk()
	# Gentle dusk richening — too much over-saturated the cool snow palette into vivid purple.
	_env.adjustment_saturation = clampf(1.0 + dusk * 0.32 - (Weather.rain + Weather.snow) * 0.18, 0.7, 1.5)
	_env.adjustment_contrast = 1.0 + dusk * 0.08
	# TERRAIN MOOD: the ground is unshaded (see toon_ground.gdshader) — it ignores the sun colour/
	# direction/shadows entirely. The ONLY time/weather influence on terrain is this single uniform
	# multiplier, applied evenly so biome colours stay stable while the world still darkens at night.
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("terrain_mood", _terrain_mood())


## Single UNIFORM day/night/weather multiplier for the terrain ground. Brightness + a faint cool-night
## bias only — NOT the sun's colour/direction, never per-tile — so terrain stays stable and readable.
func _terrain_mood() -> Color:
	var dl := clampf(DayNight.daylight(), 0.0, 1.0)   # 0 night .. 1 day
	var b := lerpf(0.62, 1.0, dl)                     # day ~1.0, deep night ~0.62
	b *= 1.0 - Weather.rain * 0.12                    # rain dims a touch
	b *= 1.0 + Weather.snow * 0.04                    # snow stays bright
	b = clampf(b, 0.5, 1.05)
	# A whisper of cool at night (uniform, subtle — day is neutral white) so biome colours stay put.
	var cool := Color(0.93, 0.97, 1.05)
	var tint := Color(1.0, 1.0, 1.0).lerp(cool, (1.0 - dl) * 0.5)
	return Color(b * tint.r, b * tint.g, b * tint.b, 1.0)


## View-distance slider hook. The per-frame update() is the actual driver (it reads the live
## visual extent, which already scales with the slider), so this only exists for API/compat.
func apply_view_distance() -> void:
	pass


func get_environment() -> Environment:
	return _env


func get_sun() -> DirectionalLight3D:
	return _sun
