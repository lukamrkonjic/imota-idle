extends Node
## world_trace — OFFLINE map importer. Converts the hand-drawn Aldreth outline
## (data/world/source/aldreth_atlas.png) into CLEAN, EDITABLE world masks. The
## runtime/baker never parse the illustration — only the masks this writes.
##
##   godot --headless --path . res://tools/world_trace.tscn
##   godot --headless --path . res://tools/world_trace.tscn -- --from-mask
##
## Pipeline:
##   1. classify every atlas pixel: LAND (warm cream) / OCEAN (navy) / INK
##      (near-black/gold frame, legend panel, compass, scale text)
##   2. flood the OUTER background from the borders over {OCEAN ∪ INK} — this
##      strips the frame, legend, compass and scale-bar (all connected to the
##      open sea) in one pass; OCEAN pixels NOT reached are enclosed = rivers/lakes
##   3. remove compact INK panels (legend / scale bar) by bbox; keep the frame
##   4. despeckle by connected-component AREA — drop text/icon specks, KEEP real
##      coastal islands; fill pinhole sea holes; preserve the fractal coast (no
##      morphological rounding into blobs)
##   5. crop to the playable field and emit:
##        data/world/masks/aldreth_land.png    (binary land/water — EDIT THIS)
##        data/world/masks/aldreth_rivers.png  (river/lake layer, for roads/rivers)
##        data/world/masks/aldreth_trace_preview.png  (review overlay — APPROVE THIS)
##        data/world/masks/aldreth_mask.json   (mask↔world mapping + recommended bounds)
##
## --from-mask re-emits the preview + meta from a hand-edited aldreth_land.png
## (manual-correction step) without re-tracing the illustration.

const SRC_DIR := "res://data/world/source/"
const OUT_DIR := "res://data/world/masks/"
const INDEX := "res://data/world/worldspec/index.json"
# Per-world paths, resolved in _ready from --world=<id> (else worldspec/index active, else aldreth).
var _id := "aldreth"
var _src := ""
var _land_png := ""
var _rivers_png := ""
var _preview_png := ""
var _meta_json := ""

# Pixel classification (tuned for the cream-on-navy refined outline; adjust here
# and re-run if the preview shows misreads — that's the whole point of the preview).
const LAND_MIN_LUMA := 150.0     # cream land is bright
const OCEAN_MAX_LUMA := 135.0    # navy sea is dark
const OCEAN_BLUE_BIAS := 8.0     # ocean: B clearly above R
const GOLD_R_MIN := 150.0        # frame/compass gold: warm but B-poor
const GOLD_B_MAX := 120.0
const INK_MAX_LUMA := 60.0       # frame/legend backing: near-black

# Cleanup thresholds expressed as a FRACTION of total pixels, so they scale with
# whatever resolution the atlas is supplied at.
const MIN_ISLAND_FRAC := 0.000018   # land components below this are specks (text/icons) -> removed
const MIN_RIVER_FRAC := 0.000010    # enclosed-sea components below this -> filled back to land
const LEGEND_MIN_FRAC := 0.004      # compact INK panels above this -> nuked by bbox (legend/scale)
const FRAME_BBOX_FRAC := 0.55       # an INK component whose bbox spans >this of W AND H is the frame -> kept

# Decoration the flood/despeckle can't catch: the legend TITLE + compass + scale
# bar are cream/gold marks sitting in the open-sea corners (the legend panel is the
# same navy as the ocean, so there's no ink block to strip, and the big title
# letters survive the speck filter). These normalized rects are forced to sea.
# They sit over water on this map; widen/trim here if a future map differs.
const IGNORE_ZONES: Array[Rect2] = [
	Rect2(0.0, 0.0, 0.185, 0.255),     # top-left: ALDRETH title + subtitle + compass
	Rect2(0.0, 0.975, 0.185, 0.025),   # bottom-left: scale bar
]

# Coordinate frame: world bounds derive from the playable-area aspect, centred on
# the origin (chunk 0,0 ~ map centre), height fixed so bake cost stays ~current.
const CHUNK_TILES := 16
const TARGET_CHUNK_HEIGHT := 90

var _w := 0
var _h := 0


func _ready() -> void:
	if _has_autoload("SaveManager"): SaveManager.suppress = true
	if _has_autoload("GameSettings"): GameSettings.suppress = true

	_id = _resolve_world_id()
	_src = SRC_DIR + _id + "_atlas.png"
	_land_png = OUT_DIR + _id + "_land.png"
	_rivers_png = OUT_DIR + _id + "_rivers.png"
	_preview_png = OUT_DIR + _id + "_trace_preview.png"
	_meta_json = OUT_DIR + _id + "_mask.json"
	print("world_trace: importing world '%s' from %s" % [_id, _src])

	var from_mask := OS.get_cmdline_user_args().has("--from-mask")
	var t0 := Time.get_ticks_msec()

	if from_mask:
		_rebuild_from_mask(t0)
		return

	var img := _load_png(_src)
	if img == null:
		push_error("world_trace: missing source atlas at %s — add the illustrated map there first." % _src)
		get_tree().quit(1)
		return
	img.convert(Image.FORMAT_RGB8)
	_w = img.get_width()
	_h = img.get_height()
	var total := _w * _h

	# 1. classify -------------------------------------------------------------
	var cls := _classify(img)   # 0=ocean, 1=land, 2=ink

	# 2. flood outer background over {ocean ∪ ink} from the image border -------
	var bg := _flood_background(cls)

	# land = cream and NOT outer background; river = navy and NOT outer background
	var land := PackedByteArray(); land.resize(total)
	var river := PackedByteArray(); river.resize(total)
	for i: int in total:
		if bg[i] == 1:
			continue
		if cls[i] == 1:
			land[i] = 1
		elif cls[i] == 0:
			river[i] = 1   # enclosed navy = inland water

	# 3. nuke compact INK panels (legend / scale bar); keep the frame ----------
	_remove_ink_panels(cls, land, river, int(round(total * LEGEND_MIN_FRAC)))

	# 4. despeckle (keep islands, fill pinholes — no coastline smoothing) ------
	var min_island := maxi(20, int(round(total * MIN_ISLAND_FRAC)))
	var min_river := maxi(12, int(round(total * MIN_RIVER_FRAC)))
	var removed_specks := _despeckle(land, min_island)        # drop tiny land artifacts
	var filled := _despeckle_into(river, land, min_river)     # tiny enclosed sea -> land
	var zoned := _apply_ignore_zones(land, river)             # force decoration corners to sea

	# 5. crop to the playable field + emit ------------------------------------
	var play := _play_rect(land, river, cls)
	var land_img := _crop_binary(land, play, Color8(232, 226, 208), Color8(20, 38, 64))
	var river_img := _crop_binary(river, play, Color.WHITE, Color.BLACK)
	var preview := _build_preview(land, river, cls, bg, play)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	land_img.save_png(_land_png)
	river_img.save_png(_rivers_png)
	preview.save_png(_preview_png)
	var meta := _write_meta(play)

	var land_px := _count(land)
	print(JSON.stringify({
		"tool": "world_trace",
		"atlas_px": [_w, _h],
		"play_rect": [play.position.x, play.position.y, play.size.x, play.size.y],
		"mask_px": [play.size.x, play.size.y],
		"land_pixels": land_px,
		"land_fraction": float(land_px) / float(total),
		"specks_removed": removed_specks,
		"sea_holes_filled": filled,
		"decoration_cleared": zoned,
		"recommended_bounds": meta["recommendedBounds"],
		"outputs": [_land_png, _rivers_png, _preview_png, _meta_json],
		"took_s": float(Time.get_ticks_msec() - t0) / 1000.0,
	}, "\t"))
	print("\nReview %s — if the trace looks right, the land mask is ready for the bake." % ProjectSettings.globalize_path(_preview_png))
	get_tree().quit(0)


# --- classification -----------------------------------------------------------

func _classify(img: Image) -> PackedByteArray:
	var cls := PackedByteArray(); cls.resize(_w * _h)
	for y: int in _h:
		for x: int in _w:
			var c := img.get_pixel(x, y)
			var r := c.r * 255.0
			var g := c.g * 255.0
			var b := c.b * 255.0
			var luma := 0.299 * r + 0.587 * g + 0.114 * b
			var kind := 2   # default INK / decoration
			if r > GOLD_R_MIN and b < GOLD_B_MAX and r > b + 30.0:
				kind = 2     # gold frame / compass / scale ticks
			elif luma < INK_MAX_LUMA and b <= r + OCEAN_BLUE_BIAS:
				kind = 2     # near-black frame / legend backing (non-blue dark)
			elif luma <= OCEAN_MAX_LUMA and b > r + OCEAN_BLUE_BIAS:
				kind = 0     # navy ocean
			elif luma >= LAND_MIN_LUMA:
				kind = 1     # cream land
			else:
				# ambiguous mid-tone: lean by blueness
				kind = 0 if b > r + OCEAN_BLUE_BIAS else 1
			cls[y * _w + x] = kind
	return cls


# Flood from every border pixel that is NOT land, spreading through ocean AND ink
# (8-connected). Everything reached is the outer sea + connected decoration.
func _flood_background(cls: PackedByteArray) -> PackedByteArray:
	var bg := PackedByteArray(); bg.resize(_w * _h)
	var stack := PackedInt32Array()
	for x: int in _w:
		_seed_bg(cls, bg, stack, x, 0)
		_seed_bg(cls, bg, stack, x, _h - 1)
	for y: int in _h:
		_seed_bg(cls, bg, stack, 0, y)
		_seed_bg(cls, bg, stack, _w - 1, y)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var x := i % _w
		var y := i / _w
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
					continue
				var ni := ny * _w + nx
				if bg[ni] == 1 or cls[ni] == 1:
					continue
				bg[ni] = 1
				stack.push_back(ni)
	return bg


func _seed_bg(cls: PackedByteArray, bg: PackedByteArray, stack: PackedInt32Array, x: int, y: int) -> void:
	var i := y * _w + x
	if cls[i] != 1 and bg[i] == 0:
		bg[i] = 1
		stack.push_back(i)


# --- decoration & despeckle ---------------------------------------------------

## Label INK connected components; any COMPACT panel (legend, scale bar) above
## min_area has its (padded) bbox cleared of land/river. The big frame component
## (bbox spans most of the image) is left alone.
func _remove_ink_panels(cls: PackedByteArray, land: PackedByteArray, river: PackedByteArray, min_area: int) -> void:
	var seen := PackedByteArray(); seen.resize(_w * _h)
	for start: int in _w * _h:
		if cls[start] != 2 or seen[start] == 1:
			continue
		var comp := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var x0 := _w; var y0 := _h; var x1 := 0; var y1 := 0
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			comp.push_back(i)
			var x := i % _w; var y := i / _w
			x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
			for d: int in [-1, 1]:
				_push_ink(cls, seen, stack, i + d, x + d, y)
				_push_ink(cls, seen, stack, i + d * _w, x, y + d)
		if comp.size() < min_area:
			continue
		var bw := float(x1 - x0 + 1) / float(_w)
		var bh := float(y1 - y0 + 1) / float(_h)
		if bw > FRAME_BBOX_FRAC and bh > FRAME_BBOX_FRAC:
			continue   # the decorative frame — keep it, don't nuke the whole map
		# compact panel: clear a padded bbox
		var pad := 6
		for yy: int in range(maxi(0, y0 - pad), mini(_h, y1 + pad + 1)):
			for xx: int in range(maxi(0, x0 - pad), mini(_w, x1 + pad + 1)):
				var k := yy * _w + xx
				land[k] = 0
				river[k] = 0


func _push_ink(cls: PackedByteArray, seen: PackedByteArray, stack: PackedInt32Array, i: int, nx: int, ny: int) -> void:
	if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
		return
	if cls[i] == 2 and seen[i] == 0:
		seen[i] = 1
		stack.push_back(i)


## Remove connected components of `mask` (value 1) smaller than min_area. Returns
## the number of components removed. 4-connected (coastlines stay crisp).
func _despeckle(mask: PackedByteArray, min_area: int) -> int:
	var removed := 0
	var seen := PackedByteArray(); seen.resize(mask.size())
	for start: int in mask.size():
		if mask[start] != 1 or seen[start] == 1:
			continue
		var comp := _component(mask, seen, start)
		if comp.size() < min_area:
			for i: int in comp:
				mask[i] = 0
			removed += 1
	return removed


## Like _despeckle, but small components of `mask` are MOVED into `into` (used to
## fill tiny enclosed-sea specks back to land). Returns components moved.
func _despeckle_into(mask: PackedByteArray, into: PackedByteArray, min_area: int) -> int:
	var moved := 0
	var seen := PackedByteArray(); seen.resize(mask.size())
	for start: int in mask.size():
		if mask[start] != 1 or seen[start] == 1:
			continue
		var comp := _component(mask, seen, start)
		if comp.size() < min_area:
			for i: int in comp:
				mask[i] = 0
				into[i] = 1
			moved += 1
	return moved


## Force the configured normalized decoration rects to sea. Returns pixels cleared.
func _apply_ignore_zones(land: PackedByteArray, river: PackedByteArray) -> int:
	var cleared := 0
	for z: Rect2 in IGNORE_ZONES:
		var x0 := int(floor(z.position.x * _w))
		var y0 := int(floor(z.position.y * _h))
		var x1 := int(ceil((z.position.x + z.size.x) * _w))
		var y1 := int(ceil((z.position.y + z.size.y) * _h))
		for y: int in range(maxi(0, y0), mini(_h, y1)):
			for x: int in range(maxi(0, x0), mini(_w, x1)):
				var i := y * _w + x
				if land[i] == 1 or river[i] == 1:
					cleared += 1
				land[i] = 0
				river[i] = 0
	return cleared


func _component(mask: PackedByteArray, seen: PackedByteArray, start: int) -> PackedInt32Array:
	var comp := PackedInt32Array()
	var stack := PackedInt32Array([start])
	seen[start] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		comp.push_back(i)
		var x := i % _w; var y := i / _w
		if x > 0 and mask[i - 1] == 1 and seen[i - 1] == 0: seen[i - 1] = 1; stack.push_back(i - 1)
		if x < _w - 1 and mask[i + 1] == 1 and seen[i + 1] == 0: seen[i + 1] = 1; stack.push_back(i + 1)
		if y > 0 and mask[i - _w] == 1 and seen[i - _w] == 0: seen[i - _w] = 1; stack.push_back(i - _w)
		if y < _h - 1 and mask[i + _w] == 1 and seen[i + _w] == 0: seen[i + _w] = 1; stack.push_back(i + _w)
	return comp


# --- crop, preview, meta ------------------------------------------------------

## Playable field = bbox of all land ∪ river ∪ ocean (everything inside the
## frame). Ink frame is excluded.
func _play_rect(land: PackedByteArray, river: PackedByteArray, cls: PackedByteArray) -> Rect2i:
	var x0 := _w; var y0 := _h; var x1 := -1; var y1 := -1
	for y: int in _h:
		for x: int in _w:
			var i := y * _w + x
			if land[i] == 1 or river[i] == 1 or cls[i] == 0:
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < x0:
		return Rect2i(0, 0, _w, _h)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _crop_binary(mask: PackedByteArray, play: Rect2i, on: Color, off: Color) -> Image:
	var img := Image.create_empty(play.size.x, play.size.y, false, Image.FORMAT_RGB8)
	for y: int in play.size.y:
		for x: int in play.size.x:
			var i := (play.position.y + y) * _w + (play.position.x + x)
			img.set_pixel(x, y, on if mask[i] == 1 else off)
	return img


func _build_preview(land: PackedByteArray, river: PackedByteArray, cls: PackedByteArray, bg: PackedByteArray, play: Rect2i) -> Image:
	# land=cream, sea=navy, river=cyan, REMOVED decoration (ink not in frame, or
	# specks) tinted magenta so you can see exactly what the importer stripped.
	var img := Image.create_empty(play.size.x, play.size.y, false, Image.FORMAT_RGB8)
	for y: int in play.size.y:
		for x: int in play.size.x:
			var i := (play.position.y + y) * _w + (play.position.x + x)
			var col := Color8(20, 38, 64)            # sea
			if land[i] == 1:
				col = Color8(232, 226, 208)          # land
			elif river[i] == 1:
				col = Color8(70, 170, 200)           # inland water
			elif cls[i] == 2 and bg[i] == 0:
				col = Color8(190, 40, 150)           # stripped decoration (enclosed ink)
			img.set_pixel(x, y, col)
	return img


func _write_meta(play: Rect2i) -> Dictionary:
	var aspect := float(play.size.x) / float(play.size.y)
	var hc := TARGET_CHUNK_HEIGHT
	var wc := int(round(float(hc) * aspect))
	var cx0 := -(wc / 2)
	var cy0 := -(hc / 2)
	var meta := {
		"_doc": "Generated by tools/world_trace.gd. Maps the land/river masks to world chunk-space. The land mask is the editable source of the coastline; edit <id>_land.png and re-run with --from-mask to refresh this.",
		"world": _id,
		"source": _src.get_file(),
		"land": _land_png.get_file(),
		"rivers": _rivers_png.get_file(),
		"atlasSize": [_w, _h],
		"playRect": [play.position.x, play.position.y, play.size.x, play.size.y],
		"maskSize": [play.size.x, play.size.y],
		"recommendedBounds": {"min": [cx0, cy0], "max": [cx0 + wc - 1, cy0 + hc - 1]},
	}
	var f := FileAccess.open(_meta_json, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return meta


func _rebuild_from_mask(t0: int) -> void:
	var land_img := _load_png(_land_png)
	if land_img == null:
		push_error("world_trace --from-mask: no edited mask at %s" % _land_png)
		get_tree().quit(1)
		return
	land_img.convert(Image.FORMAT_RGB8)
	_w = land_img.get_width()
	_h = land_img.get_height()
	var land := PackedByteArray(); land.resize(_w * _h)
	for y: int in _h:
		for x: int in _w:
			# treat any bright pixel as land (white/cream), dark as sea
			land[y * _w + x] = 1 if land_img.get_pixel(x, y).get_luminance() > 0.5 else 0
	var empty := PackedByteArray(); empty.resize(_w * _h)
	var play := Rect2i(0, 0, _w, _h)
	_build_preview(land, empty, empty, empty, play).save_png(_preview_png)
	var meta := _write_meta(play)
	print(JSON.stringify({
		"tool": "world_trace --from-mask",
		"mask_px": [_w, _h],
		"land_pixels": _count(land),
		"recommended_bounds": meta["recommendedBounds"],
		"took_s": float(Time.get_ticks_msec() - t0) / 1000.0,
	}, "\t"))
	get_tree().quit(0)


# --- helpers ------------------------------------------------------------------

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


static func _count(mask: PackedByteArray) -> int:
	var n := 0
	for v: int in mask:
		if v == 1:
			n += 1
	return n


func _has_autoload(name: String) -> bool:
	return Engine.has_singleton(name) or get_node_or_null("/root/" + name) != null


## World id: --world=<id> on the command line, else worldspec/index.json `active`,
## else "aldreth". Lets the same importer trace ANY world's map.
func _resolve_world_id() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			return arg.substr("--world=".length())
	if FileAccess.file_exists(INDEX):
		var idx: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if idx is Dictionary and not str((idx as Dictionary).get("active", "")).is_empty():
			return str((idx as Dictionary)["active"])
	return "aldreth"
