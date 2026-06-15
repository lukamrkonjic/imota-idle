extends Control
## Standalone 3D pixel-art rendering PREVIEW (A Short Hike-style rendering applied
## with OUR palette). This is a style spike, not the live 2D game: it renders an
## authored 3D scene (landscape, trees, house, bushes) through a low-resolution
## SubViewport and presents it at an exact 4x nearest-neighbour upscale.
##
## Touches rendering only — no save/content/gameplay code. Authored low-poly
## props (readable silhouettes, our palette colors), NOT naked primitives standing
## in for game assets. Built fresh, independent of the old spike code.
##
## Keys:  1 native(blur)  2 internal 1:1  3 final 4x nearest  |  T toon/flat
##        P palette-snap  O orbit  K save screenshot

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const TOON := preload("res://shaders/toon_world.gdshader")
const SNAP := preload("res://shaders/palette_snap.gdshader")

const INTERNAL := Vector2i(480, 270)   # 1920x1080 / 4 — exact integer scale
const WINDOW := Vector2i(1920, 1080)

var sub: SubViewport
var present: TextureRect
var snap_mat: ShaderMaterial
var world3d: Node3D
var cam: Camera3D
var _orbit := true
var _orbit_t := 0.6
var _frames := 0
var _captured := false


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# --- low-resolution world SubViewport (Stage 1) ---
	sub = SubViewport.new()
	sub.size = INTERNAL
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub.use_taa = false
	sub.use_debanding = false
	sub.positional_shadow_atlas_size = 4096
	add_child(sub)

	_build_world()

	# --- 4x nearest presentation; UI/text would stay full-res in the real game ---
	present = TextureRect.new()
	present.set_anchors_preset(Control.PRESET_FULL_RECT)
	present.texture = sub.get_texture()
	present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	present.stretch_mode = TextureRect.STRETCH_SCALE
	snap_mat = ShaderMaterial.new()
	snap_mat.shader = SNAP
	snap_mat.set_shader_parameter("palette_tex", _palette_texture())
	snap_mat.set_shader_parameter("palette_count", 28)
	snap_mat.set_shader_parameter("enabled", 0.0)
	snap_mat.set_shader_parameter("strength", 1.0)
	present.material = snap_mat
	add_child(present)

	var help := Label.new()
	help.text = "1 native  2 internal  3 final 4x   |  T toon/flat  P palette-snap  O orbit  K shot"
	help.position = Vector2(12, 8)
	help.add_theme_color_override("font_color", Color(1, 1, 0.6))
	help.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(help)


# ---------------------------------------------------------------- 3D world ----

func _build_world() -> void:
	world3d = Node3D.new()
	sub.add_child(world3d)

	# Warm flat-ish sky, no glow/ssao/fog during calibration (Stage 1/6).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PixelPalette.pal("snow_a").lerp(PixelPalette.pal("water_a"), 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = PixelPalette.pal("shadow")
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world3d.add_child(we)

	# One warm key light from the upper-right (the game's sun convention), crisp
	# palette-tinted shadows via the toon shader's shadow band (Stage 6).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	world3d.add_child(sun)

	# Orthographic, iso-leaning angle (compatible with the game's iso identity);
	# ortho keeps pixels stable under movement.
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.0
	cam.near = 0.1
	cam.far = 200.0
	world3d.add_child(cam)
	_place_camera(_orbit_t)
	cam.make_current()

	# --- landscape: broad calm grass with gentle low-frequency hills ---
	var ground := _build_ground()
	ground.material_override = _toon("grass_a", "grass_dark", "foliage_c")
	world3d.add_child(ground)

	# Dirt clearing around the house — a clean, sharp grass/dirt boundary.
	var clearing := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 5.2
	disc.bottom_radius = 5.2
	disc.height = 0.12
	disc.radial_segments = 24
	clearing.mesh = disc
	clearing.position = Vector3(0, _height(0, 1.5) + 0.06, 1.5)
	clearing.material_override = _toon("dirt_a", "dirt_b", "ore")
	world3d.add_child(clearing)

	# House (center-back of the clearing).
	_build_house(Vector3(0.5, 0, 2.0))

	# Trees scattered around (authored leafy silhouettes).
	for p: Vector2 in [Vector2(-7, -3), Vector2(-9, 4), Vector2(8, -4), Vector2(6, 6), Vector2(-3, 9)]:
		_build_tree(Vector3(p.x, 0, p.y))

	# Bushes as low foreground accents (10-15% detail, not ground cover).
	for p: Vector2 in [Vector2(-4, -1), Vector2(3, -2), Vector2(-5.5, 3), Vector2(4.5, 3.5), Vector2(2, 5), Vector2(-2, -5)]:
		_build_bush(Vector3(p.x, 0, p.y))


## Smooth low-frequency hills, smooth normals so the ground reads as broad bands,
## not faceted triangles. Pure broad masks — no per-pixel/per-cell noise.
func _height(x: float, z: float) -> float:
	return 0.55 * sin(x * 0.16) * cos(z * 0.15) + 0.35 * sin((x + z) * 0.08)


## Analytic up-facing normal from the height gradient (reliable, gently varying).
func _normal(x: float, z: float) -> Vector3:
	var e := 0.25
	var dx := _height(x + e, z) - _height(x - e, z)
	var dz := _height(x, z + e) - _height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _build_ground() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 56
	var extent := 34.0
	var step := (extent * 2.0) / float(n)
	for j: int in n:
		for i: int in n:
			var x0 := -extent + float(i) * step
			var z0 := -extent + float(j) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var a := Vector3(x0, _height(x0, z0), z0)
			var b := Vector3(x1, _height(x1, z0), z0)
			var c := Vector3(x1, _height(x1, z1), z1)
			var d := Vector3(x0, _height(x0, z1), z1)
			# Explicit up-facing analytic normals (reliable lighting + gentle bands).
			for v: Vector3 in [a, b, c, a, c, d]:
				st.set_normal(_normal(v.x, v.z))
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _build_tree(base: Vector3) -> void:
	base.y = _height(base.x, base.z)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.16
	tm.bottom_radius = 0.26
	tm.height = 1.7
	tm.radial_segments = 7
	trunk.mesh = tm
	trunk.position = base + Vector3(0, 0.85, 0)
	trunk.material_override = _toon("trunk_a", "trunk_b", "dirt_a")
	world3d.add_child(trunk)
	var leaf := _toon("foliage_a", "foliage_b", "foliage_c")
	# Three squashed canopy lobes -> a rounded, readable leafy silhouette.
	var lobes := [
		[Vector3(0, 2.3, 0), 1.35],
		[Vector3(-0.5, 1.9, 0.35), 1.0],
		[Vector3(0.55, 2.0, -0.25), 0.95],
	]
	for lobe: Array in lobes:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(lobe[1])
		sm.height = float(lobe[1]) * 1.7
		sm.radial_segments = 10
		sm.rings = 6
		s.mesh = sm
		s.scale = Vector3(1.0, 0.82, 1.0)
		s.position = base + (lobe[0] as Vector3)
		s.material_override = leaf
		world3d.add_child(s)


func _build_bush(base: Vector3) -> void:
	base.y = _height(base.x, base.z)
	var leaf := _toon("foliage_b", "grass_dark", "foliage_a")
	for off: Vector3 in [Vector3(0, 0.35, 0), Vector3(-0.32, 0.28, 0.1), Vector3(0.3, 0.26, -0.12)]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 0.8
		sm.radial_segments = 9
		sm.rings = 5
		s.mesh = sm
		s.scale = Vector3(1.0, 0.8, 1.0)
		s.position = base + off
		s.material_override = leaf
		world3d.add_child(s)


func _build_house(base: Vector3) -> void:
	base.y = _height(base.x, base.z)
	var wood := _toon("dirt_a", "trunk_b", "gold")
	var roof_mat := _toon("stone_a", "stone_b", "snow_a")
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.8, 1.9, 2.3)
	body.mesh = bm
	body.position = base + Vector3(0, 1.0, 0)
	body.material_override = wood
	world3d.add_child(body)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.3, 1.25, 2.7)
	roof.mesh = pm
	roof.position = base + Vector3(0, 2.55, 0)
	roof.material_override = roof_mat
	world3d.add_child(roof)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.7, 1.1, 0.12)
	door.mesh = dm
	door.position = base + Vector3(0, 0.55, 1.16)
	door.material_override = _toon("trunk_b", "shadow", "trunk_a")
	world3d.add_child(door)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.6, 0.55, 0.12)
	win.mesh = wm
	win.position = base + Vector3(0.95, 1.15, 1.16)
	win.material_override = _toon("water_a", "water_b", "water_foam")
	world3d.add_child(win)


# ----------------------------------------------------------------- helpers ----

## Toon material whose three bands are distinct palette colors (not base*factor).
func _toon(base_key: String, shadow_key: String, light_key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("base_color", PixelPalette.pal(base_key))
	m.set_shader_parameter("shadow_color", PixelPalette.pal(shadow_key))
	m.set_shader_parameter("light_color", PixelPalette.pal(light_key))
	m.set_shader_parameter("shadow_threshold", 0.28)
	m.set_shader_parameter("light_threshold", 0.62)
	m.set_shader_parameter("softness", 0.08)
	return m


func _palette_texture() -> ImageTexture:
	var keys := PixelPalette.PAL.keys()
	var img := Image.create(keys.size(), 1, false, Image.FORMAT_RGBA8)
	for i: int in keys.size():
		img.set_pixel(i, 0, PixelPalette.pal(keys[i]))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _place_camera(t: float) -> void:
	var ang := t * TAU
	var radius := 22.0
	var center := Vector3(0, 1.2, 1.0)
	cam.position = center + Vector3(sin(ang) * radius, 17.0, cos(ang) * radius)
	cam.look_at(center, Vector3.UP)


# ------------------------------------------------------------------- input ----

func _process(delta: float) -> void:
	if _orbit:
		_orbit_t += delta * 0.03
		_place_camera(_orbit_t)
	_frames += 1
	if _frames == 70 and not _captured:
		_capture()


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://pixel3d_preview.png")
	print("[preview] saved user://pixel3d_preview.png")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:  # native-ish: linear upscale (blurry, no nearest)
			present.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			present.stretch_mode = TextureRect.STRETCH_SCALE
		KEY_2:  # internal resolution 1:1 (centered, no upscale)
			present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			present.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		KEY_3:  # final 4x nearest
			present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			present.stretch_mode = TextureRect.STRETCH_SCALE
		KEY_T:  # toon vs flat (flat = base band only)
			for mi: Node in world3d.find_children("*", "MeshInstance3D"):
				var mat := (mi as MeshInstance3D).material_override
				if mat is ShaderMaterial:
					var soft: float = float((mat as ShaderMaterial).get_shader_parameter("softness"))
					(mat as ShaderMaterial).set_shader_parameter("light_threshold", 2.0 if soft < 1.0 else 0.84)
					(mat as ShaderMaterial).set_shader_parameter("shadow_threshold", -1.0 if soft < 1.0 else 0.34)
		KEY_P:
			var en: float = float(snap_mat.get_shader_parameter("enabled"))
			snap_mat.set_shader_parameter("enabled", 0.0 if en > 0.5 else 1.0)
		KEY_O:
			_orbit = not _orbit
		KEY_K:
			_captured = false
			_capture()
