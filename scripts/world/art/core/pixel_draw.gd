extends RefCounted
class_name PixelDraw

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")


static func px_rect(canvas: CanvasItem, x: float, y: float, w: float, h: float, color: Color, alpha: float = 1.0) -> void:
	var c := color
	c.a *= alpha
	canvas.draw_rect(
		Rect2(PixelPalette.snap(x), PixelPalette.snap(y),
			maxf(PixelPalette.PX, PixelPalette.snap(w)),
			maxf(PixelPalette.PX, PixelPalette.snap(h))),
		c)


static func px_row(canvas: CanvasItem, cx: float, y: float, half_w: float, color: Color, alpha: float = 1.0) -> void:
	if half_w <= 0.0:
		return
	px_rect(canvas, cx - half_w, y, half_w * 2.0, PixelPalette.PX, color, alpha)


static func px_blob(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, alpha: float = 1.0) -> void:
	var steps := maxi(3, int(rx / PixelPalette.PX))
	for i: int in range(-steps, steps + 1):
		var t := float(i) / float(steps)
		var w := sqrt(maxf(0.0, 1.0 - t * t)) * rx
		px_rect(canvas, cx - w, cy + t * ry - PixelPalette.PX, w * 2.0, PixelPalette.PX * 2.0, color, alpha)


static func px_diamond(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, color: Color, alpha: float = 1.0) -> void:
	var c := color
	c.a *= alpha
	var pts := PackedVector2Array([
		Vector2(PixelPalette.snap(cx), PixelPalette.snap(cy - hh)),
		Vector2(PixelPalette.snap(cx + hw), PixelPalette.snap(cy)),
		Vector2(PixelPalette.snap(cx), PixelPalette.snap(cy + hh)),
		Vector2(PixelPalette.snap(cx - hw), PixelPalette.snap(cy)),
	])
	canvas.draw_colored_polygon(pts, c)


static func draw_foot_shadow(canvas: CanvasItem, radius_x: float, radius_y: float = 5.0, alpha: float = 0.3) -> void:
	px_blob(canvas, 0.0, PixelPalette.snap(radius_y * 0.6), radius_x, radius_y, PixelPalette.pal("shadow"), alpha)


## Compact ground contact shadow for characters — thin, tight, and darker than
## draw_foot_shadow so sprites read punchier against terrain.
static func draw_tight_character_shadow(canvas: CanvasItem, half_width: float, y: float = 4.0, alpha: float = 0.58) -> void:
	var sh := PixelPalette.pal("shadow")
	var px := float(PixelPalette.PX)
	var ox := px * 0.35
	var hw := maxf(half_width, px * 2.5)
	px_blob(canvas, ox, y, hw * 0.64, px * 0.9, sh, alpha)
	px_blob(canvas, ox + px * 0.25, y + px * 0.35, hw * 0.40, px * 0.55, sh, minf(alpha * 1.12, 1.0))
	px_row(canvas, ox + px * 0.5, y + px * 0.65, hw * 0.52, sh, alpha * 0.72)


static func draw_tree_shadow(canvas: CanvasItem, radius_x: float, alpha: float = 0.22) -> void:
	px_blob(canvas, 0.0, 6.0, radius_x * 0.88, radius_x * 0.26, PixelPalette.pal("shadow"), alpha)


static func draw_ellipse(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	px_blob(canvas, cx, cy, maxf(rx, PixelPalette.PX), maxf(ry, PixelPalette.PX), color)


static func draw_foliage_clump(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	var hi := PixelPalette.shade(color, 1.28)
	var lo := PixelPalette.shade(color, 0.68)
	px_blob(canvas, cx, cy, rx, ry, color)
	px_blob(canvas, cx - rx * 0.28, cy - ry * 0.32, rx * 0.58, ry * 0.48, hi, 0.82)
	px_blob(canvas, cx + rx * 0.22, cy + ry * 0.12, rx * 0.52, ry * 0.38, lo, 0.55)
	var px := float(PixelPalette.PX)
	px_rect(canvas, PixelPalette.snap(cx - rx * 0.35), PixelPalette.snap(cy - ry * 0.4), px * 2.0, px * 2.0, hi, 0.9)
	px_rect(canvas, PixelPalette.snap(cx - rx * 0.15), PixelPalette.snap(cy - ry * 0.5), px, px, PixelPalette.shade(hi, 1.1), 0.85)


static func draw_cloud_clump(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	draw_foliage_clump(canvas, cx, cy, rx, ry, color)


static func draw_trunk_base(canvas: CanvasItem, half_w: float, height: float, color: Color = PixelPalette.pal("trunk_a"), shadow: Color = PixelPalette.pal("trunk_b")) -> void:
	var px := float(PixelPalette.PX)
	var w := PixelPalette.snap(maxf(px * 2.0, half_w))
	var h := PixelPalette.snap(maxf(px * 2.0, height))
	px_rect(canvas, -w - px, -px, w * 2.0 + px * 2.0, px, PixelPalette.shade(shadow, 0.85))
	px_rect(canvas, -w - px * 2.0, -px, px * 2.0, px, shadow)
	px_rect(canvas, w, -px, px * 2.0, px, shadow)
	px_rect(canvas, -w, -h, w * 2.0, h, color)
	px_rect(canvas, w - px, -h + px, px, h - px, shadow)
	px_rect(canvas, -w, -h, px, h, PixelPalette.shade(color, 1.14))
	var ly := -h + px * 2.0
	while ly < -px:
		px_rect(canvas, -w + px, ly, w * 2.0 - px * 2.0, px, PixelPalette.shade(shadow, 0.35), 0.45)
		ly += px * 3.0


static func draw_simple_trunk(canvas: CanvasItem, half_w: float, height: float, color: Color = PixelPalette.pal("trunk_a"), shadow: Color = PixelPalette.pal("trunk_b")) -> void:
	draw_trunk_base(canvas, half_w, height, color, shadow)
