extends Node
## region_preview — FAST region-placement authoring aid for Phase 2. Draws the
## authored land mask with every WorldSpec region's ellipse (centre + rx/ry +
## rotation) overlaid in its biome colour, labelled, so you can see at a glance
## whether each region sits on the right landmass. Pure data — no chunk gen.
##
##   godot --headless --path . res://tools/region_preview.tscn
## Writes res://data/world/masks/aldreth_region_preview.png

const WG := preload("res://scripts/worldgen/wg.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")

const STEP := 1            # mask px per output px
const LAND := Color8(232, 226, 208)
const SEA := Color8(20, 38, 64)
const GRID := Color8(36, 56, 86)

# Per-biome overlay colour (matches coast_preview's expanded palette).
const BIOME_COL := {
	"plains": Color8(96, 140, 64), "wheatfield": Color8(196, 168, 78),
	"flower_meadow": Color8(140, 178, 96), "forest": Color8(54, 96, 52),
	"dense_forest": Color8(32, 66, 36), "grove": Color8(96, 150, 80),
	"boreal_forest": Color8(60, 104, 92), "rocky_hills": Color8(126, 124, 120),
	"heather_moor": Color8(150, 96, 160), "tundra": Color8(210, 216, 220),
	"snowdrift": Color8(236, 240, 246), "alpine": Color8(214, 220, 230),
	"desert": Color8(214, 184, 120), "cactus_plain": Color8(196, 174, 112),
	"oasis": Color8(80, 180, 120), "salt_pan": Color8(236, 232, 222),
	"savanna": Color8(190, 168, 80), "savanna_scrub": Color8(150, 140, 80),
	"badlands": Color8(178, 104, 72), "swamp": Color8(64, 96, 66),
	"bog": Color8(84, 84, 56), "jungle": Color8(38, 110, 50),
	"volcanic": Color8(150, 56, 44), "geyser_field": Color8(150, 170, 180),
	"dead_forest": Color8(110, 100, 90), "corrupted_bog": Color8(110, 64, 120),
	"beach": Color8(214, 196, 142),
}


func _ready() -> void:
	if Engine.has_singleton("SaveManager") or get_node_or_null("/root/SaveManager"):
		SaveManager.suppress = true

	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("region_preview: active spec is not a finite world.")
		get_tree().quit(1)
		return

	var mask := _load_png(BiomeClassifier.land_mask_path(str(spec.id)))
	if mask == null:
		push_error("region_preview: no land mask — run world_trace first.")
		get_tree().quit(1)
		return
	mask.convert(Image.FORMAT_RGB8)
	var mw := mask.get_width()
	var mh := mask.get_height()

	var b: Rect2i = spec.bounds
	var out_w := mw / STEP
	var out_h := mh / STEP
	var img := Image.create_empty(out_w, out_h, false, Image.FORMAT_RGB8)

	# base: land / sea from the mask
	for py: int in out_h:
		for px: int in out_w:
			var land := mask.get_pixel(px * STEP, py * STEP).r > 0.5
			img.set_pixel(px, py, LAND if land else SEA)

	# chunk grid so coords are readable off the image (origin axes brightest)
	_draw_grid(img, b, out_w, out_h)

	# overlay each region ellipse, tinted by biome; brighter ring at the edge
	for r: Dictionary in spec.regions:
		_draw_region(img, r, b, out_w, out_h)

	# overlay authored roads (tile space) so we can see they stay on land
	for road: Dictionary in spec.roads:
		_draw_road(img, road, b, out_w, out_h)

	var out := "res://data/world/masks/" + str(spec.id) + "_region_preview.png"
	img.save_png(out)

	# Deterministic placement report: is each region's CENTRE on land? (samples the
	# mask, with a 1-chunk neighbourhood so a centre in a thin inlet still counts).
	var in_sea: Array = []
	for r: Dictionary in spec.regions:
		if not _center_on_land(mask, r, b):
			in_sea.append({"id": str(r["id"]), "at": [int(r["cx"]), int(r["cy"])],
				"nearest_land": _nearest_land_chunk(mask, r, b)})
	# Road water-crossings: how many sampled points along each road fall in sea
	# (a few = a bridge/strait; many = the road wanders off the coast — re-route it).
	var road_sea: Array = []
	for road: Dictionary in spec.roads:
		var sea := _road_sea_points(mask, road, b)
		if sea[0] > 0:
			road_sea.append({"id": str(road.get("id", "")), "sea_pts": sea[0], "total": sea[1]})
	print(JSON.stringify({
		"tool": "region_preview", "png": ProjectSettings.globalize_path(out),
		"regions": spec.regions.size(), "roads": spec.roads.size(), "px": [out_w, out_h],
		"centers_in_sea": in_sea,
		"roads_crossing_sea": road_sea,
	}, "\t"))
	get_tree().quit(0)


## [sea_point_count, total_sampled] along a road polyline against the land mask.
func _road_sea_points(mask: Image, road: Dictionary, b: Rect2i) -> Array:
	var mw := mask.get_width()
	var mh := mask.get_height()
	var pts: Array = road.get("points", [])
	var sea := 0
	var total := 0
	for i: int in range(pts.size() - 1):
		var a: Vector2i = pts[i]
		var c: Vector2i = pts[i + 1]
		var steps := maxi(1, int(Vector2(c - a).length() / 8.0))
		for s: int in range(steps + 1):
			var t := float(s) / float(steps)
			var px := int((lerpf(float(a.x), float(c.x), t) / 16.0 - float(b.position.x)) / float(b.size.x) * float(mw))
			var py := int((lerpf(float(a.y), float(c.y), t) / 16.0 - float(b.position.y)) / float(b.size.y) * float(mh))
			px = clampi(px, 0, mw - 1)
			py = clampi(py, 0, mh - 1)
			total += 1
			if mask.get_pixel(px, py).r <= 0.5:
				sea += 1
	return [sea, total]


## Spiral out from the region centre to the nearest land chunk; returns [cx,cy].
func _nearest_land_chunk(mask: Image, r: Dictionary, b: Rect2i) -> Array:
	var mw := mask.get_width()
	var mh := mask.get_height()
	var cx := int(r["cx"])
	var cy := int(r["cy"])
	for radius: int in range(1, 40):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var ccx := cx + dx
				var ccy := cy + dy
				var px := int((float(ccx) - float(b.position.x)) / float(b.size.x) * float(mw))
				var py := int((float(ccy) - float(b.position.y)) / float(b.size.y) * float(mh))
				if px < 0 or py < 0 or px >= mw or py >= mh:
					continue
				if mask.get_pixel(px, py).r > 0.5:
					return [ccx, ccy]
	return [cx, cy]


func _center_on_land(mask: Image, r: Dictionary, b: Rect2i) -> bool:
	var mw := mask.get_width()
	var mh := mask.get_height()
	var px := int((float(r["cx"]) - float(b.position.x)) / float(b.size.x) * float(mw))
	var py := int((float(r["cy"]) - float(b.position.y)) / float(b.size.y) * float(mh))
	var step := mw / b.size.x   # ~1 chunk in px
	for dy: int in [-step, 0, step]:
		for dx: int in [-step, 0, step]:
			var x := clampi(px + dx, 0, mw - 1)
			var y := clampi(py + dy, 0, mh - 1)
			if mask.get_pixel(x, y).r > 0.5:
				return true
	return false


## Draw an authored road (tile-space polyline) as a bright line on the overlay.
func _draw_road(img: Image, road: Dictionary, b: Rect2i, out_w: int, out_h: int) -> void:
	var pts: Array = road.get("points", [])
	var col := Color8(236, 206, 120) if str(road.get("kind", "")) == "major" else Color8(200, 170, 110)
	for i: int in range(pts.size() - 1):
		var a: Vector2i = pts[i]
		var c: Vector2i = pts[i + 1]
		var steps := maxi(1, int(Vector2(c - a).length() / 4.0))
		for s: int in range(steps + 1):
			var t := float(s) / float(steps)
			var tx := lerpf(float(a.x), float(c.x), t)
			var ty := lerpf(float(a.y), float(c.y), t)
			var px := int((tx / 16.0 - float(b.position.x)) / float(b.size.x) * float(out_w))
			var py := int((ty / 16.0 - float(b.position.y)) / float(b.size.y) * float(out_h))
			_dot(img, px, py, out_w, out_h, col, 1)


## Grid lines every 10 chunks; brighter every 50; brightest on the x=0 / y=0 axes.
## Blended over both land and sea so coords are readable anywhere.
func _draw_grid(img: Image, b: Rect2i, out_w: int, out_h: int) -> void:
	for cx: int in range(b.position.x, b.end.x + 1):
		if cx % 10 != 0:
			continue
		var px := int((float(cx) - float(b.position.x)) / float(b.size.x) * float(out_w))
		_grid_line(img, px, -1, out_w, out_h, _grid_col(cx))
	for cy: int in range(b.position.y, b.end.y + 1):
		if cy % 10 != 0:
			continue
		var py := int((float(cy) - float(b.position.y)) / float(b.size.y) * float(out_h))
		_grid_line(img, -1, py, out_w, out_h, _grid_col(cy))


func _grid_col(c: int) -> Color:
	if c == 0:
		return Color8(220, 150, 90)        # origin axis
	if c % 50 == 0:
		return Color8(120, 150, 200)       # every 50
	return Color8(120, 140, 170)           # every 10


func _grid_line(img: Image, fx: int, fy: int, out_w: int, out_h: int, col: Color) -> void:
	var strong := col.r > 0.8   # origin axis: draw solid
	if fx >= 0:
		for py: int in out_h:
			var base := img.get_pixel(fx, py)
			img.set_pixel(fx, py, col if strong else base.lerp(col, 0.3))
	elif fy >= 0:
		for px: int in out_w:
			var base := img.get_pixel(px, fy)
			img.set_pixel(px, fy, col if strong else base.lerp(col, 0.3))


func _draw_region(img: Image, r: Dictionary, b: Rect2i, out_w: int, out_h: int) -> void:
	var biome := str(r.get("biome", ""))
	var col: Color = BIOME_COL.get(biome, Color8(255, 0, 255))
	# region centre/extents are in CHUNK space; convert to output px via bounds.
	var cx := (float(r["cx"]) - float(b.position.x)) / float(b.size.x) * float(out_w)
	var cy := (float(r["cy"]) - float(b.position.y)) / float(b.size.y) * float(out_h)
	var sx := float(out_w) / float(b.size.x)   # px per chunk, x
	var sy := float(out_h) / float(b.size.y)
	var rx: float = maxf(float(r.get("rx", 1.0)) * sx, 1.0)
	var ry: float = maxf(float(r.get("ry", 1.0)) * sy, 1.0)
	var rot: float = float(r.get("rot", 0.0))
	var ca := cos(-rot)
	var sa := sin(-rot)
	var pad := int(ceil(maxf(rx, ry))) + 2
	for y: int in range(maxi(0, int(cy) - pad), mini(out_h, int(cy) + pad)):
		for x: int in range(maxi(0, int(cx) - pad), mini(out_w, int(cx) + pad)):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var lx := (dx * ca - dy * sa) / rx
			var ly := (dx * sa + dy * ca) / ry
			var ed := sqrt(lx * lx + ly * ly)
			if ed > 1.0:
				continue
			var base := img.get_pixel(x, y)
			# stronger tint at the rim so overlapping regions stay legible
			var t: float = lerpf(0.35, 0.7, smoothstep(0.4, 1.0, ed))
			img.set_pixel(x, y, base.lerp(col, t))
	# centre marker
	_dot(img, int(cx), int(cy), out_w, out_h, Color8(255, 255, 255))
	_dot(img, int(cx), int(cy), out_w, out_h, col, 1)


func _dot(img: Image, x: int, y: int, w: int, h: int, c: Color, r: int = 2) -> void:
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h:
				img.set_pixel(nx, ny, c)


static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img
