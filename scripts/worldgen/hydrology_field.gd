extends RefCounted
class_name HydrologyField
## Surface water: rivers, lakes, and the shore-water check — split out of biome_classifier
## (which still owns classification + climate). The 3 water-noise fields live here; geography
## (fields) comes from the classifier via `_cl`.

const WG := preload("res://scripts/worldgen/wg.gd")

var _cl
var _river: FastNoiseLite
var _river_mask: FastNoiseLite
var _lake: FastNoiseLite


func setup(cl, p_seed: int) -> void:
	_cl = cl
	_river = cl._noise(p_seed + 303, 0.0050, 1)
	_river_mask = cl._noise(p_seed + 304, 0.0028, 2)
	_lake = cl._noise(p_seed + 404, 0.021, 2)


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
	# Lakes occupy broad local basins. Noise alone used to stamp pale aqua onto
	# hillsides and mountain feet, producing water-shaped decals on dry land.
	if _basin_depth(tx, ty, h) < 0.012:
		return 0
	var lv := _lake.get_noise_2d(tx, ty) * 0.5 + 0.5
	if lv > 0.84:
		return 2
	if lv > 0.815:
		return 1
	return 0


func _basin_depth(tx: float, ty: float, h: float) -> float:
	var rim := 0.0
	for off: Vector2 in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12),
			Vector2(8, 8), Vector2(-8, 8), Vector2(8, -8), Vector2(-8, -8)]:
		rim += _cl.fields(tx + off.x, ty + off.y).x
	return rim / 8.0 - h


func _touches_water_tile(tx: float, ty: float) -> bool:
	for off: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var nx := tx + off.x
		var ny := ty + off.y
		var nf: Vector3 = _cl.fields(nx, ny)
		if nf.x < 0.345:
			return true
		if lake_at(nx, ny, nf.x, "") > 0:
			return true
		if river_at(nx, ny, nf.x) > 0:
			return true
	return false


func _near_surface_water(tx: float, ty: float, h: float) -> bool:
	return _touches_water_tile(tx, ty)
