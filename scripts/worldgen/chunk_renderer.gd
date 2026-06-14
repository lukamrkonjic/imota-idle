extends Node2D
## Isometric ground visuals for one chunk — drawn once, then frozen for performance.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const WorldLighting := preload("res://scripts/world/art/core/world_lighting.gd")

const TILE_OVERLAP := 0.65
const CARDINAL: Array = [
	[Vector2i(0, -1), 1],
	[Vector2i(1, 0), 2],
	[Vector2i(0, 1), 3],
	[Vector2i(-1, 0), 0],
]
const CORNERS: Array = [
	[Vector2i(0, -1), Vector2i(-1, 0), 0],
	[Vector2i(0, -1), Vector2i(1, 0), 1],
	[Vector2i(0, 1), Vector2i(1, 0), 2],
	[Vector2i(0, 1), Vector2i(-1, 0), 3],
]

var chunk: RefCounted
var _placeholder: Color = Color(0.25, 0.35, 0.22)


func _init(p_chunk: RefCounted, avg_color: Color) -> void:
	chunk = p_chunk
	_placeholder = avg_color
	# Order ground chunks back-to-front by isometric depth so a raised chunk's
	# terrain risers can never poke through the flat chunk in front of it. Kept
	# well below entities (which y-sort around z 0+) so ground stays underneath.
	z_index = -1000 + p_chunk.cx + p_chunk.cy


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
	# A window/viewport resize makes the engine drop this CanvasItem's cached
	# draw commands and re-issue _draw. An earlier "draw once then freeze"
	# guard turned that re-issue into a blank, so the ground went black on
	# resize while entities (which redraw on signals) stayed. Redraw fully on
	# every _draw, and force one on resize so the ground is never left blank.
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var reg: RefCounted = WorldGen.reg if WorldGen != null else null
	if reg == null:
		_draw_placeholder()
	else:
		_draw_chunk(self, chunk, reg)


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


static func _draw_chunk(canvas: CanvasItem, p_chunk: RefCounted, reg: RefCounted) -> void:
	var base_tx: int = p_chunk.cx * WG.CHUNK_TILES
	var base_ty: int = p_chunk.cy * WG.CHUNK_TILES
	var order: Array = []
	for ty: int in WG.CHUNK_TILES:
		for tx: int in WG.CHUNK_TILES:
			order.append(Vector3i(base_tx + tx, base_ty + ty, p_chunk.tile_id(tx, ty)))
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (a.x + a.y) < (b.x + b.y))
	for item: Vector3i in order:
		var tile_name: String = _tile_name(reg, item.z)
		var td: Dictionary = reg.tile_def(item.z)
		var cols: Array = td["colors"]
		var lx: int = item.x - base_tx
		var ly: int = item.y - base_ty
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
		# Cast shadow: darken ground that taller terrain toward the sun shades. This
		# is the key depth cue — a peak throws a visible shadow onto the land below.
		if not water:
			var sh := _terrain_shadow(p_chunk, lx, ly, elev)
			if sh > 0.0:
				top = PixelPalette.shade(top, 1.0 - sh)
				accent = PixelPalette.shade(accent, 1.0 - sh)
		# Beveled risers down to the lower neighbours toward the camera first, then
		# the raised top so the top edge sits cleanly on the wall.
		if elev > 0:
			_draw_risers(canvas, p_chunk, lx, ly, item.x, item.y, elev, top, oy)
		_draw_flat_tile(canvas, item.x, item.y, top, water, soft, oy)
		if not water and not soft:
			_draw_tile_speckles(canvas, item.x, item.y, top, accent, oy)
		elif tile_name == "frozen_grass":
			_draw_frozen_grass(canvas, item.x, item.y, top, accent, oy)
		_draw_surface_borders(canvas, p_chunk, reg, lx, ly, item.x, item.y, top, water, oy)


## Beveled vertical risers on the two camera-facing edges (SE toward +x, SW
## toward +y), one per elevation step the tile stands above that neighbour, so a
## hillside reads as terraced ground with the same bevel used between biomes.
static func _draw_risers(canvas: CanvasItem, p_chunk: RefCounted, lx: int, ly: int, gtx: int, gty: int, elev: int, top: Color, oy: float) -> void:
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


static func _draw_one_riser(canvas: CanvasItem, a: Vector2, b: Vector2, drop_steps: int, face: Color) -> void:
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


static func _draw_flat_tile(canvas: CanvasItem, gtx: int, gty: int, top: Color, water: bool, soft: bool, oy: float = 0.0) -> void:
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
		canvas: CanvasItem,
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


static func _draw_frozen_grass(canvas: CanvasItem, gtx: int, gty: int, _top: Color, accent: Color, oy: float = 0.0) -> void:
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
	var nc: RefCounted = WorldGen.get_chunk(p_chunk.layer, c.x, c.y)
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
		canvas: CanvasItem,
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
	for corner: Array in CORNERS:
		var a: Vector2i = corner[0]
		var b: Vector2i = corner[1]
		var corner_id: int = corner[2]
		var pa: int = _parent_at(p_chunk, lx + a.x, ly + a.y)
		var pb: int = _parent_at(p_chunk, lx + b.x, ly + b.y)
		var ba: int = _biome_idx_at(p_chunk, lx + a.x, ly + a.y)
		var bb: int = _biome_idx_at(p_chunk, lx + b.x, ly + b.y)
		var ca: int = _surface_category(reg, _tile_id_at(p_chunk, lx + a.x, ly + a.y))
		var cb: int = _surface_category(reg, _tile_id_at(p_chunk, lx + b.x, ly + b.y))
		var edge_a := _needs_bevel(reg, my_parent, pa, my_biome, ba, my_cat, ca)
		var edge_b := _needs_bevel(reg, my_parent, pb, my_biome, bb, my_cat, cb)
		if edge_a and edge_b:
			_draw_beveled_corner(canvas, cx, cy, hw, hh, corner_id, top, water)


static func _draw_edge_inset(
		canvas: CanvasItem,
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


static func _draw_beveled_corner(
		canvas: CanvasItem,
		cx: float,
		cy: float,
		hw: float,
		hh: float,
		corner: int,
		top: Color,
		water: bool) -> void:
	var bevel := 0.20
	var tip := Vector2.ZERO
	var p1 := Vector2.ZERO
	var p2 := Vector2.ZERO
	match corner:
		0:
			tip = Vector2(cx, cy - hh)
			p1 = tip.lerp(Vector2(cx - hw, cy), bevel)
			p2 = tip.lerp(Vector2(cx + hw, cy), bevel)
		1:
			tip = Vector2(cx + hw, cy)
			p1 = tip.lerp(Vector2(cx, cy - hh), bevel)
			p2 = tip.lerp(Vector2(cx, cy + hh), bevel)
		2:
			tip = Vector2(cx, cy + hh)
			p1 = tip.lerp(Vector2(cx + hw, cy), bevel)
			p2 = tip.lerp(Vector2(cx - hw, cy), bevel)
		_:
			tip = Vector2(cx - hw, cy)
			p1 = tip.lerp(Vector2(cx, cy + hh), bevel)
			p2 = tip.lerp(Vector2(cx, cy - hh), bevel)
	var shadow := PixelPalette.pal("shadow")
	shadow.a = 0.42 if water else 0.36
	canvas.draw_colored_polygon(PackedVector2Array([tip, p1, p2]), shadow)
	var contact := PixelPalette.shade(top, 0.70)
	contact.a = 0.50
	canvas.draw_line(p1, p2, contact, 1.1)


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
