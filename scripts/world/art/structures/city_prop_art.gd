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
		"well": _well(canvas, variant)
		"flowerbox": _flowerbox(canvas, variant)
		"hay": _hay(canvas, variant)
		"cart": _cart(canvas)
		_: _crate(canvas, variant)


static func _lamp(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 6.0, 3.0, 0.3, 40.0)
	PixelDraw.draw_ground_collar(canvas, 5.0, false)
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
	PixelDraw.draw_ground_collar(canvas, 9.0, false)
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
	PixelDraw.draw_ground_collar(canvas, 7.0, false)
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


static func _well(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 8.0, 0.3, 48.0)
	PixelDraw.draw_ground_collar(canvas, 18.0, false)
	var stone := PixelPalette.pal("stone_b")
	var stone_l := PixelPalette.pal("stone_a")
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.38)
	var dark := PixelPalette.hex(0x121118)
	var px := float(PixelPalette.PX)

	# Uneven stone curb: squat, chipped, and mossy rather than a clean square.
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 18.0, 9.0, 7.0, PixelPalette.shade(stone, 0.86), variant)
	PixelDraw.px_diamond(canvas, 0.0, -8.0, 11.0, 5.5, dark)
	PixelDraw.px_diamond(canvas, 0.0, -9.0, 16.0, 8.0, PixelPalette.shade(stone_l, 0.88), 0.55)
	PixelDraw.px_diamond(canvas, 0.0, -10.0, 10.0, 5.0, dark)
	PixelDraw.px_rect(canvas, -14.0, -10.0, 7.0, 4.0, PixelPalette.shade(stone_l, 1.08), 0.8)
	PixelDraw.px_rect(canvas, 8.0, -7.0, 8.0, 4.0, PixelPalette.shade(stone, 0.72), 0.85)
	PixelDraw.px_rect(canvas, -9.0, -16.0, 12.0, 4.0, moss, 0.58)
	PixelDraw.px_rect(canvas, 4.0, -15.0, 8.0, 4.0, moss, 0.42)

	# Crooked posts and crossbeam.
	PixelDraw.iso_block_tex(canvas, -13.0, -2.0, 2.0, 1.0, 34.0, PixelPalette.shade(wood_d, 0.92), 1)
	PixelDraw.iso_block_tex(canvas, 13.0, -2.0, 2.0, 1.0, 32.0, PixelPalette.shade(wood_d, 1.04), 3)
	PixelDraw.px_rect(canvas, -17.0, -40.0, 34.0, 5.0, wood_d)
	PixelDraw.px_rect(canvas, -14.0, -43.0, 28.0, 4.0, PixelPalette.shade(wood, 1.05))

	# Sagging shingle roof with patchy rows.
	var roof := PixelPalette.hex(0xA77A4E).lerp(PixelPalette.pal("trunk_a"), 0.25)
	for r: int in 5:
		var y := -58.0 + float(r) * px
		var half := 16.0 + float(r) * 2.5
		var col := PixelPalette.shade(roof, 1.12 - float(r) * 0.08)
		PixelDraw.px_row(canvas, 0.0, y, half, col)
		PixelDraw.px_rect(canvas, -half + 3.0 + float((r + variant) % 3) * px, y + px, px * 2.0, px, PixelPalette.shade(col, 0.72), 0.65)
	PixelDraw.px_rect(canvas, -4.0, -62.0, 8.0, 4.0, PixelPalette.shade(roof, 1.2))

	# Rope, handle and bucket.
	PixelDraw.px_rect(canvas, -px * 0.5, -39.0, px, 24.0, PixelPalette.shade(wood_d, 0.72), 0.75)
	PixelDraw.px_rect(canvas, 4.0, -38.0, 10.0, 3.0, wood_d, 0.9)
	PixelDraw.iso_block_tex(canvas, 0.0, -17.0, 5.0, 2.5, 7.0, PixelPalette.shade(wood, 0.82), 5)
	PixelDraw.px_rect(canvas, -3.0, -25.0, 6.0, 3.0, PixelPalette.shade(stone_l, 0.75), 0.75)


static func _flowerbox(canvas: CanvasItem, variant: int) -> void:
	PixelDraw.draw_foot_shadow(canvas, 10.0, 4.0, 0.3, 10.0)
	PixelDraw.draw_ground_collar(canvas, 10.0, false)
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
	PixelDraw.draw_foot_shadow(canvas, 18.0, 7.0, 0.3, 18.0)
	PixelDraw.draw_ground_collar(canvas, 16.0, false)
	var wood := PixelPalette.pal("trunk_a")
	var wood_d := PixelPalette.pal("trunk_b")
	var iron := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.6)
	# Two big bold wheels first, so the cart reads unmistakably even tiny.
	for wx: float in [-11.0, 11.0]:
		PixelDraw.px_blob(canvas, wx, -2.0, 7.0, 7.0, iron)
		PixelDraw.px_blob(canvas, wx, -2.0, 4.0, 4.0, PixelPalette.shade(wood_d, 1.05))
		PixelDraw.px_rect(canvas, wx - 1.0, -3.0, 2.0, 2.0, PixelPalette.shade(iron, 1.3))
	# Cart bed raised on the wheels: one chunky iso block.
	PixelDraw.iso_block_tex(canvas, 0.0, -7.0, 15.0, 7.0, 9.0, wood)
	# Bold side rail mass so the open bed is obvious.
	PixelDraw.px_rect(canvas, -15.0, -22.0, 30.0, 5.0, wood_d)
	PixelDraw.px_rect(canvas, -15.0, -22.0, 30.0, 2.0, PixelPalette.shade(wood, 1.15), 0.8)
	# Thick draw shaft.
	PixelDraw.px_rect(canvas, 14.0, -12.0, 11.0, 3.0, wood_d)
