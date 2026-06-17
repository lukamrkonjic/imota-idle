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
var _region: FastNoiseLite       # blends geographic biome-region boundaries
var _mtn_range: FastNoiseLite    # where mountain RANGES sit (large blobs)
var _mtn_ridge: FastNoiseLite    # the ridgelines within a range (ridged)
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
var _radius := 512.0          # tiles from centre to the rim

# --- continent landmass shape (RuneScape-style irregular coast) ---------------
# The continent is deliberately NOT a radial blob. A low-frequency, heavily
# domain-warped landmass field carves big peninsulas, gulfs and inlets; a ridged
# detail field adds fjord-fingers and coves; an offshore field scatters islands
# in the shallow sea just past the coast. A gentle radial term keeps the
# inhabited core solid and fades land toward the rim, and authored regions get an
# explicit land guarantee (plus connecting corridors) so content never drowns and
# the mainland stays one walkable body. Tune these to reshape every world:
const _SHORE_R := 0.80          # norm_dist at the nominal coastline
const _FALL_SLOPE := 0.80       # gentle => low-freq noise carves deep gulfs/capes
const _SEA_LEVEL := 0.435       # landmass threshold; lower => more solid dominant landmass
const _ASPECT := 1.5            # continent ~1.5:1 wider than tall (per spec)
const _COAST_BAND := 0.12       # landmass span of the beach/shallow transition
const _ISLAND_REACH := 0.34     # how far offshore (landmass units) islands form
const _ISLAND_LIFT := 0.50      # how strongly an island peak rises from the sea
const _GUARANTEE_LAND := 0.20   # solid-land value forced under authored content
var _land_discs: Array = []     # [{c:Vector2, r:float}] forced-land discs (tiles)
var _land_corridors: Array = [] # [{a,b:Vector2, r:float}] connecting land bridges

# --- tectonic mountain ranges (connected dividing spines) ---------------------
# Mountains are NOT blob noise. A handful of seed-derived spine polylines sweep
# wiggly chords across the continent (like fault lines); mountain mass rises near
# a spine and falls off with distance, textured by ridged noise. Low spots along
# a spine become PASSES (walkable gaps), and land-guarantee corridors carve the
# ranges so the mainland stays connected. Result: ranges that wall off regions
# and force travel through passes, instead of random isolated peaks.
var _mtn_spines: Array = []     # [PackedVector2Array of tile points]
var _mtn_crest := 8.0           # tiles: half-width of the high crest band
var _mtn_width := 40.0          # tiles: foothill reach from the spine line


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
	_region = _noise(p_seed + 1407, 0.0030, 2)
	_mtn_range = _noise(p_seed + 1511, 0.0050, 2)
	_mtn_ridge = _noise(p_seed + 1607, 0.0190, 3)
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
	_build_land_guarantees()
	_build_mountain_spines()


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


## Seed-derived tectonic spines: wiggly chords sweeping across the continent.
## Each becomes a mountain range; mountain_field() raises terrain near these lines.
func _build_mountain_spines() -> void:
	_mtn_spines.clear()
	if not _finite:
		return
	_mtn_crest = maxf(5.0, _radius * 0.022)
	_mtn_width = maxf(24.0, _radius * 0.11)
	var n_spines: int = 3 + (WG.hash_i(world_seed, 7001) % 3)   # 3..5 ranges
	for i: int in n_spines:
		var a0: float = WG.r01(world_seed, i, 7100) * TAU
		# End roughly opposite so the range crosses the landmass, with spread.
		var a1: float = a0 + PI + (WG.r01(world_seed, i, 7101) - 0.5) * 1.6
		var r0: float = _radius * lerpf(0.55, 1.05, WG.r01(world_seed, i, 7102))
		var r1: float = _radius * lerpf(0.55, 1.05, WG.r01(world_seed, i, 7103))
		var p0: Vector2 = _center + Vector2(cos(a0), sin(a0)) * r0
		var p1: Vector2 = _center + Vector2(cos(a1), sin(a1)) * r1
		var dir: Vector2 = (p1 - p0).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var amp: float = _radius * lerpf(0.14, 0.30, WG.r01(world_seed, i, 7104))
		var segs: int = 8 + (WG.hash_i(world_seed, i, 7105) % 4)   # 8..11
		var pts: PackedVector2Array = PackedVector2Array()
		var bmin := Vector2(1.0e9, 1.0e9)
		var bmax := Vector2(-1.0e9, -1.0e9)
		for s: int in segs + 1:
			var f: float = float(s) / float(segs)
			var base: Vector2 = p0.lerp(p1, f)
			# Perpendicular wander, max at the middle, 0 at the ends (endpoints anchor).
			var wob: float = _mtn_range.get_noise_2d(base.x * 0.6 + float(i) * 97.0, base.y * 0.6)
			base += perp * amp * sin(f * PI) * wob
			pts.append(base)
			bmin = bmin.min(base)
			bmax = bmax.max(base)
		_mtn_spines.append({"pts": pts, "bmin": bmin, "bmax": bmax})


## Nearest mountain spine to a tile: {d: distance in tiles, near: closest point}.
## Spines whose bounds are far from the tile are skipped, so off-range tiles are
## cheap (most of the map is nowhere near a range).
func _spine_proximity(tx: float, ty: float) -> Dictionary:
	var p := Vector2(tx, ty)
	var best := 1.0e9
	var near := p
	for spine: Dictionary in _mtn_spines:
		var bmin: Vector2 = spine["bmin"]
		var bmax: Vector2 = spine["bmax"]
		if tx < bmin.x - _mtn_width or tx > bmax.x + _mtn_width \
				or ty < bmin.y - _mtn_width or ty > bmax.y + _mtn_width:
			continue
		var pts: PackedVector2Array = spine["pts"]
		for s: int in pts.size() - 1:
			var a: Vector2 = pts[s]
			var ab: Vector2 = pts[s + 1] - a
			var l2: float = ab.length_squared()
			var t: float = 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var q: Vector2 = a + ab * t
			var d: float = p.distance_to(q)
			if d < best:
				best = d
				near = q
	return {"d": best, "near": near}


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
	var t := latitude_climate(tx, ty)
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
	# Elliptical falloff: the continent is ~1.5:1 wider than tall, so the vertical
	# axis hits the rim sooner — more open ocean to the north and south.
	var dx := (tx + wx) - _center.x
	var dy := ((ty + wy) - _center.y) * _ASPECT
	return clampf(sqrt(dx * dx + dy * dy) / maxf(_radius * 0.92, 1.0), 0.0, 1.6)


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
	var wx := _domain_warp.get_noise_2d(tx * 0.0016, ty * 0.0016) * 430.0
	var wy := _domain_warp.get_noise_2d(tx * 0.0016 + 131.0, ty * 0.0016 + 57.0) * 430.0
	var sx := tx + wx
	var sy := ty + wy
	var base := _continent.get_noise_2d(sx, sy) * 0.5 + 0.5          # 0..1 big blobs
	var detail := 1.0 - absf(_coast_detail.get_noise_2d(sx, sy))     # 0..1 ridged fingers
	var shape := base * 0.80 + detail * 0.20
	# Radial term: strongly positive in the core, ~0 at the shore radius, negative
	# past it (uses the warped norm_dist so the falloff is itself irregular).
	var d := norm_dist(tx, ty)
	var fall := (d - _SHORE_R) * _FALL_SLOPE
	# Solid dominant interior: a core plateau keeps the inland from punching below
	# sea level (no inland sea-holes / beach speckle), fading out before the rim so
	# the coastline still wiggles into bays and peninsulas.
	var core_bonus := smoothstep(0.84, 0.24, d) * 0.30
	var lm := shape - _SEA_LEVEL - fall + core_bonus
	# Offshore archipelago: in the shallow band just past the coast, strong noise
	# peaks lift back above sea level into scattered islands of varying size.
	if lm < 0.0 and lm > -_ISLAND_REACH:
		var isl := _island.get_noise_2d(sx, sy) * 0.5 + 0.5
		var peak := smoothstep(0.66, 0.95, isl)   # only strong peaks => fewer, larger isles
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


## Continuous mountain mass 0..~1.2 (0 = no mountain here). The field is broader
## than the visible ridge crest so mountains have foothills and hidden back-side
## depth instead of a tall front face sitting beside flat walkable tiles.
func mountain_field(tx: float, ty: float) -> float:
	if not _finite or _mtn_spines.is_empty():
		return 0.0
	var dd: float = geo(tx, ty)["d"]
	if dd < 0.20:                       # keep the safe central hub flat
		return 0.0
	var shore := coast_sink(tx, ty)
	if shore > 0.88:
		return 0.0
	var prox := _spine_proximity(tx, ty)
	var dist: float = prox["d"]
	if dist > _mtn_width:               # beyond the foothills of every range
		return 0.0
	# Cross-section profile: full mass in the crest band, tapering out to foothills.
	var core := 1.0 - smoothstep(_mtn_crest, _mtn_width, dist)
	# Passes: a low-freq value sampled along the spine dips here and there; where
	# it's low the range drops to a walkable saddle so regions aren't fully sealed.
	var near: Vector2 = prox["near"]
	var pv := _mtn_range.get_noise_2d(near.x * 0.9 + 311.0, near.y * 0.9 - 211.0) * 0.5 + 0.5
	var pass_h := smoothstep(0.30, 0.50, pv)
	# Ridge texture + macro variation for crests, shoulders and saddles.
	var ridged := 1.0 - absf(_mtn_ridge.get_noise_2d(tx, ty))
	var ridge := smoothstep(0.38, 0.92, ridged)
	var macro := _height_macro.get_noise_2d(tx * 0.7, ty * 0.7) * 0.5 + 0.5
	var mass := core * pass_h * (0.30 + ridge * 0.55 + macro * 0.15)
	# Fade mountain MASS into lowland/water by the broad continental height, so a
	# range always slopes DOWN to any shore — ocean OR inland lake — over several
	# tiles. Because elevation is derived straight from this (no value-scaling
	# taper), the steps decrease cleanly 30->27->...->0 instead of a 30->0 wall.
	# Steep where the lowland band is narrow, gradual where it's wide; always
	# terraced, never a single cliff into the water.
	var bh := _apply_continent(tx, ty, _height_macro.get_noise_2d(tx, ty) * 0.5 + 0.5)
	mass *= smoothstep(0.36, 0.60, bh)
	# Carve ranges out of authored land (hub, region cores, connecting corridors)
	# so settlements stay flat and the mainland stays one walkable body.
	mass *= 1.0 - _land_guarantee01(tx, ty) * 0.85
	return clampf(mass, 0.0, 1.20)


## Discrete terrain elevation in steps (0 = flat lowland). The mountains ARE this
## terraced height — no sprites — so peaks tower well over the player while the
## ground climbs gradually to them. Aligned to the mountain tiles (mf >= 0.70,
## all impassable) so elevation is non-zero only on rock the player cannot stand
## on; lowlands, valleys, hub and settlements stay flat (entities assume flat
## ground). Each step is drawn raised by WG.ELEV_STEP_PX with a bevel riser.
## Smoothed heightfield used by elevation_steps(). Neighbour samples give the
## ridge physical shoulders on all sides, not just a thin visible crest.
func mountain_height_field(tx: float, ty: float) -> float:
	# Smoothed with 4 neighbour samples only (was 12) — the spine field is the heavy
	# per-tile cost, sampled ~13x per elevation query, which made bakes crawl.
	var total := mountain_field(tx, ty) * 4.0
	var weight := 4.0
	for off: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		total += mountain_field(tx + off.x, ty + off.y) * 1.5
		weight += 1.5
	return clampf(total / weight, 0.0, 1.20)


const ELEV_MAX_STEPS := 52   # taller peaks (per request); slope-off comes from mass fade
const ELEV_FOOT_THRESHOLD := 0.18
const ELEV_PEAK_THRESHOLD := 0.92
const ELEV_BAND := 1
func elevation_steps(tx: float, ty: float) -> int:
	if not _finite:
		return 0
	var mh := mountain_height_field(tx, ty)
	if mh < ELEV_FOOT_THRESHOLD:
		return 0
	# Steep exponent so foothills stay low but the cold alpine ridges (high mf)
	# climb to a towering height; quantise into bands for big readable terraces.
	var shaped := smoothstep(ELEV_FOOT_THRESHOLD, ELEV_PEAK_THRESHOLD, mh)
	# Elevation is the TRUE height — never scaled by a coast taper. That value-
	# scaling was exactly what made shore tiles read 2-3 instead of 30. The slope-
	# off to water now comes from the mountain MASS fading (mountain_field), so the
	# quantised steps decrease cleanly toward the shore with correct values.
	var raw := pow(shaped, 1.18) * float(ELEV_MAX_STEPS)
	var steps := int(round(raw / float(ELEV_BAND))) * ELEV_BAND
	return clampi(steps, 0, ELEV_MAX_STEPS)


## Mountain elevation at a tile: 0 none, 1 foothill (walkable rock), 2 rock peak
## (impassable), 3 snow peak (impassable).
func mountain_level(tx: float, ty: float) -> int:
	var e := elevation_steps(tx, ty)
	if e <= 0:
		return 0
	if e > WG.MAX_REACHABLE_ELEV:
		# Snow caps on the tallest peaks anywhere (altitude makes its own cold) and
		# on every peak in cold northern climate.
		if e >= int(float(ELEV_MAX_STEPS) * 0.6) or latitude_climate(tx, ty) < 0.30:
			return 3                                                   # snow cap
		return 2                                                       # rock peak (impassable)
	return 1                                                           # foothill


func classify_fields(tx: float, ty: float) -> Vector3:
	var h := _height_macro.get_noise_2d(tx, ty) * 0.5 + 0.5
	var m := _moist_macro.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t := latitude_climate(tx, ty)
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


## Latitude-driven temperature, 0 = frozen .. 1 = scorching. This is the climate
## BACKBONE (spec): cold far north, temperate heartland, hot/arid far south. The
## north-south axis is warped by low-freq noise so the bands bulge and wave rather
## than running as straight horizontal stripes. Altitude (mountains -> colder) is
## applied by the biome picker, not here, so "altitude overrides latitude".
func latitude_climate(tx: float, ty: float) -> float:
	if not _finite:
		return 0.5
	var warp := _climate.get_noise_2d(tx, ty) * _radius * 0.20
	# rel spans roughly -1 (far north) .. +1 (far south) over the continent height
	# (height is _radius/_ASPECT because the landmass is wider than tall).
	var rel := clampf(((ty + warp) - _center.y) * _ASPECT / maxf(_radius, 1.0), -1.3, 1.3)
	var base := 0.5 + rel * 0.6
	base += _temp.get_noise_2d(tx, ty) * 0.05   # small organic jitter on the band edges
	return clampf(base, 0.0, 1.0)


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
