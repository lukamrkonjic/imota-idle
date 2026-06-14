extends RefCounted
class_name CityWallArt
## City rampart pieces rebuilt as bold blocky masonry to match the pillar/altar
## set: large iso-block masses, a couple of broad shade bands, and a few fat
## chunky merlons. No brick-by-brick mortar grid or tiny crenellation detail.
## `piece`: 0 wall segment, 1 gatehouse, 2 tower.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, piece: int) -> void:
	match piece:
		1: _draw_gate(canvas)
		2: _draw_tower(canvas)
		_: _draw_segment(canvas)


## One big stone mass with two broad value bands painted across the lit/shadow
## faces — chunky low-res stonework instead of a per-brick mortar grid.
static func _stone_mass(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, base: Color, salt: int) -> void:
	PixelDraw.iso_block_tex(canvas, cx, cy, hw, hh, h, base, salt)
	var c := PixelDraw.iso_corners(cx, cy, hw, hh)
	# Two broad horizontal courses: one light, one shadowed — bold, not fine.
	for face: Array in [[c[0], c[1], 1.12], [c[1], c[2], 0.78]]:
		var a: Vector2 = face[0]
		var b: Vector2 = face[1]
		var tone: float = face[2]
		PixelDraw.iso_face_quad(canvas, a, b, h, 0.0, 1.0, 0.30, 0.42, PixelPalette.shade(base, tone), 0.4)
		PixelDraw.iso_face_quad(canvas, a, b, h, 0.0, 1.0, 0.66, 0.76, PixelPalette.shade(base, tone), 0.3)


## A few fat merlons spaced wide apart.
static func _battlements(canvas: CanvasItem, cx: float, top_y: float, hw: float, stone: Color) -> void:
	var step := 9.0
	var n := int(hw / step)
	for i: int in range(-n, n + 1):
		PixelDraw.iso_block_tex(canvas, cx + float(i) * step, top_y, 4.0, 2.0, 7.0, stone, i)


static func _draw_segment(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 11.0, 0.3, 38.0)
	PixelDraw.draw_ground_collar(canvas, 20.0, true, 7)
	var stone := PixelPalette.pal("stone_b")
	var h := 30.0
	_stone_mass(canvas, 0.0, 0.0, 18.0, 9.0, h, stone, 0)
	PixelDraw.iso_block_tex(canvas, 0.0, -h, 20.0, 10.0, 5.0, PixelPalette.shade(stone, 1.08), 8)
	_battlements(canvas, 0.0, -h - 5.0, 18.0, stone)


static func _draw_tower(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 9.0, 0.3, 64.0)
	PixelDraw.draw_ground_collar(canvas, 15.0, true)
	var stone := PixelPalette.pal("stone_b")
	var flag := PixelPalette.pal("outfit_a")
	var h := 50.0
	# Thick squat tower — fewer, larger masses.
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 16.0, 8.0, 8.0, PixelPalette.shade(stone, 0.84), 2)
	_stone_mass(canvas, 0.0, -8.0, 14.0, 7.0, h, stone, 5)
	PixelDraw.iso_block_tex(canvas, 0.0, -h - 8.0, 16.0, 8.0, 6.0, PixelPalette.shade(stone, 1.08), 8)
	_battlements(canvas, 0.0, -h - 14.0, 15.0, stone)
	# One big dark window slit.
	PixelDraw.px_rect(canvas, -3.0, -h * 0.62, 6.0, 12.0, PixelPalette.hex(0x1A1820))
	# Flag.
	PixelDraw.px_rect(canvas, -1.0, -h - 30.0, 2.0, 16.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, 1.0, -h - 30.0, 10.0, 7.0, flag)


static func _draw_gate(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 28.0, 13.0, 0.3, 58.0)
	PixelDraw.draw_ground_collar(canvas, 24.0, true, 7)
	var stone := PixelPalette.pal("stone_b")
	var h := 40.0
	# Big central block flanked by two fat towers.
	_stone_mass(canvas, 0.0, 0.0, 22.0, 11.0, h, stone, 3)
	_stone_mass(canvas, -18.0, -3.0, 7.0, 3.5, h + 12.0, PixelPalette.shade(stone, 0.94), 7)
	_stone_mass(canvas, 18.0, -3.0, 7.0, 3.5, h + 12.0, PixelPalette.shade(stone, 0.98), 9)
	PixelDraw.iso_block_tex(canvas, 0.0, -h, 23.0, 11.5, 5.0, PixelPalette.shade(stone, 1.08), 10)
	_battlements(canvas, 0.0, -h - 5.0, 14.0, stone)

	# Simple bold dark archway opening — one chunky dark mass.
	var aw := 9.0
	var ah := 26.0
	PixelDraw.px_rect(canvas, -aw - 3.0, -ah, (aw + 3.0) * 2.0, ah, PixelPalette.shade(stone, 1.1))
	var dark := PixelPalette.hex(0x14121A)
	PixelDraw.px_rect(canvas, -aw, -ah + 3.0, aw * 2.0, ah - 3.0, dark)
	PixelDraw.px_diamond(canvas, 0.0, -ah + 3.0, aw, aw * 0.6, dark)

	var banner := PixelPalette.pal("water_a").lerp(PixelPalette.pal("outfit_a"), 0.35)
	PixelDraw.px_rect(canvas, -21.0, -h + 6.0, 6.0, 18.0, banner, 0.92)
	PixelDraw.px_rect(canvas, 15.0, -h + 6.0, 6.0, 18.0, banner, 0.92)
