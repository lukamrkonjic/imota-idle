extends RefCounted
class_name TentArt
## A canvas tent drawn as a true isometric pyramid, textured like pixel-art cloth:
## four lit/shaded faces, vertical panel seams converging to the apex, a darker
## hem band along the base, a dark silhouette outline and a ridge highlight — so
## it reads as a hand-drawn tent, not a smooth shaded 3-D cone.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")


static func _face(canvas: CanvasItem, pts: PackedVector2Array, col: Color, alpha: float = 1.0) -> void:
	canvas.draw_colored_polygon(pts, SilhouetteDraw.ink(col, alpha))


static func _seam(canvas: CanvasItem, p0: Vector2, p1: Vector2, col: Color, w: float) -> void:
	canvas.draw_line(p0, p1, SilhouetteDraw.ink(col), w)


static func draw(canvas: CanvasItem, size: float, color: Color) -> void:
	var w := PixelPalette.snap(size * 0.72)
	var hh := w * 0.5
	var height := PixelPalette.snap(size * 0.95)
	PixelDraw.draw_foot_shadow(canvas, w + 2.0, hh + 1.0, 0.3, height)
	var W := Vector2(-w, 0.0)
	var N := Vector2(0.0, -hh)
	var E := Vector2(w, 0.0)
	var S := Vector2(0.0, hh)
	var apex := Vector2(0.0, -height)
	var lit := PixelPalette.shade(color, 1.12)
	var sw := PixelPalette.shade(color, 0.66)
	var px := float(PixelPalette.PX)
	# back faces first, then the two camera-facing faces
	_face(canvas, PackedVector2Array([W, N, apex]), PixelPalette.shade(color, 0.82))
	_face(canvas, PackedVector2Array([N, E, apex]), PixelPalette.shade(color, 0.94))
	_face(canvas, PackedVector2Array([W, S, apex]), sw)
	_face(canvas, PackedVector2Array([S, E, apex]), lit)
	# chunky pixel dither across the cloth so it reads hand-drawn, not smooth
	PixelDraw.iso_tri_dither(canvas, W, S, apex, sw, 0)
	PixelDraw.iso_tri_dither(canvas, S, E, apex, lit, 2)
	# darker hem band along the two front base edges (a trapezoid up to 18%)
	var hem := 0.18
	_face(canvas, PackedVector2Array([W, S, S.lerp(apex, hem), W.lerp(apex, hem)]), PixelPalette.shade(sw, 0.82))
	_face(canvas, PackedVector2Array([S, E, E.lerp(apex, hem), S.lerp(apex, hem)]), PixelPalette.shade(lit, 0.85))
	# vertical panel seams converging on the apex
	for u: float in [0.34, 0.67]:
		_seam(canvas, W.lerp(S, u), apex, PixelPalette.shade(sw, 0.78), px * 0.5)
		_seam(canvas, S.lerp(E, u), apex, PixelPalette.shade(lit, 0.82), px * 0.5)
	# ridge highlight + dark silhouette outline
	_seam(canvas, apex, S, PixelPalette.shade(color, 1.28), px * 0.6)
	var edge := PixelPalette.shade(color, 0.48)
	_seam(canvas, apex, W, edge, px * 0.5)
	_seam(canvas, apex, E, edge, px * 0.5)
	_seam(canvas, W, S, edge, px * 0.5)
	_seam(canvas, S, E, edge, px * 0.5)
	# entry slit at the front
	PixelDraw.px_rect(canvas, -px, -hh * 1.2, px * 2.0, hh * 1.2, Color(0.12, 0.09, 0.07), 0.9)
	# guy pegs
	PixelDraw.px_rect(canvas, -w - px, 0.0, px, px * 2.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, w, 0.0, px, px * 2.0, PixelPalette.pal("trunk_b"))
