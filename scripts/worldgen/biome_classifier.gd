extends RefCounted
## Terrain fields (height / moisture / temperature), rivers, lakes, and tile
## palettes. Parent/sub biome placement lives in biome_map_generator.gd.

const WG := preload("res://scripts/worldgen/wg.gd")
const BiomeMapGenerator := preload("res://scripts/worldgen/biome_map_generator.gd")

const SPAWN_SHAPE_CHUNKS := 2.2

var reg: RefCounted
var world_seed: int = 0
var map_gen: RefCounted = BiomeMapGenerator.new()

var _height: FastNoiseLite
var _height_macro: FastNoiseLite
var _moist: FastNoiseLite
var _moist_macro: FastNoiseLite
var _temp: FastNoiseLite
var _climate: FastNoiseLite
var _land_continents: FastNoiseLite
var _hydro: HydrologyField       # rivers + lakes + shore water (hydrology_field.gd)
var _dune: FastNoiseLite
var _volcanic_rift: FastNoiseLite
var _domain_warp: FastNoiseLite
var _surface_detail: FastNoiseLite
var _region: FastNoiseLite       # blends geographic biome-region boundaries
var _mtn: MountainField          # orography (mountains/elevation/snow), see mountain_field.gd
var _continent: FastNoiseLite    # big landmass blobs (low freq) — peninsulas/gulfs
var _coast_detail: FastNoiseLite # ridged coast fingers (fjords, capes, coves)
var _island: FastNoiseLite       # MEDIUM offshore islands
var _island_big: FastNoiseLite   # LARGE offshore islands (low freq, multi-biome capable)
var _island_small: FastNoiseLite # small islets + scattered rock fragments (high freq)

var _t_deep: int
var _t_water: int
var _t_shallow: int
var _t_sand: int
var _t_rock: int
var _t_cobble: int

# Finite-world geography: a continent centred on the bounds, with progression
# radiating outward (safe green core -> rough dangerous rim -> sea).
var _finite := false
var _center := Vector2.ZERO   # world centre in tiles
var _radius_x := 512.0        # tiles centre->rim along X (wider than Y => a WIDE continent)
var _radius_y := 512.0        # tiles centre->rim along Y

# --- continent landmass shape (RuneScape-style irregular coast) ---------------
# The continent is deliberately NOT a radial blob. A low-frequency, heavily
# domain-warped landmass field carves big peninsulas, gulfs and inlets; a ridged
# detail field adds fjord-fingers and coves; an offshore field scatters islands
# in the shallow sea just past the coast. A gentle radial term keeps the
# inhabited core solid and fades land toward the rim, and authored regions get an
# explicit land guarantee (plus connecting corridors) so content never drowns and
# the mainland stays one walkable body. Tune these to reshape every world:
const _SHORE_R := 0.82          # norm_dist at the nominal coastline
const _FALL_SLOPE := 0.62       # gentle => low-freq noise carves deep gulfs/capes (lower = wilder coast)
const _SEA_LEVEL := 0.47        # landmass threshold; higher => more/deeper bays
const _COAST_BAND := 0.12       # landmass span of the beach/shallow transition
const _GUARANTEE_LAND := 0.20   # solid-land value forced under authored content
# --- OSRS-style multi-continent landmass ---
# A handful of AUTHORED continents (main + a desert peninsula + 2 large secondary landmasses)
# instead of one radial blob. A tile is land if it sits inside ANY continent's ellipse; the
# coastline noise wiggles each edge into bays/capes. Continents are in absolute world tiles so
# the layout is fixed + expansion-safe (never normalised to the current bounds).
const _COAST_AMP := 0.46        # coastline wiggle amplitude (bays/capes/peninsular fingers)
var _continents: Array = []     # [{c:Vector2, rx:float, ry:float}] authored landmasses (tiles)
var _land_discs: Array = []     # [{c:Vector2, r:float}] forced-land discs (tiles)
var _land_corridors: Array = [] # [{a,b:Vector2, r:float}] connecting land bridges

# --- AUTHORED land mask (the real Aldreth coastline) --------------------------
# When data/world/masks/<world>_land.png exists (world = active spec id), it — not
# the ellipse field above — is the single source of the continent SHAPE (traced from
# the illustrated map by tools/world_trace.gd). We precompute a signed-distance field
# from it once (positive = tiles inland, negative = tiles offshore) and sample THAT,
# so the coast follows the map's fractal outline with a controllable beach width, and
# the per-tile cost is just a few float reads. No mask => the ellipse path runs
# unchanged, so other specs/worlds still work.
const _MASK_DIR := "res://data/world/masks/"
const _MASK_SHORE := 0.04       # landmass value at the waterline (=> coast_sink ~0.72, ocean/beach edge)
const _MASK_SLOPE := 0.013      # landmass gained per tile inland (=> ~3-tile beach, solid land beyond ~6)
const _MASK_FRAY := 0.012       # tile-scale jitter on the waterline so it isn't a smooth interpolation
var _has_land_mask := false
var _land_sdf: PackedFloat32Array = PackedFloat32Array()  # signed dist in MASK PIXELS (+inland/-sea)
var _mask_w := 0
var _mask_h := 0
var _mask_min_tx := 0.0
var _mask_min_ty := 0.0
var _mask_tile_w := 1.0
var _mask_tile_h := 1.0
var _tiles_per_mask_px := 1.0

# Authored data masks (same geometry/bounds as the land mask): per-tile biome,
# elevation and rivers/lakes traced from the reference art (tools/trace_world.py).
# When present they DRIVE biome/elevation/water directly — the procedural
# climate/orography/hydrology models are bypassed.
const _ELEV_MAX := 44            # mirrors MountainField.ELEV_MAX_STEPS
var _has_biome_mask := false
var _has_elev_mask := false
var _has_river_mask := false
var _biome_data: PackedByteArray = PackedByteArray()   # 1 byte/px = palette index
var _elev_data: PackedByteArray = PackedByteArray()    # 1 byte/px = 0..255 height
var _river_data: PackedByteArray = PackedByteArray()   # 1 byte/px = 0/255 water
var _biome_lut: PackedInt32Array = PackedInt32Array()  # palette index -> reg biome index


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed
	map_gen.setup(reg, p_seed, self)
	_finite = reg.spec.active and reg.spec.finite
	if _finite:
		var b: Rect2i = reg.spec.bounds
		_center = Vector2(
			(float(b.position.x) + float(b.size.x) * 0.5) * WG.CHUNK_TILES,
			(float(b.position.y) + float(b.size.y) * 0.5) * WG.CHUNK_TILES)
		# Anisotropic: each axis fills its own half-extent, so wide bounds -> wide continent.
		_radius_x = float(b.size.x) * WG.CHUNK_TILES * 0.5
		_radius_y = float(b.size.y) * WG.CHUNK_TILES * 0.5
	_region = _noise(p_seed + 1407, 0.0030, 2)
	_mtn = MountainField.new()
	_mtn.setup(self, p_seed)
	_continent = _noise(p_seed + 1700, 0.0013, 4)
	_coast_detail = _noise(p_seed + 1701, 0.0045, 3)
	_island = _noise(p_seed + 1702, 0.0060, 2)
	_island_big = _noise(p_seed + 1722, 0.0020, 3)    # large landforms a long way offshore
	_island_small = _noise(p_seed + 1742, 0.0150, 2)  # islets / rock fragments hugging the coast
	_height = _noise(p_seed, 0.011, 4)
	_height_macro = _noise(p_seed + 11, 0.0026, 3)
	_moist = _noise(p_seed + 101, 0.016, 3)
	_moist_macro = _noise(p_seed + 111, 0.0020, 2)
	_temp = _noise(p_seed + 202, 0.006, 2)
	_climate = _noise(p_seed + 505, 0.0016, 2)
	_land_continents = _noise(p_seed + 909, 0.00038, 2)
	_hydro = HydrologyField.new()
	_hydro.setup(self, p_seed)
	_dune = _noise(p_seed + 808, 0.018, 2)
	_volcanic_rift = _noise(p_seed + 707, 0.0011, 2)
	_domain_warp = _noise(p_seed + 1201, 0.0032, 2)
	_surface_detail = _noise(p_seed + 1202, 0.11, 1)
	_t_deep = int(reg.tile_index["deep_water"])
	_t_water = int(reg.tile_index["water"])
	_t_shallow = int(reg.tile_index["shallow"])
	_t_sand = int(reg.tile_index["sand"])
	_t_rock = int(reg.tile_index["rock"])
	_t_cobble = int(reg.tile_index["cobble"])
	if _finite:
		_load_land_mask()
		_load_data_masks()
	# The ellipse continents + land-guarantee discs are only the FALLBACK shape;
	# skip them entirely when the authored mask is driving the coastline.
	if not _has_land_mask:
		_build_continents()
		_build_land_guarantees()


## Precompute the forced-land discs (every authored region + the home core) and
## the land bridges that connect each region back to the core, so the irregular
## coastline can never sever authored content from the mainland.
## Author the macro-geography: a big MAIN continent, a desert PENINSULA protruding from its
## south-east, and two LARGE secondary continents (east + west) separated by real sea — an
## OSRS-style world of a few meaningful landmasses, not one blob ringed by specks. Absolute
## tile coords => the silhouette is fixed and survives world expansion.
func _build_continents() -> void:
	_continents.clear()
	if not _finite:
		return
	# center, half-extents (tiles). Tuned against bounds ~x[-1088,1072] y[-704,688].
	_continents = [
		{"c": Vector2(-120.0, -40.0), "rx": 600.0, "ry": 560.0},   # MAIN — temperate heart, cold/hostile N, swamp S
		{"c": Vector2(700.0, 340.0),  "rx": 340.0, "ry": 230.0},   # DESERT peninsula — protrudes SE off the main
		{"c": Vector2(980.0, -280.0), "rx": 240.0, "ry": 300.0},   # EASTERN island (large secondary)
		{"c": Vector2(-820.0, 210.0), "rx": 290.0, "ry": 340.0},   # WESTERN island (large secondary)
	]


## Continent "mass" 0..1 at a (warped) sample point: ~1 deep inside the nearest continent,
## falling through a controlled edge band to 0 well outside, so each landmass has a TIGHT coast
## (~0.85x its radius) instead of bleeding halfway to the next. MAX over continents => they join
## where they overlap (peninsula) and stand apart where they don't (separate islands/seas).
func _continent_mass(sx: float, sy: float) -> float:
	var best := 0.0
	for cont: Dictionary in _continents:
		var c: Vector2 = cont["c"]
		var dx: float = (sx - c.x) / float(cont["rx"])
		var dy: float = (sy - c.y) / float(cont["ry"])
		var ed := sqrt(dx * dx + dy * dy)
		best = maxf(best, 1.0 - smoothstep(0.55, 1.15, ed))
	return best


func _build_land_guarantees() -> void:
	_land_discs.clear()
	_land_corridors.clear()
	if not _finite:
		return
	var ct := float(WG.CHUNK_TILES)
	_land_discs.append({"c": _center, "r": 3.0 * ct})   # home / spawn core
	for r: Dictionary in reg.spec.regions:
		var c := Vector2(float(r["cx"]) * ct + ct * 0.5, float(r["cy"]) * ct + ct * 0.5)
		_land_discs.append({"c": c, "r": (float(r["radius"]) + 0.5) * ct})
		# Only bridge regions that sit on the MAIN BODY (main continent + its desert peninsula)
		# back to spawn. Regions on the secondary ISLAND continents get a land disc but NO
		# corridor, so the islands stay true islands across open sea (reached by boat, later).
		if _on_main_body(c.x, c.y):
			_land_corridors.append({"a": _center, "b": c, "r": 1.4 * ct})


## True when a tile sits on the connected main landmass (continent 0 = main, continent 1 = the
## desert peninsula, which overlaps it) — as opposed to a separate island continent.
func _on_main_body(tx: float, ty: float) -> bool:
	for i: int in [0, 1]:
		if i >= _continents.size():
			break
		var cont: Dictionary = _continents[i]
		var c: Vector2 = cont["c"]
		var dx: float = (tx - c.x) / float(cont["rx"])
		var dy: float = (ty - c.y) / float(cont["ry"])
		if sqrt(dx * dx + dy * dy) < 1.15:
			return true
	return false


static func _noise(p_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


func classify_fields_warped(tx: float, ty: float) -> Vector3:
	var wx := _domain_warp.get_noise_2d(tx * 0.0035, ty * 0.0035) * 14.0
	var wy := _domain_warp.get_noise_2d(tx * 0.0035 + 97.0, ty * 0.0035 + 53.0) * 14.0
	return classify_fields(tx + wx, ty + wy)


func fields(tx: float, ty: float) -> Vector3:
	var h := _height.get_noise_2d(tx, ty) * 0.5 + 0.5
	var m := _moist.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t_local := _temp.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t_region := _climate.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t := _temperature_for_tile(t_local, t_region)
	var dist_chunks := Vector2(tx, ty).length() / float(WG.CHUNK_TILES)
	if dist_chunks < SPAWN_SHAPE_CHUNKS:
		var s := 1.0 - smoothstep(0.0, SPAWN_SHAPE_CHUNKS, dist_chunks)
		h = lerpf(h, clampf(h, 0.46, 0.62), s)
		m = lerpf(m, clampf(m, 0.30, 0.50), s)
		t = lerpf(t, clampf(t, 0.38, 0.58), s)
	h = _apply_continent(tx, ty, h)
	return Vector3(h, m, t)


# Normalised distance from the continent centre (0 core .. 1 rim), with a touch
# of domain warp so progression bands read as organic, not perfect circles.
func norm_dist(tx: float, ty: float) -> float:
	if not _finite:
		return 0.0
	var wx := _domain_warp.get_noise_2d(tx * 0.004, ty * 0.004) * 90.0
	var wy := _domain_warp.get_noise_2d(tx * 0.004 + 71.0, ty * 0.004 + 23.0) * 90.0
	# Elliptical (anisotropic) distance: each axis normalised by its own radius, so a
	# wide bounds yields a wide continent instead of a circle squeezed to the short side.
	var dx := (tx + wx - _center.x) / maxf(_radius_x * 0.92, 1.0)
	var dy := (ty + wy - _center.y) / maxf(_radius_y * 0.92, 1.0)
	return clampf(sqrt(dx * dx + dy * dy), 0.0, 1.6)


## 0 at the safe green core, 1 at the dangerous rim — drives biome harshness,
## enemy levels and resource tiers for a centre-out progression.
func danger01(tx: float, ty: float) -> float:
	return clampf(norm_dist(tx, ty), 0.0, 1.0)


# Sink the terrain toward open sea past the rim so the finite world is a real
# continent. The shore radius is modulated by low-freq coast noise, so instead
# of a clean disc the landmass grows bays, capes and a few offshore islets — an
# organically shaped island. (Progression stays radial via norm_dist/danger01,
# independent of the irregular coast.)
func _apply_continent(tx: float, ty: float, h: float) -> float:
	if not _finite:
		return h
	return h - coast_sink(tx, ty) * 0.75


## Smooth 0..1 "how close to / past the shore" factor — 0 well inland, rising to
## 1 out past the organic coastline. Drives the continent sink AND the coastal
## elevation taper, so both follow the same shore. Derived from the signed
## landmass field, so it follows the irregular coast (peninsulas/gulfs/islands)
## while still varying smoothly.
func coast_sink(tx: float, ty: float) -> float:
	if not _finite:
		return 0.0
	var lm := _landmass(tx, ty)
	return clampf(1.0 - smoothstep(0.0, _COAST_BAND, lm), 0.0, 1.0)


## Signed continent field: > 0 is land, < 0 is open sea; the magnitude is how far
## inland / offshore a tile sits. This is the single source of the continent's
## SHAPE — an irregular RuneScape-style landmass, not a radial blob. (Progression
## stays radial via norm_dist/danger01, independent of this coastline.)
func _landmass(tx: float, ty: float) -> float:
	if not _finite:
		return 1.0
	# AUTHORED mask drives the shape when present: signed tile-distance to the coast,
	# mapped into the same landmass scale (>0 land, <0 sea) the rest of the pipeline
	# expects, with a small waterline fray. No ellipse/island/guarantee maths here.
	if _has_land_mask:
		var s := _land_signed_tiles(tx, ty)
		if s <= -900.0:
			return -1.0   # beyond the authored bounds = open sea
		var fray := _surface_detail.get_noise_2d(tx * 3.0, ty * 3.0) * _MASK_FRAY
		return _MASK_SHORE + s * _MASK_SLOPE + fray
	# Heavy, low-frequency domain warp twists the coast into peninsulas and gulfs
	# rather than a clean disc.
	var wx := _domain_warp.get_noise_2d(tx * 0.0016, ty * 0.0016) * 470.0
	var wy := _domain_warp.get_noise_2d(tx * 0.0016 + 131.0, ty * 0.0016 + 57.0) * 470.0
	var sx := tx + wx
	var sy := ty + wy
	var base := _continent.get_noise_2d(sx, sy) * 0.5 + 0.5          # 0..1 big blobs
	var detail := 1.0 - absf(_coast_detail.get_noise_2d(sx, sy))     # 0..1 ridged fingers
	var shape := base * 0.74 + detail * 0.26
	# Multi-continent mass (gentle warp => recognisable but irregular coasts), combined with the
	# coastline noise so each landmass grows bays/capes/peninsular fingers around its nominal edge.
	var gx := tx + _domain_warp.get_noise_2d(tx * 0.004, ty * 0.004) * 130.0
	var gy := ty + _domain_warp.get_noise_2d(tx * 0.004 + 71.0, ty * 0.004 + 23.0) * 130.0
	var mass := _continent_mass(gx, gy)
	var lm := (mass - 0.5) + (shape - 0.5) * _COAST_AMP
	# Offshore islands — kept SPARSE and skewed to the larger sizes (the authored continents are
	# the big landmasses now). A few medium islands + occasional small islets; almost no specks.
	if lm < 0.0:
		var off := -lm                                  # 0 at the coast .. deeper = further out
		# MEDIUM islands (low-freq, rare): the only sizeable offshore land beyond the continents.
		var big := _island_big.get_noise_2d(sx, sy) * 0.5 + 0.5
		var big_lift := smoothstep(0.70, 0.90, big) * 0.80 * (1.0 - smoothstep(0.0, 0.70, off))
		# SMALL islets, sparse, hugging the coast — flavour, not a speckle field.
		var sml := _island.get_noise_2d(sx, sy) * 0.5 + 0.5
		var sml_lift := smoothstep(0.84, 0.98, sml) * 0.42 * (1.0 - smoothstep(0.0, 0.24, off))
		lm += maxf(big_lift, sml_lift)
	# Authored-content land guarantee — only ever ADDS land, blended by a soft edge
	# so the coast still wiggles naturally just outside the guaranteed zone.
	var g := _land_guarantee01(tx, ty)
	if g > 0.0:
		lm = lerpf(lm, maxf(lm, _GUARANTEE_LAND), g)
	return lm


## True when the authored land mask is the active coastline source.
func has_land_mask() -> bool:
	return _has_land_mask


## Path to a world's authored land mask (single source of truth for all tools).
static func land_mask_path(world_id: String) -> String:
	return _MASK_DIR + world_id + "_land.png"


## Load the traced land mask (if any) and precompute its signed-distance field.
## The mask covers the full authored bounds 1:1 in tile space.
func _load_land_mask() -> void:
	var img := _load_png_image(land_mask_path(str(reg.spec.id)))
	if img == null:
		return
	img.convert(Image.FORMAT_RGB8)
	_mask_w = img.get_width()
	_mask_h = img.get_height()
	if _mask_w < 2 or _mask_h < 2:
		return
	var b: Rect2i = reg.spec.bounds
	_mask_min_tx = float(b.position.x) * WG.CHUNK_TILES
	_mask_min_ty = float(b.position.y) * WG.CHUNK_TILES
	_mask_tile_w = float(b.size.x) * WG.CHUNK_TILES
	_mask_tile_h = float(b.size.y) * WG.CHUNK_TILES
	_tiles_per_mask_px = (_mask_tile_w / float(_mask_w) + _mask_tile_h / float(_mask_h)) * 0.5
	_build_land_sdf(img)
	_has_land_mask = true


## Load the authored biome / elevation / river masks (same size as the land mask).
func _load_data_masks() -> void:
	if not _has_land_mask:
		return
	var id := str(reg.spec.id)
	_biome_data = _load_mask_bytes(_MASK_DIR + id + "_biomes.png")
	_elev_data = _load_mask_bytes(_MASK_DIR + id + "_elev.png")
	_river_data = _load_mask_bytes(_MASK_DIR + id + "_rivers.png")
	var n := _mask_w * _mask_h
	_has_biome_mask = _biome_data.size() == n
	_has_elev_mask = _elev_data.size() == n
	_has_river_mask = _river_data.size() == n
	if _has_biome_mask:
		_build_biome_lut(id)
		if _biome_lut.is_empty():
			_has_biome_mask = false


func _load_mask_bytes(path: String) -> PackedByteArray:
	var img := _load_png_image(path)
	if img == null:
		return PackedByteArray()
	if img.get_width() != _mask_w or img.get_height() != _mask_h:
		push_warning("Data mask size mismatch, ignored: " + path)
		return PackedByteArray()
	img.convert(Image.FORMAT_R8)   # one byte per pixel (red channel)
	return img.get_data()


## Map the mask's palette (index -> biome id, from aldreth_mask.json) to runtime
## biome indices, so a pixel value resolves to a reg biome.
func _build_biome_lut(id: String) -> void:
	_biome_lut = PackedInt32Array()
	var path := _MASK_DIR + id + "_mask.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var palette: Array = (parsed as Dictionary).get("biomePalette", [])
	var fallback := int(reg.biome_index.get("forest", 0))
	for entry: Variant in palette:
		_biome_lut.append(int(reg.biome_index.get(str(entry), fallback)))


## Nearest mask-pixel flat index for a world tile, or -1 outside the bounds.
func _mask_pi(tx: float, ty: float) -> int:
	var u := (tx - _mask_min_tx) / _mask_tile_w
	var v := (ty - _mask_min_ty) / _mask_tile_h
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return -1
	var x := clampi(int(u * float(_mask_w)), 0, _mask_w - 1)
	var y := clampi(int(v * float(_mask_h)), 0, _mask_h - 1)
	return y * _mask_w + x


func has_biome_mask() -> bool:
	return _has_biome_mask


## Runtime biome index from the authored biome mask, or -1 (out of bounds / no mask).
func mask_biome_idx(tx: float, ty: float) -> int:
	if not _has_biome_mask:
		return -1
	var pi := _mask_pi(tx, ty)
	if pi < 0:
		return -1
	var p := int(_biome_data[pi])
	return _biome_lut[p] if p < _biome_lut.size() else -1


func has_elev_mask() -> bool:
	return _has_elev_mask


## Authored elevation in steps (0..ELEV_MAX). A mild gamma keeps lowland flat while
## still reaching tall peaks where the traversability map is "Blocked"/snow.
func mask_elev_steps(tx: float, ty: float) -> int:
	var pi := _mask_pi(tx, ty)
	if pi < 0:
		return 0
	var v := float(_elev_data[pi]) / 255.0
	return clampi(int(round(pow(v, 1.4) * float(_ELEV_MAX))), 0, _ELEV_MAX)


func has_river_mask() -> bool:
	return _has_river_mask


func mask_is_water(tx: float, ty: float) -> bool:
	if not _has_river_mask:
		return false
	var pi := _mask_pi(tx, ty)
	return pi >= 0 and _river_data[pi] > 127


## Two-pass chamfer signed-distance transform of the binary mask (land = bright).
## sdf > 0 inside land (distance to nearest sea, in mask pixels); < 0 in the sea
## (negative distance to nearest land). Cheap (O(2·W·H)) and runs once at setup.
func _build_land_sdf(img: Image) -> void:
	var n := _mask_w * _mask_h
	var INF := 1.0e9
	var d_in := PackedFloat32Array()  # dist to nearest SEA (0 on sea)
	var d_out := PackedFloat32Array() # dist to nearest LAND (0 on land)
	d_in.resize(n)
	d_out.resize(n)
	# Read the raw RGB8 buffer once (red byte per pixel) — far faster than get_pixel
	# 1.5M times, which matters because every bake worker builds this.
	var data := img.get_data()   # FORMAT_RGB8 => 3 bytes/pixel, R first
	for i: int in n:
		var is_land := data[i * 3] > 127
		d_in[i] = INF if is_land else 0.0
		d_out[i] = 0.0 if is_land else INF
	_chamfer(d_in, INF)
	_chamfer(d_out, INF)
	_land_sdf = PackedFloat32Array()
	_land_sdf.resize(n)
	for i: int in n:
		_land_sdf[i] = d_in[i] - d_out[i]


## In-place chamfer distance transform (forward + backward 3×3 passes).
func _chamfer(d: PackedFloat32Array, INF: float) -> void:
	var DIAG := 1.4142136
	var w := _mask_w
	var h := _mask_h
	for y: int in h:
		for x: int in w:
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x > 0: m = minf(m, d[i - 1] + 1.0)
			if y > 0: m = minf(m, d[i - w] + 1.0)
			if x > 0 and y > 0: m = minf(m, d[i - w - 1] + DIAG)
			if x < w - 1 and y > 0: m = minf(m, d[i - w + 1] + DIAG)
			d[i] = m
	for y: int in range(h - 1, -1, -1):
		for x: int in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x < w - 1: m = minf(m, d[i + 1] + 1.0)
			if y < h - 1: m = minf(m, d[i + w] + 1.0)
			if x < w - 1 and y < h - 1: m = minf(m, d[i + w + 1] + DIAG)
			if x > 0 and y < h - 1: m = minf(m, d[i + w - 1] + DIAG)
			d[i] = m


## Signed distance to the coast at a world tile, in TILES (+inland / -offshore).
## Returns -999 well beyond the authored bounds. Bilinear over the SDF.
func _land_signed_tiles(tx: float, ty: float) -> float:
	var u := (tx - _mask_min_tx) / _mask_tile_w
	var v := (ty - _mask_min_ty) / _mask_tile_h
	if u < -0.02 or u > 1.02 or v < -0.02 or v > 1.02:
		return -999.0
	var fx := clampf(u, 0.0, 1.0) * float(_mask_w - 1)
	var fy := clampf(v, 0.0, 1.0) * float(_mask_h - 1)
	var x0 := floori(fx)
	var y0 := floori(fy)
	var x1 := mini(x0 + 1, _mask_w - 1)
	var y1 := mini(y0 + 1, _mask_h - 1)
	var tfx := fx - float(x0)
	var tfy := fy - float(y0)
	var s00 := _land_sdf[y0 * _mask_w + x0]
	var s10 := _land_sdf[y0 * _mask_w + x1]
	var s01 := _land_sdf[y1 * _mask_w + x0]
	var s11 := _land_sdf[y1 * _mask_w + x1]
	var s := lerpf(lerpf(s00, s10, tfx), lerpf(s01, s11, tfx), tfy)
	return s * _tiles_per_mask_px


static func _load_png_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


## 0..1 strength of the forced-land guarantee at a tile: 1 in a region/corridor
## core, fading to 0 over a margin so the coastline stays organic just beyond it.
func _land_guarantee01(tx: float, ty: float) -> float:
	if _land_discs.is_empty() and _land_corridors.is_empty():
		return 0.0
	var p := Vector2(tx, ty)
	var best := 0.0
	for disc: Dictionary in _land_discs:
		var r: float = disc["r"]
		best = maxf(best, 1.0 - smoothstep(r * 0.70, r, p.distance_to(disc["c"])))
	for cor: Dictionary in _land_corridors:
		var r: float = cor["r"]
		best = maxf(best, 1.0 - smoothstep(r * 0.60, r, _dist_to_segment(p, cor["a"], cor["b"])))
	return best


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Compass direction from the continent centre as a unit-ish bias, plus a region
## blend value. Returns {n, e, d, region}: n>0 = north, e>0 = east, d = radial
## distance, region = low-freq noise [0,1] for organic biome-band boundaries.
func geo(tx: float, ty: float) -> Dictionary:
	# Warp the direction so geographic biome bands have wiggly, organic borders
	# instead of clean pie slices.
	var wx := _domain_warp.get_noise_2d(tx * 0.0030, ty * 0.0030) * 130.0
	var wy := _domain_warp.get_noise_2d(tx * 0.0030 + 40.0, ty * 0.0030 + 40.0) * 130.0
	var dx := (tx + wx) - _center.x
	var dy := (ty + wy) - _center.y
	var len := maxf(sqrt(dx * dx + dy * dy), 0.001)
	return {
		"n": -dy / len,                                        # north component (+up)
		"e": dx / len,                                         # east component (+right)
		"d": norm_dist(tx, ty),
		"region": _region.get_noise_2d(tx, ty) * 0.5 + 0.5,
	}




# Orography delegated to MountainField (mountain_field.gd).
func elevation_steps(tx: float, ty: float) -> int:
	return _mtn.elevation_steps(tx, ty)


func mountain_level(tx: float, ty: float) -> int:
	return _mtn.mountain_level(tx, ty)


func snow01(tx: float, ty: float, e: int) -> float:
	return _mtn.snow01(tx, ty, e)


func classify_fields(tx: float, ty: float) -> Vector3:
	var h := _height_macro.get_noise_2d(tx, ty) * 0.5 + 0.5
	var m := _moist_macro.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t_local := _temp.get_noise_2d(tx * 0.08, ty * 0.08) * 0.5 + 0.5
	var t_region := climate_region(tx, ty)
	var t := _temperature_for_tile(t_local, t_region)
	var dist_chunks := Vector2(tx, ty).length() / float(WG.CHUNK_TILES)
	if dist_chunks < SPAWN_SHAPE_CHUNKS:
		var s := 1.0 - smoothstep(0.0, SPAWN_SHAPE_CHUNKS, dist_chunks)
		h = lerpf(h, clampf(h, 0.46, 0.62), s)
		m = lerpf(m, clampf(m, 0.30, 0.50), s)
		t = lerpf(t, clampf(t, 0.38, 0.58), s)
	h = _apply_continent(tx, ty, h)
	return Vector3(h, m, t)


static func _temperature_for_tile(t_local: float, t_region: float) -> float:
	if t_region >= 0.36 and t_region <= 0.64:
		return clampf(lerpf(t_region, t_local, 0.22), 0.34, 0.66)
	if t_region < 0.36:
		var cold_blend := smoothstep(0.36, 0.20, t_region)
		var blended := lerpf(t_local, t_region, cold_blend * 0.82 + 0.18)
		return lerpf(clampf(lerpf(t_region, t_local, 0.22), 0.34, 0.66), blended, cold_blend)
	var hot_blend := smoothstep(0.64, 0.80, t_region)
	var blended_hot := lerpf(t_local, t_region, hot_blend * 0.82 + 0.18)
	return lerpf(clampf(lerpf(t_region, t_local, 0.22), 0.34, 0.66), blended_hot, hot_blend)


func biome_idx(tx: float, ty: float) -> int:
	return map_gen.effective_idx_at(tx, ty)


func parent_biome_idx(tx: float, ty: float) -> int:
	return map_gen.parent_idx_at(tx, ty)


func biome_idx_jittered(tx: float, ty: float, _jitter: float) -> int:
	return map_gen.effective_idx_at(tx, ty)


func climate_region(tx: float, ty: float) -> float:
	return _climate.get_noise_2d(tx, ty) * 0.5 + 0.5


func continent_kind(tx: float, ty: float) -> String:
	var climate := climate_region(tx, ty)
	var land := _land_continents.get_noise_2d(tx, ty) * 0.5 + 0.5
	if climate < 0.34:
		return "cold"
	if climate > 0.66:
		return "arid" if land > 0.50 else "humid_hot"
	return "temperate"


func volcanic_region_ok(tx: float, ty: float, f: Vector3) -> bool:
	# A volcanic massif is elevated RIFT terrain — not climate-gated. The old gate also
	# required a hot temperature (f.z >= 0.78), which never co-occurs with the NE-corner
	# (cold-north) placement, so volcanic terrain never generated. A volcano makes its own
	# heat; geography + the rift noise decide where it sits.
	if f.x < 0.40:
		return false
	var rift := _volcanic_rift.get_noise_2d(tx, ty) * 0.5 + 0.5
	return rift >= 0.42




# Hydrology: the authored river/lake mask DRIVES all inland water when present
# (procedural rivers/lakes are bypassed); otherwise delegate to HydrologyField.
func river_at(tx: float, ty: float, h: float) -> int:
	if _has_river_mask:
		return 2 if mask_is_water(tx, ty) else 0
	return _hydro.river_at(tx, ty, h)


func lake_at(tx: float, ty: float, h: float, parent_id: String = "") -> int:
	if _has_river_mask:
		return 0   # lakes are part of the river mask, resolved by river_at
	return _hydro.lake_at(tx, ty, h, parent_id)


func _touches_water_tile(tx: float, ty: float) -> bool:
	if _has_river_mask:
		return mask_is_water(tx + 1.0, ty) or mask_is_water(tx - 1.0, ty) \
			or mask_is_water(tx, ty + 1.0) or mask_is_water(tx, ty - 1.0)
	return _hydro._touches_water_tile(tx, ty)


func _near_surface_water(tx: float, ty: float, h: float) -> bool:
	if _has_river_mask:
		return _touches_water_tile(tx, ty)
	return _hydro._near_surface_water(tx, ty, h)


func tile_at(tx: float, ty: float, f: Vector3, b_idx: int, chunk: RefCounted = null, lx: int = -1, ly: int = -1) -> int:
	var h := f.x
	var biome_id := str(reg.biomes[b_idx]["id"])
	var parent_id: String = reg.parent_biome_id(b_idx)
	if biome_id == "ocean":
		return _t_deep if h < 0.24 else _t_water
	match lake_at(tx, ty, h, parent_id):
		2: return _t_water
		1: return _t_shallow
	match river_at(tx, ty, h):
		2: return _t_water
		1: return _t_shallow
	# Occasional shallow puddles in swamp (never in dry biomes).
	if parent_id == "swamp" or biome_id == "marsh_pool":
		if _near_surface_water(tx, ty, h) and WG.r01(world_seed, floori(tx), floori(ty), 9) < 0.08:
			return _t_shallow
	# One-tile sand beach ring on walkable land directly touching water.
	if parent_id in ["forest", "plains", "swamp", "rocky_hills", "savanna", "jungle", "boreal_forest", "badlands", "alpine"] and _touches_water_tile(tx, ty):
		return _t_sand
	return _pick_biome_surface(b_idx, tx, ty)


func _pick_biome_surface(b_idx: int, tx: float, ty: float) -> int:
	var weights: Array = reg.biomes[b_idx]["_tile_weights"]
	if weights.is_empty():
		return _t_sand
	if weights.size() == 1:
		return int(weights[0][0])
	var detail := _surface_detail.get_noise_2d(tx, ty) * 0.5 + 0.5
	var primary: int = int(weights[0][0])
	var secondary: int = int(weights[1][0]) if weights.size() > 1 else primary
	var biome_id: String = str(reg.biomes[b_idx]["id"])
	match biome_id:
		"desert", "beach", "savanna", "badlands":
			return secondary if detail > 0.62 else primary
		"forest", "plains", "swamp", "tundra", "rocky_hills", "volcanic", "jungle", "boreal_forest", "alpine", "wheatfield":
			return secondary if detail > 0.56 else primary
		"dense_forest", "bamboo_thicket", "grove", "heather_moor", "savanna_scrub":
			return secondary if detail > 0.54 else primary
		_:
			return primary


func _pick_weighted_tiles(weights: Array, roll: float) -> int:
	if weights.is_empty():
		return _t_sand
	var total := 0.0
	for entry: Array in weights:
		total += float(entry[1])
	var target := roll * total
	for entry: Array in weights:
		target -= float(entry[1])
		if target <= 0.0:
			return int(entry[0])
	return int(weights.back()[0])
