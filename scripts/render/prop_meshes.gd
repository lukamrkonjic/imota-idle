extends RefCounted
## Shared 3D mesh + toon-material library for the 3D pixel-art port. Exposes each
## prop/decor kind as a list of PARTS ({mesh, mat, off, scl}); the renderer batches
## identical parts into per-(mesh,material) MultiMeshInstance3D groups, so hundreds
## of trees/tufts/rocks cost a handful of draw calls. Movers (player/enemies) are
## built as individual nodes via build_node().
##
## Meshes and materials are cached statically and SHARED across every instance.

const TOON := preload("res://shaders/toon_world.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


# --------------------------------------------------------------- part lists ----

## Static (batchable) parts for a world entity, or [] if it should not be batched
## (movers like enemies, or unmapped kinds rendered by the terrain).
static func entity_parts(e: Node) -> Array:
	match str(e.kind):
		"tree", "landmark_tree":
			return _conifer_parts() if TreeArt.classify(str(e.get("label"))) == "fir" else _tree_parts()
		"rock":
			return _rock_parts()
		"node":
			return _bush_parts()
		"house", "building":
			return _house_parts()
		"stall", "tent":
			return _tent_parts()
		_:
			return []


static func is_moving(e: Node) -> bool:
	return str(e.kind) == "enemy"


static func decor_parts(kind: String) -> Array:
	match kind:
		"flower":
			return [
				_part(_sphere("d_ftuft", 0.16), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.12, 0), Vector3(1.0, 0.7, 1.0)),
				_part(_sphere("d_fhead", 0.1), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.34, 0))]
		"shrub", "bramble", "shrubbery":
			return [_part(_sphere("d_bush", 0.3), _mat("foliage_b", "grass_dark", "foliage_a"), Vector3(0, 0.22, 0), Vector3(1.1, 0.8, 1.1))]
		"mushroom":
			return [
				_part(_cyl("d_mstalk", 0.05, 0.07, 0.22), _mat("snow_a", "stone_b", "snow_a"), Vector3(0, 0.11, 0)),
				_part(_sphere("d_mcap", 0.14), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 0.26, 0), Vector3(1.0, 0.6, 1.0))]
		"cactus":
			return [_part(_cone("d_cact", 0.16, 0.12, 0.6), _mat("fir_a", "fir_b", "foliage_c"), Vector3(0, 0.3, 0))]
		"pebble", "rubble", "shell", "stone":
			return [_part(_sphere("d_peb", 0.16), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.06, 0), Vector3(1.3, 0.55, 1.1))]
		"stick", "driftwood", "bone":
			return [_part(_box("d_stick", Vector3(0.5, 0.07, 0.09)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.05, 0))]
		_:  # grass, fern, reed, vine, moss, lichen, ... -> green tuft
			return [_part(_sphere("d_tuft", 0.22), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.16, 0), Vector3(1.0, 0.7, 1.0))]


static func _tree_parts() -> Array:
	# Fuller, rounder canopy (A Short Hike-ish): a big central mass, side lobes,
	# and a lighter sunlit crown — the toon bands do the soft shading.
	var leaf := _mat("foliage_a", "foliage_b", "foliage_c")
	var crown := _mat("foliage_c", "foliage_a", "foliage_c")
	return [
		_part(_cyl("trunk", 0.16, 0.26, 1.5), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.75, 0)),
		_part(_sphere("can_main", 1.35), leaf, Vector3(0, 2.05, 0), Vector3(1.05, 0.9, 1.05)),
		_part(_sphere("can_l", 0.95), leaf, Vector3(-0.78, 1.85, 0.32), Vector3(1, 0.85, 1)),
		_part(_sphere("can_r", 0.9), leaf, Vector3(0.8, 1.9, -0.24), Vector3(1, 0.85, 1)),
		_part(_sphere("can_f", 0.85), leaf, Vector3(0.1, 1.8, 0.7), Vector3(1, 0.85, 1)),
		_part(_sphere("can_top", 1.0), crown, Vector3(0.05, 2.75, -0.05), Vector3(1, 0.85, 1))]


static func _conifer_parts() -> Array:
	var dark := _mat("fir_a", "fir_b", "foliage_c")
	return [
		_part(_cyl("contrunk", 0.14, 0.2, 1.0), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.5, 0)),
		_part(_cone("fir0", 1.15, 0.78, 1.1), dark, Vector3(0, 1.0, 0)),
		_part(_cone("fir1", 0.9, 0.55, 1.0), dark, Vector3(0.05, 1.7, 0)),
		_part(_cone("fir2", 0.62, 0.3, 0.95), dark, Vector3(-0.04, 2.35, 0.02)),
		_part(_cone("fir3", 0.36, 0.05, 0.85), dark, Vector3(0.02, 2.95, 0))]


static func _bush_parts() -> Array:
	var leaf := _mat("foliage_b", "grass_dark", "foliage_a")
	return [
		_part(_sphere("bush_m", 0.55), leaf, Vector3(0, 0.4, 0), Vector3(1.1, 0.85, 1.1)),
		_part(_sphere("bush_l", 0.38), leaf, Vector3(-0.4, 0.32, 0.12), Vector3(1.1, 0.8, 1.1)),
		_part(_sphere("bush_r", 0.36), leaf, Vector3(0.4, 0.3, -0.1), Vector3(1.1, 0.8, 1.1))]


static func _rock_parts() -> Array:
	return [_part(_octa("rock"), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.3, 0), Vector3(0.9, 0.7, 0.9))]


static func _house_parts() -> Array:
	return [
		_part(_box("house_body", Vector3(2.6, 1.7, 2.2)), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 1.0, 0)),
		_part(_prism("house_roof", Vector3(3.2, 1.2, 2.7)), _mat("stone_a", "stone_b", "snow_a"), Vector3(0, 2.45, 0))]


static func _tent_parts() -> Array:
	return [_part(_prism("tent", Vector3(1.6, 1.3, 1.6)), _mat("outfit_a", "outfit_b", "water_foam"), Vector3(0, 0.65, 0))]


static func figure_parts(body: Color, head: Color) -> Array:
	return [
		_part(_capsule("fig_body", 0.28, 1.0), _mat_from(body, body.darkened(0.35), body.lightened(0.2)), Vector3(0, 0.6, 0)),
		_part(_sphere("fig_head", 0.26), _mat_from(head, head.darkened(0.3), head.lightened(0.2)), Vector3(0, 1.3, 0))]


# ----------------------------------------------------------- node (movers) ----

## Build an individual Node3D from a part list (used for the player and enemies).
static func build_node(parts: Array) -> Node3D:
	var root := Node3D.new()
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = p["mat"]
		mi.position = p["off"]
		mi.scale = p["scl"]
		root.add_child(mi)
	return root


# ------------------------------------------------------------------ helpers ----

static func _part(mesh: Mesh, mat: Material, off: Vector3, scl := Vector3.ONE) -> Dictionary:
	return {"mesh": mesh, "mat": mat, "off": off, "scl": scl}


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
		# Foliage sways gently in the wind; trunks/stone/walls stay put.
		if base_key.begins_with("foliage") or base_key.begins_with("fir"):
			m.set_shader_parameter("wind", 0.06)
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
