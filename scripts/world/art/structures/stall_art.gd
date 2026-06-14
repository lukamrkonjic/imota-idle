extends RefCounted
class_name StallArt
## A market stall: a dithered isometric wooden counter (with plank seams) on
## corner posts under a striped cloth awning, goods set on top. The awning is a
## hanging cloth (a flat plane is right for fabric); the solid timber is textured
## pixel-art iso blocks like the rest of the world.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 20.0, 8.0, 0.3, 28.0)
	PixelDraw.draw_ground_collar(canvas, 18.0, false)
	var wood := PixelPalette.hex(0x8A6848)
	var red := Color8(0xc0, 0x4a, 0x3a)
	var cream := Color8(0xe8, 0xdc, 0xc0)
	# corner posts holding up the awning
	PixelDraw.iso_block_tex(canvas, -14.0, -1.0, 1.5, 1.0, 28.0, PixelPalette.shade(wood, 0.8), 1)
	PixelDraw.iso_block_tex(canvas, 14.0, -1.0, 1.5, 1.0, 28.0, PixelPalette.shade(wood, 0.8), 3)
	# counter prism + plank seams
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, 16.0, 8.0, 12.0, wood, 0)
	var cr := PixelDraw.iso_corners(0.0, 0.0, 16.0, 8.0)
	for face: Array in [[cr[0], cr[1]], [cr[1], cr[2]]]:
		for u: float in [0.33, 0.66]:
			PixelDraw.iso_face_quad(canvas, face[0], face[1], 12.0, u, u + 0.03, 0.0, 1.0, PixelPalette.shade(wood, 0.74), 0.5)
	# striped cloth awning draped above
	var x := -20.0
	var i := 0
	while x < 20.0:
		PixelDraw.px_rect(canvas, x, -30.0, 5.0, 9.0, red if i % 2 == 0 else cream)
		x += 5.0
		i += 1
	PixelDraw.px_rect(canvas, -20.0, -31.0, 40.0, 3.0, PixelPalette.shade(red, 0.8))
	# goods on the counter top
	PixelDraw.px_rect(canvas, -9.0, -16.0, 6.0, 4.0, Color8(0xf0, 0xd0, 0x50))
	PixelDraw.px_rect(canvas, 3.0, -16.0, 5.0, 4.0, Color8(0xe0, 0x80, 0xa0))
