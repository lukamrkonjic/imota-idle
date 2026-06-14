extends RefCounted
class_name ChestArt
## A compact treasure coffer: dark planked body, rounded lid rows, metal straps,
## a bright lock plate and a few coin pixels. It is deliberately more "spritey"
## and chunky than a plain iso crate so it does not read as a tiny hut.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func _coin(canvas: CanvasItem, x: float, y: float, alpha: float = 1.0) -> void:
	var gold := PixelPalette.pal("gold")
	var px := float(PixelPalette.PX)
	PixelDraw.px_blob(canvas, x, y, px * 0.95, px * 0.55, PixelPalette.shade(gold, 0.92), alpha)
	PixelDraw.px_rect(canvas, x - px * 0.35, y - px * 0.65, px, px, PixelPalette.shade(gold, 1.28), alpha * 0.75)


static func draw(canvas: CanvasItem, size: float, color: Color, depleted: bool) -> void:
	var px := float(PixelPalette.PX)
	var w := PixelPalette.snap(size * 0.54)
	var depth := PixelPalette.snap(size * 0.16)
	var body_h := PixelPalette.snap(size * 0.30)
	var lid_h := PixelPalette.snap(size * 0.28)
	PixelDraw.draw_foot_shadow(canvas, w * 0.55 + 4.0, depth + 3.0, 0.3, body_h + lid_h)
	PixelDraw.draw_ground_collar(canvas, w * 0.50 + 2.0, true)

	var wood := PixelPalette.pal("stone_b") if depleted else color.lerp(PixelPalette.hex(0x6A3A2A), 0.66)
	var wood_dark := PixelPalette.shade(wood, 0.55)
	var wood_lit := PixelPalette.shade(wood, 1.18)
	var band := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.62) if depleted else PixelPalette.hex(0x3F3640)
	var gold := PixelPalette.pal("stone_a") if depleted else PixelPalette.pal("gold")

	# Tiny ground plinth gives the mostly front-facing coffer an iso footprint.
	PixelDraw.px_diamond(canvas, 0.0, px, w * 0.52, depth, PixelPalette.shade(PixelPalette.pal("dirt_a"), 0.82), 0.44)

	# Front face and a small right side: readable treasure chest first, iso hint second.
	PixelDraw.px_rect(canvas, -w * 0.50, -body_h, w, body_h, PixelPalette.shade(wood, 0.82))
	PixelDraw.px_rect(canvas, w * 0.28, -body_h + px, w * 0.22, body_h - px, wood_dark, 0.92)
	PixelDraw.px_rect(canvas, -w * 0.50, -body_h, w, px, PixelPalette.shade(wood_lit, 0.90), 0.92)
	PixelDraw.px_rect(canvas, -w * 0.50, -px, w, px, PixelPalette.shade(wood_dark, 0.78), 0.9)

	# Rounded lid as a short barrel vault.
	for r: int in range(0, 7):
		var t := float(r) / 6.0
		var y := -body_h - lid_h + float(r) * px
		var row_hw := lerpf(w * 0.22, w * 0.54, t)
		var row_col := PixelPalette.shade(wood_lit, lerpf(1.14, 0.78, t))
		PixelDraw.px_row(canvas, 0.0, y, row_hw, row_col, 0.98)
		if r in [2, 4, 6]:
			PixelDraw.px_row(canvas, 0.0, y + px, row_hw, wood_dark, 0.24)

	PixelDraw.px_rect(canvas, -w * 0.55, -body_h - px, w * 1.10, px, band, 0.88)
	PixelDraw.px_rect(canvas, -w * 0.45, -body_h - lid_h * 0.68, px * 1.5, body_h + lid_h * 0.72, band, 0.86)
	PixelDraw.px_rect(canvas, w * 0.34, -body_h - lid_h * 0.58, px * 1.5, body_h + lid_h * 0.60, band, 0.86)
	PixelDraw.px_rect(canvas, -w * 0.52, -body_h + px * 1.2, w * 1.02, px, band, 0.62)
	PixelDraw.px_rect(canvas, -w * 0.52, -body_h + body_h * 0.62, w * 1.02, px, PixelPalette.shade(wood_dark, 0.78), 0.45)

	if not depleted:
		PixelDraw.px_rect(canvas, -px * 1.5, -body_h * 0.64, px * 3.0, px * 2.5, gold)
		PixelDraw.px_rect(canvas, -px * 0.5, -body_h * 0.26, px, px, PixelPalette.shade(wood_dark, 0.55))
		_coin(canvas, -w * 0.32, px * 0.9, 0.78)
		_coin(canvas, w * 0.24, px * 0.7, 0.70)
