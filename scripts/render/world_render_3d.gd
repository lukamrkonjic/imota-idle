extends Node
## 3D pixel-art renderer for the live world (committed port — replaces the 2D
## draw output, no toggle). Hosts a low-resolution SubViewport with a 3D world
## (iso ortho Camera3D, one key light, toon materials, OUR palette), presented at
## nearest-neighbour under the full-res HUD. The 2D nodes remain as the logic
## substrate (positions, pathing, picking) but their visuals are hidden.
##
## Stage A: 3D terrain from real chunk data + camera follow.  Stage C adds props.

const WG := preload("res://scripts/worldgen/wg.gd")
const TOON_GROUND := preload("res://shaders/toon_ground.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const INTERNAL := Vector2i(640, 360)
const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := 0.25                # height per elevation step (8px / 32px tile)

var world: Node2D
var sub: SubViewport
var world3d: Node3D
var cam: Camera3D
var present: TextureRect
var terrain_root: Node3D
var props_root: Node3D
var _ground_mat: ShaderMaterial
var _chunk_meshes: Dictionary = {}   # chunk key -> MeshInstance3D
var _prop_nodes: Dictionary = {}     # entity instance id -> Node3D (Stage C)
var _frames := 0
var _captured := false
var _active := false


func setup(w: Node2D) -> void:
	world = w
	if DisplayServer.get_name() == "headless":
		return   # tests run headless; keep the 2D path, no 3D build
	_active = true
	_build()
	_hide_2d()


func _build() -> void:
	sub = SubViewport.new()
	sub.size = INTERNAL
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub.use_taa = false
	sub.use_debanding = false
	sub.positional_shadow_atlas_size = 4096
	add_child(sub)

	world3d = Node3D.new()
	sub.add_child(world3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PixelPalette.pal("snow_a").lerp(PixelPalette.pal("water_a"), 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world3d.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	world3d.add_child(sun)

	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24.0
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)

	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("grass_dark"))
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("foliage_c"))

	# Present the low-res 3D world at nearest-neighbour, under the HUD (layer 1).
	var layer := CanvasLayer.new()
	layer.layer = 0
	world.add_child(layer)
	present = TextureRect.new()
	present.set_anchors_preset(Control.PRESET_FULL_RECT)
	present.texture = sub.get_texture()
	present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	present.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(present)


## Hide the 2D world visuals — every CanvasItem child of the world root — while
## the nodes stay alive as the logic substrate (positions, pathing, picking).
func _hide_2d() -> void:
	for node: Node in world.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false


# ----------------------------------------------------------------- runtime ----

func _process(_delta: float) -> void:
	if not _active or world.player == null:
		return
	_sync_camera()
	_sync_terrain()
	PropMeshes.sync_entities(self)
	_frames += 1
	if _frames == 90 and not _captured:
		_capture()


func _sync_camera() -> void:
	var c := iso_to_3d(world.player.position, 0.0)
	# Iso offset: yaw 45, pitch ~30 (2:1). Keep it constant so pixels stay stable.
	var dir := Vector3(1.0, 1.15, 1.0).normalized()
	cam.position = c + dir * 60.0
	cam.look_at(c, Vector3.UP)


## Build/free per-chunk terrain meshes to match the currently loaded chunks.
func _sync_terrain() -> void:
	var live := {}
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
		var key: String = chunk.key()
		live[key] = true
		if not _chunk_meshes.has(key):
			var mi := _build_chunk_terrain(chunk)
			terrain_root.add_child(mi)
			_chunk_meshes[key] = mi
	for key: String in _chunk_meshes.keys():
		if not live.has(key):
			var mi: Node = _chunk_meshes[key]
			if is_instance_valid(mi):
				mi.queue_free()
			_chunk_meshes.erase(key)


func _build_chunk_terrain(chunk: RefCounted) -> MeshInstance3D:
	var reg: RefCounted = WorldGen.reg
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := WG.CHUNK_TILES
	for ty: int in n:
		for tx: int in n:
			var gtx: int = int(chunk.cx) * n + tx
			var gty: int = int(chunk.cy) * n + ty
			var e: float = float(chunk.elev[ty * n + tx]) * ELEV_H
			var col: Color = reg.tile_def(chunk.tile_id(tx, ty))["colors"][0]
			var x0 := float(gtx) * TILE_S
			var z0 := float(gty) * TILE_S
			var x1 := x0 + TILE_S
			var z1 := z0 + TILE_S
			var a := Vector3(x0, e, z0)
			var b := Vector3(x1, e, z0)
			var cc := Vector3(x1, e, z1)
			var d := Vector3(x0, e, z1)
			for v: Vector3 in [a, b, cc, a, cc, d]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			# Vertical risers wherever this tile is higher than an in-chunk
			# neighbor, so terraced terrain reads as 3D blocks (the higher tile
			# owns the face; sideways normals fall into the toon shadow band).
			var rcol := col.darkened(0.06)
			if tx + 1 < n:
				var er := float(chunk.elev[ty * n + (tx + 1)]) * ELEV_H
				if e > er:
					_riser(st, Vector3(x1, e, z0), Vector3(x1, e, z1), er, Vector3(1, 0, 0), rcol)
			if tx > 0:
				var el := float(chunk.elev[ty * n + (tx - 1)]) * ELEV_H
				if e > el:
					_riser(st, Vector3(x0, e, z1), Vector3(x0, e, z0), el, Vector3(-1, 0, 0), rcol)
			if ty + 1 < n:
				var ef := float(chunk.elev[(ty + 1) * n + tx]) * ELEV_H
				if e > ef:
					_riser(st, Vector3(x1, e, z1), Vector3(x0, e, z1), ef, Vector3(0, 0, 1), rcol)
			if ty > 0:
				var eb := float(chunk.elev[(ty - 1) * n + tx]) * ELEV_H
				if e > eb:
					_riser(st, Vector3(x0, e, z0), Vector3(x1, e, z0), eb, Vector3(0, 0, -1), rcol)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ground_mat
	return mi


## A vertical riser quad from the top edge (p0->p1 at height top_y) down to bot_y.
func _riser(st: SurfaceTool, p0: Vector3, p1: Vector3, bot_y: float, normal: Vector3, col: Color) -> void:
	var a := p0
	var b := p1
	var c := Vector3(p1.x, bot_y, p1.z)
	var d := Vector3(p0.x, bot_y, p0.z)
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(normal)
		st.add_vertex(v)


## Map a 2D iso-pixel position to a 3D world position (Y from elevation/height).
func iso_to_3d(pos: Vector2, y: float) -> Vector3:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	return Vector3(gx * TILE_S, y, gy * TILE_S)


## Terrain height (3D Y) at a 2D iso position, sampled from the loaded chunk.
func height_at(pos: Vector2) -> float:
	var t := WG.world_to_tile(pos)
	var ck := WG.tile_to_chunk(t)
	var key := WG.key(world.current_layer, ck.x, ck.y)
	if not _chunk_meshes.has(key):
		return 0.0
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
		if chunk.key() == key:
			var lx: int = t.x - ck.x * WG.CHUNK_TILES
			var ly: int = t.y - ck.y * WG.CHUNK_TILES
			if lx >= 0 and lx < WG.CHUNK_TILES and ly >= 0 and ly < WG.CHUNK_TILES:
				return float(chunk.elev[ly * WG.CHUNK_TILES + lx]) * ELEV_H
			return 0.0
	return 0.0


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world3d_shot.png")
	print("[world3d] saved user://world3d_shot.png")
