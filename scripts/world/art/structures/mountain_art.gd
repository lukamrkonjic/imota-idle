extends RefCounted
class_name MountainArt
## A chunky isometric ROCK MASSIF: a broad rounded base of bedrock and boulders
## rising to one blunt, flat-topped summit flanked by a couple of lower rocky
## shoulders — wide rather than tall, faceted, lit from the upper-right with
## shadowed left faces, horizontal rock strata and dark crevices. Snow caps the
## tall/cold crowns. A few of these on a ridge crest read as a mountain range.
##
## `foot` footprint in tiles; `variant` seeds the layout; `snow` 0..1.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")
const WG := preload("res://scripts/worldgen/wg.gd")


# Deliberately squat: height tracks width so the form reads as a chunky rock
# mass, not a spike (footprint half-width is foot*16, so height ~= width).
static func height_for(foot: float, variant: int) -> float:
	return 24.0 + foot * 8.0 + float(variant % 3) * 5.0


static func _ext(foot: float) -> Vector2:
	return Vector2(foot * float(WG.ISO_HW), foot * float(WG.ISO_HH))


static func _rock() -> Color:
	return PixelPalette.pal("stone_b").lerp(PixelPalette.pal("trunk_b"), 0.10)


static func draw(canvas: CanvasItem, foot: float, variant: int, snow: float = 0.0) -> void:
	var e := _ext(foot)
	var h := height_for(foot, variant)
	ShadowProjector.cast_silhouette(
		canvas, PackedVector2Array([Vector2(-e.x, 0), Vector2(0, -e.y), Vector2(e.x, 0), Vector2(0, e.y)]), h, 0.5)

	var rk := _rock()
	_scree(canvas, e, rk, variant)
	# Lower rocky shoulders first (behind), then the main blunt summit on top.
	var shoulders := 1 + variant % 2
	for i: int in shoulders:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var off := Vector2(side * e.x * (0.34 + 0.12 * WG.r01(variant, i, 4, 5)), e.y * 0.16)
		_summit(canvas, e, off, h * (0.5 + 0.12 * WG.r01(variant, i, 6, 3)),
			e.x * (0.42 + 0.1 * WG.r01(variant, i, 7, 2)), rk, variant * 7 + i + 1, snow)
	_summit(canvas, e, Vector2(0, -e.y * 0.1), h, e.x * 0.62, rk, variant, snow)


# Boulder/scree apron — grounds the massif so it sits in the terrain.
static func _scree(canvas: CanvasItem, e: Vector2, rk: Color, variant: int) -> void:
	var n := 8 + variant % 4
	for i: int in n:
		var ang := TAU * float(i) / float(n) + WG.r01(variant, i, 7, 2)
		var rad := e.x * (0.55 + 0.45 * WG.r01(variant, i, 8, 4))
		var bx := cos(ang) * rad
		var by := sin(ang) * rad * 0.5 + e.y * 0.42
		var r := maxf(e.x * 0.2, 5.0) * (0.7 + 0.6 * WG.r01(variant, i, 9, 6))
		PixelDraw.px_blob(canvas, bx, by, r, r * 0.58, PixelPalette.shade(rk, 0.7))
		PixelDraw.px_blob(canvas, bx, by - r * 0.28, r * 0.7, r * 0.4, PixelPalette.shade(rk, 1.02))
		PixelDraw.px_blob(canvas, bx - r * 0.2, by - r * 0.4, r * 0.32, r * 0.2, PixelPalette.shade(rk, 1.3), 0.85)


# One blunt, flat-topped rock mass: a wide base sweeping to a short horizontal
# crown (not a point). Split into a shadowed left face and a lit right face, with
# horizontal rock strata, a couple of crevices and an optional snow cap.
static func _summit(canvas: CanvasItem, e: Vector2, center: Vector2, h: float, hw: float, rk: Color, salt: int, snow: float) -> void:
	var lean := (WG.r01(salt, 1, 2, 3) - 0.5) * hw * 0.3
	var base_y := center.y + hw * 0.16
	var bl := center + Vector2(-hw, base_y - center.y)
	var br := center + Vector2(hw, base_y - center.y)
	var cw := hw * 0.34                                   # blunt crown half-width
	var cl := center + Vector2(lean - cw, -h)
	var cr := center + Vector2(lean + cw, -h)
	var bc := center + Vector2(0.0, base_y - center.y)    # base centre
	var tc := center + Vector2(lean, -h)                  # crown centre

	var lit := PixelPalette.shade(rk, 1.22)
	var mid := PixelPalette.shade(rk, 0.95)
	var dark := PixelPalette.shade(rk, 0.6)
	# shoulders of the slope (back faces) give it girth
	canvas.draw_colored_polygon(PackedVector2Array([bl, cl, tc, bc]), dark)         # left / shadow
	canvas.draw_colored_polygon(PackedVector2Array([bc, tc, cr, br]), lit)          # right / lit
	# blunt crown top facet (catches the most light)
	var tb := tc + Vector2(0.0, -hw * 0.05)
	canvas.draw_colored_polygon(PackedVector2Array([cl, tb, cr, tc]), PixelPalette.shade(rk, 1.36))

	# horizontal rock strata across both faces
	var strata := PixelPalette.shade(rk, 0.74)
	strata.a = 0.5
	for s: int in 3:
		var t := 0.28 + 0.22 * float(s)
		var ll := bl.lerp(cl, t)
		var rr := br.lerp(cr, t)
		canvas.draw_line(ll, bc.lerp(tc, t), strata, 1.0)
		canvas.draw_line(bc.lerp(tc, t), rr, strata, 1.0)
	# central ridge highlight + a crevice
	canvas.draw_line(bc, tc, PixelPalette.shade(rk, 1.5) * Color(1, 1, 1, 0.7), 1.5)
	var crev := PixelPalette.shade(rk, 0.42)
	crev.a = 0.55
	canvas.draw_line(bl.lerp(cl, 0.2), tc.lerp(cr, 0.4), crev, 1.0)

	# snow cap — clean cap from the snow line up over the blunt crown
	if snow > 0.02 and h > 26.0:
		var t := clampf(0.58 - snow * 0.18, 0.4, 0.68)
		var sc := PixelPalette.pal("snow_a")
		var sl := bl.lerp(cl, t)
		var sr := br.lerp(cr, t)
		var sm := bc.lerp(tc, t)
		canvas.draw_colored_polygon(PackedVector2Array([sm, tc, cr, sr]), sc)
		canvas.draw_colored_polygon(PackedVector2Array([sl, cl, tc, sm]), PixelPalette.shade(sc, 0.84))
		canvas.draw_colored_polygon(PackedVector2Array([cl, tb, cr, tc]), sc)
