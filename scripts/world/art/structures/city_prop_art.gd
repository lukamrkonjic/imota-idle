extends RefCounted
class_name CityPropArt
## Small outdoor street clutter that breaks up the bare paving — lamp posts,
## crates, barrels, wells, flower boxes, hay and carts. `kind` selects the prop.
## Solid props are built from isometric blocks (like the ruin family); the hay
## pile stays an organic blob.

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
	# iron post (thin iso block) on a small base
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 4.0, 2.0, 3.0, iron)
	PixelDraw.iso_block_tex(canvas, 0.0, -3.0, 1.5, 0.75, 34.0, iron)
	# lantern housing
	PixelDraw.iso_block_tex(canvas, 0.0, -37.0, 5.0, 2.5, 8.0, iron)
	var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("outfit_a"), 0.2)
	var pulse := 0.7 + sin(t * 3.0) * 0.18
	PixelDraw.px_rect(canvas, -3.0, -44.0, 6.0, 5.0, glow, pulse)
	PixelDraw.px_blob(canvas, 0.0, -41.0, 12.0, 9.0, glow, 0.12 * pulse)


static func _crate(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 10.0, 4.0, 0.3, 18.0)
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	var s := 1.0 + float(variant % 2) * 0.3
	var hw := 9.0 * s
	var hh := hw * 0.5
	var ht := 15.0 * s
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, hw, hh, ht, wood)
	# slat lines on the lit face
	PixelDraw.px_rect(canvas, -1.0, -ht + 2.0, 2.0, ht - 4.0, wood_d, 0.7)
	PixelDraw.px_rect(canvas, 2.0, -ht * 0.55, hw - 2.0, 2.0, wood_d, 0.6)


static func _barrel(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 8.0, 4.0, 0.3, 18.0)
	var wood := PixelPalette.shade(PixelPalette.pal("trunk_a"), 0.95)
	var hoop := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.8)
	# drum body as an iso block, lid diamond on top
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 7.0, 3.5, 16.0, wood)
	PixelDraw.px_diamond(canvas, 0.0, -16.0, 7.0, 3.5, PixelPalette.shade(wood, 1.12))
	# iron hoops wrapping the lit face
	PixelDraw.px_rect(canvas, 0.0, -13.0, 7.0, 2.0, hoop)
	PixelDraw.px_rect(canvas, 0.0, -5.0, 7.0, 2.0, hoop)
	if variant % 2 == 0:
		PixelDraw.px_rect(canvas, 1.0, -15.0, 2.0, 14.0, PixelPalette.shade(wood, 1.1), 0.5)


static func _well(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 14.0, 7.0, 0.3, 34.0)
	var stone := PixelPalette.pal("stone_b")
	# stone curb as a low iso ring, dark shaft inside
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 16.0, 8.0, 6.0, PixelPalette.shade(stone, 0.88))
	PixelDraw.px_diamond(canvas, 0.0, -6.0, 9.0, 4.5, Color(0.10, 0.10, 0.14))
	# posts + roof
	PixelDraw.iso_block_tex(canvas, -12.0, -2.0, 1.5, 0.75, 26.0, PixelPalette.pal("trunk_b"))
	PixelDraw.iso_block_tex(canvas, 12.0, -2.0, 1.5, 0.75, 26.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_diamond(canvas, 0.0, -34.0, 18.0, 8.0, PixelPalette.shade(PixelPalette.pal("trunk_a"), 0.8))


static func _flowerbox(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 10.0, 4.0, 0.3, 10.0)
	var wood := PixelPalette.pal("trunk_b")
	# planter as a low iso box
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 10.0, 5.0, 7.0, wood)
	var cols := [PixelPalette.pal("outfit_a"), PixelPalette.pal("gold"), PixelPalette.pal("water_a")]
	for i: int in 5:
		var fx := -8.0 + float(i) * 4.0
		PixelDraw.px_rect(canvas, fx, -14.0, 2.0, 5.0, PixelPalette.pal("grass_b"))
		PixelDraw.px_rect(canvas, fx - 1.0, -18.0, 4.0, 4.0, cols[(i + variant) % cols.size()], 0.95)


static func _hay(canvas: CanvasItem, _variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 11.0, 4.0, 0.3, 12.0)
	var hay := PixelPalette.pal("gold").lerp(PixelPalette.pal("trunk_a"), 0.3)
	PixelDraw.px_blob(canvas, 0.0, -6.0, 13.0, 9.0, hay)
	PixelDraw.px_blob(canvas, 0.0, -12.0, 9.0, 6.0, PixelPalette.shade(hay, 1.08))
	for i: int in 4:
		PixelDraw.px_rect(canvas, -11.0 + float(i) * 6.0, -4.0, 1.0, 6.0, PixelPalette.shade(hay, 0.8), 0.6)


static func _cart(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 6.0, 0.3, 16.0)
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	# cart bed as an iso block raised on wheels
	PixelDraw.iso_block_tex(canvas, 0.0, -4.0, 15.0, 7.0, 8.0, wood)
	PixelDraw.px_blob(canvas, -10.0, -1.0, 5.0, 5.0, wood_d)
	PixelDraw.px_blob(canvas, 10.0, -1.0, 5.0, 5.0, wood_d)
	PixelDraw.px_rect(canvas, 15.0, -10.0, 8.0, 2.0, wood_d)        # shaft
