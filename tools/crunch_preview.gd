extends Control
## SPIKE preview v4: art-direction pass toward A Short Hike. ~70% art / 30%
## render. Palette-controlled 3-band warm cel shading, authored vertex-coloured
## terrain (elevation + dirt path + scatter), irregular hand-jittered trees/rocks,
## warm soft lighting, and a restrained palette-tinted screen-space edge pass.
##
##   Godot_v4.6.3-stable_win64.exe --path C:/Dev/imota-idle res://tools/crunch_preview.tscn
##   Esc quit.  [ / ] finer/chunkier.

const OUTLINE_SHADER := preload("res://tools/crunch_outline.gdshader")
const SHOT_PATH := "res://generated/props/_preview_shot.png"

# Warm, slightly-desaturated, harmonious palette.
const GRASS := [Color(0.42, 0.54, 0.29), Color(0.50, 0.59, 0.33), Color(0.36, 0.47, 0.27), Color(0.47, 0.53, 0.31)]
const DIRT := [Color(0.60, 0.49, 0.33), Color(0.53, 0.43, 0.29)]
const PINE := [Color(0.34, 0.45, 0.31), Color(0.40, 0.52, 0.34), Color(0.30, 0.40, 0.29)]
const DECID := [Color(0.80, 0.57, 0.32), Color(0.74, 0.47, 0.30), Color(0.84, 0.66, 0.38)]
const BARK := Color(0.46, 0.36, 0.27)
const STONE := [Color(0.60, 0.58, 0.55), Color(0.54, 0.52, 0.52)]
const FLOWER := [Color(0.88, 0.43, 0.42), Color(0.93, 0.80, 0.38), Color(0.76, 0.56, 0.86), Color(0.95, 0.95, 0.95)]

var shrink := 3
var _container: SubViewportContainer
var _vp: SubViewport
var _hint: Label
var _shot_done := false
var _frames := 0
var _hn := FastNoiseLite.new()
var _pn := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_hn.seed = 7
	_hn.frequency = 0.05
	_hn.fractal_octaves = 3
	_pn.seed = 21
	_pn.frequency = 0.06  # broader colour patches
	_rng.seed = 1234

	_container = SubViewportContainer.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.stretch_shrink = shrink
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_container)

	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)

	world.add_child(_terrain())
	_scatter(world)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 26.0
	cam.near = 0.1
	cam.far = 120.0
	world.add_child(cam)
	var target := Vector3(0, 0.6, 0)
	var pitch := 40.0
	var yaw := 45.0
	var dir := Vector3(
		cos(deg_to_rad(pitch)) * sin(deg_to_rad(yaw)),
		sin(deg_to_rad(pitch)),
		cos(deg_to_rad(pitch)) * cos(deg_to_rad(yaw)))
	cam.fov = 30.0
	cam.position = target + dir * 23.0
	cam.look_at(target, Vector3.UP)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	quad.extra_cull_margin = 16384.0
	var omat := ShaderMaterial.new()
	omat.shader = OUTLINE_SHADER
	omat.render_priority = 100
	quad.material_override = omat
	quad.position = Vector3(0, 0, -1.0)
	cam.add_child(quad)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -118.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.84)  # gently warm sun
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.80, 0.82)  # soft sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.64)  # mild warm fill -> warm, non-black shadows
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env

	_hint = Label.new()
	_hint.position = Vector2(12, 10)
	_hint.add_theme_color_override("font_color", Color(0.18, 0.16, 0.16))
	add_child(_hint)
	_update_hint()


func _process(_delta: float) -> void:
	_frames += 1
	if not _shot_done and _frames == 8:
		_shot_done = true
		_vp.get_texture().get_image().save_png(SHOT_PATH)


func _update_hint() -> void:
	if _hint != null:
		_hint.text = "Crunch preview v4 (art pass) — 1/%d res.  [ ] finer/chunkier,  Esc quit." % shrink


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.keycode == KEY_BRACKETLEFT:
		shrink = maxi(2, shrink - 1)
		_container.stretch_shrink = shrink
		_update_hint()
	elif event.keycode == KEY_BRACKETRIGHT:
		shrink = mini(8, shrink + 1)
		_container.stretch_shrink = shrink
		_update_hint()


# ----------------------------------------------------------- materials ----

## 3-band warm cel: broad quantised lighting, world-space value variation, and
## optional vertex-colour tint. Warm ambient supplies the (non-black) shadow.
func _cel(albedo: Color, use_vcol: float = 0.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float use_vcol = 0.0;
varying vec3 vw;
void vertex(){ vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h2(vec2 p){ return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
void fragment(){
	vec3 c = mix(albedo.rgb, COLOR.rgb, use_vcol);
	float n = h2(floor(vw.xz * 1.1));
	c *= mix(0.96, 1.04, n);
	ALBEDO = c;
}
void light(){
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float b = (d < 0.12) ? 0.0 : ((d < 0.5) ? 0.55 : 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * ATTENUATION * b;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("use_vcol", use_vcol)
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	return mi


# ------------------------------------------------------------ terrain ----

func _path_z(wx: float) -> float:
	return sin(wx * 0.42) * 3.0 + cos(wx * 0.21) * 1.4


func _height(wx: float, wz: float) -> float:
	var h := _hn.get_noise_2d(wx, wz) * 1.15
	# Carve the winding path slightly.
	var pd: float = absf(wz - _path_z(wx))
	if pd < 1.4:
		h -= (1.4 - pd) * 0.18
	return h


func _terr_color(wx: float, wz: float, wy: float) -> Color:
	var pd: float = absf(wz - _path_z(wx))
	if pd < 1.1:
		return DIRT[0] if _pn.get_noise_2d(wx * 2.0, wz * 2.0) > 0.0 else DIRT[1]
	var t: float = _pn.get_noise_2d(wx, wz) * 0.5 + 0.5
	if wy < -0.35:
		return GRASS[2].lerp(DIRT[1], 0.25)
	if t < 0.30:
		return GRASS[2]
	elif t < 0.6:
		return GRASS[0]
	elif t < 0.85:
		return GRASS[1]
	return GRASS[3]


func _terrain() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 46
	var sz := 26.0
	var s := sz / float(n)
	for iz: int in n:
		for ix: int in n:
			var x0 := -sz * 0.5 + float(ix) * s
			var z0 := -sz * 0.5 + float(iz) * s
			var corners := [Vector2(x0, z0), Vector2(x0 + s, z0), Vector2(x0 + s, z0 + s), Vector2(x0, z0 + s)]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for ci: int in tri:
					var c: Vector2 = corners[ci]
					var wy := _height(c.x, c.y)
					st.set_color(_terr_color(c.x, c.y, wy))
					st.add_vertex(Vector3(c.x, wy, c.y))
	st.generate_normals()
	return _mi(st.commit(), _cel(Color.WHITE, 1.0), Vector3.ZERO)


# ------------------------------------------------------------ scatter ----

func _scatter(world: Node3D) -> void:
	# Trees away from the path; rocks, flowers, tufts everywhere.
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 400:
		tries += 1
		var wx := _rng.randf_range(-11.0, 11.0)
		var wz := _rng.randf_range(-11.0, 11.0)
		if absf(wz - _path_z(wx)) < 2.4:
			continue
		var wy := _height(wx, wz)
		var pos := Vector3(wx, wy, wz)
		if _rng.randf() < 0.55:
			world.add_child(_pine(pos))
		else:
			world.add_child(_broadleaf(pos))
		placed += 1
	for i: int in 9:
		var wx := _rng.randf_range(-12.0, 12.0)
		var wz := _rng.randf_range(-12.0, 12.0)
		world.add_child(_rock(Vector3(wx, _height(wx, wz), wz)))
	for i: int in 40:
		var wx := _rng.randf_range(-12.0, 12.0)
		var wz := _rng.randf_range(-12.0, 12.0)
		var wy := _height(wx, wz)
		if _rng.randf() < 0.4:
			world.add_child(_flower(Vector3(wx, wy, wz)))
		else:
			world.add_child(_tuft(Vector3(wx, wy, wz)))


func _jit(v: float) -> float:
	return _rng.randf_range(-v, v)


func _blob(radius: float, segs: int = 8) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(3, segs / 2)
	return sm


func _cone(radius: float, height: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


## Pine: tapered slightly-leaning trunk + several irregular overlapping foliage
## masses (not one symmetric cone), jittered per instance.
func _pine(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = _rng.randf() * TAU
	var hgt := _rng.randf_range(2.6, 3.8)
	var trunk_h := hgt * 0.24
	var tr := CylinderMesh.new()
	tr.top_radius = 0.08
	tr.bottom_radius = 0.17
	tr.height = trunk_h
	tr.radial_segments = 6
	root.add_child(_mi(tr, _cel(BARK), Vector3(0, trunk_h * 0.5, 0), Vector3(_jit(0.05), 0, _jit(0.05))))
	var base := trunk_h * 0.7
	var n := _rng.randi_range(3, 4)
	for i: int in n:
		var f := float(i) / float(n - 1)
		var col: Color = PINE[_rng.randi() % PINE.size()]
		var r := lerpf(1.05, 0.4, f) * _rng.randf_range(0.85, 1.1)
		var ch := hgt * lerpf(0.46, 0.34, f)
		var y := base + hgt * lerpf(0.16, 0.66, f)
		var off := Vector3(_jit(0.18), _jit(0.06), _jit(0.18))
		root.add_child(_mi(_cone(r, ch, 7), _cel(col), Vector3(0, y, 0) + off,
			Vector3(_jit(0.12), _rng.randf() * TAU, _jit(0.12))))
	return root


## Deciduous: leaning trunk + an asymmetric cluster of warm canopy blobs.
func _broadleaf(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = _rng.randf() * TAU
	var hgt := _rng.randf_range(2.2, 3.2)
	var trunk_h := hgt * 0.46
	var lean := _jit(0.1)
	var tr := CylinderMesh.new()
	tr.top_radius = 0.09
	tr.bottom_radius = 0.16
	tr.height = trunk_h
	tr.radial_segments = 6
	root.add_child(_mi(tr, _cel(BARK), Vector3(0, trunk_h * 0.5, 0), Vector3(lean, 0, _jit(0.08))))
	var cy := trunk_h + hgt * 0.18
	var n := _rng.randi_range(4, 6)
	for i: int in n:
		var col: Color = DECID[_rng.randi() % DECID.size()]
		var r := _rng.randf_range(0.45, 0.85)
		var off := Vector3(_jit(0.55), cy + _jit(0.45), _jit(0.55))
		root.add_child(_mi(_blob(r, 8), _cel(col), off, Vector3.ZERO,
			Vector3(_rng.randf_range(0.85, 1.15), _rng.randf_range(0.8, 1.05), _rng.randf_range(0.85, 1.15))))
	return root


## Rock: an uneven low-poly lump, randomly squashed/rotated and partly buried.
func _rock(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos + Vector3(0, -_rng.randf_range(0.05, 0.2), 0)  # partly buried
	root.rotation = Vector3(_jit(0.25), _rng.randf() * TAU, _jit(0.25))
	var col: Color = STONE[_rng.randi() % STONE.size()]
	var r := _rng.randf_range(0.3, 0.7)
	root.add_child(_mi(_blob(r, 6), _cel(col), Vector3(0, r * 0.5, 0), Vector3.ZERO,
		Vector3(_rng.randf_range(1.0, 1.4), _rng.randf_range(0.55, 0.8), _rng.randf_range(1.0, 1.3))))
	if _rng.randf() < 0.5:
		root.add_child(_mi(_blob(r * 0.6, 6), _cel(col), Vector3(_jit(0.3), r * 0.3, _jit(0.3)), Vector3.ZERO,
			Vector3(1.1, 0.7, 1.0)))
	return root


func _flower(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var stem := _cone(0.02, 0.28, 4)
	root.add_child(_mi(stem, _cel(Color(0.4, 0.55, 0.3)), Vector3(0, 0.14, 0)))
	var col: Color = FLOWER[_rng.randi() % FLOWER.size()]
	root.add_child(_mi(_blob(0.07, 5), _cel(col), Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.6, 1)))
	return root


func _tuft(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = _rng.randf() * TAU
	var col: Color = GRASS[_rng.randi() % GRASS.size()].darkened(0.05)
	for off: Vector3 in [Vector3(0, 0, 0), Vector3(0.08, 0, 0.05), Vector3(-0.07, 0, -0.04)]:
		root.add_child(_mi(_cone(0.05, _rng.randf_range(0.22, 0.36), 3), _cel(col),
			off + Vector3(0, 0.14, 0), Vector3(_jit(0.15), 0, _jit(0.15))))
	return root
