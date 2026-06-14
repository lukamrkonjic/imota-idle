extends RefCounted
class_name RuinArchArt
## A grand, half-collapsed ceremonial gateway — the centrepiece of a ruined
## city — built from isometric blocks: two column prisms carry a snapped lintel
## beam. The variant decides whether the far column still stands (closed arch)
## or has toppled, plus the overall height.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	PixelDraw.draw_foot_shadow(canvas, 30.0, 8.0, 0.3, 92.0)
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.32)
	var vine := PixelPalette.pal("grass_c")
	var h := 84.0 + float(variant % 2) * 14.0
	var closed := variant % 3 == 0
	# left column (always tall)
	_column(canvas, -22.0, 4.0, h, stone)
	# lintel beam cantilevered off the left column top
	_lintel(canvas, -22.0, 18.0, -h, stone)
	if closed:
		# far column intact — completes the arch and carries the crown
		_column(canvas, 14.0, -4.0, h, stone)
		_lintel(canvas, 8.0, 14.0, -h, stone)
	else:
		# far column snapped short; lintel breaks off in mid-air
		_column(canvas, 14.0, -4.0, 40.0, stone)
		PixelDraw.iso_block_tex(canvas, 12.0, -h, 8.0, 4.0, 7.0, PixelPalette.shade(stone, 0.72))
	# overgrowth: moss band + hanging vines down the tall column
	PixelDraw.px_rect(canvas, -27.0, -h * 0.55, 12.0, 6.0, moss, 0.5)
	PixelDraw.px_rect(canvas, -16.0, -h + 8.0, 2.0, 20.0, vine, 0.5)
	PixelDraw.px_rect(canvas, -8.0, -h - 2.0, 2.0, 22.0, vine, 0.5)


static func _column(canvas: CanvasItem, x: float, z: float, h: float, stone: Color) -> void:
	# z nudges the screen-y of the base so the two columns sit at slightly
	# different isometric depths (far column a touch higher up the screen).
	PixelDraw.iso_block_tex(canvas, x, z, 10.0, 5.0, 8.0, PixelPalette.shade(stone, 0.9))   # base
	PixelDraw.iso_block_tex(canvas, x, z - 8.0, 7.0, 3.5, h - 8.0, stone)                    # shaft


static func _lintel(canvas: CanvasItem, x: float, half: float, top_y: float, stone: Color) -> void:
	# A short horizontal beam: a wide, shallow iso block sitting at the top.
	PixelDraw.iso_block_tex(canvas, x + half * 0.5, top_y - 3.0, half, half * 0.5, 9.0, PixelPalette.shade(stone, 1.0))
