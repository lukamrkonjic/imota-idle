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
var _island: FastNoiseLite       # offshore archipelago field (scattered islands)

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
const _ISLAND_REACH := 0.50     # how far offshore (landmass units) islands form
const _ISLAND_LIFT := 0.60      # how strongly an island peak rises from the sea
const _GUARANTEE_LAND := 0.20   # solid-land value forced under authored content
var _land_discs: Array = []     # [{c:Vector2, r:float}] forced-land discs (tiles)
var _land_corridors: Array = [] # [{a,b:Vector2, r:float}] connecting land bridges


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
	_build_land_guarantees()


## Precompute the forced-land discs (every authored region + the home core) and
## the land bridges that connect each region back to the core, so the irregular
## coastline can never sever authored content from the mainland.
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
		_land_corridors.append({"a": _center, "b": c, "r": 1.4 * ct})


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
	# Heavy, low-frequency domain warp twists the coast into peninsulas and gulfs
	# rather than a clean disc.
	var wx := _domain_warp.get_noise_2d(tx * 0.0016, ty * 0.0016) * 470.0
	var wy := _domain_warp.get_noise_2d(tx * 0.0016 + 131.0, ty * 0.0016 + 57.0) * 470.0
	var sx := tx + wx
	var sy := ty + wy
	var base := _continent.get_noise_2d(sx, sy) * 0.5 + 0.5          # 0..1 big blobs
	var detail := 1.0 - absf(_coast_detail.get_noise_2d(sx, sy))     # 0..1 ridged fingers
	var shape := base * 0.80 + detail * 0.20
	# Radial term: strongly positive in the core, ~0 at the shore radius, negative
	# past it (uses the warped norm_dist so the falloff is itself irregular).
	var d := norm_dist(tx, ty)
	var fall := (d - _SHORE_R) * _FALL_SLOPE
	var lm := shape - _SEA_LEVEL - fall
	# Offshore archipelago: in the shallow band just past the coast, strong noise
	# peaks lift back above sea level into scattered islands of varying size.
	if lm < 0.0 and lm > -_ISLAND_REACH:
		var isl := _island.get_noise_2d(sx, sy) * 0.5 + 0.5
		var peak := smoothstep(0.52, 0.92, isl)   # lower gate => more islands, large and small
		lm += peak * _ISLAND_LIFT * (1.0 - (-lm) / _ISLAND_REACH)
	# Authored-content land guarantee — only ever ADDS land, blended by a soft edge
	# so the coast still wiggles naturally just outside the guaranteed zone.
	var g := _land_guarantee01(tx, ty)
	if g > 0.0:
		lm = lerpf(lm, maxf(lm, _GUARANTEE_LAND), g)
	return lm


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




# Hydrology delegated to HydrologyField (hydrology_field.gd).
func river_at(tx: float, ty: float, h: float) -> int:
	return _hydro.river_at(tx, ty, h)


func lake_at(tx: float, ty: float, h: float, parent_id: String = "") -> int:
	return _hydro.lake_at(tx, ty, h, parent_id)


func _touches_water_tile(tx: float, ty: float) -> bool:
	return _hydro._touches_water_tile(tx, ty)


func _near_surface_water(tx: float, ty: float, h: float) -> bool:
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
