extends RefCounted
class_name CityWallArt
## Crenellated city rampart pieces built from isometric stone blocks with painted
## masonry (mortar courses + staggered joints + dither) so they read as
## hand-drawn pixel-art stonework, matching the buildings and the ruin family.
## `piece`:  0 wall segment   1 gatehouse (recessed arch + portcullis)   2 tower.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, piece: int) -> void:
	match piece:
		1: _draw_gate(canvas)
		2: _draw_tower(canvas)
		_: _draw_segment(canvas)


## A masonry block: textured iso block + mortar courses and staggered vertical
## joints painted onto its two camera-facing faces.
static func _masonry(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, base: Color, salt: int) -> void:
	PixelDraw.iso_block_tex(canvas, cx, cy, hw, hh, h, base, salt)
	var c := PixelDraw.iso_corners(cx, cy, hw, hh)
	var mortar := PixelPalette.shade(base, 0.58)
	var px := float(PixelPalette.PX)
	var rows := maxi(2, int(h / (px * 2.0)))            # 8 px courses
	for face: Array in [[c[0], c[1]], [c[1], c[2]]]:
		var a: Vector2 = face[0]
		var b: Vector2 = face[1]
		var jw := px / maxf(a.distance_to(b), 1.0)
		var mv := px / h
		for r: int in rows:
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			PixelDraw.iso_face_quad(canvas, a, b, h, 0.0, 1.0, v1 - mv, v1, mortar, 0.5)
			var stag := 0.5 * float(r % 2)
			for j: int in 4:
				var u := fmod(float(j) / 3.0 + stag, 1.0)
				PixelDraw.iso_face_quad(canvas, a, b, h, u, u + jw, v0, v1 - mv, mortar, 0.4)


## Battlement merlons marching across the top of a block, every other slot.
static func _battlements(canvas: CanvasItem, cx: float, top_y: float, hw: float, stone: Color) -> void:
	var n := int(hw / 5.0)
	for i: int in range(-n, n + 1):
		if i % 2 == 0:
			PixelDraw.iso_block_tex(canvas, cx + float(i) * 5.0, top_y, 2.5, 1.25, 6.0, stone, i)


static func _draw_segment(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 11.0, 0.3, 34.0)
	var stone := PixelPalette.pal("stone_b")
	var h := 30.0
	_masonry(canvas, 0.0, 0.0, 20.0, 10.0, h, stone, 0)
	_battlements(canvas, 0.0, -h, 20.0, stone)


static func _draw_tower(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 9.0, 0.3, 54.0)
	var stone := PixelPalette.pal("stone_b")
	var flag := PixelPalette.pal("outfit_a")
	var h := 50.0
	_masonry(canvas, 0.0, 0.0, 13.0, 6.5, h, stone, 5)
	_battlements(canvas, 0.0, -h, 13.0, stone)
	# flagpole + pennant
	PixelDraw.px_rect(canvas, -1.0, -h - 16.0, 2.0, 14.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, 1.0, -h - 16.0, 9.0, 6.0, flag)


static func _draw_gate(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 28.0, 13.0, 0.3, 50.0)
	var stone := PixelPalette.pal("stone_b")
	var h := 40.0
	# solid gatehouse spanning the tile (so the doorway is a recess, never a
	# floating black box), with taller tower caps at each end
	_masonry(canvas, 0.0, 0.0, 22.0, 11.0, h, stone, 3)
	_masonry(canvas, -17.0, -3.0, 6.0, 3.0, h + 10.0, stone, 7)
	_masonry(canvas, 17.0, -3.0, 6.0, 3.0, h + 10.0, stone, 9)
	_battlements(canvas, 0.0, -h, 14.0, stone)
	# recessed arched gateway carved into the front face
	var aw := 8.0
	var ah := 24.0
	# lighter stone voussoir ring
	PixelDraw.px_rect(canvas, -aw - 2.0, -ah - 1.0, (aw + 2.0) * 2.0, ah + 1.0, PixelPalette.shade(stone, 1.08))
	PixelDraw.px_diamond(canvas, 0.0, -ah - 1.0, aw + 2.0, (aw + 2.0) * 0.65, PixelPalette.shade(stone, 1.08))
	# dark tunnel
	var dark := PixelPalette.hex(0x1A1820)
	PixelDraw.px_rect(canvas, -aw, -ah + 2.0, aw * 2.0, ah - 2.0, dark)
	PixelDraw.px_diamond(canvas, 0.0, -ah + 2.0, aw, aw * 0.65, dark)
	# portcullis bars
	for i: int in 3:
		PixelDraw.px_rect(canvas, -aw + 2.0 + float(i) * 5.0, -ah + 4.0, 1.5, ah - 6.0, PixelPalette.shade(stone, 0.7), 0.8)
	PixelDraw.px_rect(canvas, -aw, -ah * 0.55, aw * 2.0, 1.5, PixelPalette.shade(stone, 0.7), 0.8)
	# hanging banners on the towers
	var banner := PixelPalette.pal("water_a").lerp(PixelPalette.pal("outfit_a"), 0.35)
	PixelDraw.px_rect(canvas, -19.0, -h + 6.0, 5.0, 16.0, banner, 0.92)
	PixelDraw.px_rect(canvas, 14.0, -h + 6.0, 5.0, 16.0, banner, 0.92)
