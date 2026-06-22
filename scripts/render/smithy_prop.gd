extends RefCounted
class_name SmithyProp
## Loads models/smithy.glb and gives it a fitting hand-painted look. The mesh ships flat white
## (no UVs, no vertex colours, no texture), so we SYNTHESISE per-vertex colours from height
## bands — grey stone footing, timber-brown walls/posts, dark weathered roof — with a little
## hash dither so the low-poly facets read as worked, weathered material (matching the world's
## stylised props). Returns a ready-to-place Node3D; bottom_offset() lifts it to sit on ground.

const GLB := preload("res://models/smithy.glb")

# GLB scene-space AABB (from tools/glb_inspect): bottom at y≈-0.909, ~2 units across.
const SCENE_BOTTOM_Y := -0.9089
const NATIVE_WIDTH := 2.0

const STONE := Color(0.38, 0.38, 0.41)   # foundation / anvil base — grey stone
const WOOD := Color(0.44, 0.28, 0.15)    # timber walls + posts
const ROOF := Color(0.26, 0.20, 0.18)    # dark weathered roof


## Native bottom offset (world units) to add after scaling so the model sits ON the ground.
static func bottom_offset(model_scale: float) -> float:
	return -SCENE_BOTTOM_Y * model_scale


## Scale factor to make the smithy span `target_tiles` tiles (1 tile = 1 world unit).
static func scale_for(target_tiles: float) -> float:
	return target_tiles / NATIVE_WIDTH


static func build() -> Node3D:
	var inst: Node3D = GLB.instantiate()
	for mi: MeshInstance3D in _all_meshes(inst):
		_recolor(mi)
	return inst


static func _recolor(mi: MeshInstance3D) -> void:
	var src: Mesh = mi.mesh
	if src == null:
		return
	var aabb := src.get_aabb()
	var y0 := aabb.position.y
	var h := maxf(aabb.size.y, 0.0001)
	var out := ArrayMesh.new()
	for s: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i: int in verts.size():
			var v := verts[i]
			var t := clampf((v.y - y0) / h, 0.0, 1.0)   # 0 = footing, 1 = roof ridge
			var base: Color
			if t < 0.30:
				base = STONE
			elif t < 0.65:
				base = WOOD
			else:
				base = ROOF
			var n := _hash01(v) * 0.10 - 0.05            # ±5% facet dither
			cols[i] = Color(clampf(base.r + n, 0.0, 1.0), clampf(base.g + n, 0.0, 1.0),
				clampf(base.b + n, 0.0, 1.0), 1.0)
		arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = out
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.metallic = 0.0
	mi.material_override = mat


static func _hash01(v: Vector3) -> float:
	var x := sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453
	return x - floor(x)


static func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_all_meshes(c))
	return out
