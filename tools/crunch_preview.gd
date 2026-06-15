extends Control
## SPIKE preview v3: 3D-pixel-art pipeline (technique from the Godot 3d-pixelart
## demos): low-res render + nearest upscale, FLAT cohesive shading, and a
## screen-space depth+normal edge OUTLINE post-process (the clean A Short Hike
## outline) — no more inverted hull.
##
##   Godot_v4.6.3-stable_win64.exe --path C:/Dev/imota-idle res://tools/crunch_preview.tscn
##   Esc quit.  [ / ] finer/chunkier pixels.

const OUTLINE_SHADER := preload("res://tools/crunch_outline.gdshader")
const SHOT_PATH := "res://generated/props/_preview_shot.png"

var shrink := 4
const CAM_YAW := 45.0
const CAM_PITCH := 35.0

var _spin: Node3D
var _container: SubViewportContainer
var _vp: SubViewport
var _hint: Label
var _shot_done := false
var _frames := 0


func _ready() -> void:
	_container = SubViewportContainer.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.stretch_shrink = shrink
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_container)

	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)

	world.add_child(_ground(Vector2(18, 18), Color(0.49, 0.67, 0.33)))
	world.add_child(_dirt(Vector3(0.2, 0, 1.0), 2.2))
	world.add_child(_dirt(Vector3(-2.2, 0, -0.6), 1.6))

	_spin = Node3D.new()
	world.add_child(_spin)
	_spin.add_child(_at(_pine(3.4), Vector3(-2.4, 0, -1.2)))
	_spin.add_child(_at(_pine(2.6), Vector3(-3.6, 0, 1.0)))
	_spin.add_child(_at(_broadleaf(3.0), Vector3(2.1, 0, -1.8)))
	_spin.add_child(_at(_broadleaf(2.4), Vector3(3.3, 0, 1.4)))
	_spin.add_child(_at(_rock(), Vector3(-1.4, 0, 1.9)))
	_spin.add_child(_at(_bush(), Vector3(0.5, 0, 0.5)))
	_spin.add_child(_at(_bush(), Vector3(1.3, 0, 2.1)))
	for gp: Vector3 in [Vector3(-0.8, 0, -0.4), Vector3(1.6, 0, -0.6), Vector3(-2.4, 0, 0.6)]:
		_spin.add_child(_at(_grass(), gp))

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	cam.near = 0.05
	cam.far = 60.0
	world.add_child(cam)
	var target := Vector3(0, 1.0, 0)
	var dir := Vector3(
		cos(deg_to_rad(CAM_PITCH)) * sin(deg_to_rad(CAM_YAW)),
		sin(deg_to_rad(CAM_PITCH)),
		cos(deg_to_rad(CAM_PITCH)) * cos(deg_to_rad(CAM_YAW)))
	cam.position = target + dir * 20.0
	cam.look_at(target, Vector3.UP)

	# Screen-space outline as a fullscreen quad parented to the camera.
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	quad.extra_cull_margin = 16384.0
	var omat := ShaderMaterial.new()
	omat.shader = OUTLINE_SHADER
	omat.render_priority = 100
	omat.set_shader_parameter("outline_color", Color(0.10, 0.08, 0.10))
	omat.set_shader_parameter("depth_threshold", 0.6)  # world units: only big silhouette steps, not the ground's smooth slope
	omat.set_shader_parameter("normal_threshold", 0.55)
	omat.set_shader_parameter("thickness", 1.0)
	omat.set_shader_parameter("outline_opacity", 1.0)
	quad.material_override = omat
	quad.position = Vector3(0, 0, -1.0)
	cam.add_child(quad)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -120.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.67, 0.81, 0.89)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.66)
	env.ambient_light_energy = 0.45  # lower so flat albedos don't blow to white
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # truer flat colors
	cam.environment = env

	_hint = Label.new()
	_hint.position = Vector2(12, 10)
	_hint.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	add_child(_hint)
	_update_hint()


func _process(_delta: float) -> void:
	# Capture one frame to PNG so the look can be inspected without a screenshot.
	_frames += 1
	if not _shot_done and _frames == 8:
		_shot_done = true
		var img := _vp.get_texture().get_image()
		img.save_png(SHOT_PATH)


func _update_hint() -> void:
	if _hint != null:
		_hint.text = "Crunch preview v3 (screen-space outline) — 1/%d res.  [ ] finer/chunkier,  Esc quit." % shrink


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

## Flat, cohesive shading (the inspo uses near-flat textures): one gentle band,
## bright shadow side, NO per-mesh outline — the screen-space pass draws those.
func _flat(albedo: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color;
void fragment() {
	ALBEDO = albedo.rgb;
}
void light() {
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float band = smoothstep(0.0, 0.55, d) * 0.42 + 0.58; // 0.58 .. 1.0
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * ATTENUATION * band;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo", albedo)
	return mat


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

func _ground(sz: Vector2, col: Color) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = sz
	return _mi(pm, _flat(col), Vector3(0, -0.01, 0))


func _dirt(pos: Vector3, r: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.02
	c.radial_segments = 12
	return _mi(c, _flat(Color(0.56, 0.44, 0.28)), pos + Vector3(0, 0.005, 0))


func _cone(radius: float, height: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


func _pine(height: float) -> Node3D:
	var root := Node3D.new()
	var trunk_h := height * 0.22
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.11
	trunk.bottom_radius = 0.17
	trunk.height = trunk_h
	trunk.radial_segments = 8
	root.add_child(_mi(trunk, _flat(Color(0.47, 0.32, 0.2)), Vector3(0, trunk_h * 0.5, 0)))
	var dark := Color(0.26, 0.46, 0.28)
	var lite := Color(0.36, 0.58, 0.31)
	var base := trunk_h * 0.7
	root.add_child(_mi(_cone(1.0, height * 0.46, 10), _flat(dark), Vector3(0, base + height * 0.17, 0)))
	root.add_child(_mi(_cone(0.78, height * 0.42, 10), _flat(lite), Vector3(0, base + height * 0.40, 0)))
	root.add_child(_mi(_cone(0.52, height * 0.38, 10), _flat(dark), Vector3(0, base + height * 0.64, 0)))
	return root


func _broadleaf(height: float) -> Node3D:
	var root := Node3D.new()
	var trunk_h := height * 0.42
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.10
	trunk.bottom_radius = 0.16
	trunk.height = trunk_h
	trunk.radial_segments = 8
	root.add_child(_mi(trunk, _flat(Color(0.5, 0.36, 0.22)), Vector3(0, trunk_h * 0.5, 0)))
	var o1 := Color(0.86, 0.44, 0.18)
	var o2 := Color(0.92, 0.57, 0.22)
	var cy := trunk_h + height * 0.22
	for b: Array in [
		[Vector3(0, cy + 0.18, 0), 0.9, o1], [Vector3(-0.52, cy, 0.15), 0.62, o2],
		[Vector3(0.52, cy - 0.05, -0.1), 0.64, o1], [Vector3(0.05, cy + 0.52, 0.0), 0.56, o2]]:
		var s := SphereMesh.new()
		s.radius = float(b[1])
		s.height = float(b[1]) * 1.9
		s.radial_segments = 10
		s.rings = 6
		root.add_child(_mi(s, _flat(b[2]), b[0]))
	return root


func _rock() -> Node3D:
	var root := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.0
	s.radial_segments = 7
	s.rings = 4
	root.add_child(_mi(s, _flat(Color(0.63, 0.62, 0.59)), Vector3(0, 0.4, 0), Vector3(1.1, 0.7, 1.0)))
	return root


func _bush() -> Node3D:
	var root := Node3D.new()
	for p: Array in [[Vector3(0, 0.42, 0), 0.5], [Vector3(0.32, 0.34, 0.1), 0.34], [Vector3(-0.3, 0.32, -0.05), 0.32]]:
		var s := SphereMesh.new()
		s.radius = float(p[1])
		s.height = float(p[1]) * 1.8
		s.radial_segments = 9
		s.rings = 5
		root.add_child(_mi(s, _flat(Color(0.37, 0.56, 0.27)), p[0]))
	return root


func _grass() -> Node3D:
	var root := Node3D.new()
	for off: Vector3 in [Vector3(0, 0, 0), Vector3(0.1, 0, 0.06), Vector3(-0.08, 0, -0.05)]:
		root.add_child(_mi(_cone(0.07, 0.34, 4), _flat(Color(0.43, 0.63, 0.29)), off + Vector3(0, 0.17, 0)))
	return root
