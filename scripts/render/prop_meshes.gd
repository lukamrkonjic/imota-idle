extends RefCounted
## Shared 3D mesh + toon-material library keyed by entity "kind", and the mirror
## that instances one 3D node per live WorldEntity for the 3D renderer.
## (Stage C of the port — later replaced by per-chunk MultiMesh; see PORT_3D_PLAN.)
##
## Meshes and materials are cached statically and SHARED across instances — each
## entity just gets cheap MeshInstance3D nodes pointing at the shared resources.

const TOON := preload("res://shaders/toon_world.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


## Mirror render.world.entities into 3D prop nodes under render.props_root.
static func sync_entities(render) -> void:
	var live := {}
	for e: Node in render.world.entities:
		if not is_instance_valid(e):
			continue
		var id := e.get_instance_id()
		live[id] = true
		var node: Node3D = render._prop_nodes.get(id)
		if node == null:
			node = _build_for(e)
			if node == null:
				continue
			render.props_root.add_child(node)
			render._prop_nodes[id] = node
		node.position = render.iso_to_3d(e.position, render.height_at(e.position))
	for id: int in render._prop_nodes.keys():
		if not live.has(id):
			var n: Node = render._prop_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			render._prop_nodes.erase(id)


## Build a 3D prop node for an entity kind (shared meshes/materials). Returns null
## for kinds rendered by the terrain (water) or not yet mapped.
static func _build_for(e: Node) -> Node3D:
	var kind := str(e.kind)
	match kind:
		"tree", "landmark_tree":
			# Match the 2D species silhouettes: conifers are conical, the rest round.
			var species := TreeArt.classify(str(e.get("label")))
			return _conifer() if species == "fir" else _tree()
		"rock":
			return _rock()
		"node":
			return _bush()
		"enemy":
			return _figure(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a"))
		"house", "building":
			return _house()
		"stall", "tent":
			return _tent()
		_:
			return null


# ------------------------------------------------------------------ builders ----

static func _tree() -> Node3D:
	var root := Node3D.new()
	_add(root, _cyl("trunk", 0.16, 0.24, 1.6), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.8, 0))
	var leaf := _mat("foliage_a", "foliage_b", "foliage_c")
	_add(root, _sphere("canopy_lo", 1.2), leaf, Vector3(0, 2.0, 0), Vector3(1, 0.82, 1))
	_add(root, _sphere("canopy_hi", 0.85), _mat("foliage_c", "foliage_a", "foliage_c"), Vector3(0.15, 2.8, -0.1), Vector3(1, 0.82, 1))
	return root


static func _conifer() -> Node3D:
	var root := Node3D.new()
	_add(root, _cyl("contrunk", 0.14, 0.2, 1.0), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.5, 0))
	var dark := _mat("fir_a", "fir_b", "foliage_c")
	# 3 narrowing offset sections -> a readable conifer (not one perfect cone).
	_add(root, _cone("fir0", 1.05, 0.7, 1.0), dark, Vector3(0, 1.0, 0))
	_add(root, _cone("fir1", 0.82, 0.5, 0.95), dark, Vector3(0.05, 1.7, 0))
	_add(root, _cone("fir2", 0.55, 0.08, 0.9), dark, Vector3(-0.04, 2.35, 0))
	return root


static func _bush() -> Node3D:
	var root := Node3D.new()
	var leaf := _mat("foliage_b", "grass_dark", "foliage_a")
	_add(root, _sphere("bush", 0.55), leaf, Vector3(0, 0.4, 0), Vector3(1.1, 0.8, 1.1))
	return root


static func _rock() -> Node3D:
	var root := Node3D.new()
	_add(root, _octa("rock"), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.3, 0), Vector3(0.9, 0.7, 0.9))
	return root


static func _figure(body_key: Color, head_key: Color) -> Node3D:
	var root := Node3D.new()
	var bm := _mat_from(body_key, body_key.darkened(0.35), body_key.lightened(0.2))
	var hm := _mat_from(head_key, head_key.darkened(0.3), head_key.lightened(0.2))
	_add(root, _capsule("fig_body", 0.28, 1.0), bm, Vector3(0, 0.6, 0))
	_add(root, _sphere("fig_head", 0.26), hm, Vector3(0, 1.3, 0))
	return root


static func _house() -> Node3D:
	var root := Node3D.new()
	_add(root, _box("house_body", Vector3(2.6, 1.7, 2.2)), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 1.0, 0))
	_add(root, _prism("house_roof", Vector3(3.2, 1.2, 2.7)), _mat("stone_a", "stone_b", "snow_a"), Vector3(0, 2.45, 0))
	return root


static func _tent() -> Node3D:
	var root := Node3D.new()
	_add(root, _prism("tent", Vector3(1.6, 1.3, 1.6)), _mat("outfit_a", "outfit_b", "water_foam"), Vector3(0, 0.65, 0))
	return root


# ------------------------------------------------------------------ helpers ----

static func _add(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	root.add_child(mi)


static func _cyl(key: String, top: float, bot: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bot
		m.height = h
		m.radial_segments = 7
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cone(key: String, bot: float, top: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bot
		m.height = h
		m.radial_segments = 8
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _sphere(key: String, r: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 1.7
		m.radial_segments = 9
		m.rings = 5
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _capsule(key: String, r: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 3
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _box(key: String, size: Vector3) -> Mesh:
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _prism(key: String, size: Vector3) -> Mesh:
	if not _mesh_cache.has(key):
		var m := PrismMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _octa(key: String) -> Mesh:
	if not _mesh_cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, -0.6, 0)]
		var f := [[4, 0, 2], [4, 2, 1], [4, 1, 3], [4, 3, 0], [5, 2, 0], [5, 1, 2], [5, 3, 1], [5, 0, 3]]
		for tri: Array in f:
			for vi: int in tri:
				st.add_vertex(v[vi] as Vector3)
		st.generate_normals()
		_mesh_cache[key] = st.commit()
	return _mesh_cache[key]


static func _mat(base_key: String, shadow_key: String, light_key: String) -> ShaderMaterial:
	var ck := base_key + "|" + shadow_key + "|" + light_key
	if not _mat_cache.has(ck):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("base_color", PixelPalette.pal(base_key))
		m.set_shader_parameter("shadow_color", PixelPalette.pal(shadow_key))
		m.set_shader_parameter("light_color", PixelPalette.pal(light_key))
		_mat_cache[ck] = m
	return _mat_cache[ck]


static func _mat_from(base: Color, shadow: Color, light: Color) -> ShaderMaterial:
	var ck := "%s|%s|%s" % [base, shadow, light]
	if not _mat_cache.has(ck):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("shadow_color", shadow)
		m.set_shader_parameter("light_color", light)
		_mat_cache[ck] = m
	return _mat_cache[ck]
