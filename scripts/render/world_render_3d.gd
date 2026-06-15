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
const TOON_WATER := preload("res://shaders/toon_water.gdshader")
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
var _water_mat: ShaderMaterial
var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (O(1) height lookup)
var batches_root: Node3D             # holds the per-(mesh,material) MultiMeshInstance3D
var _mover_nodes: Dictionary = {}    # moving entity id -> Node3D (player/enemies)
var _player_node: Node3D
var _static_sig := -1
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

	# Soft warm gradient sky (A Short Hike-ish) using palette-derived colors.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = PixelPalette.pal("water_a").lerp(PixelPalette.pal("snow_a"), 0.55)
	sky_mat.sky_horizon_color = PixelPalette.pal("snow_a").lerp(PixelPalette.pal("gold"), 0.28)
	sky_mat.ground_horizon_color = PixelPalette.pal("snow_a").lerp(PixelPalette.pal("gold"), 0.28)
	sky_mat.ground_bottom_color = PixelPalette.pal("grass_a").lerp(PixelPalette.pal("snow_a"), 0.3)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world3d.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_color = Color(1.0, 0.94, 0.8)   # warm afternoon sun (A Short Hike)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	sun.shadow_blur = 1.1   # softer shadow edge (the low-res render keeps it crisp enough)
	world3d.add_child(sun)

	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 17.0
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)

	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)
	batches_root = Node3D.new()
	world3d.add_child(batches_root)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("grass_dark"))
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("foliage_c"))

	_water_mat = ShaderMaterial.new()
	_water_mat.shader = TOON_WATER
	_water_mat.set_shader_parameter("base_color", PixelPalette.pal("water_a"))
	_water_mat.set_shader_parameter("shadow_color", PixelPalette.pal("water_b"))
	_water_mat.set_shader_parameter("light_color", PixelPalette.pal("water_foam"))

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
	_sync_movers()
	_sync_static_batches()
	_frames += 1
	if _frames == 90 and not _captured:
		_capture()


func _sync_camera() -> void:
	var c := iso_to_3d(world.player.position, height_at(world.player.position))
	# Exact 2:1 isometric: yaw 45, pitch 30. A ground tile then projects 2:1 like
	# the old 2D iso. dir.y = tan(30) * sqrt(2) = 0.8165 for the 1,_,1 horizontal.
	var dir := Vector3(1.0, 0.8165, 1.0).normalized()
	cam.position = c + dir * 80.0
	cam.look_at(c, Vector3.UP)


## Build/free per-chunk terrain meshes to match the currently loaded chunks.
func _sync_terrain() -> void:
	var live := {}
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
		var key: String = chunk.key()
		live[key] = true
		_chunk_by_key[key] = chunk
		if not _chunk_meshes.has(key):
			var node := _build_chunk_terrain(chunk)
			terrain_root.add_child(node)
			_chunk_meshes[key] = node
	for key: String in _chunk_meshes.keys():
		if not live.has(key):
			var mi: Node = _chunk_meshes[key]
			if is_instance_valid(mi):
				mi.queue_free()
			_chunk_meshes.erase(key)


const WATER_DROP := 0.14   # how far water sits below the surrounding ground

func _build_chunk_terrain(chunk: RefCounted) -> Node3D:
	var reg: RefCounted = WorldGen.reg
	var st := SurfaceTool.new()       # ground (non-water tiles)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wst := SurfaceTool.new()      # recessed water surface
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false
	var n := WG.CHUNK_TILES
	for ty: int in n:
		for tx: int in n:
			var gtx: int = int(chunk.cx) * n + tx
			var gty: int = int(chunk.cy) * n + ty
			var e: float = float(chunk.elev[ty * n + tx]) * ELEV_H
			var tdef: Dictionary = reg.tile_def(chunk.tile_id(tx, ty))
			var col: Color = _grade_ground(tdef["colors"][0], gtx, gty)
			var x0 := float(gtx) * TILE_S
			var z0 := float(gty) * TILE_S
			var x1 := x0 + TILE_S
			var z1 := z0 + TILE_S
			if bool(tdef.get("water", false)):
				# Recessed flat water quad (own toon-water material + waves).
				has_water = true
				var wy := e - WATER_DROP
				for v: Vector3 in [Vector3(x0, wy, z0), Vector3(x1, wy, z0), Vector3(x1, wy, z1), Vector3(x0, wy, z0), Vector3(x1, wy, z1), Vector3(x0, wy, z1)]:
					wst.set_normal(Vector3.UP)
					wst.add_vertex(v)
				continue
			var a := Vector3(x0, e, z0)
			var b := Vector3(x1, e, z0)
			var cc := Vector3(x1, e, z1)
			var d := Vector3(x0, e, z1)
			for v: Vector3 in [a, b, cc, a, cc, d]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			# Vertical risers wherever this tile is higher than an in-chunk
			# neighbor, so terraced terrain reads as 3D blocks (sideways normals
			# fall into the toon shadow band).
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
	var root := Node3D.new()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _ground_mat
	root.add_child(ground)
	if has_water:
		var water := MeshInstance3D.new()
		water.mesh = wst.commit()
		water.material_override = _water_mat
		root.add_child(water)
	return root


## Warm + enrich a terrain tile color and add BROAD low-frequency variation
## (large painted regions, not noise) so the ground reads painterly, not as flat
## monotone diamonds. Original warm grading — our palette, A Short Hike vibe.
func _grade_ground(col: Color, gtx: int, gty: int) -> Color:
	var c := Color.from_hsv(col.h, minf(col.s * 1.22, 1.0), minf(col.v * 1.12, 1.0), col.a)
	var fx := float(gtx)
	var fz := float(gty)
	# Two broad bands (period ~14-25 tiles) -> large sunlit/shaded patches.
	var bright := 0.5 + 0.5 * sin(fx * 0.07) * cos(fz * 0.06)
	var warm := clampf(sin((fx + fz) * 0.045 + 1.3), 0.0, 1.0)
	c = c.lerp(c.lightened(0.16), bright * 0.55)
	# Warm dry/golden patches in some regions (subtle).
	c = c.lerp(Color.from_hsv(0.12, 0.36, c.v * 1.04, c.a), warm * 0.16)
	return c


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


## Movers (player + enemies) stay individual nodes — few of them, and they move.
func _sync_movers() -> void:
	if _player_node == null:
		_player_node = PropMeshes.build_node(PropMeshes.figure_parts(PixelPalette.pal("outfit_a"), PixelPalette.pal("skin_a")))
		props_root.add_child(_player_node)
	_player_node.position = iso_to_3d(world.player.position, height_at(world.player.position))
	var live := {}
	for e: Node in world.entities:
		if not is_instance_valid(e) or not PropMeshes.is_moving(e):
			continue
		var id := e.get_instance_id()
		live[id] = true
		var n: Node3D = _mover_nodes.get(id)
		if n == null:
			n = PropMeshes.build_node(PropMeshes.figure_parts(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a")))
			props_root.add_child(n)
			_mover_nodes[id] = n
		n.position = iso_to_3d(e.position, height_at(e.position))
	for id: int in _mover_nodes.keys():
		if not live.has(id):
			var n: Node = _mover_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			_mover_nodes.erase(id)


## Batch all static decor + props into per-(mesh,material) MultiMeshes. Rebuilt
## only when the static set changes (or a periodic safety pass), not every frame.
func _sync_static_batches() -> void:
	var sig: int = int(world._decor_nodes.size()) * 100003 + int(world.entities.size())
	if sig == _static_sig and _frames % 120 != 0:
		return
	_static_sig = sig
	for c: Node in batches_root.get_children():
		c.queue_free()
	var groups := {}
	for d: Node in world._decor_nodes:
		if not is_instance_valid(d):
			continue
		var pl := Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.131), iso_to_3d(d.position, height_at(d.position)))
		_collect(PropMeshes.decor_parts(str(d.kind)), pl, groups)
	for e: Node in world.entities:
		if not is_instance_valid(e) or PropMeshes.is_moving(e):
			continue
		var parts: Array = PropMeshes.entity_parts(e)
		if parts.is_empty():
			continue
		_collect(parts, Transform3D(Basis.IDENTITY, iso_to_3d(e.position, height_at(e.position))), groups)
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		var xf: Array = g["xf"]
		mm.instance_count = xf.size()
		for i: int in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		batches_root.add_child(mmi)


func _collect(parts: Array, placement: Transform3D, groups: Dictionary) -> void:
	for p: Dictionary in parts:
		var key := str(p["mesh"].get_instance_id()) + "|" + str(p["mat"].get_instance_id())
		if not groups.has(key):
			groups[key] = {"mesh": p["mesh"], "mat": p["mat"], "xf": []}
		var local := Transform3D(Basis().scaled(p["scl"]), p["off"])
		groups[key]["xf"].append(placement * local)


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
	var chunk: RefCounted = _chunk_by_key.get(key)
	if chunk == null:
		return 0.0
	var lx: int = t.x - ck.x * WG.CHUNK_TILES
	var ly: int = t.y - ck.y * WG.CHUNK_TILES
	if lx >= 0 and lx < WG.CHUNK_TILES and ly >= 0 and ly < WG.CHUNK_TILES:
		return float(chunk.elev[ly * WG.CHUNK_TILES + lx]) * ELEV_H
	return 0.0


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world3d_shot.png")
	print("[world3d] saved user://world3d_shot.png")
