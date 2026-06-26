extends RefCounted
class_name MountainField
## Orography: mountains, the terraced elevation field, and the snowline — split out of
## biome_classifier (which still owns classification + hydrology). Pure functions over the
## mountain noise; geography (geo/coast_sink/_finite) comes from the classifier via `_cl`.

const WG := preload("res://scripts/worldgen/wg.gd")

var _cl
var _mtn_range: FastNoiseLite    # where mountain RANGES sit (large blobs)
var _mtn_ridge: FastNoiseLite    # the ridgelines within a range (ridged)
var _mtn_peak: FastNoiseLite     # primary ridged crests -> big peaks & valleys
var _mtn_spur: FastNoiseLite     # secondary ridged spurs off the main crests


func setup(cl, p_seed: int) -> void:
	_cl = cl
	_mtn_range = cl._noise(p_seed + 1511, 0.0072, 2)
	_mtn_ridge = cl._noise(p_seed + 1607, 0.0190, 3)
	_mtn_peak = cl._noise(p_seed + 1521, 0.0060, 1)
	_mtn_spur = cl._noise(p_seed + 1531, 0.0130, 1)


## Continuous mountain mass 0..~1.2 (0 = no mountain here). The field is broader
## than the visible ridge crest so mountains have foothills and hidden back-side
## depth instead of a tall front face sitting beside flat walkable tiles.
func mountain_field(tx: float, ty: float) -> float:
	if not _cl._finite:
		return 0.0
	var g: Dictionary = _cl.geo(tx, ty)
	var nn: float = g["n"]
	var dd: float = g["d"]
	var range_mask := _mtn_range.get_noise_2d(tx, ty) * 0.5 + 0.5     # 0..1
	if dd < 0.24:
		return 0.0
	var shore: float = _cl.coast_sink(tx, ty)
	if shore > 0.88:
		return 0.0
	# Geography only says WHERE mountains are allowed.  The local range mask
	# must still say there is an actual massif here; letting the north belt act
	# as a mountain by itself produced one continent-wide striped ramp.
	var north_belt := smoothstep(0.16, 0.42, nn) \
		* smoothstep(0.28, 0.46, dd) \
		* (1.0 - smoothstep(0.86, 1.06, dd))
	var local_mass := smoothstep(0.43, 0.72, range_mask)
	var spine := smoothstep(0.62, 0.84, range_mask) \
		* smoothstep(0.30, 0.48, dd) \
		* (1.0 - smoothstep(0.90, 1.08, dd))
	var gate: float = clampf(maxf(north_belt * local_mass, spine), 0.0, 1.0)
	if gate <= 0.01:
		return 0.0
	# Keep ridge detail subordinate to the big mass. Strong ridge noise at this
	# stage makes every contour inherit the same long, parallel wiggle.
	var r1 := 1.0 - absf(_mtn_peak.get_noise_2d(tx, ty))
	var r2 := 1.0 - absf(_mtn_spur.get_noise_2d(tx, ty))
	var ridged := (r1 * r1) * 0.82 + (r2 * r2) * 0.18                 # 0 valley .. 1 crest
	# A broad DOME (range_mask, raised to a power to concentrate height) gives each range one
	# dominant summit and gentle foothills; the ridged crests are carved INTO that dome so the
	# flanks break into ridgelines and recessed valleys instead of a uniform ridge net or a
	# smooth wall. Summit = dome high AND on a crest; valleys = troughs on the dome flanks.
	var dome := pow(smoothstep(0.40, 0.94, range_mask), 1.42)
	# The dome owns the silhouette and guarantees one legible high point. Ridges
	# only carve broad shoulders/valleys into it; they no longer redraw every
	# elevation boundary as a parallel contour.
	var carved := dome * (0.82 + 0.18 * ridged)
	const FOOT_BASE := 0.10
	var mass := gate * (FOOT_BASE + (1.0 - FOOT_BASE) * carved)
	mass *= 1.0 - smoothstep(0.18, 0.76, shore)
	return clampf(mass, 0.0, 1.30)


## Discrete terrain elevation in steps (0 = flat lowland). The mountains ARE this
## terraced height — no sprites — so peaks tower well over the player while the
## ground climbs gradually to them. Aligned to the mountain tiles (mf >= 0.70,
## all impassable) so elevation is non-zero only on rock the player cannot stand
## on; lowlands, valleys, hub and settlements stay flat (entities assume flat
## ground). Each step is drawn raised by WG.ELEV_STEP_PX with a bevel riser.
## Smoothed heightfield used by elevation_steps(). Neighbour samples give the
## ridge physical shoulders on all sides, not just a thin visible crest.
func mountain_height_field(tx: float, ty: float) -> float:
	# A broad isotropic low-pass removes grid teeth before quantisation.  Sampling
	# a balanced 5x5-ish kernel is important: cardinal-only rings preserve axis
	# aligned staircases, while this kernel produces calm rounded silhouettes.
	var total := mountain_field(tx, ty) * 5.0
	var weight := 5.0
	for off: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		total += mountain_field(tx + off.x, ty + off.y) * 1.5
		weight += 1.5
	for off: Vector2 in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2)]:
		total += mountain_field(tx + off.x, ty + off.y) * 1.25
		weight += 1.25
	for off: Vector2 in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
		total += mountain_field(tx + off.x, ty + off.y) * 0.65
		weight += 0.65
	for off: Vector2 in [Vector2(5, 5), Vector2(-5, 5), Vector2(5, -5), Vector2(-5, -5)]:
		total += mountain_field(tx + off.x, ty + off.y) * 0.4
		weight += 0.4
	return clampf(total / weight, 0.0, 1.20)


const ELEV_MAX_STEPS := 128      # summit height in steps (×ELEV_H 0.25 = 32 world units) — tall, dramatic peaks.
                                 # KEEP IN SYNC: BiomeClassifier._ELEV_MAX, TerrainStyle.ALPINE_SUMMIT.
const ELEV_FOOT_THRESHOLD := 0.18
const ELEV_PEAK_THRESHOLD := 0.96
func elevation_steps(tx: float, ty: float) -> int:
	if not _cl._finite:
		return 0
	# Authored elevation mask wins (drives terraces, mountains, snow) when present.
	if _cl.has_elev_mask():
		return _cl.mask_elev_steps(tx, ty)
	var mh := mountain_height_field(tx, ty)
	if mh < ELEV_FOOT_THRESHOLD:
		return 0
	# Smooth normalised height up the massif (0 at the foot, 1 at the summit).
	var shaped := smoothstep(ELEV_FOOT_THRESHOLD, ELEV_PEAK_THRESHOLD, mh)
	# Slope down toward the sea using the SMOOTH coastline so coastal mountains taper
	# to the beach instead of dropping a wall into the surf.
	shaped *= 1.0 - smoothstep(0.10, 0.70, _cl.coast_sink(tx, ty))
	# Keep the main slope continuous. Two LOCAL shelf masks flatten selected
	# shoulders into scenic ledges; because each mask fades in world space, neither
	# shelf completes a ring around the summit. The remaining sides stay grassy
	# slopes or recessed valleys instead of becoming stacked contour bands.
	var shelf_field := _mtn_spur.get_noise_2d(tx * 0.72 + 31.0, ty * 0.72 - 19.0) * 0.5 + 0.5
	var continuous := shaped
	shaped = _localized_shelf(shaped, 0.34, shelf_field, 0.56)
	shaped = _localized_shelf(shaped, 0.63, 1.0 - shelf_field, 0.61)
	# The painted hiking trail is also a physical ramp: restore the continuous
	# pre-shelf slope along it so shelf cliffs never seal off the upper mountain.
	shaped = lerpf(shaped, continuous, alpine_trail01(tx, ty, shaped) * 0.92)
	return clampi(int(round(clampf(shaped, 0.0, 1.0) * float(ELEV_MAX_STEPS))), 0, ELEV_MAX_STEPS)


## Flatten a short segment of one shoulder without creating a closed elevation
## ring. `mask` is broad spatial noise; thresholding it leaves deliberate shelf
## patches separated by uninterrupted slope and valley faces.
static func _localized_shelf(height01: float, level: float, mask: float, threshold: float) -> float:
	var spatial := smoothstep(threshold, threshold + 0.20, mask)
	var near_level := 1.0 - smoothstep(0.055, 0.15, absf(height01 - level))
	var flattened := level + (height01 - level) * 0.16
	return lerpf(height01, flattened, spatial * near_level * 0.88)


## Shared traversal language: one sparse meandering route on lower/mid slopes.
## Renderer uses the same equation for its ochre trail material.
static func alpine_trail01(tx: float, ty: float, height01: float) -> float:
	var wave := sin((tx + ty) * 0.020 + sin(tx * 0.011 - 0.6) * 1.4)
	# Fade in above the foot; stay active nearly to the summit so the trail is a continuous
	# gentle ramp all the way to the top (it only eases off on the final crown).
	return (1.0 - smoothstep(0.025, 0.105, absf(wave))) \
		* smoothstep(0.10, 0.22, height01) * (1.0 - smoothstep(0.93, 1.0, height01))


const SNOW_BLEND_STEPS := 7.0
## Snow coverage 0..1 at a mountain tile, from LATITUDE (north = colder) and ELEVATION.
## Northern mountains gain snow well down their flanks; southern peaks must be very tall
## to cap at all — so the snowline visibly communicates the world's climate gradient.
func snow01(tx: float, ty: float, e: int) -> float:
	if e <= 0:
		return 0.0
	var g: Dictionary = _cl.geo(tx, ty)
	var north := clampf(float(g["n"]) * 0.5 + 0.5, 0.0, 1.0)   # 0 due-south .. 1 due-north
	# Snowline (in steps): high up on southern slopes, dropping toward the far north.
	# Even the cold north keeps snow on the summit crown rather than painting
	# every upper shoulder white; exposed cliff and alpine grass remain visible.
	var snowline := lerpf(0.96, 0.64, north) * float(ELEV_MAX_STEPS)
	return clampf((float(e) - snowline) / SNOW_BLEND_STEPS, 0.0, 1.0)


## Mountain elevation at a tile: 0 none, 1 foothill (walkable rock), 2 rock peak
## (impassable), 3 snow peak (impassable, snow-capped).
func mountain_level(tx: float, ty: float) -> int:
	var e := elevation_steps(tx, ty)
	if e <= 0:
		return 0
	if e > WG.MAX_REACHABLE_ELEV:
		return 3 if snow01(tx, ty, e) >= 0.5 else 2
	return 1                                                           # foothill
