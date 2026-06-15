extends Node
## SPIKE (throwaway): hybrid 3D -> iso-sprite baker.
##
## Builds low-poly 3D props in a SubViewport, renders them at a fixed dimetric
## (~2:1 iso) angle with flat/cel shading + an inverted-hull outline at LOW
## resolution (that low-res render IS the "crunch"), then saves transparent PNGs.
## Runtime would just draw these sprites in the existing 2D world.
##
## Run windowed (needs a GPU; --headless has no rendering):
##   Godot_v4.6.3-stable_win64.exe --path C:/Dev/imota-idle res://tools/prop_baker_3d.tscn
##
## Output: res://generated/props/*.png  (+ a contact sheet for eyeballing)

const OUT_DIR := "res://generated/props/"

# Dimetric camera: yaw 45°, pitch ~30° -> close to the world's 2:1 iso. Tunable.
const CAM_YAW := 45.0
const CAM_PITCH := 30.0

var _vp: SubViewport
var _cam: Camera3D
var _prop_root: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	await _bake_all()
	print("baker: done")
	get_tree().quit(0)


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(112, 144)
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED  # no AA -> crisp pixels
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)
	_prop_root = Node3D.new()
	world.add_child(_prop_root)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 4.0
	world.add_child(_cam)

	# Upper-right "sun" (matches the 2D art guide) + soft ambient fill.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -125.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam.environment = env


## Frame the camera on a prop of the given height and bake one PNG.
func _bake(prop: Node3D, height: float, vp_size: Vector2i, out_name: String) -> void:
	for c: Node in _prop_root.get_children():
		c.queue_free()
	_prop_root.add_child(prop)
	_vp.size = vp_size

	var target := Vector3(0.0, height * 0.45, 0.0)
	var dir := Vector3(
		cos(deg_to_rad(CAM_PITCH)) * sin(deg_to_rad(CAM_YAW)),
		sin(deg_to_rad(CAM_PITCH)),
		cos(deg_to_rad(CAM_PITCH)) * cos(deg_to_rad(CAM_YAW)))
	_cam.position = target + dir * 12.0
	_cam.look_at(target, Vector3.UP)
	_cam.size = height * 1.25

	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw  # second frame so shadows settle
	var img := _vp.get_texture().get_image()
	var err := img.save_png(OUT_DIR + out_name)
	print("  %s %s (%dx%d)" % ["ok " if err == OK else "ERR", out_name, vp_size.x, vp_size.y])


func _bake_all() -> void:
	await _bake(_make_tree(2, 3.2), 3.4, Vector2i(112, 150), "tree_oak.png")
	await _bake(_make_tree(1, 2.4), 2.6, Vector2i(96, 128), "tree_small.png")
	await _bake(_make_rock(), 1.2, Vector2i(112, 90), "rock.png")
	await _bake(_make_bush(), 1.0, Vector2i(96, 80), "bush.png")
	# Deliberately crunchy variants to judge the pixel-art density.
	await _bake(_make_tree(2, 3.2), 3.4, Vector2i(56, 74), "tree_oak_crunchy.png")
	await _bake(_make_rock(), 1.2, Vector2i(54, 44), "rock_crunchy.png")


# ------------------------------------------------------------- materials ----

## Flat-faceted + 2-band cel shader: forces per-face normals (low-poly facets)
## and steps the lighting, with an inverted-hull black outline as next_pass.
func _flat_toon_mat(albedo: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color;
void fragment() {
	ALBEDO = albedo.rgb;
	NORMAL = -normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
}
void light() {
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float band = d > 0.5 ? 1.0 : (d > 0.0 ? 0.62 : 0.4);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * ATTENUATION * band;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo", albedo)
	mat.next_pass = _outline_mat()
	return mat


func _outline_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.07, 0.06, 0.08)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = 0.035
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	return mi


# ----------------------------------------------------------------- props ----

func _cone(radius: float, height: float, segs: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


func _make_tree(tier: int, height: float) -> Node3D:
	var root := Node3D.new()
	var trunk_h := height * 0.34
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.10
	trunk.bottom_radius = 0.16
	trunk.height = trunk_h
	trunk.radial_segments = 5
	root.add_child(_mesh(trunk, _flat_toon_mat(Color(0.42, 0.29, 0.18)), Vector3(0, trunk_h * 0.5, 0)))
	var green := Color(0.30, 0.55, 0.26) if tier == 1 else Color(0.22, 0.48, 0.24)
	var green2 := green.lightened(0.12)
	var base := trunk_h * 0.85
	root.add_child(_mesh(_cone(0.95, height * 0.45), _flat_toon_mat(green), Vector3(0, base + height * 0.18, 0)))
	root.add_child(_mesh(_cone(0.70, height * 0.40), _flat_toon_mat(green2), Vector3(0, base + height * 0.42, 0)))
	root.add_child(_mesh(_cone(0.45, height * 0.34), _flat_toon_mat(green), Vector3(0, base + height * 0.64, 0)))
	return root


func _make_rock() -> Node3D:
	var root := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.7
	s.height = 1.1
	s.radial_segments = 6
	s.rings = 3
	root.add_child(_mesh(s, _flat_toon_mat(Color(0.55, 0.55, 0.6)), Vector3(0, 0.45, 0), Vector3(1.0, 0.7, 1.0)))
	var s2 := SphereMesh.new()
	s2.radius = 0.4
	s2.height = 0.6
	s2.radial_segments = 6
	s2.rings = 2
	root.add_child(_mesh(s2, _flat_toon_mat(Color(0.5, 0.5, 0.56)), Vector3(0.45, 0.25, 0.2), Vector3(1, 0.7, 1)))
	return root


func _make_bush() -> Node3D:
	var root := Node3D.new()
	for p: Array in [[Vector3(0, 0.45, 0), 0.5], [Vector3(0.35, 0.35, 0.1), 0.34], [Vector3(-0.3, 0.32, -0.05), 0.32]]:
		var s := SphereMesh.new()
		s.radius = float(p[1])
		s.height = float(p[1]) * 1.7
		s.radial_segments = 6
		s.rings = 3
		root.add_child(_mesh(s, _flat_toon_mat(Color(0.32, 0.52, 0.24)), p[0]))
	return root
