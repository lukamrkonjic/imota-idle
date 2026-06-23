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
var road_tiles: Dictionary = {}       # Vector2i -> tile id
var road_elev: Dictionary = {}        # Vector2i -> int : a slope-limited ramp so the road climbs
                                      # hills as a WALKABLE grade (A Short Hike) instead of stepping
var structures: Dictionary = {}       # "cx:cy"  -> Array[part dict]  (roadside decor)

# Max elevation change per centerline sample (~1 tile). The world's climb step is 1, so a road
# graded to this stays walkable end-to-end even where it cuts across steeper terrain.
const MAX_GRADE := 1.0

var _reg: RefCounted
var _seed: int
var _styles: Dictionary = {}
var _kind_to_style: Dictionary = {}
var _elev_at: Callable                 # optional elev(gx, gy) -> int sampler; enables road grading


## Compile every authored road in the spec. Pass an elev(gx,gy)->int sampler to grade roads
## up hills (a slope-limited walkable ramp); omit it to keep the legacy flat-following behaviour.
func build(p_reg: RefCounted, p_seed: int, p_elev := Callable()) -> void:
	build_roads(p_reg, p_seed, p_reg.spec.roads, p_elev)


## Compile an explicit road list (the editor uses this for a live preview before
## the roads are committed to the spec).
func build_roads(p_reg: RefCounted, p_seed: int, roads: Array, p_elev := Callable()) -> void:
	_reg = p_reg
	_seed = p_seed
	_elev_at = p_elev
	road_tiles.clear()
	road_elev.clear()
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
	if bool(st.get("fence", false)):
		# A fence follows the DRAWN curve (no straightening like a bridge) and paints no tiles — it
		# drops connected post+rail segments that sit on the terrain, so it climbs hills naturally.
		_emit_fence(center)
		return
	if bool(st.get("deck", false)):
		# A bridge is a STRAIGHT floating span from the first authored point to the last — it
		# doesn't wind. Replace the smoothed curve with a straight, per-tile-sampled line so the
		# deck goes cleanly A->B (the renderer also tilts it to one ramp between the endpoints).
		center = _straight_line(center[0], center[center.size() - 1])
	var core := _tile(str(st.get("core", "dirt")), "dirt")
	var base_w := float(st.get("width", 2.0))
	# An explicit per-road width (the editor's width slider, in tiles/diameter) takes over the
	# style default so the drawn road is exactly as thick as chosen; else use the style width.
	var road_w := float(road.get("width", 0))
	if road_w > 0.0:
		base_w = road_w * 0.5
	var jitter := float(st.get("jitter", 0.6))
	var feather := float(st.get("feather", 1.3))

	var arcs := PackedFloat32Array()
	var acc := 0.0
	for i: int in center.size():
		if i > 0:
			acc += center[i].distance_to(center[i - 1])
		arcs.append(acc)

	# A "deck" road (bridge) paints NO ground tiles — the water/river/terrain underneath stays
	# visible and the deck mesh floats over it. A normal road stamps its body into the tiles.
	var is_deck := bool(st.get("deck", false))
	if not is_deck:
		for i: int in center.size():
			var w := maxf(0.6, base_w + jitter * _wnoise(arcs[i]))
			_stamp_point(center[i], w, feather, core)
		# Grade the road into a smooth, walkable climb (beveled into the terrain) where a sampler is given.
		if _elev_at.is_valid():
			_bevel_road_elev(center, arcs, base_w, jitter, _grade_profile(center))

	if is_deck:
		_emit_bridge(center, base_w)
	else:
		_emit_decor(center, base_w, float(st.get("decor", 0.0)))


# A straight, per-tile-sampled line from a to b (for bridges, which don't wind).
func _straight_line(a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	var steps := maxi(1, int(ceil(a.distance_to(b))))
	for i: int in steps + 1:
		out.append(a.lerp(b, float(i) / float(steps)))
	return out


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


# Beveled road elevation: each tile takes the graded bed height of its NEAREST centerline point
# (no sawtooth from overlapping stamps), held flat across the road, then ramped back up to the
# surrounding terrain over a few shoulder tiles — so a road cut into a slope reads as a smooth
# carved channel instead of a 1-tile wall of jagged spikes.
const BEVEL := 3.0     # shoulder tiles over which the cut/fill blends back to terrain

func _bevel_road_elev(center: Array, arcs: PackedFloat32Array, base_w: float, jitter: float, prof: PackedInt32Array) -> void:
	var bed_dist: Dictionary = {}    # Vector2i -> nearest centerline distance
	var bed_elev: Dictionary = {}    # Vector2i -> bed elevation of that nearest point
	var bed_w: Dictionary = {}       # Vector2i -> that point's half-width (bevel start)
	for i: int in center.size():
		var w := maxf(0.6, base_w + jitter * _wnoise(arcs[i]))
		var cx := int(round(center[i].x))
		var cy := int(round(center[i].y))
		var rr := int(ceil(w + BEVEL + 1.0))
		for dy: int in range(-rr, rr + 1):
			for dx: int in range(-rr, rr + 1):
				var d := sqrt(float(dx * dx + dy * dy))
				if d > w + BEVEL:
					continue
				var key := Vector2i(cx + dx, cy + dy)
				if not bed_dist.has(key) or d < float(bed_dist[key]):
					bed_dist[key] = d
					bed_elev[key] = prof[i]
					bed_w[key] = w
	for key: Vector2i in bed_dist:
		var d: float = bed_dist[key]
		var w: float = bed_w[key]
		var bedh := float(int(bed_elev[key]))
		if d <= w:
			road_elev[key] = int(round(bedh))
		else:
			var t := clampf((d - w) / BEVEL, 0.0, 1.0)
			var terr := float(int(_elev_at.call(key.x, key.y)))
			road_elev[key] = int(round(lerpf(bedh, terr, t)))


## Slope-limited elevation profile along the centerline: sample the terrain, smooth it, then cap
## the change per sample to MAX_GRADE so the road becomes a gentle WALKABLE ramp — it follows the
## land where it's gentle and cuts a graded path where the land is steeper than the climb step.
func _grade_profile(center: Array) -> PackedInt32Array:
	var n := center.size()
	var raw: Array = []
	for i: int in n:
		raw.append(float(int(_elev_at.call(int(round(center[i].x)), int(round(center[i].y))))))
	# moving average (window ±3) flattens single-tile bumps under the road
	var avg: Array = raw.duplicate()
	for i: int in n:
		var s := 0.0
		var c := 0
		for k: int in range(maxi(0, i - 3), mini(n, i + 4)):
			s += raw[k]
			c += 1
		avg[i] = s / float(c)
	# relax toward a <=MAX_GRADE-per-step ramp (forward + backward passes)
	for _p: int in 4:
		for i: int in range(1, n):
			avg[i] = clampf(avg[i], avg[i - 1] - MAX_GRADE, avg[i - 1] + MAX_GRADE)
		for i: int in range(n - 2, -1, -1):
			avg[i] = clampf(avg[i], avg[i + 1] - MAX_GRADE, avg[i + 1] + MAX_GRADE)
	var out := PackedInt32Array()
	for i: int in n:
		out.append(int(round(avg[i])))
	return out


# --- plank bridge structures (the "bridge" style, core=plank_floor) -----------

func _emit_bridge(center: Array, _hw: float) -> void:
	# One ORIENTED deck segment per bridge tile (yaw along the path -> a clean boardwalk ribbon,
	# the mesh provides the deck width), plus support pillars at the edges every few tiles. The
	# narrow plank_floor strip painted underneath stays walkable.
	var n := center.size()
	# The span's two SOLID-GROUND ends. The renderer lerps each segment's height between the
	# terrain heights here, so the deck stays LEVEL and floats over the water/gap (instead of
	# sagging tile-by-tile into the water bed or staircasing down a canyon). A small lift keeps
	# the boards just clear of that line. Smooth (linear) -> no notches, traversable.
	var a: Vector2 = center[0]
	var b: Vector2 = center[n - 1]
	var h := 0.05
	for i: int in n:
		var c: Vector2 = center[i]
		var fwd: Vector2 = center[mini(i + 1, n - 1)] - center[maxi(i - 1, 0)]
		var yaw := atan2(fwd.x, fwd.y) if fwd.length() > 0.01 else 0.0
		var t := float(i) / float(maxi(1, n - 1))
		var span := {"ax": a.x, "ay": a.y, "bx": b.x, "by": b.y, "t": t}
		var key := Vector2i(int(round(c.x)), int(round(c.y)))
		# ONE deck segment per sample point at its exact gx/gy — NO tile dedup. Dedup left holes
		# on diagonals (two samples round to one tile, or to tiles sqrt(2)~1.41 apart while the
		# deck is only 1.35 long). At ~1u spacing the 1.35u decks overlap into a seamless ribbon.
		var part := {"kind": "bridge", "yaw": yaw, "gx": c.x, "gy": c.y, "h": h}
		part.merge(span)
		_add_struct(key.x, key.y, part)
		# support pillars just off each deck edge, every few tiles (they hang from the deck line)
		if i % 4 == 0 and fwd.length() > 0.01:
			var perp := Vector2(-fwd.y, fwd.x).normalized()
			for side: float in [-1.0, 1.0]:
				var pp := c + perp * side * 0.85
				var ppart := {"kind": "bridge_pole", "gx": pp.x, "gy": pp.y, "h": h}
				ppart.merge(span)
				_add_struct(int(round(pp.x)), int(round(pp.y)), ppart)


# --- draggable fence (the "fence" style) --------------------------------------

const FENCE_SPACING := 2.0     # tiles between posts; the rail mesh spans exactly one gap

func _emit_fence(center: Array) -> void:
	# Resample the drawn curve to EVENLY spaced posts so the fence reads as a clean post-and-rail
	# run (not a dense pile of overlapping rails). Each segment is a post + a rail reaching to the
	# next post (yaw aligned along the run); the final post carries no forward rail. Each sits on
	# the terrain (placed at ground height), so the run steps up and down hills with the land.
	var pts := _resample_even(center, FENCE_SPACING)
	var n := pts.size()
	for i: int in n:
		var c: Vector2 = pts[i]
		var fwd: Vector2 = (pts[i + 1] - c) if i < n - 1 else (c - pts[i - 1])
		var yaw := atan2(fwd.x, fwd.y) if fwd.length() > 0.01 else 0.0
		var kind := "fence" if i < n - 1 else "fence_post"   # last post has no rail to connect forward
		_add_struct(int(round(c.x)), int(round(c.y)), {"kind": kind, "yaw": yaw, "gx": c.x, "gy": c.y})


## Walk a polyline and emit a point every `step` of arc length (even spacing), always keeping the
## final endpoint so the run reaches where it was drawn.
func _resample_even(pts: Array, step: float) -> Array:
	if pts.size() < 2:
		return pts
	var out: Array = [pts[0]]
	var acc := 0.0
	for i: int in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		var dir := (b - a) / seg
		var d := step - acc
		while d <= seg:
			out.append(a + dir * d)
			d += step
		acc = seg - (d - step)
	var last: Vector2 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(last) > step * 0.4:
		out.append(last)
	return out


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
