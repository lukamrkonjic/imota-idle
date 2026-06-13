extends Node2D
## Ground visuals for one chunk: a small baked image (SUB subtiles per tile,
## Bayer-dithered between each tile's palette pair, biome borders dissolved by
## jittered classification) scaled up with nearest filtering so it lands on
## the chunky Aldenfall pixel grid. bake() is static and touches no scene
## state, so the chunk manager can run it on a worker thread.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const SUB := 4  # subtiles per tile side -> 64x64 image per chunk

const BAYER4: Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var chunk: RefCounted
var _sprite: Sprite2D
var _placeholder: Color = Color(0.25, 0.35, 0.22)


func _init(p_chunk: RefCounted, avg_color: Color) -> void:
	chunk = p_chunk
	_placeholder = avg_color
	position = chunk.origin()
	z_index = -100


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if _sprite == null:  # flat fill until the baked texture arrives
		draw_rect(Rect2(Vector2.ZERO, Vector2(WG.CHUNK_SIZE, WG.CHUNK_SIZE)), _placeholder)


func apply_image(img: Image) -> void:
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * (WG.TILE / float(SUB))
	add_child(_sprite)
	queue_redraw()


## Average ground colour for the placeholder fill and the minimap.
static func tile_color(reg: RefCounted, byte_id: int) -> Color:
	var cols: Array = reg.tile_def(byte_id)["colors"]
	return cols[0]


static func _noise(p_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


static func _grass_patch_strength(biome_id: String, mass: float, detail: float) -> float:
	var threshold := 0.72
	var strength := 0.34
	match biome_id:
		"forest":
			threshold = 0.49
			strength = 0.70
		"dense_forest":
			threshold = 0.36
			strength = 0.84
		"swamp":
			threshold = 0.43
			strength = 0.68
		"plains":
			threshold = 0.70
			strength = 0.34
		_:
			threshold = 0.64
			strength = 0.36
	var shaped := mass + (detail - 0.5) * 0.20
	var edge := smoothstep(threshold - 0.24, threshold + 0.20, shaped)
	return edge * strength


static func _tree_shade_strength(tree_shades: Array, gx: float, gy: float) -> float:
	var shade := 0.0
	for t: Array in tree_shades:
		var dx := gx - float(t[0])
		var dy := gy - float(t[1])
		var radius := float(t[2])
		var d := sqrt(dx * dx + dy * dy)
		if d >= radius:
			continue
		var local := 1.0 - smoothstep(radius * 0.34, radius, d)
		shade = maxf(shade, local * float(t[3]))
	return shade


## Thread-safe ground bake. Pass 1 samples the classifier once per subtile
## (with a margin) into height/biome/tile grids; pass 2 colors pixels using
## only grid lookups, so neighbour-aware effects come for free:
##   - rolling-hill shading: smooth NW-lit gradient from the height field
##     (no terraces, no contour lines)
##   - biome-edge blending: ground colors fade across seams instead of
##     foreign tiles popping in as lone squares
##   - worn paths: ground blends toward the dirt palette by road strength
## Cave chunks pattern their stored tiles directly, as before.
static func bake(p_chunk: RefCounted, reg: RefCounted, classifier: RefCounted, p_seed: int,
		_elevation: RefCounted = null, roads: RefCounted = null) -> Image:
	var n := WG.CHUNK_TILES * SUB
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var base_tx: int = p_chunk.cx * WG.CHUNK_TILES
	var base_ty: int = p_chunk.cy * WG.CHUNK_TILES
	var surface: bool = p_chunk.layer == 0

	var elev_rules: Dictionary = reg.gen_rules.get("elevation", {})
	var slope_shade := float(elev_rules.get("slopeShade", 4.0))
	var slope_max := float(elev_rules.get("slopeShadeMax", 0.085))
	var highland_tint := float(elev_rules.get("highlandTint", 0.30))
	var road_cols: Array = []
	if surface and roads != null:
		var road_tile := str(reg.gen_rules.get("roads", {}).get("tile", "dirt"))
		if reg.tile_index.has(road_tile):
			road_cols = reg.tile_def(int(reg.tile_index[road_tile]))["colors"]

	# Pass 1: field grids with margin M so pass 2 can look sideways freely.
	var M := 3
	var gw := n + M * 2
	var hgrid := PackedFloat32Array()
	var bgrid := PackedByteArray()
	var tgrid := PackedByteArray()
	if surface:
		hgrid.resize(gw * gw)
		bgrid.resize(gw * gw)
		tgrid.resize(gw * gw)
		for ly: int in gw:
			var ey := float(base_ty) + (float(ly - M) + 0.5) / float(SUB)
			for lx: int in gw:
				var ex := float(base_tx) + (float(lx - M) + 0.5) / float(SUB)
				var f: Vector3 = classifier.fields(ex, ey)
				var gi := ly * gw + lx
				hgrid[gi] = f.x
				bgrid[gi] = classifier.classify(f)
				tgrid[gi] = classifier.tile_at(ex, ey, f, int(bgrid[gi]))

	var grass_id := int(reg.tile_index.get("grass", -1))
	var grass_dark_id := int(reg.tile_index.get("grass_dark", -1))
	var grass_cols: Array = reg.tile_def(grass_id)["colors"] if grass_id >= 0 else []
	var grass_dark_cols: Array = reg.tile_def(grass_dark_id)["colors"] if grass_dark_id >= 0 else []
	var patch_noise := _noise(p_seed + 808, 0.022, 3)
	var detail_noise := _noise(p_seed + 809, 0.066, 2)
	var tree_shades: Array = []
	if surface:
		for s: Dictionary in p_chunk.sites:
			if str(s.get("kind", "")) != "tree":
				continue
			var tx := float(base_tx + int(s["tx"])) + 0.5
			var ty := float(base_ty + int(s["ty"])) + 0.5
			var roll := WG.r01(p_seed, int(tx * 17.0), int(ty * 19.0), 812)
			var radius := lerpf(4.0, 7.6, roll)
			var strength := 0.22
			var b_idx: int = p_chunk.biome_at(int(s["tx"]), int(s["ty"]))
			if b_idx != 255:
				match str(reg.biomes[b_idx]["id"]):
					"forest":
						strength = 0.34
					"dense_forest":
						strength = 0.42
					"swamp":
						strength = 0.32
			tree_shades.append([tx, ty, radius, strength])

	for sy: int in n:
		var gy := float(base_ty) + (float(sy) + 0.5) / float(SUB)
		for sx: int in n:
			var gx := float(base_tx) + (float(sx) + 0.5) / float(SUB)
			var gi := (sy + M) * gw + (sx + M)
			var byte_id: int
			var biome_id := ""
			var biome_index := 0
			if surface:
				biome_index = bgrid[gi]
				biome_id = str(reg.biomes[biome_index]["id"])
				byte_id = tgrid[gi]
			else:
				byte_id = p_chunk.tile_id(
					clampi(sx / SUB, 0, WG.CHUNK_TILES - 1),
					clampi(sy / SUB, 0, WG.CHUNK_TILES - 1))
			var tile: Dictionary = reg.tile_def(byte_id)
			var cols: Array = tile["colors"]
			var is_water := bool(tile.get("water", false))
			var gsx: int = base_tx * SUB + sx
			var gsy: int = base_ty * SUB + sy
			var soft_noise := WG.r01(p_seed, floori(gx / 3.0), floori(gy / 3.0), 5)
			var bayer := (float(BAYER4[(gsy % 4) * 4 + (gsx % 4)]) / 16.0 - 0.5) * 0.06
			var blend := clampf(0.24 + soft_noise * 0.16 + bayer, 0.0, 1.0)
			var col: Color
			if surface and (byte_id == grass_id or byte_id == grass_dark_id) and not grass_cols.is_empty() and not grass_dark_cols.is_empty():
				var mass := patch_noise.get_noise_2d(gx, gy) * 0.5 + 0.5
				var detail := detail_noise.get_noise_2d(gx, gy) * 0.5 + 0.5
				var patch_strength := _grass_patch_strength(biome_id, mass, detail)
				patch_strength = clampf(patch_strength + _tree_shade_strength(tree_shades, gx, gy), 0.0, 0.92)
				var base_col: Color = Color(grass_cols[0]).lerp(Color(grass_cols[1]), blend * 0.55)
				var dark_col: Color = Color(grass_dark_cols[0]).lerp(Color(grass_dark_cols[1]), blend * 0.50)
				col = base_col.lerp(dark_col, patch_strength)
			else:
				col = Color(cols[0]).lerp(Color(cols[1]), blend)
			# Very subtle local variation: enough to avoid flat wallpaper,
			# not enough to create harsh dark blocks in forests.
			var patch := WG.r01(p_seed, floori(gx / 5.0), floori(gy / 5.0), 6)
			if is_water:
				col = col.lightened((patch - 0.5) * 0.045)
			else:
				col = col.lightened((patch - 0.5) * 0.018)
			var speck := WG.r01(p_seed, gsx, gsy, 8)
			if not is_water and speck > 0.996:
				col = col.lightened(0.025)
			if surface:
				# Biome-edge gradient: fade toward differing neighbours' ground
				# colors so seams melt together (never bleed water onto land).
				if not is_water:
					var mix := Color(0, 0, 0)
					var diff := 0
					for off: Vector2i in [Vector2i(M, 0), Vector2i(-M, 0), Vector2i(0, M), Vector2i(0, -M)]:
						var ni := (sy + M + off.y) * gw + (sx + M + off.x)
						if int(bgrid[ni]) == biome_index:
							continue
						var ntile: Dictionary = reg.tile_def(tgrid[ni])
						if bool(ntile.get("water", false)):
							continue
						var ncols: Array = ntile["colors"]
						mix += Color(ncols[0]).lerp(Color(ncols[1]), blend * 0.6)
						diff += 1
					if diff > 0:
						col = col.lerp(mix / float(diff), float(diff) / 4.0 * 0.5)
				# Worn path: soft-edged blend toward the dirt palette.
				if not road_cols.is_empty() and not is_water and not bool(tile.get("hazard", false)):
					var rs: float = roads.road_strength_at(gx, gy)
					if rs > 0.0:
						var road_col: Color = Color(road_cols[0]).lerp(Color(road_cols[1]), blend * 0.7)
						col = col.lerp(road_col, smoothstep(0.0, 1.0, rs) * 0.85)
				# Rolling hills: smooth NW-lit slope shading + gentle pale
				# tint at altitude. Gradients over +-M subtiles stay soft.
				if not is_water:
					var dhdx: float = hgrid[gi + M] - hgrid[gi - M]
					var dhdy: float = hgrid[gi + M * gw] - hgrid[gi - M * gw]
					var lum := clampf((dhdx + dhdy) * slope_shade, -slope_max, slope_max)
					col = col.lightened(lum) if lum > 0.0 else col.darkened(-lum)
					var h0: float = hgrid[gi]
					if h0 > 0.62:
						col = col.lightened((h0 - 0.62) * highland_tint)
			img.set_pixel(sx, sy, col)
	return img