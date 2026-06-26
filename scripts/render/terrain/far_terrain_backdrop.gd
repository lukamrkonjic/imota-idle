extends RefCounted
class_name FarTerrainBackdrop
## A deterministic, low-cost terrain safety net for the camera footprint. It samples WorldGen's
## no-chunk surface probe at 4x4 cells per chunk and sits below detailed terrain, so real streamed
## meshes always win while a rapid orbit never exposes the clear colour behind missing terrain.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

const CELL_TILES := 4
const UNDERLAY_Y := -1.25

var world: Node2D
var material: Material
var instance: MeshInstance3D
var _last_visible: Dictionary = {}


func setup(w: Node2D, terrain_root: Node3D, terrain_material: Material) -> void:
	world = w
	material = terrain_material
	instance = MeshInstance3D.new()
	instance.name = "FarTerrainBackdrop"
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(instance)


func update(stream_view: TerrainStreamView) -> void:
	if world.current_layer != 0:
		instance.visible = false
		return
	var visible := stream_view.visible_chunks()
	if visible == _last_visible:
		return
	_last_visible = visible.duplicate()
	instance.mesh = _build_mesh(visible)
	instance.visible = instance.mesh != null


func _build_mesh(visible: Dictionary) -> ArrayMesh:
	if visible.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for key: String in visible:
		var parts := key.split(":")
		if parts.size() != 3:
			continue
		_emit_chunk(st, int(parts[1]), int(parts[2]))
	return st.commit()


func _emit_chunk(st: SurfaceTool, cx: int, cy: int) -> void:
	var x0 := cx * WG.CHUNK_TILES
	var z0 := cy * WG.CHUNK_TILES
	for z: int in range(0, WG.CHUNK_TILES, CELL_TILES):
		for x: int in range(0, WG.CHUNK_TILES, CELL_TILES):
			var sx := x0 + x + int(CELL_TILES * 0.5)
			var sz := z0 + z + int(CELL_TILES * 0.5)
			var tid := WorldGen.surface_tile_id(sx, sz)
			if tid < 0 or tid >= WorldGen.reg.tile_order.size():
				tid = int(WorldGen.reg.tile_index.get("grass", 0))
			_emit_quad(st, float(x0 + x), float(z0 + z), float(CELL_TILES), ChunkRenderer.tile_color(WorldGen.reg, tid))


func _emit_quad(st: SurfaceTool, x: float, z: float, size: float, color: Color) -> void:
	var a := Vector3(x, UNDERLAY_Y, z)
	var b := Vector3(x + size, UNDERLAY_Y, z)
	var c := Vector3(x + size, UNDERLAY_Y, z + size)
	var d := Vector3(x, UNDERLAY_Y, z + size)
	for p: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.set_color(color)
		st.set_uv(Vector2.ZERO)
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(p)
