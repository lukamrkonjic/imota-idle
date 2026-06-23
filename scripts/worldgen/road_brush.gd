extends RefCounted
class_name RoadBrush
## Compiles authored road polylines into terrain tile overrides with a NATURAL look:
##   • Catmull-Rom smoothing  -> coarse authored points become flowing curves
##   • variable half-width     -> the road swells / pinches along its length
##   • soft feathered rim      -> a stochastic edge that dithers into the grass
##                                (the mesher's biome-edge dither softens it more)
##   • keeps terrain elevation -> roads roll over hills instead of cutting flat
##   • roadside decor          -> sparse pebbles / tufts for the foot-worn feel
##
## Material / width / feather / decor are data-driven from data/world/road_styles.json,
## so roads are restyled by editing JSON + re-baking. A "bridge" style is just another
## entry whose `core` is the plank deck tile — you draw bridges directly wherever you
## want them (no water detection; the brush paints exactly the stroke you draw).
##
## Built single-threaded in FiniteWorldGenerator.setup() (and per-stroke in the editor);
## the per-chunk apply just reads the resulting dictionaries.

const WG := preload("res://scripts/worldgen/wg.gd")

# results — world-tile keyed (Vector2i) unless noted
var road_tiles: Dictionary = {}       # Vector2i -> tile id   (KEEPS terrain elevation)
var structures: Dictionary = {}       # "cx:cy"  -> Array[part dict]  (roadside decor)

var _reg: RefCounted
var _seed: int
var _styles: Dictionary = {}
var _kind_to_style: Dictionary = {}


## Compile every authored road in the spec.
func build(p_reg: RefCounted, p_seed: int) -> void:
	build_roads(p_reg, p_seed, p_reg.spec.roads)


## Compile an explicit road list (the editor uses this for a live preview before
## the roads are committed to the spec).
func build_roads(p_reg: RefCounted, p_seed: int, roads: Array) -> void:
	_reg = p_reg
	_seed = p_seed
	road_tiles.clear()
	structures.clear()
	_load_styles()
	for road: Dictionary in roads:
		_stamp_road(road)


# --- style table --------------------------------------------------------------

func _load_styles() -> void:
	var d := _read_json("res://data/world/road_styles.json")
	_styles = d.get("styles", {})
	_kind_to_style = d.get("kindToStyle", {})


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}


func _style_for(road: Dictionary) -> Dictionary:
	var sid := str(road.get("style", ""))
	if sid.is_empty():
		sid = str(_kind_to_style.get(str(road.get("kind", "minor")), "road"))
	return _styles.get(sid, _styles.get("road", {}))


func _tile(name: String, fallback: String) -> int:
	return int(_reg.tile_index.get(name, _reg.tile_index.get(fallback, 0)))


# --- one road -----------------------------------------------------------------

func _stamp_road(road: Dictionary) -> void:
	var center := _smooth(road.get("points", []))
	if center.size() < 2:
		return
	var st := _style_for(road)
	var core := _tile(str(st.get("core", "dirt")), "dirt")
	var base_w := float(st.get("width", 2.0))
	# An authored per-road width acts as a minimum (lets one road be wider).
	base_w = maxf(base_w, float(road.get("width", 0)) * 0.5)
	var jitter := float(st.get("jitter", 0.6))
	var feather := float(st.get("feather", 1.3))

	var arcs := PackedFloat32Array()
	var acc := 0.0
	for i: int in center.size():
		if i > 0:
			acc += center[i].distance_to(center[i - 1])
		arcs.append(acc)

	for i: int in center.size():
		var w := maxf(0.6, base_w + jitter * _wnoise(arcs[i]))
		_stamp_point(center[i], w, feather, core)

	if bool(st.get("deck", false)):
		_emit_bridge(center, base_w)
	else:
		_emit_decor(center, base_w, float(st.get("decor", 0.0)))


# --- smoothing (Catmull-Rom, ~1 sample / tile) --------------------------------

func _smooth(points: Array) -> Array:
	var pts: Array = []
	for p: Variant in points:
		pts.append(Vector2(p) if (p is Vector2i or p is Vector2) else Vector2(float(p[0]), float(p[1])))
	if pts.size() < 2:
		return pts
	var ext: Array = [pts[0]]
	ext.append_array(pts)
	ext.append(pts[pts.size() - 1])
	var out: Array = []
	for k: int in range(1, ext.size() - 2):
		var p0: Vector2 = ext[k - 1]
		var p1: Vector2 = ext[k]
		var p2: Vector2 = ext[k + 1]
		var p3: Vector2 = ext[k + 2]
		var steps := maxi(1, int(ceil(p1.distance_to(p2))))
		for j: int in steps:
			out.append(_catmull(p0, p1, p2, p3, float(j) / float(steps)))
	out.append(pts[pts.size() - 1])
	return out


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# --- variable-width stamp with feathered stochastic rim -----------------------

func _stamp_point(c: Vector2, w: float, feather: float, core: int) -> void:
	var cx := int(round(c.x))
	var cy := int(round(c.y))
	var rr := int(ceil(w + feather + 1.0))
	for dy: int in range(-rr, rr + 1):
		for dx: int in range(-rr, rr + 1):
			var tx := cx + dx
			var ty := cy + dy
			# gentle coherent wobble so the boundary scallops instead of a clean disc
			var d := sqrt(float(dx * dx + dy * dy)) + 0.6 * _ewarp(tx, ty)
			if d <= w:
				road_tiles[Vector2i(tx, ty)] = core
			elif d <= w + feather:
				if _hash01(tx, ty, 7771) < 1.0 - (d - w) / feather:
					road_tiles[Vector2i(tx, ty)] = core


# --- plank bridge structures (the "bridge" style, core=plank_floor) -----------

func _emit_bridge(center: Array, _hw: float) -> void:
	# One ORIENTED deck segment per bridge tile (yaw along the path -> a clean boardwalk ribbon,
	# the mesh provides the deck width), plus support pillars at the edges every few tiles. The
	# narrow plank_floor strip painted underneath stays walkable.
	var seen: Dictionary = {}
	var n := center.size()
	for i: int in n:
		var c: Vector2 = center[i]
		var fwd: Vector2 = center[mini(i + 1, n - 1)] - center[maxi(i - 1, 0)]
		var yaw := atan2(fwd.x, fwd.y) if fwd.length() > 0.01 else 0.0
		# raise the deck above the water with a gentle arch (highest mid-span)
		var prog := float(i) / float(maxi(1, n - 1))
		var h := 0.34 + 0.20 * sin(prog * PI)
		var key := Vector2i(int(round(c.x)), int(round(c.y)))
		if not seen.has(key):
			seen[key] = true
			# gx/gy = the exact smooth centerline so segments line up instead of staircasing
			_add_struct(key.x, key.y, {"kind": "bridge", "yaw": yaw, "gx": c.x, "gy": c.y, "h": h})
		# support pillars just off each deck edge, every few tiles
		if i % 4 == 0 and fwd.length() > 0.01:
			var perp := Vector2(-fwd.y, fwd.x).normalized()
			for side: float in [-1.0, 1.0]:
				var pp := c + perp * side * 0.85
				_add_struct(int(round(pp.x)), int(round(pp.y)), {"kind": "bridge_pole", "gx": pp.x, "gy": pp.y, "h": h})


# --- roadside decor -----------------------------------------------------------

func _emit_decor(center: Array, base_w: float, density: float) -> void:
	if density <= 0.0:
		return
	for i: int in center.size():
		if _hash01(int(round(center[i].x)), int(round(center[i].y)), 313) >= density:
			continue
		# drop just off the road edge, on the side picked by a second hash
		var c: Vector2 = center[i]
		var fwd: Vector2 = (center[mini(i + 1, center.size() - 1)] - center[maxi(i - 1, 0)])
		var perp := Vector2(-fwd.y, fwd.x).normalized() if fwd.length() > 0.01 else Vector2.RIGHT
		var side := 1.0 if _hash01(int(c.x), int(c.y), 99) < 0.5 else -1.0
		var off := base_w + 0.6 + _hash01(int(c.x), int(c.y), 71)
		var p := c + perp * side * off
		var tx := int(round(p.x))
		var ty := int(round(p.y))
		if road_tiles.has(Vector2i(tx, ty)):
			continue
		var prop := "pebble" if _hash01(tx, ty, 51) < 0.6 else "grass"
		_add_struct(tx, ty, {"kind": "decor", "prop": prop})


# --- helpers ------------------------------------------------------------------

func _add_struct(tx: int, ty: int, part: Dictionary) -> void:
	var cx := floori(float(tx) / float(WG.CHUNK_TILES))
	var cy := floori(float(ty) / float(WG.CHUNK_TILES))
	var key := "%d:%d" % [cx, cy]
	var lp := part.duplicate()
	lp["tx"] = tx - cx * WG.CHUNK_TILES
	lp["ty"] = ty - cy * WG.CHUNK_TILES
	if not structures.has(key):
		structures[key] = []
	structures[key].append(lp)


func _hash01(x: int, y: int, salt: int) -> float:
	return WG.r01(_seed, x, y, salt)


func _wnoise(s: float) -> float:
	return sin(s * 0.22) * 0.6 + sin(s * 0.07 + 1.7) * 0.4


func _ewarp(x: int, y: int) -> float:
	return (sin(x * 0.10 + y * 0.06) * 0.5
		+ sin(x * 0.05 - y * 0.13 + 2.1) * 0.3
		+ sin(x * 0.21 + y * 0.17 - 1.0) * 0.2)
