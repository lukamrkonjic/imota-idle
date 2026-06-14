extends Node2D
## Isometric ground visuals for one chunk — drawn once, then frozen for performance.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const WorldLighting := preload("res://scripts/world/art/core/world_lighting.gd")

# Tiles are drawn slightly larger than their cell so neighbours overlap and hide
# the hairline between diamonds.
const TILE_OVERLAP := 4.0
const CARDINAL: Array = [
	[Vector2i(0, -1), 1],
	[Vector2i(1, 0), 2],
	[Vector2i(0, 1), 3],
	[Vector2i(-1, 0), 0],
]
const DETAIL_LOW := 0
const DETAIL_FULL := 1

var chunk: RefCounted
var detail_level := DETAIL_FULL
var _placeholder: Color = Color(0.25, 0.35, 0.22)
# The chunk's ~300 per-tile polygons are baked ONCE into a single vertex-coloured
# triangle mesh (the Terraria/Minecraft "chunk mesh") and drawn in ONE draw_mesh()
# call. Built on the CPU — NO render-to-texture, so no GPU readback and no stall
# while terrain streams in during movement. Rebuilt only when a neighbour changes.
var _mesh: ArrayMesh = null
var _mesh_dirty := true
static var _white_tex: Texture2D = null


func _init(p_chunk: RefCounted, avg_color: Color, p_detail_level: int = DETAIL_FULL) -> void:
	chunk = p_chunk
	_placeholder = avg_color
	detail_level = p_detail_level
	# Order ground chunks back-to-front by isometric depth so a raised chunk's
	# terrain risers can never poke through the flat chunk in front of it. Kept
	# well below entities (which y-sort around z 0+) so ground stays underneath.
	z_index = -1000 + p_chunk.cx + p_chunk.cy


func set_detail_level(p_detail_level: int) -> void:
	var next_detail := clampi(p_detail_level, DETAIL_LOW, DETAIL_FULL)
	if detail_level == next_detail:
		return
	detail_level = next_detail
	mark_dirty()


## Terrain elevation (in steps) for a tile, read from the chunk's baked per-tile
## elevation — zero on water and all non-mountain ground. Resolves across chunk
## seams (like _tile_id_at) so risers line up between chunks.
static func _elev_at(p_chunk: RefCounted, lx: int, ly: int) -> int:
	var n := _resolve(p_chunk, lx, ly)
	if n.is_empty():
		return 0
	var c: RefCounted = n[0]
	if c.elev.size() == 0:
		return 0
	return c.elev[Chunk.idx(n[1], n[2])]


## How deeply this tile is shaded (0..~0.5) by taller terrain standing between it
## and the sun — a stepped cliff casts a shadow onto the lower ground toward the
## shadow side, roughly one tile of shadow per elevation step. Tile space equals
## world-ground space, so the sun bearing maps straight onto tile offsets.
static func _terrain_shadow(p_chunk: RefCounted, lx: int, ly: int, e: int) -> float:
	var a := deg_to_rad(WorldLighting.sun_azimuth_deg)
	var dir := Vector2(cos(a), sin(a))      # toward the sun, in tile space
	var sh := 0.0
	for d: int in range(1, 7):
		var ox: int = int(round(dir.x * float(d)))
		var oy: int = int(round(dir.y * float(d)))
		if ox == 0 and oy == 0:
			continue
		var cast := float(_elev_at(p_chunk, lx + ox, ly + oy) - e) - float(d)
		if cast > sh:
			sh = cast
	return clampf(sh / 8.0, 0.0, 0.5)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, _white_texture())
		return
	# Until the mesh is built, show one cheap flat diamond placeholder.
	var center := WG.tile_to_world(chunk.cx * WG.CHUNK_TILES + 8, chunk.cy * WG.CHUNK_TILES + 8)
	PixelDraw.px_diamond(self, center.x, center.y,
		float(WG.CHUNK_TILES) * WG.ISO_HW, float(WG.CHUNK_TILES) * WG.ISO_HH, _placeholder)


## Mark the chunk's mesh stale; ChunkManager rebuilds dirty meshes from its
## time-sliced queue so _draw() never does surprise CPU work.
func mark_dirty() -> void:
	_mesh_dirty = true


func needs_mesh_rebuild() -> bool:
	return _mesh_dirty


func rebuild_mesh() -> void:
	if not _mesh_dirty:
		return
	_rebuild_mesh()
	queue_redraw()


## Bake the whole chunk into ONE vertex-coloured triangle mesh. Reuses the exact
## per-tile paint logic by feeding it a triangle-accumulating builder in place of
## the canvas, so diamonds/shading/risers/borders all land in one draw_mesh call.
func _rebuild_mesh() -> void:
	_mesh_dirty = false
	var reg: RefCounted = WorldGen.reg if WorldGen != null else null
	if reg == null:
		return
	var b := _MeshBuilder.new()
	if detail_level == DETAIL_LOW:
		_draw_coarse_lod(b)
	else:
		_draw_chunk(b, chunk, reg)
	if b.verts.is_empty():
		_mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.verts
	arr[Mesh.ARRAY_COLOR] = b.cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh = m


func _draw_coarse_lod(canvas: Variant) -> void:
	var center := WG.tile_to_world(chunk.cx * WG.CHUNK_TILES + 8, chunk.cy * WG.CHUNK_TILES + 8)
	PixelDraw.px_diamond(canvas, center.x, center.y,
		float(WG.CHUNK_TILES) * WG.ISO_HW, float(WG.CHUNK_TILES) * WG.ISO_HH, _placeholder)


static func _white_texture() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


## Duck-typed as a CanvasItem for the existing paint helpers (which only call
## draw_colored_polygon and draw_rect): instead of issuing draw commands it
## accumulates triangle soup with per-vertex colours for one ArrayMesh.
class _MeshBuilder:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()

	func draw_colored_polygon(points: PackedVector2Array, color: Color,
			_uvs: PackedVector2Array = PackedVector2Array(), _texture: Variant = null) -> void:
		for i: int in range(1, points.size() - 1):
			_tri(points[0], points[i], points[i + 1], color)

	func draw_rect(rect: Rect2, color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		var p := rect.position
		var s := rect.size
		_tri(p, p + Vector2(s.x, 0.0), p + s, color)
		_tri(p, p + s, p + Vector2(0.0, s.y), color)

	func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
		verts.push_back(Vector3(a.x, a.y, 0.0))
		verts.push_back(Vector3(b.x, b.y, 0.0))
		verts.push_back(Vector3(c.x, c.y, 0.0))
		cols.push_back(color)
		cols.push_back(color)
		cols.push_back(color)


func _draw_placeholder() -> void:
	var base_tx: int = chunk.cx * WG.CHUNK_TILES
	var base_ty: int = chunk.cy * WG.CHUNK_TILES
	for ty: int in WG.CHUNK_TILES:
		for tx: int in WG.CHUNK_TILES:
			_draw_flat_tile(self, base_tx + tx, base_ty + ty, _placeholder, false, false)


static func tile_color(reg: RefCounted, byte_id: int) -> Color:
	var cols: Array = reg.tile_def(byte_id)["colors"]
	return cols[0]


static func _tile_name(reg: RefCounted, byte_id: int) -> String:
	if byte_id < 0 or byte_id >= reg.tile_order.size():
		return ""
	return reg.tile_order[byte_id]


static func _biome_id(reg: RefCounted, p_chunk: RefCounted, lx: int, ly: int) -> String:
	var b_idx: int = p_chunk.parent_biome_at(lx, ly)
	if b_idx == 255 or b_idx >= reg.biomes.size():
		return ""
	return str(reg.biomes[b_idx]["id"])


static func _resolve_colors(reg: RefCounted, p_chunk: RefCounted, lx: int, ly: int, tile_name: String, cols: Array) -> Array:
	var biome_id := _biome_id(reg, p_chunk, lx, ly)
	var top := PixelPalette.harmonize_for_biome(PixelPalette.enrich_tile(tile_name, Color(cols[0])), biome_id)
	var accent := PixelPalette.harmonize_for_biome(PixelPalette.enrich_tile(tile_name, Color(cols[1])), biome_id)
	return [top, accent]


static func _draw_chunk(canvas: Variant, p_chunk: RefCounted, reg: RefCounted) -> void:
	var base_tx: int = p_chunk.cx * WG.CHUNK_TILES
	var base_ty: int = p_chunk.cy * WG.CHUNK_TILES
	for diag: int in range(0, WG.CHUNK_TILES * 2 - 1):
		var tx0: int = maxi(0, diag - (WG.CHUNK_TILES - 1))
		var tx1: int = mini(WG.CHUNK_TILES - 1, diag)
		for tx: int in range(tx0, tx1 + 1):
			var ty: int = diag - tx
			var tile_id: int = p_chunk.tile_id(tx, ty)
			var tile_name: String = _tile_name(reg, tile_id)
			var td: Dictionary = reg.tile_def(tile_id)
			_draw_full_tile(canvas, p_chunk, reg, tx, ty, base_tx + tx, base_ty + ty, tile_name, td)


static func _draw_full_tile(
		canvas: Variant,
		p_chunk: RefCounted,
		reg: RefCounted,
		lx: int,
		ly: int,
		gtx: int,
		gty: int,
		tile_name: String,
		td: Dictionary) -> void:
	var cols: Array = td["colors"]
	var resolved: Array = _resolve_colors(reg, p_chunk, lx, ly, tile_name, cols)
	var top: Color = resolved[0]
	var accent: Color = resolved[1]
	var water := bool(td.get("water", false))
	var soft := tile_name in ["sand", "sand_dune", "snow", "marsh", "mud", "frozen_grass", "savanna_grass", "jungle_loam", "boreal_moss", "badland_clay", "gravel"]
	if tile_name == "frozen_grass":
		top = PixelPalette.hex(0xD8E0DC)
		accent = PixelPalette.hex(0x8A9478)
	var elev := _elev_at(p_chunk, lx, ly)
	var oy := -float(elev) * WG.ELEV_STEP_PX
	if not water:
		var sh := _terrain_shadow(p_chunk, lx, ly, elev)
		if sh > 0.0:
			top = PixelPalette.shade(top, 1.0 - sh)
			accent = PixelPalette.shade(accent, 1.0 - sh)
	if elev > 0:
		_draw_risers(canvas, p_chunk, lx, ly, gtx, gty, elev, top, oy)
	_draw_flat_tile(canvas, gtx, gty, top, water, soft, oy)
	if not water and not soft:
		_draw_tile_speckles(canvas, gtx, gty, top, accent, oy)
	elif tile_name == "frozen_grass":
		_draw_frozen_grass(canvas, gtx, gty, top, accent, oy)
	_draw_surface_borders(canvas, p_chunk, reg, lx, ly, gtx, gty, top, water, oy)
	if elev > 0:
		_draw_cliff_edges(canvas, p_chunk, lx, ly, gtx, gty, elev, top, oy)


static func _draw_chunk_lod(canvas: Variant, p_chunk: RefCounted, reg: RefCounted) -> void:
	var base_tx: int = p_chunk.cx * WG.CHUNK_TILES
	var base_ty: int = p_chunk.cy * WG.CHUNK_TILES
	for diag: int in range(0, WG.CHUNK_TILES * 2 - 1):
		var tx0: int = maxi(0, diag - (WG.CHUNK_TILES - 1))
		var tx1: int = mini(WG.CHUNK_TILES - 1, diag)
		for tx: int in range(tx0, tx1 + 1):
			var ty: int = diag - tx
			var tile_id: int = p_chunk.tile_id(tx, ty)
			var tile_name: String = _tile_name(reg, tile_id)
			var td: Dictionary = reg.tile_def(tile_id)
			var cols: Array = td["colors"]
			var top := PixelPalette.enrich_tile(tile_name, Color(cols[0]))
			var water := bool(td.get("water", false))
			var elev: int = _local_elev(p_chunk, tx, ty)
			var oy := -float(elev) * WG.ELEV_STEP_PX
			var gtx: int = base_tx + tx
			var gty: int = base_ty + ty
			if elev > 0:
				_draw_lod_risers(canvas, p_chunk, tx, ty, gtx, gty, elev, top, oy)
			_draw_flat_tile(canvas, gtx, gty, top, water, true, oy)


static func _local_elev(p_chunk: RefCounted, lx: int, ly: int) -> int:
	if lx < 0 or ly < 0 or lx >= WG.CHUNK_TILES or ly >= WG.CHUNK_TILES:
		return 0
	if p_chunk.elev.size() == 0:
		return 0
	return p_chunk.elev[Chunk.idx(lx, ly)]


static func _draw_lod_risers(canvas: Variant, p_chunk: RefCounted, lx: int, ly: int, gtx: int, gty: int, elev: int, top: Color, oy: float) -> void:
	var center := WG.tile_to_world(gtx, gty)
	var cx := center.x
	var cy := center.y + oy
	var hw := WG.ISO_HW + TILE_OVERLAP
	var hh := WG.ISO_HH + TILE_OVERLAP * 0.5
	var e := Vector2(cx + hw, cy)
	var s := Vector2(cx, cy + hh)
	var w := Vector2(cx - hw, cy)
	_draw_one_riser(canvas, e, s, elev - _local_elev(p_chunk, lx + 1, ly), PixelPalette.shade(top, 0.58))
	_draw_one_riser(canvas, s, w, elev - _local_elev(p_chunk, lx, ly + 1), PixelPalette.shade(top, 0.40))


## Beveled vertical risers on the two camera-facing edges (SE toward +x, SW
## toward +y), one per elevation step the tile stands above that neighbour, so a
## hillside reads as terraced ground with the same bevel used between biomes.
static func _draw_risers(canvas: Variant, p_chunk: RefCounted, lx: int, ly: int, gtx: int, gty: int, elev: int, top: Color, oy: float) -> void:
	var center := WG.tile_to_world(gtx, gty)
	var cx := center.x
	var cy := center.y + oy
	var hw := WG.ISO_HW + TILE_OVERLAP
	var hh := WG.ISO_HH + TILE_OVERLAP * 0.5
	var e := Vector2(cx + hw, cy)
	var s := Vector2(cx, cy + hh)
	var w := Vector2(cx - hw, cy)
	# Strong value separation makes the drop read as a wall, not texture: the top
	# surface stays full-bright, the SE cliff face is much darker, the SW face
	# (away from the sun) darker still.
	_draw_one_riser(canvas, e, s, elev - _elev_at(p_chunk, lx + 1, ly), PixelPalette.shade(top, 0.62))
	_draw_one_riser(canvas, s, w, elev - _elev_at(p_chunk, lx, ly + 1), PixelPalette.shade(top, 0.42))


## Black beveled rim on the UPPER (top-surface) side of a cliff lip — the same
## shadow/contact bevel used between biomes, so the plateau edge reads as a
## distinct dark edge against the tile rather than white-next-to-white. Only the
## camera-facing edges that actually drop get one.
static func _draw_cliff_edges(canvas: Variant, p_chunk: RefCounted, lx: int, ly: int, gtx: int, gty: int, elev: int, top: Color, oy: float) -> void:
	var center := WG.tile_to_world(gtx, gty)
	var cx := center.x
	var cy := center.y + oy
	var hw := WG.ISO_HW + TILE_OVERLAP
	var hh := WG.ISO_HH + TILE_OVERLAP * 0.5
	var e := Vector2(cx + hw, cy)
	var s := Vector2(cx, cy + hh)
	var w := Vector2(cx - hw, cy)
	if elev - _elev_at(p_chunk, lx + 1, ly) > 0:
		_edge_line(canvas, e, s)
	if elev - _elev_at(p_chunk, lx, ly + 1) > 0:
		_edge_line(canvas, s, w)


static func _edge_line(canvas: Variant, a: Vector2, b: Vector2) -> void:
	# A dark band sitting just inside the top surface (upper side of the lip),
	# matching the biome-boundary bevel look but stronger since it marks a cliff.
	var up := Vector2(0.0, -float(PixelPalette.PX))
	var shadow := PixelPalette.pal("shadow")
	shadow.a = 0.55
	canvas.draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), shadow)
	# A crisp near-black contour right on the lip itself.
	shadow.a = 0.7
	canvas.draw_colored_polygon(PackedVector2Array([
		a, b, b + up * 0.4, a + up * 0.4]), shadow)


static func _draw_one_riser(canvas: Variant, a: Vector2, b: Vector2, drop_steps: int, face: Color) -> void:
	if drop_steps <= 0:
		return
	var h := float(drop_steps) * WG.ELEV_STEP_PX
	var down := Vector2(0.0, h)
	# Solid cliff face (no per-step strata — those just read as noise).
	canvas.draw_colored_polygon(PackedVector2Array([a, b, b + down, a + down]), face)
	# A subtle darker band under the plateau lip separates "walkable top" from
	# "vertical cliff" without a heavy black line.
	var lip := minf(h, 2.0)
	canvas.draw_colored_polygon(PackedVector2Array([
		a, b, b + Vector2(0.0, lip), a + Vector2(0.0, lip)]), PixelPalette.shade(face, 0.78))


static func _draw_flat_tile(canvas: Variant, gtx: int, gty: int, top: Color, water: bool, soft: bool, oy: float = 0.0) -> void:
	var center := WG.tile_to_world(gtx, gty)
	center.y += oy
	var hw := WG.ISO_HW + TILE_OVERLAP
	var hh := WG.ISO_HH + TILE_OVERLAP * 0.5
	var face := top.lightened(0.03) if water else top
	PixelDraw.px_diamond(canvas, center.x, center.y, hw, hh, face)
	if water or soft:
		return
	PixelDraw.px_diamond(
		canvas,
		center.x - hw * 0.06,
		center.y - hh * 0.22,
		hw * 0.48,
		hh * 0.38,
		PixelPalette.shade(top, 1.05),
		0.18)


static func _draw_tile_speckles(
		canvas: Variant,
		gtx: int,
		gty: int,
		top: Color,
		accent: Color,
		oy: float = 0.0) -> void:
	var seed: int = WG.hash_i(WorldGen.store.world_seed, gtx, gty, 41)
	if seed % 3 == 0:
		return
	var center := WG.tile_to_world(gtx, gty)
	center.y += oy
	var px := float(PixelPalette.PX)
	var rx := (WG.r01(seed, 0, 0, 0) - 0.5) * WG.ISO_HW * 0.9
	var ry := (WG.r01(seed, 0, 1, 0) - 0.5) * WG.ISO_HH * 1.0
	var col := top.lerp(accent, 0.35)
	PixelDraw.px_rect(canvas, center.x + rx, center.y + ry, px, px, col, 0.22)


static func _draw_frozen_grass(canvas: Variant, gtx: int, gty: int, _top: Color, accent: Color, oy: float = 0.0) -> void:
	var ice := PixelPalette.hex(0xD8E0DC)
	var center := WG.tile_to_world(gtx, gty)
	center.y += oy
	var px := float(PixelPalette.PX)
	var seed: int = WG.hash_i(WorldGen.store.world_seed, gtx, gty, 44)
	for i: int in 3:
		var rx := (WG.r01(seed, i, 0, 0) - 0.5) * WG.ISO_HW * 0.85
		var ry := (WG.r01(seed, i, 1, 0) - 0.5) * WG.ISO_HH * 0.75
		var dot := accent.lerp(ice, 0.35)
		PixelDraw.px_rect(canvas, center.x + rx, center.y + ry, px, px, dot, 0.55)


static func _surface_category(reg: RefCounted, tile_id: int) -> int:
	if tile_id < 0 or tile_id >= reg.tile_order.size():
		return 0
	var name: String = reg.tile_order[tile_id]
	if name in ["deep_water", "water", "shallow"]:
		return 1
	if name in ["sand", "sand_dune"]:
		return 2
	if name in ["snow", "frozen_grass", "gravel"]:
		return 3
	return 0


## Resolve a possibly-out-of-range local tile to its owning chunk and local
## coords so border bevels compare against the neighbour's stored — already
## mode-smoothed (see BiomeMapGenerator.fill_chunk) — biome/tile data. Querying
## the generator directly returns the raw, unsmoothed field, which desyncs from
## the stored field at chunk seams and paints a false bevel down the whole edge.
static func _resolve(p_chunk: RefCounted, lx: int, ly: int) -> Array:
	if lx >= 0 and ly >= 0 and lx < WG.CHUNK_TILES and ly < WG.CHUNK_TILES:
		return [p_chunk, lx, ly]
	if WorldGen == null:
		return []
	var gtx: int = p_chunk.cx * WG.CHUNK_TILES + lx
	var gty: int = p_chunk.cy * WG.CHUNK_TILES + ly
	var c := WG.tile_to_chunk(Vector2i(gtx, gty))
	var key := WG.key(p_chunk.layer, c.x, c.y)
	if not WorldGen.chunks.has(key):
		return []
	var nc: RefCounted = WorldGen.chunks[key]
	return [nc, gtx - c.x * WG.CHUNK_TILES, gty - c.y * WG.CHUNK_TILES]


static func _tile_id_at(p_chunk: RefCounted, lx: int, ly: int) -> int:
	var n := _resolve(p_chunk, lx, ly)
	if n.is_empty():
		return -1
	return n[0].tile_id(n[1], n[2])


static func _biome_idx_at(p_chunk: RefCounted, lx: int, ly: int) -> int:
	var n := _resolve(p_chunk, lx, ly)
	if n.is_empty():
		return 255
	return n[0].biome_at(n[1], n[2])


## A bevel marks a *visible* surface-type change only — land↔water,
## land↔sand/beach, or land↔snow/ice/gravel (the surface categories). Parent-
## and sub-biome boundaries between tiles that look identical (forest grass
## meeting plains grass, or a sub-biome on the same ground) must stay seamless;
## bevelling them painted stray dashed lines across otherwise uniform terrain.
static func _needs_bevel(
		_reg: RefCounted,
		_my_parent: int,
		n_parent: int,
		_my_biome: int,
		_n_biome: int,
		my_cat: int,
		n_cat: int) -> bool:
	if n_parent == 255:
		return false
	return my_cat != n_cat


static func _parent_at(p_chunk: RefCounted, lx: int, ly: int) -> int:
	var n := _resolve(p_chunk, lx, ly)
	if n.is_empty():
		return 255
	return n[0].parent_biome_at(n[1], n[2])


static func _draw_surface_borders(
		canvas: Variant,
		p_chunk: RefCounted,
		reg: RefCounted,
		lx: int,
		ly: int,
		gtx: int,
		gty: int,
		top: Color,
		water: bool,
		oy: float = 0.0) -> void:
	var my_parent: int = p_chunk.parent_biome_at(lx, ly)
	if my_parent == 255:
		return
	var my_biome: int = p_chunk.biome_at(lx, ly)
	var my_cat: int = _surface_category(reg, p_chunk.tile_id(lx, ly))
	var center := WG.tile_to_world(gtx, gty)
	var cx := center.x
	var cy := center.y + oy
	var hw := WG.ISO_HW
	var hh := WG.ISO_HH
	for n: Array in CARDINAL:
		var offset: Vector2i = n[0]
		var edge: int = n[1]
		var n_parent: int = _parent_at(p_chunk, lx + offset.x, ly + offset.y)
		var n_biome: int = _biome_idx_at(p_chunk, lx + offset.x, ly + offset.y)
		var n_cat: int = _surface_category(reg, _tile_id_at(p_chunk, lx + offset.x, ly + offset.y))
		if not _needs_bevel(reg, my_parent, n_parent, my_biome, n_biome, my_cat, n_cat):
			continue
		_draw_edge_inset(canvas, cx, cy, hw, hh, edge, top, water)
	# No corner treatment: floor tiles keep sharp diamond corners. Chamfering the
	# diamond tips (an earlier "beveled corner") made sand and other surface-change
	# tiles read as rounded. Only the straight edge insets above mark a shoreline /
	# surface change, so every tile silhouette stays crisp like the grass/wheat tiles.


static func _draw_edge_inset(
		canvas: Variant,
		cx: float,
		cy: float,
		hw: float,
		hh: float,
		edge: int,
		top: Color,
		water: bool) -> void:
	var pts := _edge_points(cx, cy, hw, hh, edge)
	# No inset — draw full edge so adjacent tiles' segments connect without gaps.
	var a := pts[0]
	var b := pts[1]
	var px := float(PixelPalette.PX)
	var shadow := PixelPalette.pal("shadow")
	shadow.a = 0.34 if water else 0.26
	# Shadow drop strip below the edge line
	canvas.draw_colored_polygon(PackedVector2Array([
		a, b, b + Vector2(0.0, px), a + Vector2(0.0, px)]), shadow)
	# Contact highlight — use a thin polygon instead of draw_line so it respects PX
	var contact := PixelPalette.shade(top, 0.80)
	contact.a = 0.42
	canvas.draw_colored_polygon(PackedVector2Array([
		a, b, b + Vector2(0.0, px * 0.5), a + Vector2(0.0, px * 0.5)]), contact)


static func _edge_points(cx: float, cy: float, hw: float, hh: float, edge: int) -> PackedVector2Array:
	match edge:
		0:
			return PackedVector2Array([Vector2(cx - hw, cy), Vector2(cx, cy + hh)])
		1:
			return PackedVector2Array([Vector2(cx, cy - hh), Vector2(cx + hw, cy)])
		2:
			return PackedVector2Array([Vector2(cx + hw, cy), Vector2(cx, cy + hh)])
		_:
			return PackedVector2Array([Vector2(cx, cy + hh), Vector2(cx - hw, cy)])


static func bake(p_chunk: RefCounted, reg: RefCounted, _classifier: RefCounted, _p_seed: int) -> Image:
	var img_side := WG.CHUNK_TILES * 4
	var img := Image.create_empty(img_side, img_side, false, Image.FORMAT_RGB8)
	for ty: int in WG.CHUNK_TILES:
		for tx: int in WG.CHUNK_TILES:
			var col := tile_color(reg, p_chunk.tile_id(tx, ty))
			for sy: int in 4:
				for sx: int in 4:
					img.set_pixel(tx * 4 + sx, ty * 4 + sy, col)
	return img
