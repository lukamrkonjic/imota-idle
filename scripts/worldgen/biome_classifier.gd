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
var _river: FastNoiseLite
var _river_mask: FastNoiseLite
var _lake: FastNoiseLite
var _dune: FastNoiseLite
var _volcanic_rift: FastNoiseLite
var _domain_warp: FastNoiseLite
var _surface_detail: FastNoiseLite
var _coast: FastNoiseLite        # low-freq mask that wobbles the coastline (bays/capes)
var _region: FastNoiseLite       # blends geographic biome-region boundaries
var _mtn_range: FastNoiseLite    # where mountain RANGES sit (large blobs)
var _mtn_ridge: FastNoiseLite    # the ridgelines within a range (ridged)

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
var _radius := 512.0          # tiles from centre to the rim


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
		_radius = float(mini(b.size.x, b.size.y)) * WG.CHUNK_TILES * 0.5
	_coast = _noise(p_seed + 1303, 0.0042, 3)
	_region = _noise(p_seed + 1407, 0.0030, 2)
	_mtn_range = _noise(p_seed + 1511, 0.0050, 2)
	_mtn_ridge = _noise(p_seed + 1607, 0.0190, 3)
	_height = _noise(p_seed, 0.011, 4)
	_height_macro = _noise(p_seed + 11, 0.0026, 3)
	_moist = _noise(p_seed + 101, 0.016, 3)
	_moist_macro = _noise(p_seed + 111, 0.0020, 2)
	_temp = _noise(p_seed + 202, 0.006, 2)
	_climate = _noise(p_seed + 505, 0.0016, 2)
	_land_continents = _noise(p_seed + 909, 0.00038, 2)
	_river = _noise(p_seed + 303, 0.0050, 1)
	_river_mask = _noise(p_seed + 304, 0.0028, 2)
	_lake = _noise(p_seed + 404, 0.021, 2)
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
	return clampf(Vector2(tx + wx, ty + wy).distance_to(_center) / maxf(_radius * 0.92, 1.0), 0.0, 1.6)


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
	var d := norm_dist(tx, ty)
	var coast := _coast.get_noise_2d(tx, ty) * 0.5 + 0.5      # 0..1
	var edge := 0.62 + coast * 0.46                            # land ends ~0.62..1.08 of radius
	return h - smoothstep(edge, edge + 0.22, d) * 0.75


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


## Mountain elevation at a tile: 0 none, 1 foothill (walkable rock), 2 rock peak
## (impassable), 3 snow peak (impassable). Ranges sit in a northern highland belt
## plus occasional spines; ridged noise carves ridgelines with gaps (passes), so
## a cluster reads as a range with valleys and walkable passes between peaks.
## Continuous mountain elevation 0..~1.2 (0 = no mountain here). The ridged noise
## carves ridgelines; gated to the northern highland belt or a range spine. Used
## both to classify tiles and to find ridge crests for placing massif art.
func mountain_field(tx: float, ty: float) -> float:
	if not _finite:
		return 0.0
	var g: Dictionary = geo(tx, ty)
	var nn: float = g["n"]
	var dd: float = g["d"]
	var range_mask := _mtn_range.get_noise_2d(tx, ty) * 0.5 + 0.5     # 0..1
	# Mountains belong to the northern highlands, or wherever a strong range
	# spine pushes through; never in the safe central hub or out at sea.
	var north_belt := nn > 0.22 and dd > 0.32 and dd < 0.88
	var spine := range_mask > 0.74
	if not (north_belt or spine) or dd < 0.26:
		return 0.0
	var ridged := 1.0 - absf(_mtn_ridge.get_noise_2d(tx, ty))          # ~0..1, peaks ~1
	return ridged * (0.62 + range_mask * 0.6)


## Discrete terrain elevation in steps (0 = flat lowland). The mountains ARE this
## terraced height — no sprites — so peaks tower well over the player while the
## ground climbs gradually to them. Aligned to the mountain tiles (mf >= 0.70,
## all impassable) so elevation is non-zero only on rock the player cannot stand
## on; lowlands, valleys, hub and settlements stay flat (entities assume flat
## ground). Each step is drawn raised by WG.ELEV_STEP_PX with a bevel riser.
const ELEV_MAX_STEPS := 80
const ELEV_BAND := 4        # snap heights to bands so terraces are wide (walkable)
                            # and cliff faces are tall and continuous, not 1-tile
                            # staircases
func elevation_steps(tx: float, ty: float) -> int:
	if not _finite:
		return 0
	var mf := mountain_field(tx, ty)
	if mf < 0.70:
		return 0
	# Steep exponent so foothills stay low but the cold alpine ridges (high mf)
	# climb to a towering height; quantise into bands for big readable terraces.
	var raw := pow((mf - 0.70) / 0.54, 1.35) * float(ELEV_MAX_STEPS)
	# Slope down toward the sea: fade elevation as the land height approaches sea
	# level so coastal mountains taper to the shore instead of dropping as a sheer
	# cliff into the water (also smooths the rim where mountains meet lowland).
	var land_h := _apply_continent(tx, ty, _height.get_noise_2d(tx, ty) * 0.5 + 0.5)
	raw *= smoothstep(0.30, 0.54, land_h)
	return int(round(raw / float(ELEV_BAND))) * ELEV_BAND


## Mountain elevation at a tile: 0 none, 1 foothill (walkable rock), 2 rock peak
## (impassable), 3 snow peak (impassable).
func mountain_level(tx: float, ty: float) -> int:
	var v := mountain_field(tx, ty)
	if v < 0.70:
		return 0
	var g: Dictionary = geo(tx, ty)
	if v > 0.90 and (float(g["n"]) > 0.42 or float(g["d"]) > 0.62):
		return 3                                                       # snow cap
	if v > 0.80:
		return 2                                                       # rock peak (impassable)
	return 1                                                           # foothill


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
	if f.x < 0.58 or f.z < 0.78:
		return false
	if climate_region(tx, ty) < 0.72:
		return false
	var rift := _volcanic_rift.get_noise_2d(tx, ty) * 0.5 + 0.5
	return rift >= 0.58


func river_at(tx: float, ty: float, h: float) -> int:
	if h < 0.34 or h > 0.74:
		return 0
	var mask := _river_mask.get_noise_2d(tx, ty) * 0.5 + 0.5
	if mask < 0.46:
		return 0
	var rv: float = absf(_river.get_noise_2d(tx, ty))
	var w := 0.018 + 0.030 * (1.0 - smoothstep(0.34, 0.74, h))
	if rv < w * 0.58:
		return 2
	if rv < w:
		return 1
	return 0


func lake_at(tx: float, ty: float, h: float, parent_id: String = "") -> int:
	if not parent_id.is_empty() and parent_id not in ["forest", "plains", "swamp", "oasis", "marsh_pool"]:
		return 0
	if h < 0.345 or h > 0.62:
		return 0
	var lv := _lake.get_noise_2d(tx, ty) * 0.5 + 0.5
	if lv > 0.84:
		return 2
	if lv > 0.815:
		return 1
	return 0


func _touches_water_tile(tx: float, ty: float) -> bool:
	for off: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var nx := tx + off.x
		var ny := ty + off.y
		var nf := fields(nx, ny)
		if nf.x < 0.345:
			return true
		if lake_at(nx, ny, nf.x, "") > 0:
			return true
		if river_at(nx, ny, nf.x) > 0:
			return true
	return false


func _near_surface_water(tx: float, ty: float, h: float) -> bool:
	return _touches_water_tile(tx, ty)


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
