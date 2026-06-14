extends RefCounted
class_name NatureDecorHelpers

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func leaf_dark() -> Color:
	return PixelPalette.pal("grass_c").lerp(PixelPalette.pal("grass_a"), 0.18)


static func leaf_mid() -> Color:
	return PixelPalette.pal("grass_a")


static func leaf_hi() -> Color:
	return PixelPalette.pal("grass_b").lerp(PixelPalette.pal("grass_a"), 0.25)


static func leaf_blue() -> Color:
	return Color8(34, 132, 112)


static func leaf_yellow() -> Color:
	return Color8(218, 196, 50)


static func leaf_autumn() -> Color:
	return Color8(207, 140, 42)


static func bark_dark() -> Color:
	return Color8(82, 55, 35)


static func bark_mid() -> Color:
	return Color8(126, 82, 43)


static func bark_hi() -> Color:
	return Color8(178, 126, 66)


static func stone_dark() -> Color:
	return Color8(92, 98, 94)


static func stone_mid() -> Color:
	return Color8(135, 143, 136)


static func stone_hi() -> Color:
	return Color8(185, 194, 184)


static func sand_dark() -> Color:
	return Color8(139, 118, 70)


static func sand_mid() -> Color:
	return Color8(202, 181, 102)


static func _tinted(color: Color, tint: Color) -> Color:
	if tint.a <= 0.0:
		return color
	return color.lerp(Color(tint.r, tint.g, tint.b, 1.0), clampf(tint.a, 0.0, 0.70))


static func r(canvas: CanvasItem, x: float, y: float, w: float, h: float, color: Color, alpha: float, tint: Color) -> void:
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, x * px, y * px, w * px, h * px, _tinted(color, tint), alpha)


static func shadow(canvas: CanvasItem, w: float, alpha: float, tint: Color) -> void:
	r(canvas, -w * 0.5, -1.0, w, 2.0, Color8(14, 22, 18), alpha, tint)


## An isometric solid block in decor art-pixel space (coords ×PX), tint-aware.
## Use this for man-made wooden/stone clutter so it reads as real volume like the
## world structures, rather than a flat billboard.
static func iso(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, base: Color, tint: Color) -> void:
	var px := float(PixelPalette.PX)
	PixelDraw.iso_block_tex(canvas, cx * px, cy * px, hw * px, hh * px, h * px, _tinted(base, tint))


static func blob(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, alpha: float, tint: Color) -> void:
	var iy0 := int(floor(-ry))
	var iy1 := int(ceil(ry))
	for iy: int in range(iy0, iy1 + 1):
		var n := absf(float(iy)) / maxf(ry, 0.001)
		var half := floor(rx * sqrt(maxf(0.0, 1.0 - n * n)))
		if half >= 0.0:
			r(canvas, cx - half, cy + float(iy), half * 2.0 + 1.0, 1.0, color, alpha, tint)


static func blob_patch(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, alpha: float, tint: Color) -> void:
	blob(canvas, cx, cy, rx + 1.0, ry + 1.0, leaf_dark(), minf(alpha, 0.70), tint)
	blob(canvas, cx, cy, rx, ry, color, alpha, tint)
	blob(canvas, cx - rx * 0.25, cy - ry * 0.25, rx * 0.45, ry * 0.35, leaf_hi(), minf(alpha, 0.60), tint)


static func trunk(canvas: CanvasItem, x: float, top_y: float, bottom_y: float, width: float, tint: Color) -> void:
	var h := bottom_y - top_y
	r(canvas, x - width * 0.5, top_y, width, h, bark_dark(), 0.95, tint)
	if width > 2.0:
		r(canvas, x - width * 0.5 + 1.0, top_y + 1.0, maxf(1.0, width - 2.0), h - 1.0, bark_mid(), 0.88, tint)
		r(canvas, x + width * 0.5 - 1.0, top_y + 2.0, 1.0, maxf(1.0, h - 4.0), bark_hi(), 0.45, tint)
	for i: int in range(2):
		var yy := top_y + 4.0 + float(i) * 5.0
		if yy < bottom_y - 2.0:
			r(canvas, x - width * 0.5, yy, 1.0, 2.0, bark_dark().lerp(Color.BLACK, 0.20), 0.45, tint)


static func root_feet(canvas: CanvasItem, x: float, y: float, spread: float, tint: Color) -> void:
	r(canvas, x - spread, y - 1.0, spread, 1.0, bark_dark(), 0.75, tint)
	r(canvas, x + 1.0, y - 1.0, spread, 1.0, bark_dark(), 0.75, tint)
	r(canvas, x - 1.0, y - 2.0, 2.0, 2.0, bark_mid(), 0.85, tint)


static func branch(canvas: CanvasItem, x: float, y: float, length: float, side: int, tint: Color) -> void:
	var s := float(side)
	for i: int in range(int(length)):
		r(canvas, x + s * float(i), y - float(i) * 0.45, 1.0, 1.0, bark_mid(), 0.72, tint)


static func broadleaf_tree(canvas: CanvasItem, variant: int, trunk_h: float, rx: float, ry: float, color_mode: int, tint: Color) -> void:
	shadow(canvas, rx * 1.8, 0.18, tint)
	var bend := float((variant % 3) - 1)
	trunk(canvas, bend, -trunk_h, 0.0, 6.0 + float(variant % 2), tint)
	root_feet(canvas, bend, 0.0, 4.0, tint)
	branch(canvas, bend - 1.0, -trunk_h + 8.0, 6.0, -1, tint)
	branch(canvas, bend + 1.0, -trunk_h + 6.0, 5.0, 1, tint)
	var mid := leaf_mid()
	var hi := leaf_hi()
	if color_mode == 1:
		mid = leaf_yellow()
		hi = Color8(244, 224, 78)
	elif color_mode == 2:
		mid = leaf_autumn()
		hi = Color8(239, 184, 67)
	elif color_mode == 3:
		mid = leaf_blue()
		hi = Color8(83, 178, 148)
	blob(canvas, bend, -trunk_h - ry * 0.28, rx + 2.0, ry + 1.0, leaf_dark(), 0.70, tint)
	blob(canvas, bend - rx * 0.38, -trunk_h - ry * 0.30, rx * 0.65, ry * 0.68, mid, 0.92, tint)
	blob(canvas, bend + rx * 0.32, -trunk_h - ry * 0.28, rx * 0.68, ry * 0.72, mid, 0.88, tint)
	blob(canvas, bend, -trunk_h - ry * 0.62, rx * 0.62, ry * 0.62, mid, 0.90, tint)
	blob(canvas, bend - rx * 0.35, -trunk_h - ry * 0.55, rx * 0.28, ry * 0.25, hi, 0.62, tint)
	blob(canvas, bend + rx * 0.18, -trunk_h - ry * 0.82, rx * 0.26, ry * 0.20, hi, 0.50, tint)
	if color_mode == 4:
		for i: int in range(6):
			var sx := -rx * 0.55 + float((i * 5 + variant * 3) % int(rx * 1.1))
			var sy := -trunk_h - ry * 0.75 + float((i * 7 + variant) % int(ry))
			r(canvas, sx, sy, 2.0, 2.0, Color8(199, 48, 42), 0.90, tint)


static func dense_bush(canvas: CanvasItem, variant: int, rx: float, ry: float, fruit: Color, tint: Color) -> void:
	shadow(canvas, rx * 1.8, 0.12, tint)
	blob(canvas, 0.0, -ry * 0.65, rx + 1.0, ry + 1.0, leaf_dark(), 0.72, tint)
	blob(canvas, -rx * 0.28, -ry * 0.72, rx * 0.55, ry * 0.55, leaf_mid(), 0.92, tint)
	blob(canvas, rx * 0.30, -ry * 0.62, rx * 0.55, ry * 0.55, leaf_mid(), 0.86, tint)
	blob(canvas, 0.0, -ry * 0.95, rx * 0.52, ry * 0.45, leaf_hi(), 0.50, tint)
	if fruit.a > 0.0:
		for i: int in range(7):
			var sx := -rx * 0.65 + float((i * 5 + variant * 4) % int(maxf(1.0, rx * 1.25)))
			var sy := -ry * 1.05 + float((i * 7 + variant * 2) % int(maxf(1.0, ry * 0.85)))
			r(canvas, sx, sy, 2.0, 2.0, fruit, 0.92, tint)


static func conifer_tree(canvas: CanvasItem, variant: int, height: float, width: float, levels: int, tint: Color) -> void:
	shadow(canvas, width * 0.78, 0.15, tint)
	trunk(canvas, 0.0, -height * 0.35, 0.0, 5.0, tint)
	var dark := leaf_dark().lerp(Color8(0, 65, 70), 0.45)
	var mid := Color8(24, 112, 96)
	var hi := Color8(53, 157, 119)
	for l: int in range(levels):
		var t := float(l) / maxf(1.0, float(levels - 1))
		var layer_y := -height + t * height * 0.64
		var layer_h := height * (0.18 + 0.045 * float(l % 2))
		var layer_w := width * (0.36 + 0.68 * t)
		for row: int in range(int(layer_h)):
			var half := floor(layer_w * (float(row) / maxf(1.0, layer_h)) * 0.5)
			var y := layer_y + float(row)
			var col := mid if row % 3 != 0 else dark
			r(canvas, -half, y, half * 2.0 + 1.0, 1.0, col, 0.90, tint)
			r(canvas, -half * 0.55, y, maxf(1.0, half * 0.6), 1.0, hi, 0.33, tint)


static func palm(canvas: CanvasItem, variant: int, height: float, tint: Color) -> void:
	shadow(canvas, 22.0, 0.14, tint)
	var lean := float((variant % 3) - 1)
	for i: int in range(int(height)):
		var x := lean * float(i) / maxf(1.0, height) * 5.0
		var y := -float(i)
		r(canvas, x - 2.0, y, 4.0, 1.0, bark_dark(), 0.95, tint)
		r(canvas, x - 1.0, y, 2.0, 1.0, bark_mid(), 0.90, tint)
		if i % 5 == 0:
			r(canvas, x + 1.0, y, 2.0, 1.0, bark_hi(), 0.55, tint)
	var top_x := lean * 5.0
	var top_y := -height
	for arm: int in range(8):
		var side := -1.0 if arm < 4 else 1.0
		var len := 11.0 + float((arm + variant) % 4)
		var dy := -3.0 + float(arm % 4) * 2.0
		for i: int in range(int(len)):
			var yy := top_y + dy + float(i) * 0.35
			var xx := top_x + side * float(i)
			r(canvas, xx, yy, 3.0, 1.0, leaf_mid(), 0.82, tint)
			if i % 2 == 0:
				r(canvas, xx, yy - 1.0, 2.0, 1.0, leaf_hi(), 0.45, tint)


static func cactus(canvas: CanvasItem, variant: int, height: float, tint: Color) -> void:
	shadow(canvas, 14.0, 0.12, tint)
	var dark := Color8(42, 118, 75)
	var mid := Color8(69, 158, 88)
	var hi := Color8(134, 205, 108)
	r(canvas, -3.0, -height, 6.0, height, dark, 0.95, tint)
	r(canvas, -1.5, -height + 1.0, 3.0, height - 2.0, mid, 0.92, tint)
	r(canvas, 1.5, -height + 3.0, 1.0, height - 6.0, hi, 0.45, tint)
	if variant % 2 == 0:
		r(canvas, -8.0, -height * 0.55, 4.0, 5.0, dark, 0.95, tint)
		r(canvas, -10.0, -height * 0.74, 4.0, height * 0.22, dark, 0.95, tint)
		r(canvas, 4.0, -height * 0.42, 4.0, 5.0, dark, 0.95, tint)
		r(canvas, 7.0, -height * 0.60, 4.0, height * 0.20, dark, 0.95, tint)
	else:
		r(canvas, 4.0, -height * 0.62, 4.0, 5.0, dark, 0.95, tint)
		r(canvas, 7.0, -height * 0.82, 4.0, height * 0.22, dark, 0.95, tint)
	for i: int in range(5):
		r(canvas, -1.0, -height + 4.0 + float(i) * 5.0, 1.0, 1.0, Color8(236, 244, 198), 0.55, tint)


static func rock(canvas: CanvasItem, variant: int, w: float, h: float, moss: bool, tint: Color) -> void:
	shadow(canvas, w * 0.95, 0.10, tint)
	blob(canvas, 0.0, -h * 0.45, w * 0.5, h * 0.45, stone_dark(), 0.95, tint)
	blob(canvas, -w * 0.10, -h * 0.58, w * 0.38, h * 0.30, stone_mid(), 0.90, tint)
	r(canvas, -w * 0.20, -h * 0.78, w * 0.28, 1.0, stone_hi(), 0.50, tint)
	if moss:
		blob(canvas, -w * 0.16, -h * 0.82, w * 0.22, h * 0.10, leaf_mid(), 0.68, tint)
	if variant % 2 == 1:
		r(canvas, w * 0.10, -h * 0.50, w * 0.18, 1.0, stone_dark().lerp(Color.BLACK, 0.20), 0.35, tint)


static func mushroom(canvas: CanvasItem, x: float, y: float, cap: Color, scale: float, tint: Color) -> void:
	r(canvas, x - 1.0 * scale, y - 4.0 * scale, 2.0 * scale, 4.0 * scale, Color8(225, 215, 174), 0.95, tint)
	blob(canvas, x, y - 5.0 * scale, 4.0 * scale, 2.0 * scale, cap, 0.95, tint)
	r(canvas, x - 1.0 * scale, y - 6.0 * scale, 1.0 * scale, 1.0 * scale, Color8(250, 245, 220), 0.55, tint)


static func flower(canvas: CanvasItem, x: float, y: float, col: Color, tint: Color) -> void:
	r(canvas, x, y - 5.0, 1.0, 5.0, leaf_dark(), 0.75, tint)
	r(canvas, x - 1.0, y - 3.0, 1.0, 1.0, leaf_mid(), 0.70, tint)
	r(canvas, x + 1.0, y - 4.0, 1.0, 1.0, leaf_mid(), 0.70, tint)
	r(canvas, x - 1.0, y - 6.0, 3.0, 1.0, col, 0.90, tint)
	r(canvas, x, y - 7.0, 1.0, 3.0, col, 0.85, tint)


static func fence(canvas: CanvasItem, variant: int, posts: int, tint: Color) -> void:
	var spacing := 7.0
	var total_w := float(posts - 1) * spacing + 4.0
	shadow(canvas, total_w, 0.08, tint)
	# posts as small iso blocks
	for i: int in range(posts):
		var x := -total_w * 0.5 + float(i) * spacing + 1.5
		iso(canvas, x, 0.0, 1.5, 0.75, 18.0, bark_mid(), tint)
	# two horizontal rails spanning the run
	r(canvas, -total_w * 0.5, -13.0, total_w, 3.0, bark_dark(), 0.90, tint)
	r(canvas, -total_w * 0.5, -6.0, total_w, 3.0, bark_mid(), 0.90, tint)


static func ladder(canvas: CanvasItem, variant: int, height: float, tint: Color) -> void:
	shadow(canvas, 12.0, 0.08, tint)
	r(canvas, -5.0, -height, 2.0, height, bark_dark(), 0.95, tint)
	r(canvas, 4.0, -height, 2.0, height, bark_dark(), 0.95, tint)
	for i: int in range(int(height / 7.0)):
		var y := -height + 5.0 + float(i) * 7.0
		r(canvas, -5.0, y, 11.0, 2.0, bark_mid(), 0.95, tint)
		r(canvas, -4.0, y, 7.0, 1.0, bark_hi(), 0.35, tint)


static func planks(canvas: CanvasItem, variant: int, count: int, tint: Color) -> void:
	var total := float(count) * 5.0
	shadow(canvas, total, 0.08, tint)
	# planks leaning as a stack — each a thin iso block
	for i: int in range(count):
		var x := -total * 0.5 + float(i) * 5.0 + 2.0
		var h := 18.0 + float((i + variant) % 3) * 2.0
		iso(canvas, x, 0.0, 2.0, 1.0, h, bark_mid(), tint)


static func log_pile(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 34.0, 0.12, tint)
	# stacked cordwood — each log a short iso block, back rows higher
	for row: int in range(3):
		for i: int in range(5 - row):
			var x := -15.0 + float(i) * 7.0 + float(row) * 3.5 + 3.5
			var y := -float(row) * 4.0
			iso(canvas, x, y, 3.5, 1.75, 5.0, bark_mid() if (i + row) % 2 == 0 else bark_dark(), tint)


static func chest(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 18.0, 0.10, tint)
	# coffer + lid as iso blocks, brass lock on the lit face
	iso(canvas, 0.0, 0.0, 9.0, 4.5, 8.0, bark_mid(), tint)
	iso(canvas, 0.0, -8.0, 9.5, 4.75, 4.0, bark_hi(), tint)
	r(canvas, 3.0, -7.0, 2.0, 4.0, Color8(220, 175, 69), 0.95, tint)


static func banner(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 24.0, 0.08, tint)
	r(canvas, -13.0, -35.0, 3.0, 35.0, bark_dark(), 0.95, tint)
	r(canvas, 10.0, -35.0, 3.0, 35.0, bark_dark(), 0.95, tint)
	var cloth := Color8(186, 161, 127) if variant % 2 == 0 else Color8(162, 145, 126)
	r(canvas, -10.0, -31.0, 20.0, 22.0, cloth, 0.80, tint)
	r(canvas, -8.0, -29.0, 16.0, 2.0, Color8(219, 199, 158), 0.50, tint)
	r(canvas, -8.0, -12.0, 16.0, 2.0, Color8(92, 72, 58), 0.20, tint)


static func well(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 30.0, 0.14, tint)
	# stone curb as a low iso ring with a dark shaft inside
	iso(canvas, 0.0, 0.0, 13.0, 6.5, 6.0, stone_mid(), tint)
	r(canvas, -7.0, -9.0, 14.0, 4.0, Color8(20, 22, 26), 0.95, tint)
	# roof posts as iso blocks + a cap board
	iso(canvas, -10.5, -2.0, 1.5, 0.75, 22.0, bark_dark(), tint)
	iso(canvas, 10.5, -2.0, 1.5, 0.75, 22.0, bark_dark(), tint)
	r(canvas, -13.0, -31.0, 26.0, 3.0, bark_mid(), 0.95, tint)
	r(canvas, -8.0, -36.0, 16.0, 5.0, Color8(122, 83, 52), 0.90, tint)


static func crystal(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 20.0, 0.10, tint)
	var dark := Color8(102, 160, 155)
	var mid := Color8(151, 211, 198)
	var hi := Color8(225, 252, 234)
	for i: int in range(4):
		var x := -8.0 + float(i) * 5.0
		var h := 12.0 + float((i + variant) % 3) * 5.0
		r(canvas, x, -h, 4.0, h, dark, 0.80, tint)
		r(canvas, x + 1.0, -h + 2.0, 2.0, h - 3.0, mid, 0.72, tint)
		r(canvas, x + 2.0, -h + 3.0, 1.0, h - 6.0, hi, 0.55, tint)


static func vine(canvas: CanvasItem, variant: int, height: float, tint: Color) -> void:
	r(canvas, -1.0, -height, 2.0, height, leaf_dark(), 0.70, tint)
	for i: int in range(int(height / 5.0)):
		var y := -height + float(i) * 5.0
		var side := -1.0 if (i + variant) % 2 == 0 else 1.0
		blob(canvas, side * 3.0, y + 1.0, 3.0, 2.0, leaf_mid(), 0.76, tint)


static func scarecrow(canvas: CanvasItem, variant: int, tint: Color) -> void:
	shadow(canvas, 18.0, 0.10, tint)
	r(canvas, -1.0, -32.0, 2.0, 32.0, bark_dark(), 0.95, tint)
	r(canvas, -10.0, -24.0, 20.0, 2.0, bark_mid(), 0.90, tint)
	r(canvas, -5.0, -31.0, 10.0, 8.0, sand_mid(), 0.90, tint)
	r(canvas, -7.0, -33.0, 14.0, 2.0, bark_dark(), 0.85, tint)
	r(canvas, -9.0, -35.0, 18.0, 2.0, Color8(117, 88, 49), 0.80, tint)
	r(canvas, -6.0, -21.0, 12.0, 11.0, Color8(133, 96, 68), 0.85, tint)
	r(canvas, -4.0, -28.0, 2.0, 2.0, Color8(32, 28, 23), 0.70, tint)
	r(canvas, 3.0, -28.0, 2.0, 2.0, Color8(32, 28, 23), 0.70, tint)
