extends RefCounted
class_name HouseArt
## Reusable medieval cottage drawn in true isometric volume: a stone shell on a
## 2:1 diamond footprint with four lit/shaded walls under a hipped roof. The back
## walls + interior floor draw in `draw_body` (always visible); the front walls,
## door and roof draw in `draw_roof` and fade as the player steps inside, just
## like `building_art`, so a small house matches the big ones. Variant nudges
## size/height; `roof_color` themes the building so a street reads as varied.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")


static func body_half_width(variant: int) -> float:
	return 20.0 + float(variant % 3) * 4.0


static func wall_height(variant: int) -> float:
	return 26.0 + float((variant / 3) % 3) * 5.0


static func roof_height(variant: int) -> float:
	return 20.0 + float(variant % 3) * 5.0


static func total_height(variant: int) -> float:
	return wall_height(variant) + roof_height(variant) + 6.0


## Fill a vertical wall face: the parallelogram swept from base edge a→b up by h.
static func _wall(canvas: CanvasItem, a: Vector2, b: Vector2, h: float, col: Color, alpha: float) -> void:
	var up := Vector2(0.0, -h)
	canvas.draw_colored_polygon(
		PackedVector2Array([a, b, b + up, a + up]), SilhouetteDraw.ink(col, alpha))
	# top-plate highlight along the eave
	canvas.draw_colored_polygon(
		PackedVector2Array([a + up, b + up, b + up + Vector2(0, float(PixelPalette.PX)), a + up + Vector2(0, float(PixelPalette.PX))]),
		SilhouetteDraw.ink(PixelPalette.shade(col, 1.15), alpha))


static func _roof_tri(canvas: CanvasItem, a: Vector2, b: Vector2, apex: Vector2, col: Color, alpha: float) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([a, b, apex]), SilhouetteDraw.ink(col, alpha))


static func draw_body(canvas: CanvasItem, variant: int, _accent: Color) -> void:
	var w := body_half_width(variant)
	var h := wall_height(variant)
	var e := Vector2(w, w * 0.5)
	PixelDraw.draw_foot_shadow(canvas, w + 4.0, e.y + 2.0, 0.3, total_height(variant))
	var wall := PixelPalette.pal("stone_b")
	# interior floor — revealed once the roof + front walls fade out
	PixelDraw.px_diamond(canvas, 0.0, -2.0, e.x - 3.0, e.y - 1.5, PixelPalette.shade(PixelPalette.pal("dirt_a"), 0.95))
	# back walls: NW (W→N) shaded, NE (N→E) lit
	_wall(canvas, Vector2(-e.x, 0.0), Vector2(0.0, -e.y), h, PixelPalette.shade(wall, 0.9), 1.0)
	_wall(canvas, Vector2(0.0, -e.y), Vector2(e.x, 0.0), h, PixelPalette.shade(wall, 1.06), 1.0)
	# lit windows in the back walls (stay glowing even after you enter)
	var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("outfit_a"), 0.18)
	PixelDraw.px_rect(canvas, -e.x * 0.55, -h + 7.0, 5.0, 6.0, glow, 0.9)
	PixelDraw.px_rect(canvas, e.x * 0.30, -h + 7.0, 5.0, 6.0, glow, 0.9)


static func draw_roof(canvas: CanvasItem, variant: int, roof_color: Color, alpha: float) -> void:
	if alpha <= 0.02:
		return
	var w := body_half_width(variant)
	var h := wall_height(variant)
	var rh := roof_height(variant)
	var e := Vector2(w, w * 0.5)
	var wall := PixelPalette.pal("stone_b")
	# front walls fade with the roof
	_wall(canvas, Vector2(-e.x, 0.0), Vector2(0.0, e.y), h, PixelPalette.shade(wall, 0.8), alpha)
	_wall(canvas, Vector2(0.0, e.y), Vector2(e.x, 0.0), h, PixelPalette.shade(wall, 1.0), alpha)
	# door at the south corner (on the front seam)
	var door := SilhouetteDraw.ink(PixelPalette.pal("trunk_b"), alpha)
	canvas.draw_rect(Rect2(PixelPalette.snap(-5.0), PixelPalette.snap(e.y - 17.0), 10.0, 17.0), door)
	PixelDraw.px_rect(canvas, 2.0, e.y - 10.0, 2.0, 2.0, PixelPalette.pal("gold"), alpha)
	# hipped roof over the wall tops, with eave overhang
	var ov := 5.0
	var top := Vector2(0.0, -h)
	var W := Vector2(-e.x - ov, e.y * 0.0) + top + Vector2(0.0, ov * 0.4)
	var N := Vector2(0.0, -e.y - ov * 0.4) + top
	var E := Vector2(e.x + ov, 0.0) + top + Vector2(0.0, ov * 0.4)
	var S := Vector2(0.0, e.y + ov * 0.5) + top
	var apex := Vector2(0.0, -h - rh)
	var hi := PixelPalette.shade(roof_color, 1.18)
	var mid := roof_color
	var lo := PixelPalette.shade(roof_color, 0.74)
	var dark := PixelPalette.shade(roof_color, 0.55)
	# back faces first, then the camera-facing faces
	_roof_tri(canvas, W, N, apex, lo, alpha * 0.92)
	_roof_tri(canvas, N, E, apex, mid, alpha * 0.92)
	_roof_tri(canvas, W, S, apex, dark, alpha)
	_roof_tri(canvas, S, E, apex, hi, alpha)
	# ridge highlight down the lit front hip
	PixelDraw.px_rect(canvas, -1.0, -h - rh, 3.0, rh - 2.0, PixelPalette.shade(roof_color, 1.32), alpha * 0.7)
	# chimney
	if variant % 3 != 0:
		var cx := e.x * (0.4 if variant % 2 == 0 else -0.4)
		PixelDraw.px_rect(canvas, cx - 4.0, -h - rh * 0.5 - 18.0, 9.0, 20.0, PixelPalette.shade(PixelPalette.pal("stone_a"), 0.86), alpha)
		PixelDraw.px_rect(canvas, cx - 5.0, -h - rh * 0.5 - 20.0, 11.0, 4.0, PixelPalette.shade(PixelPalette.pal("stone_a"), 1.1), alpha)
