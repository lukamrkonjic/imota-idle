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
const PALETTE_SNAP := preload("res://shaders/palette_snap.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const INTERNAL := Vector2i(448, 252)   # crunchier (fewer pixels, A Short Hike-style)
const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := 0.25                # height per elevation step (8px / 32px tile)
const DRESSING_ANCHOR := 4          # visual set dressing snaps to this tile grid
const FOREST_PREVIEW_ARG := "--forest-preview"
const TERRAIN_CULL_TILES := 34.0
const PROP_CULL_TILES := 30.0

var world: Node2D
var sub: SubViewport
var world3d: Node3D
var cam: Camera3D
var present: TextureRect
var terrain_root: Node3D
var props_root: Node3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _foam_mat: StandardMaterial3D
var _snap_mat: ShaderMaterial
var _chunk_meshes: Dictionary = {}   # chunk key -> Node3D (ground + water)
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (O(1) height lookup)
var batches_root: Node3D             # holds the per-(mesh,material) MultiMeshInstance3D
var dressing_root: Node3D            # visual-only hiking-diorama silhouettes near camera
var _mover_nodes: Dictionary = {}    # moving entity id -> Node3D (player/enemies)
var _mover_prev: Dictionary = {}     # key -> last 3D pos (for walk detection)
var _mover_yaw: Dictionary = {}      # key -> smoothed facing yaw
var _mover_walk: Dictionary = {}     # key -> smoothed walk amount 0..1
var _player_node: Node3D
var _static_sig := ""
var _dressing_sig := ""
var _forest_preview_done := false
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
	sub.positional_shadow_atlas_size = 0
	add_child(sub)
	PropMeshes.warm_static_caches()

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
	# Warm distance haze (A Short Hike atmospheric perspective): distant terrain
	# fades toward a soft warm tone, giving the world depth and coziness.
	env.fog_enabled = true
	env.fog_light_color = PixelPalette.pal("snow_a").lerp(PixelPalette.pal("gold"), 0.4)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0014
	env.fog_sky_affect = 0.04
	env.fog_aerial_perspective = 0.06
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
	cam.size = 11.8
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)

	terrain_root = Node3D.new()
	world3d.add_child(terrain_root)
	props_root = Node3D.new()
	world3d.add_child(props_root)
	batches_root = Node3D.new()
	world3d.add_child(batches_root)
	dressing_root = Node3D.new()
	world3d.add_child(dressing_root)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TOON_GROUND
	_ground_mat.set_shader_parameter("shadow_tint", PixelPalette.pal("forest_green"))
	_ground_mat.set_shader_parameter("light_tint", PixelPalette.pal("sunlit_grass"))
	_ground_mat.set_shader_parameter("ambient", 0.14)
	_ground_mat.set_shader_parameter("softness", 0.03)

	_water_mat = ShaderMaterial.new()
	_water_mat.shader = TOON_WATER
	_water_mat.set_shader_parameter("base_color", PixelPalette.pal("water_deep").lerp(PixelPalette.pal("water_c"), 0.35))
	_water_mat.set_shader_parameter("shadow_color", PixelPalette.pal("water_b"))
	_water_mat.set_shader_parameter("light_color", PixelPalette.pal("water_spark"))

	_foam_mat = StandardMaterial3D.new()
	_foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foam_mat.albedo_color = PixelPalette.pal("water_spark")
	_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Present the low-res 3D world at nearest-neighbour, under the HUD (layer 1).
	var layer := CanvasLayer.new()
	layer.layer = 0
	world.add_child(layer)
	present = TextureRect.new()
	present.set_anchors_preset(Control.PRESET_FULL_RECT)
	present.texture = sub.get_texture()
	present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	present.stretch_mode = TextureRect.STRETCH_SCALE
	# Let clicks / scroll-wheel fall through to the 2D world (movement, picking,
	# zoom all still run on the hidden 2D substrate).
	present.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_mat = ShaderMaterial.new()
	_snap_mat.shader = PALETTE_SNAP
	_snap_mat.set_shader_parameter("palette_tex", _palette_texture())
	_snap_mat.set_shader_parameter("palette_count", PixelPalette.PAL.size())
	_snap_mat.set_shader_parameter("enabled", 1.0)
	_snap_mat.set_shader_parameter("strength", 0.8)
	_snap_mat.set_shader_parameter("contrast", 1.22)
	_snap_mat.set_shader_parameter("saturation", 1.06)
	_snap_mat.set_shader_parameter("brightness", 0.88)
	present.material = _snap_mat
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
	_maybe_teleport_to_forest_preview()
	_sync_camera()
	_sync_terrain()
	_sync_movers()
	_sync_static_batches()
	# (style-dressing diorama removed — it spawned canned hike props around the
	#  camera everywhere; the real world content renders on its own now.)
	_frames += 1
	var capture_frame := 150 if _forest_preview_enabled() else 90
	if _frames == capture_frame and not _captured:
		_capture()


func _maybe_teleport_to_forest_preview() -> void:
	if _forest_preview_done:
		return
	_forest_preview_done = true
	if not _forest_preview_enabled():
		return
	var pos := _forest_preview_position()
	if pos == Vector2.INF:
		push_warning("World3D forest preview: no forest landing found")
		return
	world.teleport_to(pos)
	_static_sig = ""
	_dressing_sig = ""
	print("[world3d] forest preview teleport to tile %s" % [WG.world_to_tile(pos)])


func _forest_preview_enabled() -> bool:
	return FOREST_PREVIEW_ARG in OS.get_cmdline_args() or FOREST_PREVIEW_ARG in OS.get_cmdline_user_args()


func _forest_preview_position() -> Vector2:
	var spawn_t := WG.world_to_tile(WorldGen.spawn_position())
	var targets := ["forest", "dense_forest", "grove", "boreal_forest"]
	for dx_chunk: int in range(-18, -96, -3):
		for dy_chunk: int in range(-16, 17, 2):
			var tx := spawn_t.x + dx_chunk * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
			var ty := spawn_t.y + dy_chunk * WG.CHUNK_TILES + WG.CHUNK_TILES / 2
			var in_forest := false
			for biome: String in targets:
				if WorldGen.surface_biome_matches(tx, ty, biome):
					in_forest = true
					break
			if not in_forest:
				continue
			var pos := _verified_forest_landing(WG.tile_to_world(tx, ty), targets)
			if pos != Vector2.INF:
				return pos
	for biome: String in targets:
		var found: Dictionary = WorldGen.find_nearest_biome(WorldGen.spawn_position(), biome, 96)
		if found.is_empty():
			continue
		var landed := _verified_forest_landing(found["pos"], targets)
		if landed != Vector2.INF:
			return landed
	return Vector2.INF


func _verified_forest_landing(preferred: Vector2, targets: Array) -> Vector2:
	var center := WG.world_to_tile(preferred)
	for ring: int in range(0, 25):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if ring > 0 and maxi(absi(dx), absi(dy)) != ring:
					continue
				var pos := WG.tile_to_world(center.x + dx, center.y + dy)
				if not WorldGen.is_admin_teleport_floor(pos):
					continue
				var debug: Dictionary = WorldGen.tile_debug_at(pos, 0)
				if debug.is_empty():
					continue
				var tile_name := str(debug.get("tile_name", ""))
				if tile_name in ["sand", "sand_dune", "rock", "ash", "lava_rock", "snow", "shallow", "water", "deep_water"]:
					continue
				if _water_near_tile(center.x + dx, center.y + dy, 6):
					continue
				if str(debug.get("effective_biome", "")) in targets or str(debug.get("parent_biome", "")) in targets or str(debug.get("sub_biome", "")) in targets:
					return pos
	return Vector2.INF


func _water_near_tile(gtx: int, gty: int, radius: int) -> bool:
	for off: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
		if WorldGen.is_water_world(WG.tile_to_world(gtx + off.x, gty + off.y), 0):
			return true
	return false


const CAM_SIZE_BASE := 19.5   # ortho size at the default 1.65 zoom

func _sync_camera() -> void:
	var c := iso_to_3d(world.player.position, height_at(world.player.position))
	# Mouse-wheel zoom still drives the 2D camera (the logic substrate); mirror it
	# to the 3D ortho size so zoom works like before.
	var zoom: float = float(world._camera.zoom.x) if world._camera != null and world._camera.zoom.x > 0.01 else 1.65
	cam.size = CAM_SIZE_BASE / zoom
	# Slightly lower and closer than the exact iso math so tall original props
	# read as cozy hiking-place silhouettes instead of flattened map icons.
	var dir := Vector3(1.0, 0.62, 1.0).normalized()
	cam.position = c + dir * 31.0
	cam.look_at(c + Vector3(0, 0.75, 0), Vector3.UP)


## Build/free per-chunk terrain meshes to match the currently loaded chunks.
func _sync_terrain() -> void:
	var live := {}
	# Pass 1: index ALL loaded chunks first, so terrain sampling sees neighbors
	# (seamless smooth terrain across chunk borders).
	_chunk_by_key.clear()
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
		var key: String = chunk.key()
		live[key] = true
		_chunk_by_key[key] = chunk
	# Pass 2: build any missing chunk terrain.
	for key2: String in live:
		if not _chunk_meshes.has(key2):
			var node := _build_chunk_terrain(_chunk_by_key[key2])
			terrain_root.add_child(node)
			_chunk_meshes[key2] = node
	for key: String in _chunk_meshes.keys():
		if not live.has(key):
			var mi: Node = _chunk_meshes[key]
			if is_instance_valid(mi):
				mi.queue_free()
			_chunk_meshes.erase(key)
	_update_terrain_visibility()


func _update_terrain_visibility() -> void:
	var g := _world_to_grid(world.player.position)
	for key: String in _chunk_meshes.keys():
		var node: Node3D = _chunk_meshes[key]
		if not is_instance_valid(node):
			continue
		var parts := key.split(":")
		if parts.size() < 3:
			node.visible = true
			continue
		var cx := int(parts[1])
		var cy := int(parts[2])
		var center := Vector2(float(cx * WG.CHUNK_TILES + WG.CHUNK_TILES / 2), float(cy * WG.CHUNK_TILES + WG.CHUNK_TILES / 2))
		node.visible = absf(center.x - g.x) <= TERRAIN_CULL_TILES and absf(center.y - g.y) <= TERRAIN_CULL_TILES


const WATER_DROP := 0.45   # how far the ground floor dips under water (shore basin)
const FOAM_INSET := 0.075
const SHORE := Color(0.80, 0.75, 0.58)  # sandy shore tone under/at water edges
const PATH_TILES := ["dirt", "cobble", "mud", "gravel", "badland_clay"]
const ROCK_TILES := ["rock", "lava_rock", "ash"]

## Smooth, continuous, SEAMLESS terrain: each grid corner's height/normal/color
## is averaged from the tiles around it (sampled globally so chunk borders match),
## giving rolling sculpted land instead of flat terraced diamonds. Water tiles dip
## the floor into a basin and get a separate animated water surface on top.
func _build_chunk_terrain(chunk: RefCounted) -> Node3D:
	var n := WG.CHUNK_TILES
	var cx0: int = int(chunk.cx) * n
	var cy0: int = int(chunk.cy) * n
	var hc := {}  # memoized corner heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false
	var has_foam := false
	for ty: int in n:
		for tx: int in n:
			var gtx := cx0 + tx
			var gty := cy0 + ty
			# Four shared corners (continuous across cells -> smooth surface).
			_emit_corner(st, gtx, gty, hc)
			_emit_corner(st, gtx + 1, gty, hc)
			_emit_corner(st, gtx + 1, gty + 1, hc)
			_emit_corner(st, gtx, gty, hc)
			_emit_corner(st, gtx + 1, gty + 1, hc)
			_emit_corner(st, gtx, gty + 1, hc)
			var info := _tile_info(gtx, gty)
			if not info.is_empty() and bool(info["water"]):
				has_water = true
				var wy: float = _water_surface_height(info)
				var x0 := float(gtx) * TILE_S
				var z0 := float(gty) * TILE_S
				var x1 := x0 + TILE_S
				var z1 := z0 + TILE_S
				for v: Vector3 in [Vector3(x0, wy, z0), Vector3(x1, wy, z0), Vector3(x1, wy, z1), Vector3(x0, wy, z0), Vector3(x1, wy, z1), Vector3(x0, wy, z1)]:
					wst.set_normal(Vector3.UP)
					wst.add_vertex(v)
				for edge: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					if _shoreline_edge(gtx, gty, edge):
						_emit_foam_edge(fst, gtx, gty, wy + 0.018, edge)
						has_foam = true
	var root := Node3D.new()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	if has_water:
		var water := MeshInstance3D.new()
		water.mesh = wst.commit()
		water.material_override = _water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
	if has_foam:
		var foam := MeshInstance3D.new()
		foam.mesh = fst.commit()
		foam.material_override = _foam_mat
		foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(foam)
	return root


func _emit_corner(st: SurfaceTool, ci: int, cj: int, hc: Dictionary) -> void:
	var h := _corner_height(ci, cj, hc)
	# Smooth normal from the height field (central differences over the corners).
	var hx := _corner_height(ci + 1, cj, hc) - _corner_height(ci - 1, cj, hc)
	var hz := _corner_height(ci, cj + 1, hc) - _corner_height(ci, cj - 1, hc)
	st.set_normal(Vector3(-hx, 2.0 * TILE_S, -hz).normalized())
	st.set_color(_corner_color(ci, cj))
	st.add_vertex(Vector3(float(ci) * TILE_S, h, float(cj) * TILE_S))


func _corner_height(ci: int, cj: int, hc: Dictionary) -> float:
	var key := "%d,%d" % [ci, cj]
	if hc.has(key):
		return hc[key]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			sum += _visual_floor_height(ci + off.x, cj + off.y, info)
			cnt += 1
	var h: float = sum / float(cnt) if cnt > 0 else 0.0
	hc[key] = h
	return h


func _corner_color(ci: int, cj: int) -> Color:
	var infos := []
	var families := {}
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			infos.append(info)
			var family := _surface_family(str(info["tile"]))
			families[family] = int(families.get(family, 0)) + 1
	if infos.is_empty():
		return PixelPalette.pal("grass_a")
	var family := ""
	var best := 0
	for f: String in families:
		if int(families[f]) > best:
			best = int(families[f])
			family = f
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var cnt := 0
	for info: Dictionary in infos:
		if best < 3 or _surface_family(str(info["tile"])) == family:
			var c: Color = info["col"]
			r += c.r
			g += c.g
			b += c.b
			cnt += 1
	return Color(r / float(cnt), g / float(cnt), b / float(cnt))


## Per-global-tile info {top, water, tile, col}, or {} if the chunk isn't loaded.
func _tile_info(gtx: int, gty: int) -> Dictionary:
	var ck := WG.tile_to_chunk(Vector2i(gtx, gty))
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk == null:
		return {}
	var lx: int = gtx - ck.x * WG.CHUNK_TILES
	var ly: int = gty - ck.y * WG.CHUNK_TILES
	var tid: int = chunk.tile_id(lx, ly)
	var tdef: Dictionary = WorldGen.reg.tile_def(tid)
	var tile_name := str(WorldGen.reg.tile_order[tid])
	var water := bool(tdef.get("water", false))
	var top: float = float(chunk.elev[ly * WG.CHUNK_TILES + lx]) * ELEV_H
	var col: Color = SHORE if water else _grade_ground(tdef["colors"][0], tile_name, gtx, gty)
	return {
		"top": top,
		"water": water,
		"tile": tile_name,
		"col": col,
	}


func _visual_floor_height(gtx: int, gty: int, info: Dictionary) -> float:
	var top := float(info["top"])
	var tile := str(info["tile"])
	if bool(info["water"]):
		var extra := 0.18 if tile == "deep_water" else (0.08 if tile == "water" else 0.0)
		return top - WATER_DROP - extra
	var hill := _rolling_hill(gtx, gty)
	if _is_path(tile):
		return top + hill * 0.28 - 0.055
	if _is_rock(tile):
		return top + hill * 0.78 + _rocky_lift(gtx, gty)
	return top + hill


func _water_surface_height(info: Dictionary) -> float:
	return float(info["top"]) - 0.035


func _rolling_hill(gtx: int, gty: int) -> float:
	var x := float(gtx)
	var y := float(gty)
	var broad := sin(x * 0.118 + 0.7) * cos(y * 0.097 - 1.2)
	var swell := sin((x + y) * 0.055 + 1.8)
	return broad * 0.16 + swell * 0.075


func _rocky_lift(gtx: int, gty: int) -> float:
	var chip := sin(float(gtx) * 0.91 + float(gty) * 0.37)
	return maxf(chip, 0.0) * 0.08


func _surface_family(tile: String) -> String:
	if tile in ["deep_water", "water", "shallow"]:
		return "water"
	if _is_path(tile):
		return "path"
	if _is_rock(tile):
		return "rock"
	if tile in ["sand", "sand_dune"]:
		return "sand"
	if tile == "snow" or tile == "frozen_grass":
		return "snow"
	return "grass"


func _is_path(tile: String) -> bool:
	return tile in PATH_TILES


func _is_rock(tile: String) -> bool:
	return tile in ROCK_TILES


func _shoreline_edge(gtx: int, gty: int, edge: Vector2i) -> bool:
	var other := _tile_info(gtx + edge.x, gty + edge.y)
	return other.is_empty() or not bool(other["water"])


func _emit_foam_edge(st: SurfaceTool, gtx: int, gty: int, y: float, edge: Vector2i) -> void:
	var x0 := float(gtx) * TILE_S
	var z0 := float(gty) * TILE_S
	var x1 := x0 + TILE_S
	var z1 := z0 + TILE_S
	var w := FOAM_INSET
	var verts: Array[Vector3]
	if edge == Vector2i(0, -1):
		verts = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z0 + w), Vector3(x0, y, z0), Vector3(x1, y, z0 + w), Vector3(x0, y, z0 + w)]
	elif edge == Vector2i(1, 0):
		verts = [Vector3(x1 - w, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x1 - w, y, z0), Vector3(x1, y, z1), Vector3(x1 - w, y, z1)]
	elif edge == Vector2i(0, 1):
		verts = [Vector3(x0, y, z1 - w), Vector3(x1, y, z1 - w), Vector3(x1, y, z1), Vector3(x0, y, z1 - w), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	else:
		verts = [Vector3(x0, y, z0), Vector3(x0 + w, y, z0), Vector3(x0 + w, y, z1), Vector3(x0, y, z0), Vector3(x0 + w, y, z1), Vector3(x0, y, z1)]
	for v: Vector3 in verts:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


## Warm + enrich a terrain tile color and add BROAD low-frequency variation
## (large painted regions, not noise) so the ground reads painterly, not as flat
## monotone diamonds. Original warm grading — our palette, A Short Hike vibe.
func _grade_ground(col: Color, tile: String, gtx: int, gty: int) -> Color:
	var c := col
	var fx := float(gtx)
	var fz := float(gty)
	# Three broad low-frequency bands (no noise) -> painterly sunlit/shaded
	# gradients across the ground like A Short Hike.
	var bright := 0.5 + 0.5 * sin(fx * 0.07) * cos(fz * 0.06)
	var band2 := 0.5 + 0.5 * sin(fx * 0.13 + 1.2) * cos(fz * 0.115 - 0.7)
	var warm := clampf(sin((fx + fz) * 0.045 + 1.3), 0.0, 1.0)
	if _is_path(tile):
		var path_col := PixelPalette.pal("path_orange").lerp(PixelPalette.pal("path_light"), bright * 0.42)
		c = c.lerp(path_col, 0.94)
	elif _is_rock(tile):
		c = c.lerp(PixelPalette.pal("cliff_warm").lerp(PixelPalette.pal("cliff_light"), bright * 0.34), 0.78)
	elif tile in ["sand", "sand_dune"]:
		c = c.lerp(PixelPalette.pal("warm_stone"), 0.5)
	else:
		# Deep-forest grass gradient: mid foliage -> sunlit grass across the broad
		# bright band, drifting toward leaf-green/forest-green in shaded regions and
		# a moss highlight in others. No lime.
		var grass := PixelPalette.pal("mid_foliage").lerp(PixelPalette.pal("sunlit_grass"), bright)
		grass = grass.lerp(PixelPalette.pal("leaf_green"), (1.0 - band2) * 0.45)
		grass = grass.lerp(PixelPalette.pal("forest_green"), (1.0 - bright) * 0.2)
		grass = grass.lerp(PixelPalette.pal("moss_hi"), warm * 0.18)
		c = c.lerp(grass, 0.82)
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
	var dt := get_process_delta_time()
	var t := Time.get_ticks_msec() / 1000.0
	if _player_node == null:
		_player_node = PropMeshes.build_node(PropMeshes.figure_parts(PixelPalette.pal("outfit_a"), PixelPalette.pal("skin_a")))
		props_root.add_child(_player_node)
	_animate_mover(_player_node, "player", world.player.position, t, dt)
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
		_animate_mover(n, str(id), e.position, t, dt)
	for id: int in _mover_nodes.keys():
		if not live.has(id):
			var n: Node = _mover_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			_mover_nodes.erase(id)
			_mover_prev.erase(id); _mover_yaw.erase(id); _mover_walk.erase(id)


## A Short Hike-style walk feel: gentle vertical bob + squash-stretch while moving,
## and the body turns to face the movement direction. Idle = still and upright.
func _animate_mover(node: Node3D, key: String, pos2d: Vector2, t: float, dt: float) -> void:
	var pos3 := iso_to_3d(pos2d, height_at(pos2d))
	var prev: Vector3 = _mover_prev.get(key, pos3)
	var vel := pos3 - prev
	_mover_prev[key] = pos3
	var speed := vel.length() / maxf(dt, 0.0001)
	var target_walk := clampf(speed / 3.0, 0.0, 1.0)
	var walk: float = lerpf(float(_mover_walk.get(key, 0.0)), target_walk, clampf(dt * 10.0, 0.0, 1.0))
	_mover_walk[key] = walk
	# Face the movement direction (smoothed), keep last facing when idle.
	var yaw: float = float(_mover_yaw.get(key, 0.0))
	if vel.length() > 0.0005:
		yaw = lerp_angle(yaw, atan2(vel.x, vel.z), clampf(dt * 12.0, 0.0, 1.0))
		_mover_yaw[key] = yaw
	node.rotation.y = yaw
	# Bob + squash scale with the walk amount; a gentle idle breathe when still.
	var bob := absf(sin(t * 11.0)) * 0.09 * walk
	var sq := sin(t * 11.0) * 0.06 * walk
	var idle := (1.0 - walk) * sin(t * 2.2) * 0.018
	node.position = pos3 + Vector3(0, bob, 0)
	node.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq + idle, 1.0 - sq * 0.5)


## Batch all static decor + props into per-(mesh,material) MultiMeshes. Rebuilt
## only when the static set changes (or a periodic safety pass), not every frame.
func _sync_static_batches() -> void:
	var center := WG.world_to_chunk(world.player.position)
	var sig := "%s:%d,%d:%d:%d:%d" % [str(world.current_layer), center.x, center.y, int(world._decor_nodes.size()), int(world._water_decor_nodes.size()), int(world.entities.size())]
	if sig == _static_sig:
		return
	_static_sig = sig
	for c: Node in batches_root.get_children():
		c.queue_free()
	var groups := {}
	for d: Node in world._decor_nodes:
		if not is_instance_valid(d):
			continue
		if not _near_visual_grid(d.position, PROP_CULL_TILES):
			continue
		var pl := Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.131), iso_to_3d(d.position, height_at(d.position)))
		_collect(PropMeshes.decor_parts(str(d.kind)), pl, groups)
	for d: Node in world._water_decor_nodes:
		if not is_instance_valid(d):
			continue
		if not _near_visual_grid(d.position, PROP_CULL_TILES):
			continue
		var pl := Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.17), iso_to_3d(d.position, height_at(d.position) + 0.04))
		_collect(PropMeshes.water_decor_parts(str(d.kind)), pl, groups)
	for e: Node in world.entities:
		if not is_instance_valid(e) or PropMeshes.is_moving(e):
			continue
		if not _near_visual_grid(e.position, PROP_CULL_TILES):
			continue
		var parts: Array = PropMeshes.entity_parts(e)
		if parts.is_empty():
			continue
		_collect(parts, Transform3D(Basis.IDENTITY, iso_to_3d(e.position, height_at(e.position))), groups)
	_emit_groups(groups, batches_root)


func _sync_style_dressing() -> void:
	var g := _world_to_grid(world.player.position)
	var anchor := Vector2i(roundi(g.x / float(DRESSING_ANCHOR)) * DRESSING_ANCHOR, roundi(g.y / float(DRESSING_ANCHOR)) * DRESSING_ANCHOR)
	var sig := "%s:%d,%d" % [str(world.current_layer), anchor.x, anchor.y]
	if sig == _dressing_sig:
		return
	_dressing_sig = sig
	for c: Node in dressing_root.get_children():
		c.queue_free()
	var groups := {}
	for spec: Dictionary in _hike_dressing_specs():
		var off: Vector2i = spec["off"]
		var gtx := anchor.x + off.x
		var gty := anchor.y + off.y
		var info := _tile_info(gtx, gty)
		if info.is_empty():
			continue
		if bool(info["water"]) and str(spec["kind"]) != "hike_pool":
			continue
		var angle := float(spec.get("angle", 0.0))
		var scale := float(spec.get("scale", 1.0))
		var lift := float(spec.get("lift", 0.0))
		var pos := _tile_center_pos(gtx, gty, lift)
		var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
		var parts := PropMeshes.dressing_parts(str(spec["kind"]), int(spec.get("variant", 0)))
		_collect(parts, Transform3D(basis, pos), groups)
	_emit_groups(groups, dressing_root)


func _emit_groups(groups: Dictionary, root: Node3D) -> void:
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
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


func _hike_dressing_specs() -> Array:
	var specs := []
	var path := [
		Vector2i(-6, 4), Vector2i(-5, 3), Vector2i(-4, 2), Vector2i(-3, 2),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(3, -1), Vector2i(4, -2), Vector2i(5, -3),
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -2)]
	for i: int in path.size():
		specs.append({"kind": "hike_path", "off": path[i], "angle": -0.55 + float(i % 5) * 0.14, "scale": 1.2 + float(i % 4) * 0.08, "lift": 0.035, "variant": i})

	specs.append_array([
		{"kind": "hike_cabin", "off": Vector2i(-4, -2), "angle": -0.58, "scale": 0.96, "variant": 0},
		{"kind": "hike_lodge", "off": Vector2i(3, -1), "angle": -0.72, "scale": 0.98, "variant": 1},
		{"kind": "hike_campfire", "off": Vector2i(-1, 1), "angle": 0.2, "scale": 1.28, "lift": 0.04, "variant": 1},
		{"kind": "hike_sign", "off": Vector2i(-3, 2), "angle": -0.35, "scale": 1.05, "variant": 0},
		{"kind": "hike_pool", "off": Vector2i(4, 6), "angle": 0.24, "scale": 1.65, "lift": 0.02, "variant": 0},
		{"kind": "hike_boulder", "off": Vector2i(2, 2), "angle": 0.4, "scale": 1.15, "variant": 0},
		{"kind": "hike_boulder", "off": Vector2i(5, 2), "angle": -0.2, "scale": 0.9, "variant": 1},
		{"kind": "hike_bench", "off": Vector2i(2, 1), "angle": -0.7, "scale": 1.1, "variant": 0},
		{"kind": "hike_log", "off": Vector2i(-3, 2), "angle": 0.5, "scale": 1.3, "variant": 1},
		{"kind": "hike_log", "off": Vector2i(-2, 3), "angle": -0.25, "scale": 0.95, "variant": 2},
		{"kind": "hike_stump", "off": Vector2i(-5, -1), "angle": 0.0, "scale": 1.05, "variant": 0},
		{"kind": "hike_stump", "off": Vector2i(3, 3), "angle": 0.0, "scale": 0.9, "variant": 1},
		{"kind": "hike_mushroom", "off": Vector2i(-6, 4), "angle": 0.2, "scale": 1.05, "variant": 0},
		{"kind": "hike_mushroom", "off": Vector2i(5, 0), "angle": -0.3, "scale": 0.92, "variant": 1},
	])

	var conifers := [
		Vector2i(-10, -3), Vector2i(-9, -5), Vector2i(-8, -7), Vector2i(-6, -6),
		Vector2i(-5, -4), Vector2i(-3, -7), Vector2i(-1, -6), Vector2i(1, -7),
		Vector2i(3, -6), Vector2i(5, -5), Vector2i(7, -5), Vector2i(9, -3),
		Vector2i(10, -1), Vector2i(9, 1), Vector2i(8, 3), Vector2i(-9, 2)]
	for i: int in conifers.size():
		specs.append({"kind": "hike_conifer", "off": conifers[i], "angle": float(i) * 0.37, "scale": 1.08 + float(i % 4) * 0.1, "variant": i})

	var leaves := [
		Vector2i(-9, 5), Vector2i(-7, 3), Vector2i(-4, 5), Vector2i(-2, 4),
		Vector2i(1, 3), Vector2i(3, 2), Vector2i(5, 4), Vector2i(7, 5),
		Vector2i(7, -1), Vector2i(5, -2), Vector2i(-6, -2), Vector2i(0, -4)]
	for i: int in leaves.size():
		specs.append({"kind": "hike_deciduous", "off": leaves[i], "angle": float(i) * 0.29, "scale": 0.92 + float(i % 4) * 0.12, "variant": i})

	var cliffs := [
		Vector2i(-10, -8), Vector2i(-8, -8), Vector2i(-6, -9), Vector2i(-4, -9),
		Vector2i(-2, -9), Vector2i(0, -9), Vector2i(2, -9), Vector2i(4, -8),
		Vector2i(6, -8), Vector2i(8, -7), Vector2i(9, -5), Vector2i(-10, -5)]
	for i: int in cliffs.size():
		specs.append({"kind": "hike_cliff", "off": cliffs[i], "angle": 0.08 + float(i) * 0.14, "scale": 1.26 - float(i % 3) * 0.08, "variant": i})

	var fences := [
		{"off": Vector2i(-1, 6), "angle": -0.25}, {"off": Vector2i(1, 6), "angle": -0.12},
		{"off": Vector2i(3, 6), "angle": 0.08}, {"off": Vector2i(5, 6), "angle": 0.2},
		{"off": Vector2i(7, 4), "angle": 0.88}, {"off": Vector2i(-7, 3), "angle": 0.78},
		{"off": Vector2i(-8, 1), "angle": 0.88}, {"off": Vector2i(6, 1), "angle": 0.7}]
	for i: int in fences.size():
		var f: Dictionary = fences[i]
		specs.append({"kind": "hike_fence", "off": f["off"], "angle": f["angle"], "scale": 1.08, "variant": i})

	var flowers := [
		Vector2i(-5, 5), Vector2i(-4, 5), Vector2i(-2, 4), Vector2i(0, 3),
		Vector2i(2, 2), Vector2i(4, 3), Vector2i(6, 5), Vector2i(-7, 0),
		Vector2i(-6, 2), Vector2i(5, 2), Vector2i(7, 1), Vector2i(-1, 4)]
	for i: int in flowers.size():
		specs.append({"kind": "hike_flower", "off": flowers[i], "angle": float(i) * 0.2, "scale": 1.0 + float(i % 2) * 0.18, "lift": 0.02, "variant": i})

	var clutter := ["hike_leaf_litter", "hike_grass", "hike_pebbles", "hike_grass", "hike_leaf_litter", "hike_mushroom"]
	for i: int in range(54):
		var ox := int((i * 5) % 19) - 9
		var oy := int((i * 7 + int(i / 3)) % 17) - 8
		if absi(ox) < 2 and absi(oy) < 2:
			continue
		var kind: String = clutter[i % clutter.size()]
		var scale := 0.72 + float((i * 3) % 5) * 0.09
		specs.append({"kind": kind, "off": Vector2i(ox, oy), "angle": float(i) * 0.41, "scale": scale, "lift": 0.018, "variant": i})
	return specs


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


func _world_to_grid(pos: Vector2) -> Vector2:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	return Vector2(gx, gy)


func _near_visual_grid(pos: Vector2, radius_tiles: float) -> bool:
	var g := _world_to_grid(pos)
	var p := _world_to_grid(world.player.position)
	return absf(g.x - p.x) <= radius_tiles and absf(g.y - p.y) <= radius_tiles


func _tile_center_pos(gtx: int, gty: int, lift := 0.0) -> Vector3:
	var info := _tile_info(gtx, gty)
	var h := 0.0
	if not info.is_empty() and bool(info["water"]):
		h = _water_surface_height(info)
	elif not info.is_empty():
		var hc := {}
		h = (_corner_height(gtx, gty, hc) + _corner_height(gtx + 1, gty, hc) + _corner_height(gtx, gty + 1, hc) + _corner_height(gtx + 1, gty + 1, hc)) * 0.25
	return Vector3((float(gtx) + 0.5) * TILE_S, h + lift, (float(gty) + 0.5) * TILE_S)


## Terrain height (3D Y) at a 2D iso position, sampled from the loaded chunk.
func height_at(pos: Vector2) -> float:
	var gx := (pos.x / WG.ISO_HW + pos.y / WG.ISO_HH) * 0.5
	var gy := (pos.y / WG.ISO_HH - pos.x / WG.ISO_HW) * 0.5
	var t := Vector2i(floori(gx), floori(gy))
	var info := _tile_info(t.x, t.y)
	if not info.is_empty() and bool(info["water"]):
		return _water_surface_height(info)
	var hc := {}
	var fx := gx - floorf(gx)
	var fy := gy - floorf(gy)
	var h00 := _corner_height(t.x, t.y, hc)
	var h10 := _corner_height(t.x + 1, t.y, hc)
	var h01 := _corner_height(t.x, t.y + 1, hc)
	var h11 := _corner_height(t.x + 1, t.y + 1, hc)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


func _palette_texture() -> ImageTexture:
	var keys := PixelPalette.PAL.keys()
	var img := Image.create(keys.size(), 1, false, Image.FORMAT_RGBA8)
	for i: int in keys.size():
		img.set_pixel(i, 0, PixelPalette.pal(keys[i]))
	return ImageTexture.create_from_image(img)


func _capture() -> void:
	_captured = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world3d_shot.png")
	print("[world3d] saved user://world3d_shot.png")
