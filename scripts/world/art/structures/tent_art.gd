extends RefCounted
class_name TentArt
## A simple A-frame canvas tent reduced to a few large cloth planes with chunky
## light / mid / shadow separation, a bold dark doorway and a couple of pegs.
## Readable from silhouette alone — no patterned shading or tiny edge detail.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")


static func _v(x: float, y: float) -> Vector2:
	return Vector2(PixelPalette.snap(x), PixelPalette.snap(y))


static func _poly(canvas: CanvasItem, pts: PackedVector2Array, color: Color, alpha: float = 1.0) -> void:
	canvas.draw_colored_polygon(pts, SilhouetteDraw.ink(color, alpha))


static func draw(canvas: CanvasItem, size: float, _color: Color) -> void:
	var color := PixelPalette.hex(0xB88A58).lerp(PixelPalette.pal("dirt_a"), 0.28)
	var w := PixelPalette.snap(size * 0.64)
	var hh := PixelPalette.snap(w * 0.50)
	var height := PixelPalette.snap(size * 0.62)
	PixelDraw.draw_foot_shadow(canvas, w + 4.0, hh + 4.0, 0.3, height)
	PixelDraw.draw_ground_collar(canvas, w * 0.92, true)

	var px := float(PixelPalette.PX)
	# Footprint corners and a single ridge point: two big side planes + a front.
	var rear := _v(0.0, -hh)
	var left := _v(-w, hh * 0.4)
	var right := _v(w, hh * 0.4)
	var front := _v(0.0, hh)
	var ridge := _v(0.0, -height)

	var lit := PixelPalette.shade(color, 1.04)
	var mid := PixelPalette.shade(color, 0.84)
	var shadow := PixelPalette.shade(color, 0.56)

	# Two large flank cloth planes (lit SE, shadowed SW) and the bright front.
	_poly(canvas, PackedVector2Array([rear, left, front, ridge]), shadow)
	_poly(canvas, PackedVector2Array([rear, right, front, ridge]), mid)
	PixelDraw.iso_tri_solid(canvas, left, right, ridge, lit, 3)

	# A couple of broad chunky tonal blocks suggest cloth sag — not stripes.
	PixelDraw.px_rect(canvas, -w * 0.62, -height * 0.42, w * 0.40, height * 0.18, PixelPalette.shade(shadow, 0.86), 0.55)
	PixelDraw.px_rect(canvas, w * 0.22, -height * 0.48, w * 0.38, height * 0.16, PixelPalette.shade(mid, 1.1), 0.5)

	# Bold dark triangular doorway: the entrance reads instantly.
	var door := PixelPalette.hex(0x140F0C)
	_poly(canvas, PackedVector2Array([
		_v(-w * 0.26, hh * 0.5), _v(w * 0.26, hh * 0.5), _v(0.0, -height * 0.56)
	]), door, 0.95)
	PixelDraw.px_rect(canvas, -px * 0.5, -height * 0.56, px, height * 0.56 + hh * 0.5, PixelPalette.shade(lit, 1.18), 0.7)

	# Two chunky ground pegs.
	var peg := PixelPalette.pal("trunk_b")
	PixelDraw.px_rect(canvas, -w - px, hh * 0.42, px * 2.0, px * 2.5, peg)
	PixelDraw.px_rect(canvas, w - px, hh * 0.42, px * 2.0, px * 2.5, peg)
