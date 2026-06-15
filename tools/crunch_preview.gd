extends Control
## SPIKE preview v5: composed miniature landscape (art-direction pass).
## - World-space terrain colouring (no grid) + 3-layer winding path.
## - Lower exposure, warm-cream sun, olive ambient -> warm non-black shadows.
## - Fixed 640x360 internal render, nearest upscale (press [ ] to cycle presets).
## - Perspective cam ~38° FOV at a ~50° downward angle (trunks/faces visible).
## - 3-colour cel materials; irregular trees, clustered sunk rocks, contact
##   shadows; a deliberate composition: cabin + fence + clearing + foreground.
##
##   Godot_v4.6.3-stable_win64.exe --path C:/Dev/imota-idle res://tools/crunch_preview.tscn

const OUTLINE_SHADER := preload("res://tools/crunch_outline.gdshader")
const TERRAIN_SHADER := preload("res://tools/crunch_terrain.gdshader")
const SHOT_PATH := "res://generated/props/_preview_shot.png"

const RES := [Vector2i(480, 270), Vector2i(640, 360), Vector2i(768, 432)]
var res_idx := 1

# Palette (warm, muted — no fluorescent values).
const G := [Color("66764A"), Color("7F914E"), Color("9EAA5A"), Color("B8BC6A")]
const PATH_CENTER := Color("D9A25A")
const PATH_MAIN := Color("BF8547")
const PATH_EDGE := Color("8F6944")
const PINE := [Color("3E5A36"), Color("4F7340"), Color("5F8A4A")]
const DECID := [Color("8E3F2E"), Color("B95032"), Color("D96A3D"), Color("E68B52")]
const BARK := Color("5A4632")
const ROCK := [Color("625D56"), Color("82786D"), Color("A99A88")]
const FLOWER := [Color("CC6A6A"), Color("DBC05C"), Color("B58FCF"), Color("E2E2E2")]
const SHADOW_TINT := Color("6A6E55")  # lighter warm olive-grey -> non-black shadows
const CABIN_WALL := Color("C7B58C")
const CABIN_ROOF := Color("9C5234")

var _vp: SubViewport
var _tr: TextureRect
var _hint: Label
var _shot_done := false
var _frames := 0
var _hn := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_hn.seed = 7
	_hn.frequency = 0.045
	_hn.fractal_octaves = 3
	_rng.seed = 9931

	_vp = SubViewport.new()
	_vp.size = RES[res_idx]
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	_tr = TextureRect.new()
	_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tr.texture = _vp.get_texture()
	_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tr.stretch_mode = TextureRect.STRETCH_SCALE
	_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_tr)

	var world := Node3D.new()
	_vp.add_child(world)

	world.add_child(_terrain())
	_compose(world)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 160.0
	world.add_child(cam)
	var target := Vector3(-0.5, 1.0, -0.5)
	var pitch := 48.0  # ~48° downward; close + perspective shows trunks/faces
	var yaw := 45.0
	var dir := Vector3(
		cos(deg_to_rad(pitch)) * sin(deg_to_rad(yaw)),
		sin(deg_to_rad(pitch)),
		cos(deg_to_rad(pitch)) * cos(deg_to_rad(yaw)))
	cam.position = target + dir * 16.0
	cam.look_at(target, Vector3.UP)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	quad.extra_cull_margin = 16384.0
	var omat := ShaderMaterial.new()
	omat.shader = OUTLINE_SHADER
	omat.render_priority = 100
	omat.set_shader_parameter("outline_color", Color("3a2f30"))
	omat.set_shader_parameter("depth_threshold", 0.9)
	omat.set_shader_parameter("normal_threshold", 1.4)
	omat.set_shader_parameter("depth_strength", 0.2)
	omat.set_shader_parameter("normal_strength", 0.05)
	omat.set_shader_parameter("outline_opacity", 0.22)
	omat.set_shader_parameter("fade_start", 24.0)
	omat.set_shader_parameter("fade_end", 50.0)
	quad.material_override = omat
	quad.position = Vector3(0, 0, -1.0)
	cam.add_child(quad)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -116.0, 0.0)  # steeper -> shorter, less dominant shadows
	sun.light_color = Color("FFE1B8")  # warm cream, not yellow
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("AEC2C0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = SHADOW_TINT  # lighter olive-grey -> non-black shadows
	env.ambient_light_energy = 0.85  # lift shadows so casts aren't near-black
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	cam.environment = env

	_hint = Label.new()
	_hint.position = Vector2(12, 10)
	_hint.add_theme_color_override("font_color", Color(0.16, 0.14, 0.14))
	add_child(_hint)
	_update_hint()


func _process(_delta: float) -> void:
	_frames += 1
	if not _shot_done and _frames == 24:
		_shot_done = true
		_vp.get_texture().get_image().save_png(SHOT_PATH)


func _update_hint() -> void:
	if _hint != null:
		_hint.text = "Crunch preview v5 — internal %dx%d.  [ ] resolution,  Esc quit." % [RES[res_idx].x, RES[res_idx].y]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.keycode == KEY_BRACKETLEFT:
		res_idx = maxi(0, res_idx - 1)
		_vp.size = RES[res_idx]
		_update_hint()
	elif event.keycode == KEY_BRACKETRIGHT:
		res_idx = mini(RES.size() - 1, res_idx + 1)
		_vp.size = RES[res_idx]
		_update_hint()


# ----------------------------------------------------------- materials ----

func _noise_tex(freq: float, seed: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.seed = seed
	var nt := NoiseTexture2D.new()
	nt.noise = fn
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	return nt


## 3-colour cel: shadow/base/light derived from the albedo (shadow shifts toward
## a warm/cool palette tone, highlight warms) — palette richness, not striping.
func _cel(albedo: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert;
uniform vec4 albedo : source_color = vec4(1.0);
varying vec3 vw;
void vertex(){ vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h2(vec2 p){ return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
void fragment(){
	vec3 c = albedo.rgb * mix(0.97, 1.03, h2(floor(vw.xz * 0.7)));
	c = mix(c, vec3(dot(c, vec3(0.299, 0.587, 0.114))), 0.10);  // slightly faded
	ALBEDO = c;
}
void light(){
	vec3 base = ALBEDO;
	vec3 sh = base * vec3(0.62, 0.58, 0.64);
	vec3 hi = clamp(mix(base, vec3(1.0, 0.92, 0.78), 0.16) * 1.06, vec3(0.0), vec3(1.0));
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float t1 = smoothstep(0.34, 0.42, d);
	float t2 = smoothstep(0.64, 0.72, d);
	vec3 col = mix(mix(sh, base, t1), hi, t2);
	DIFFUSE_LIGHT += col * LIGHT_COLOR.rgb * ATTENUATION;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", albedo)
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	return mi


## Soft, lifted contact shadow disc placed under a prop (darker than the
## directional cast shadow, which is warm/olive from the ambient).
func _contact(radius: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.02
	c.radial_segments = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.20, 0.21, 0.15, 0.42)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := _mi(c, m, Vector3(0, 0.03, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------ terrain ----

func _path_z(wx: float) -> float:
	return sin(wx * 0.42) * 3.0 + cos(wx * 0.21) * 1.4


func _height(wx: float, wz: float) -> float:
	var h := _hn.get_noise_2d(wx, wz) * 1.1
	h += smoothstep(-4.0, -12.0, wz) * 3.4  # raised hill toward the back
	var pd: float = absf(wz - _path_z(wx))
	if pd < 1.3:
		h -= (1.3 - pd) * 0.16
	return h


func _terrain() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var sz := 46.0  # larger so terrain fills the frame (no floating-diorama edges)
	var s := sz / float(n)
	for iz: int in n:
		for ix: int in n:
			var x0 := -sz * 0.5 + float(ix) * s
			var z0 := -sz * 0.5 + float(iz) * s
			var corners := [Vector2(x0, z0), Vector2(x0 + s, z0), Vector2(x0 + s, z0 + s), Vector2(x0, z0 + s)]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for ci: int in tri:
					var c: Vector2 = corners[ci]
					st.add_vertex(Vector3(c.x, _height(c.x, c.y), c.y))
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("noise_lo", _noise_tex(0.7, 7))
	for i: int in G.size():
		mat.set_shader_parameter("g%d" % i, G[i])
	mat.set_shader_parameter("path_center", PATH_CENTER)
	mat.set_shader_parameter("path_main", PATH_MAIN)
	mat.set_shader_parameter("path_edge", PATH_EDGE)
	mat.set_shader_parameter("region_scale", 0.13)
	mat.set_shader_parameter("value_scale", 0.32)
	return _mi(st.commit(), mat, Vector3.ZERO)


# -------------------------------------------------------- composition ----

## Deliberate scene: cabin upper-left by the path, fence beside it, dense tree
## cluster on the right, rock cluster opposite, foreground trees cropped by the
## camera, a character for scale, sparse accents — not uniform scatter.
func _compose(world: Node3D) -> void:
	_add(world, _cabin(), Vector3(-5.5, 0, -3.0))
	_fence(world, Vector3(-3.6, 0, -1.4), Vector3(1.0, 0, 0.9), 4)
	_add(world, _character(), Vector3(-3.8, 0, -2.2))

	# Right-side dense grove (cluster).
	for p: Vector3 in [Vector3(4.6, 0, 1.0), Vector3(5.8, 0, 2.2), Vector3(4.0, 0, 2.8),
			Vector3(6.4, 0, 0.4), Vector3(5.2, 0, 3.6)]:
		_add(world, _pine() if _rng.randf() < 0.7 else _broadleaf(), p)
	# Background tree wall on the hill.
	for i: int in 7:
		var wx := _rng.randf_range(-12.0, 12.0)
		_add(world, _pine(), Vector3(wx, 0, _rng.randf_range(-13.0, -9.0)))

	# Rock cluster opposite the cabin.
	_rock_cluster(world, Vector3(3.4, 0, -3.6))
	_rock_cluster(world, Vector3(-0.6, 0, 4.4))

	# Foreground trees cropped by the camera (toward the viewer = +x,+z).
	_add(world, _broadleaf(1.35), Vector3(7.2, 0, 6.4))
	_add(world, _pine(1.3), Vector3(4.8, 0, 7.0))

	# Sparse accents: flowers + tufts, mostly near the path and clearing edges.
	for i: int in 46:
		var wx := _rng.randf_range(-12.0, 12.0)
		var wz := _rng.randf_range(-9.0, 9.0)
		if _rng.randf() < 0.35:
			_add(world, _flower(), Vector3(wx, 0, wz))
		else:
			_add(world, _tuft(), Vector3(wx, 0, wz))


func _add(world: Node3D, prop: Node3D, pos: Vector3) -> void:
	prop.position = Vector3(pos.x, _height(pos.x, pos.z), pos.z)
	world.add_child(prop)


# ------------------------------------------------------------- props ----

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


func _pine(scale_mul: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = _rng.randf() * TAU
	var hgt := _rng.randf_range(2.6, 3.6) * scale_mul
	root.add_child(_contact(hgt * 0.28))
	var trunk_h := hgt * 0.24
	var tr := CylinderMesh.new()
	tr.top_radius = 0.08
	tr.bottom_radius = 0.17
	tr.height = trunk_h
	tr.radial_segments = 6
	root.add_child(_mi(tr, _cel(BARK), Vector3(0, trunk_h * 0.5, 0), Vector3(_jit(0.05), 0, _jit(0.05))))
	# Several overlapping, irregular foliage masses; unequal left/right.
	var base := trunk_h * 0.7
	var n := _rng.randi_range(4, 5)
	for i: int in n:
		var f := float(i) / float(n - 1)
		var col: Color = PINE[mini(int(f * 2.4), PINE.size() - 1)]  # darker low, lighter top
		var r := lerpf(1.1, 0.35, f) * _rng.randf_range(0.82, 1.12)
		var ch := hgt * lerpf(0.5, 0.32, f)
		var y := base + hgt * lerpf(0.14, 0.7, f)
		var off := Vector3(_jit(0.22), _jit(0.05), _jit(0.22))
		root.add_child(_mi(_cone(r, ch, 7), _cel(col), Vector3(0, y, 0) + off,
			Vector3(_jit(0.14), _rng.randf() * TAU, _jit(0.14)),
			Vector3(_rng.randf_range(0.9, 1.15), 1.0, _rng.randf_range(0.9, 1.15))))
	return root


## Deciduous: leaning trunk + one dominant canopy mass and 4-6 satellite clumps
## at varied heights/offsets, multi-colour, asymmetric (no stacked discs).
func _broadleaf(scale_mul: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = _rng.randf() * TAU
	var hgt := _rng.randf_range(2.3, 3.1) * scale_mul
	root.add_child(_contact(hgt * 0.3))
	var trunk_h := hgt * 0.44
	var tr := CylinderMesh.new()
	tr.top_radius = 0.09
	tr.bottom_radius = 0.16
	tr.height = trunk_h
	tr.radial_segments = 6
	root.add_child(_mi(tr, _cel(BARK), Vector3(0, trunk_h * 0.5, 0), Vector3(_jit(0.1), 0, _jit(0.07))))
	var cy := trunk_h + hgt * 0.12
	# Dominant mass.
	root.add_child(_mi(_blob(0.9 * scale_mul, 9), _cel(DECID[1]), Vector3(_jit(0.18), cy + hgt * 0.14, _jit(0.18)),
		Vector3.ZERO, Vector3(1.15, 0.95, 1.1)))
	var n := _rng.randi_range(4, 6)
	for i: int in n:
		var col: Color = DECID[_rng.randi_range(0, 3)]
		var r := _rng.randf_range(0.4, 0.7) * scale_mul
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(0.4, 0.85) * scale_mul
		var off := Vector3(cos(ang) * rad, cy + _rng.randf_range(-0.1, 0.55) * hgt, sin(ang) * rad)
		root.add_child(_mi(_blob(r, 8), _cel(col), off, Vector3.ZERO,
			Vector3(_rng.randf_range(0.9, 1.2), _rng.randf_range(0.85, 1.05), _rng.randf_range(0.9, 1.2))))
	return root


func _rock(radius: float) -> Node3D:
	var root := Node3D.new()
	root.position.y = -radius * _rng.randf_range(0.15, 0.35)  # sunk into ground
	root.rotation = Vector3(_jit(0.25), _rng.randf() * TAU, _jit(0.25))
	var col: Color = ROCK[_rng.randi_range(0, ROCK.size() - 1)]
	root.add_child(_mi(_blob(radius, 6), _cel(col), Vector3(0, radius * 0.5, 0), Vector3.ZERO,
		Vector3(_rng.randf_range(1.0, 1.4), _rng.randf_range(0.55, 0.8), _rng.randf_range(1.0, 1.3))))
	return root


## Authored cluster: one large, two medium and several small stones + tufts.
func _rock_cluster(world: Node3D, center: Vector3) -> void:
	var spots := [[0.0, 0.0, 0.7], [0.7, 0.5, 0.42], [-0.6, 0.4, 0.4],
			[0.4, -0.7, 0.26], [-0.5, -0.6, 0.24], [0.9, -0.2, 0.2]]
	for sp: Array in spots:
		_add(world, _rock(float(sp[2])), center + Vector3(float(sp[0]), 0, float(sp[1])))
	for i: int in 3:
		_add(world, _tuft(), center + Vector3(_jit(1.0), 0, _jit(1.0)))


func _flower() -> Node3D:
	var root := Node3D.new()
	root.add_child(_mi(_cone(0.02, 0.26, 4), _cel(Color("4F6B33")), Vector3(0, 0.13, 0)))
	root.add_child(_mi(_blob(0.07, 5), _cel(FLOWER[_rng.randi_range(0, FLOWER.size() - 1)]),
		Vector3(0, 0.28, 0), Vector3.ZERO, Vector3(1, 0.6, 1)))
	return root


func _tuft() -> Node3D:
	var root := Node3D.new()
	root.rotation.y = _rng.randf() * TAU
	var col: Color = G[_rng.randi_range(0, 2)]
	for off: Vector3 in [Vector3(0, 0, 0), Vector3(0.08, 0, 0.05), Vector3(-0.07, 0, -0.04)]:
		root.add_child(_mi(_cone(0.05, _rng.randf_range(0.2, 0.34), 3), _cel(col),
			off + Vector3(0, 0.13, 0), Vector3(_jit(0.15), 0, _jit(0.15))))
	return root


# ----------------------------------------------------------- landmarks ----

func _box(size: Vector3, col: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, _cel(col), pos, rot)


func _cabin() -> Node3D:
	var root := Node3D.new()
	root.rotation.y = deg_to_rad(_rng.randf_range(-12.0, 12.0))
	root.add_child(_contact(2.2))
	root.add_child(_box(Vector3(2.6, 1.7, 2.2), CABIN_WALL, Vector3(0, 0.85, 0)))
	# Prism roof (ridge along Z), overhanging.
	var roof := PrismMesh.new()
	roof.size = Vector3(3.1, 1.1, 2.7)
	root.add_child(_mi(roof, _cel(CABIN_ROOF), Vector3(0, 2.25, 0)))
	# Door + windows (facing +X toward the path).
	root.add_child(_box(Vector3(0.06, 0.95, 0.55), Color("4A3320"), Vector3(1.31, 0.5, 0.3)))
	root.add_child(_box(Vector3(0.06, 0.5, 0.5), Color("F2D58A"), Vector3(1.31, 1.05, -0.55)))
	root.add_child(_box(Vector3(0.5, 0.5, 0.06), Color("F2D58A"), Vector3(-0.55, 1.05, 1.11)))
	return root


func _fence(world: Node3D, start: Vector3, step_dir: Vector3, count: int) -> void:
	var d := step_dir.normalized()
	for i: int in count:
		var p := start + step_dir * float(i)
		_add(world, _box(Vector3(0.1, 0.7, 0.1), BARK, Vector3(0, 0.35, 0)), p)
		if i < count - 1:
			var mid := p + step_dir * 0.5
			var rail := _box(Vector3(step_dir.length() * 0.95, 0.08, 0.06), BARK, Vector3(0, 0.45, 0),
				Vector3(0, atan2(d.x, d.z), 0))
			_add(world, rail, mid)


func _character() -> Node3D:
	var root := Node3D.new()
	root.rotation.y = deg_to_rad(200.0)
	root.add_child(_contact(0.35))
	root.add_child(_mi(_blob(0.18, 7), _cel(Color("3E63A8")), Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1, 1.3, 1)))
	root.add_child(_mi(_blob(0.17, 7), _cel(Color("C8966B")), Vector3(0, 0.78, 0)))
	root.add_child(_mi(_blob(0.2, 6), _cel(Color("8A5A33")), Vector3(0, 0.9, 0), Vector3.ZERO, Vector3(1, 0.55, 1)))
	return root
