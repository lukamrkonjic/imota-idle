extends RefCounted
class_name HouseArt
## Reusable medieval townhouse: a stone shell (always drawn) under a pitched
## roof drawn separately, so the roof can fade as the player steps inside and
## reveal the interior floor. Variant nudges size/height; roof_color themes the
## building so a street of these reads as a varied city.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func body_half_width(variant: int) -> float:
	return 20.0 + float(variant % 3) * 4.0


static func wall_height(variant: int) -> float:
	return 26.0 + float((variant / 3) % 3) * 5.0


static func roof_height(variant: int) -> float:
	return 20.0 + float(variant % 3) * 5.0


static func total_height(variant: int) -> float:
	return wall_height(variant) + roof_height(variant) + 6.0


static func draw_body(canvas: CanvasItem, variant: int, accent: Color) -> void:
	var w := body_half_width(variant)
	var wall_h := wall_height(variant)
	var wall := PixelPalette.pal("stone_b")
	var wall_hi := PixelPalette.pal("stone_a")
	var wall_sh := PixelPalette.shade(wall, 0.8)
	var floor_c := PixelPalette.shade(PixelPalette.pal("dirt_a"), 0.95)
	PixelDraw.draw_foot_shadow(canvas, w + 4.0, 5.0)
	# interior floor — only visible once the roof above it fades out
	PixelDraw.px_rect(canvas, -w + 4.0, -wall_h - 2.0, w * 2.0 - 8.0, 12.0, floor_c)
	# walls
	PixelDraw.px_rect(canvas, -w, -wall_h, w * 2.0, wall_h, wall)
	PixelDraw.px_rect(canvas, -w, -wall_h, 4.0, wall_h, wall_hi)        # lit corner
	PixelDraw.px_rect(canvas, w - 4.0, -wall_h, 4.0, wall_h, wall_sh)   # shaded corner
	# stone coursing
	var cy := -wall_h + 7.0
	while cy < -5.0:
		PixelDraw.px_rect(canvas, -w + 4.0, cy, w * 2.0 - 8.0, 1.0, wall_sh, 0.4)
		cy += 7.0
	# door
	PixelDraw.px_rect(canvas, -6.0, -16.0, 12.0, 16.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -6.0, -16.0, 12.0, 3.0, PixelPalette.shade(accent, 0.85))
	PixelDraw.px_rect(canvas, 3.0, -9.0, 2.0, 2.0, PixelPalette.pal("gold"))
	# lit windows
	var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("outfit_a"), 0.18)
	PixelDraw.px_rect(canvas, -w + 5.0, -wall_h + 5.0, 6.0, 6.0, glow, 0.9)
	PixelDraw.px_rect(canvas, w - 11.0, -wall_h + 5.0, 6.0, 6.0, glow, 0.9)


static func draw_roof(canvas: CanvasItem, variant: int, roof_color: Color, alpha: float) -> void:
	if alpha <= 0.02:
		return
	var w := body_half_width(variant)
	var wall_h := wall_height(variant)
	var rh := roof_height(variant)
	var overhang := w + 6.0
	var hi := PixelPalette.shade(roof_color, 1.18)
	var sh := PixelPalette.shade(roof_color, 0.8)
	var px := float(PixelPalette.PX)
	# eave board
	PixelDraw.px_rect(canvas, -overhang, -wall_h - px, overhang * 2.0, px + 2.0, sh, alpha)
	# pitched roof as narrowing rows
	var rows := maxi(3, int(rh / px))
	for i: int in rows:
		var f := float(i) / float(rows)
		var hw := lerpf(overhang - 1.0, 3.0, f)
		var col := roof_color.lerp(hi, f * 0.55)
		PixelDraw.px_row(canvas, 0.0, -wall_h - px - float(i) * px, hw, col, alpha)
	# ridge cap
	PixelDraw.px_rect(canvas, -3.0, -wall_h - px - float(rows) * px, 6.0, px, hi, alpha)
