extends RefCounted
class_name MountainArt
## A detailed isometric mountain massif: a faceted rock pyramid with shaded
## faces (lit from the upper-right to match the world sun), carved striations, a
## smaller shoulder peak for a ridgeline feel, and a snow cap on the tall/cold
## ones. Drawn big — it rises well above its footprint so a cluster of these
## reads as a mountain range with valleys and passes between them.
##
## `foot`    footprint in tiles (~2-4).
## `variant` seeds height, lean, shoulder peak, striations, snow line.
## `snow`    0..1 snow coverage (1 = white-capped alpine peak).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")
const WG := preload("res://scripts/worldgen/wg.gd")


static func height_for(foot: float, variant: int) -> float:
	return 50.0 + foot * 18.0 + float(variant % 3) * 16.0


static func _ext(foot: float) -> Vector2:
	return Vector2(foot * float(WG.ISO_HW), foot * float(WG.ISO_HH))


static func _tri(canvas: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), col)


static func draw(canvas: CanvasItem, foot: float, variant: int, snow: float = 0.0) -> void:
	var e := _ext(foot)
	var w := Vector2(-e.x, 0.0)
	var n := Vector2(0.0, -e.y)
	var ee := Vector2(e.x, 0.0)
	var s := Vector2(0.0, e.y)
	var h := height_for(foot, variant)
	var lean := (WG.r01(variant, 3, 1, 7) - 0.5) * e.x * 0.5
	var apex := Vector2(lean, -h)

	ShadowProjector.cast_silhouette(canvas, PackedVector2Array([w, n, ee, s]), h, 0.5)

	# optional shoulder peak behind/beside the main one (drawn first, so it sits behind)
	if variant % 3 != 0:
		var sx := e.x * (0.42 if variant % 2 == 0 else -0.42)
		_peak(canvas, Vector2(sx, 0.0), foot * 0.62, h * 0.66, variant + 11, snow * 0.85)

	_peak(canvas, Vector2.ZERO, foot, h, variant, snow, apex)


static func _peak(canvas: CanvasItem, off: Vector2, foot: float, h: float, variant: int,
		snow: float, apex_override := Vector2.INF) -> void:
	var e := _ext(foot)
	var w := off + Vector2(-e.x, 0.0)
	var n := off + Vector2(0.0, -e.y)
	var ee := off + Vector2(e.x, 0.0)
	var s := off + Vector2(0.0, e.y)
	var apex: Vector2 = (off + Vector2(0.0, -h)) if apex_override == Vector2.INF else apex_override

	var rock := PixelPalette.pal("stone_b")
	# Four faces, shaded by the upper-right sun: NE brightest, SW darkest.
	var f_ne := PixelPalette.shade(rock, 1.22)   # n->e (back-right)
	var f_nw := PixelPalette.shade(rock, 0.98)   # w->n (back-left)
	var f_se := PixelPalette.shade(rock, 0.80)   # e->s (front-right)
	var f_sw := PixelPalette.shade(rock, 0.62)   # s->w (front-left)
	_tri(canvas, n, ee, apex, f_ne)
	_tri(canvas, w, n, apex, f_nw)
	_tri(canvas, ee, s, apex, f_se)
	_tri(canvas, s, w, apex, f_sw)

	# carved striations: faint lines following the slopes on the front faces
	var line := PixelPalette.shade(rock, 0.5)
	line.a = 0.4
	for i: int in range(1, 4):
		var t := float(i) / 4.0
		canvas.draw_line(s.lerp(apex, t), w.lerp(apex, t), line, 1.0)
		canvas.draw_line(s.lerp(apex, t), ee.lerp(apex, t), PixelPalette.shade(rock, 0.7) * Color(1, 1, 1, 0.5), 1.0)
	# a couple of lit rock highlights near the ridge
	var hi := PixelPalette.shade(rock, 1.4)
	canvas.draw_line(n.lerp(apex, 0.15), apex, hi, 1.5)

	# snow cap — a smaller bright pyramid from a jagged snow line up to the apex
	if snow > 0.02:
		var line_t := clampf(1.0 - snow * 0.6, 0.30, 0.85)   # more snow => lower line
		var rw := w.lerp(apex, line_t)
		var rn := n.lerp(apex, line_t)
		var re := ee.lerp(apex, line_t)
		var rs := s.lerp(apex, line_t)
		# ragged drips down the front faces
		var d := PixelPalette.snap(6.0)
		rs += Vector2(0.0, d * (1.0 + WG.r01(variant, 5, 2, 9)))
		var snow_c := PixelPalette.pal("snow_a")
		_tri(canvas, rn, re, apex, snow_c)
		_tri(canvas, rw, rn, apex, PixelPalette.shade(snow_c, 0.94))
		_tri(canvas, re, rs, apex, PixelPalette.shade(snow_c, 0.86))
		_tri(canvas, rs, rw, apex, PixelPalette.shade(snow_c, 0.80))
		# bright cap tip
		PixelDraw.px_diamond(canvas, apex.x, apex.y + 2.0, 4.0, 2.0, PixelPalette.shade(snow_c, 1.05))
