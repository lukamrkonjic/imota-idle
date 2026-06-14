extends RefCounted
class_name CityWallArt
## Reusable crenellated city rampart pieces. The `piece` arg selects:
##   0 wall segment   1 gate (arched opening + banners)   2 corner tower
## Drawn front-facing; a ring of segments reads as an enclosing stone wall.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const SEGMENT := 0
const GATE := 1
const TOWER := 2


static func draw(canvas: CanvasItem, piece: int) -> void:
	match piece:
		GATE: _draw_gate(canvas)
		TOWER: _draw_tower(canvas)
		_: _draw_segment(canvas)


static func _battlements(canvas: CanvasItem, x0: float, w: float, top: float, stone: Color, stone_hi: Color) -> void:
	var mx := x0
	var i := 0
	while mx < x0 + w:
		if i % 2 == 0:
			PixelDraw.px_rect(canvas, mx, top - 6.0, 6.0, 6.0, stone)
			PixelDraw.px_rect(canvas, mx, top - 6.0, 6.0, 2.0, stone_hi)
		mx += 6.0
		i += 1


static func _draw_segment(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 5.0, 0.3, 30.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var h := 30.0
	PixelDraw.px_rect(canvas, -20.0, -h, 40.0, h, stone)
	PixelDraw.px_rect(canvas, -20.0, -h, 40.0, 3.0, stone_hi)
	PixelDraw.px_rect(canvas, -20.0, -h, 4.0, h, stone_hi)
	# stone coursing
	var cy := -h + 7.0
	while cy < -3.0:
		PixelDraw.px_rect(canvas, -20.0, cy, 40.0, 1.0, PixelPalette.shade(stone, 0.78), 0.5)
		cy += 7.0
	_battlements(canvas, -20.0, 40.0, -h, stone, stone_hi)


static func _draw_gate(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 26.0, 6.0, 0.3, 46.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var banner := PixelPalette.pal("water_a").lerp(PixelPalette.pal("outfit_a"), 0.35)
	var h := 46.0
	# twin towers flanking the opening
	for sx: float in [-26.0, 14.0]:
		PixelDraw.px_rect(canvas, sx, -h, 12.0, h, stone)
		PixelDraw.px_rect(canvas, sx, -h, 4.0, h, stone_hi)
		_battlements(canvas, sx, 12.0, -h, stone, stone_hi)
	# arch lintel over the road
	PixelDraw.px_rect(canvas, -14.0, -h, 28.0, 8.0, stone)
	PixelDraw.px_rect(canvas, -14.0, -h, 28.0, 3.0, stone_hi)
	# hanging banners
	PixelDraw.px_rect(canvas, -20.0, -h + 8.0, 5.0, 16.0, banner, 0.92)
	PixelDraw.px_rect(canvas, 15.0, -h + 8.0, 5.0, 16.0, banner, 0.92)


static func _draw_tower(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 18.0, 5.0, 0.3, 52.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	var flag := PixelPalette.pal("outfit_a")
	var h := 50.0
	PixelDraw.px_rect(canvas, -13.0, -h, 26.0, h, stone)
	PixelDraw.px_rect(canvas, -13.0, -h, 5.0, h, stone_hi)
	var cy := -h + 8.0
	while cy < -4.0:
		PixelDraw.px_rect(canvas, -13.0, cy, 26.0, 1.0, PixelPalette.shade(stone, 0.78), 0.5)
		cy += 8.0
	_battlements(canvas, -14.0, 28.0, -h, stone, stone_hi)
	# flagpole + pennant
	PixelDraw.px_rect(canvas, -1.0, -h - 14.0, 2.0, 14.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, 1.0, -h - 14.0, 9.0, 6.0, flag)
