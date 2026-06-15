extends Control
## SPIKE preview v2: live "crunch" view tuned toward A Short Hike.
## Renders a small iso 3D scene into a SubViewport at 1/SHRINK res, upscaled with
## nearest-neighbor (that upscale = the crunch). Tuned for the inspo: SOFT thin
## outlines, smooth cohesive 2-tone shading (not hard facets), ROUNDED organic
## shapes, and a warm palette.
##
##   Godot_v4.6.3-stable_win64.exe --path C:/Dev/imota-idle res://tools/crunch_preview.tscn
##   Esc to quit.  Press [ / ] to make pixels finer / chunkier.

var shrink := 4
const CAM_YAW := 45.0
const CAM_PITCH := 32.0

var _spin: Node3D
var _container: SubViewportContainer
var _hint: Label


func _ready() -> void:
	_container = SubViewportContainer.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.stretch_shrink = shrink
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crunch upscale
	add_child(_container)

	var vp := SubViewport.new()
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED  # no AA -> crisp pixels
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(vp)

	var world := Node3D.new()
	vp.add_child(world)

	# Warm grassy ground + a couple of dirt patches for color variation.
	world.add_child(_ground_plane(Vector2(16, 16), Color(0.47, 0.66, 0.31), -0.01))
	world.add_child(_dirt_patch(Vector3(0.2, 0.0, 1.0), 2.2))
	world.add_child(_dirt_patch(Vector3(-2.0, 0.0, -0.6), 1.6))

	_spin = Node3D.new()
	world.add_child(_spin)
	# A little vignette: pines, a warm autumn broadleaf, bushes, a rock, grass.
	_spin.add_child(_at(_pine(3.3), Vector3(-2.4, 0, -1.2)))
	_spin.add_child(_at(_pine(2.5), Vector3(-3.4, 0, 1.0)))
	_spin.add_child(_at(_broadleaf(3.0), Vector3(2.0, 0, -1.8)))
	_spin.add_child(_at(_broadleaf(2.4), Vector3(3.2, 0, 1.4)))
	_spin.add_child(_at(_rock(), Vector3(-1.4, 0, 1.9)))
	_spin.add_child(_at(_bush(), Vector3(0.4, 0, 0.5)))
	_spin.add_child(_at(_bush(), Vector3(1.2, 0, 2.0)))
	for gp: Vector3 in [Vector3(-0.8, 0, -0.4), Vector3(1.6, 0, -0.6), Vector3(-2.2, 0, 0.6), Vector3(2.6, 0, -0.2)]:
		_spin.add_child(_at(_grass_tuft(), gp))

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	world.add_child(cam)
	var target := Vector3(0, 1.0, 0)
	var dir := Vector3(
		cos(deg_to_rad(CAM_PITCH)) * sin(deg_to_rad(CAM_YAW)),
		sin(deg_to_rad(CAM_PITCH)),
		cos(deg_to_rad(CAM_PITCH)) * cos(deg_to_rad(CAM_YAW)))
	cam.position = target + dir * 18.0
	cam.look_at(target, Vector3.UP)

	# Warm low sun + bright warm ambient -> soft, cohesive shadows (not black).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -120.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_blend_splits = true
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.80, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.74, 0.66)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2
	cam.environment = env

	_hint = Label.new()
	_hint.position = Vector2(12, 10)
	_hint.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14))
	add_child(_hint)
	_update_hint()


func _process(delta: float) -> void:
	if _spin != null:
		_spin.rotate_y(delta * 0.4)


func _update_hint() -> void:
	if _hint != null:
		_hint.text = "Crunch preview v2 — 1/%d res, nearest upscale.  [ ] = finer/chunkier,  Esc to quit." % shrink


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

## Soft, cohesive 2-tone toon (smooth normals -> bands follow rounded geometry,
## not hard facets). Shadow side stays bright (0.66) so it reads warm, like the
## inspo. A thin, dark-tinted (not pure black) inverted-hull outline as next_pass.
func _toon(albedo: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color;
void light() {
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float band = smoothstep(0.18, 0.42, d) * 0.34 + 0.66; // 0.66 .. 1.0
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * ATTENUATION * band;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo", albedo)
	mat.next_pass = _outline(albedo.darkened(0.78))
	return mat


func _outline(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = 0.02
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	return mi


func _at(prop: Node3D, pos: Vector3) -> Node3D:
	prop.position = pos
	return prop


# -------------------------------------------------------------- props ----

func _ground_plane(sz: Vector2, col: Color, y: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = sz
	var m := _toon(col)
	m.next_pass = null  # no outline on the ground
	return _mi(pm, m, Vector3(0, y, 0))


func _dirt_patch(pos: Vector3, r: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.02
	c.radial_segments = 10
	var m := _toon(Color(0.55, 0.43, 0.27))
	m.next_pass = null
	return _mi(c, m, pos + Vector3(0, 0.005, 0))


## Rounded pine: smooth cones (more segments) so the silhouette reads soft.
func _pine(height: float) -> Node3D:
	var root := Node3D.new()
	var trunk_h := height * 0.22
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.11
	trunk.bottom_radius = 0.17
	trunk.height = trunk_h
	trunk.radial_segments = 8
	root.add_child(_mi(trunk, _toon(Color(0.46, 0.31, 0.19)), Vector3(0, trunk_h * 0.5, 0)))
	var dark := Color(0.24, 0.45, 0.27)
	var lite := Color(0.34, 0.57, 0.30)
	var base := trunk_h * 0.7
	root.add_child(_mi(_cone(1.0, height * 0.46, 9), _toon(dark), Vector3(0, base + height * 0.17, 0)))
	root.add_child(_mi(_cone(0.78, height * 0.42, 9), _toon(lite), Vector3(0, base + height * 0.40, 0)))
	root.add_child(_mi(_cone(0.52, height * 0.38, 9), _toon(dark), Vector3(0, base + height * 0.64, 0)))
	return root


## Warm autumn broadleaf: a clump of rounded blobs (spheres), like the inspo.
func _broadleaf(height: float) -> Node3D:
	var root := Node3D.new()
	var trunk_h := height * 0.42
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.10
	trunk.bottom_radius = 0.16
	trunk.height = trunk_h
	trunk.radial_segments = 8
	root.add_child(_mi(trunk, _toon(Color(0.5, 0.36, 0.22)), Vector3(0, trunk_h * 0.5, 0)))
	var o1 := Color(0.84, 0.42, 0.16)
	var o2 := Color(0.90, 0.55, 0.20)
	var cy := trunk_h + height * 0.22
	for b: Array in [
		[Vector3(0, cy + 0.18, 0), 0.85, o1], [Vector3(-0.5, cy, 0.15), 0.6, o2],
		[Vector3(0.5, cy - 0.05, -0.1), 0.62, o1], [Vector3(0.05, cy + 0.5, 0.0), 0.55, o2]]:
		var s := SphereMesh.new()
		s.radius = float(b[1])
		s.height = float(b[1]) * 1.9
		s.radial_segments = 9
		s.rings = 5
		root.add_child(_mi(s, _toon(b[2]), b[0]))
	return root


func _cone(radius: float, height: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


func _rock() -> Node3D:
	var root := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.0
	s.radial_segments = 7
	s.rings = 4
	root.add_child(_mi(s, _toon(Color(0.62, 0.61, 0.58)), Vector3(0, 0.4, 0), Vector3(1.1, 0.7, 1.0)))
	return root


func _bush() -> Node3D:
	var root := Node3D.new()
	for p: Array in [[Vector3(0, 0.42, 0), 0.5], [Vector3(0.32, 0.34, 0.1), 0.34], [Vector3(-0.3, 0.32, -0.05), 0.32]]:
		var s := SphereMesh.new()
		s.radius = float(p[1])
		s.height = float(p[1]) * 1.8
		s.radial_segments = 8
		s.rings = 5
		root.add_child(_mi(s, _toon(Color(0.36, 0.55, 0.26)), p[0]))
	return root


func _grass_tuft() -> Node3D:
	var root := Node3D.new()
	for off: Vector3 in [Vector3(0, 0, 0), Vector3(0.1, 0, 0.06), Vector3(-0.08, 0, -0.05)]:
		var blade := _cone(0.07, 0.34, 4)
		root.add_child(_mi(blade, _toon(Color(0.42, 0.62, 0.28)), off + Vector3(0, 0.17, 0)))
	return root
