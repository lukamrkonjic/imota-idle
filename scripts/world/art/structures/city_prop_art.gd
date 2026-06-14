extends RefCounted
class_name CityPropArt
## Small outdoor street clutter that breaks up the bare paving — lamp posts,
## crates, barrels, wells, flower boxes, hay and carts. `kind` selects the prop.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, kind: String, variant: int, t: float) -> void:
	match kind:
		"lamp": _lamp(canvas, t)
		"crate": _crate(canvas, variant)
		"barrel": _barrel(canvas, variant)
		"well": _well(canvas)
		"flowerbox": _flowerbox(canvas, variant)
		"hay": _hay(canvas, variant)
		"cart": _cart(canvas)
		_: _crate(canvas, variant)


static func _lamp(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 6.0, 3.0, 0.3, 40.0)
	var iron := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.7)
	PixelDraw.px_rect(canvas, -2.0, -34.0, 4.0, 34.0, iron)
	PixelDraw.px_rect(canvas, -4.0, -2.0, 8.0, 3.0, iron)            # base
	PixelDraw.px_rect(canvas, -5.0, -42.0, 10.0, 8.0, iron)         # lantern housing
	var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("outfit_a"), 0.2)
	var pulse := 0.7 + sin(t * 3.0) * 0.18
	PixelDraw.px_rect(canvas, -3.0, -40.0, 6.0, 5.0, glow, pulse)
	PixelDraw.px_blob(canvas, 0.0, -37.0, 12.0, 9.0, glow, 0.12 * pulse)


static func _crate(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 9.0, 3.0, 0.3, 16.0)
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	var s := 1.0 + float(variant % 2) * 0.3
	PixelDraw.px_rect(canvas, -9.0 * s, -16.0 * s, 18.0 * s, 16.0 * s, wood)
	PixelDraw.px_rect(canvas, -9.0 * s, -16.0 * s, 18.0 * s, 3.0, PixelPalette.shade(wood, 1.12))
	PixelDraw.px_rect(canvas, -2.0 * s, -16.0 * s, 3.0, 16.0 * s, wood_d)
	PixelDraw.px_rect(canvas, -9.0 * s, -9.0 * s, 18.0 * s, 2.0, wood_d)


static func _barrel(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 7.0, 3.0, 0.3, 18.0)
	var wood := PixelPalette.shade(PixelPalette.pal("trunk_a"), 0.95)
	var hoop := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.8)
	PixelDraw.px_rect(canvas, -7.0, -18.0, 14.0, 18.0, wood)
	PixelDraw.px_rect(canvas, -8.0, -14.0, 16.0, 2.0, hoop)
	PixelDraw.px_rect(canvas, -8.0, -6.0, 16.0, 2.0, hoop)
	PixelDraw.px_diamond(canvas, 0.0, -18.0, 7.0, 3.5, PixelPalette.shade(wood, 1.1))
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, -6.0, -18.0, 4.0, 18.0, PixelPalette.shade(wood, 1.08), 0.5)


static func _well(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 14.0, 5.0, 0.3, 34.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	PixelDraw.px_diamond(canvas, 0.0, 0.0, 16.0, 8.0, PixelPalette.shade(stone, 0.85))
	PixelDraw.px_diamond(canvas, 0.0, -2.0, 13.0, 6.5, stone_hi)
	PixelDraw.px_diamond(canvas, 0.0, -3.0, 9.0, 4.5, Color(0.12, 0.12, 0.16))
	# posts + roof
	PixelDraw.px_rect(canvas, -13.0, -30.0, 3.0, 28.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, 10.0, -30.0, 3.0, 28.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_diamond(canvas, 0.0, -34.0, 18.0, 8.0, PixelPalette.shade(PixelPalette.pal("trunk_a"), 0.8))


static func _flowerbox(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 9.0, 3.0, 0.3, 8.0)
	var wood := PixelPalette.pal("trunk_b")
	PixelDraw.px_rect(canvas, -10.0, -7.0, 20.0, 7.0, wood)
	PixelDraw.px_rect(canvas, -10.0, -7.0, 20.0, 2.0, PixelPalette.shade(wood, 1.15))
	var cols := [PixelPalette.pal("outfit_a"), PixelPalette.pal("gold"), PixelPalette.pal("water_a")]
	for i: int in 5:
		var fx := -8.0 + float(i) * 4.0
		PixelDraw.px_rect(canvas, fx, -8.0, 2.0, 4.0, PixelPalette.pal("grass_b"))
		PixelDraw.px_rect(canvas, fx - 1.0, -12.0, 4.0, 4.0, cols[(i + variant) % cols.size()], 0.95)


static func _hay(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 11.0, 4.0, 0.3, 12.0)
	var hay := PixelPalette.pal("gold").lerp(PixelPalette.pal("trunk_a"), 0.3)
	PixelDraw.px_blob(canvas, 0.0, -6.0, 13.0, 9.0, hay)
	PixelDraw.px_blob(canvas, 0.0, -12.0, 9.0, 6.0, PixelPalette.shade(hay, 1.08))
	for i: int in 4:
		PixelDraw.px_rect(canvas, -11.0 + float(i) * 6.0, -4.0, 1.0, 6.0, PixelPalette.shade(hay, 0.8), 0.6)


static func _cart(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 4.0, 0.3, 14.0)
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	PixelDraw.px_rect(canvas, -16.0, -14.0, 32.0, 8.0, wood)
	PixelDraw.px_rect(canvas, -16.0, -16.0, 32.0, 3.0, PixelPalette.shade(wood, 1.1))
	PixelDraw.px_blob(canvas, -10.0, -2.0, 5.0, 5.0, wood_d)
	PixelDraw.px_blob(canvas, 10.0, -2.0, 5.0, 5.0, wood_d)
	PixelDraw.px_rect(canvas, 16.0, -12.0, 8.0, 2.0, wood_d)        # shaft
