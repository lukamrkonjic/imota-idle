extends RefCounted
class_name StaticTerrainRegions
## PLAY-MODE terrain for a fixed authored world: loads the pre-baked region meshes (BakedTerrainSet,
## written by tools/world_bake.gd) and instances them ONCE into terrain_root with the shared ground/
## water materials. This replaces the runtime TerrainMeshManager + TerrainStreamView build loop +
## FarTerrainBackdrop underlay — there is no per-frame meshing, chunk streaming, eviction, or seam
## reconcile, and terrain colours never recompute. Godot frustum culling decides what draws.
##
## There is NO _process here — the geometry is static. Region meshes are authored in GLOBAL tile/world
## coordinates (TILE_S = 1, same as the per-chunk path), so every MeshInstance3D uses an identity
## transform under the shared terrain_root. The editor (live brushing) keeps using the dynamic mesher;
## this is only chosen for the standalone game (see WorldRender3D._init_terrain_mode).

const DIR := "res://data/world/baked/"

var world: Node2D
var terrain_root: Node3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _root: Node3D
var _region_count := 0
var _water_count := 0


func setup(w: Node2D, root: Node3D, ground_mat: ShaderMaterial, water_mat: ShaderMaterial) -> void:
	world = w
	terrain_root = root
	_ground_mat = ground_mat
	_water_mat = water_mat


## Load <id>_terrain.res and instance every region. Returns true on success; false when no baked
## terrain exists (e.g. before a first bake) so the caller can fall back to the dynamic mesher.
func load_and_instance(id: String) -> bool:
	if id == "":
		return false
	var path := DIR + id + "_terrain.res"
	if not ResourceLoader.exists(path):
		push_warning("StaticTerrainRegions: no baked terrain at %s (run tools/world_bake.tscn)" % path)
		return false
	var tset: Resource = ResourceLoader.load(path)
	if tset == null or not (tset.get("ground_meshes") is Array):
		push_error("StaticTerrainRegions: corrupt baked terrain %s" % path)
		return false

	_root = Node3D.new()
	_root.name = "StaticTerrain"
	terrain_root.add_child(_root)
	var grounds: Array = tset.ground_meshes
	var waters: Array = tset.water_meshes
	for i: int in grounds.size():
		var gm: Mesh = grounds[i]
		if gm != null:
			_add_region_mesh(gm, _ground_mat)
			_region_count += 1
		var wm: Mesh = waters[i] if i < waters.size() else null
		if wm != null:
			_add_region_mesh(wm, _water_mat)
			_water_count += 1
	return true


func _add_region_mesh(mesh: Mesh, mat: ShaderMaterial) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# Terrain is flat-lit; only props cast shadows onto it (matches the per-chunk path).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)


func region_count() -> int:
	return _region_count


func water_count() -> int:
	return _water_count
