extends RefCounted
class_name MammothArt
## A mammoth frozen mid-stride inside a block of glacier ice. The beast is drawn
## first, then glazed by a translucent isometric ice prism so it reads as a solid
## frozen block sitting in the snow rather than a flat pane.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem) -> void:
	PixelDraw.draw_tight_character_shadow(canvas, 26.0, 6.0)
	var fur := Color(0.28, 0.2, 0.16)
	var tusk := Color8(0xf0, 0xea, 0xd8)
	# the mammoth, suspended inside the block (drawn before the glaze)
	PixelDraw.px_blob(canvas, -2.0, -20.0, 16.0, 12.0, fur)       # body
	PixelDraw.px_blob(canvas, 13.0, -26.0, 8.0, 7.0, fur)        # head
	PixelDraw.px_rect(canvas, -12.0, -10.0, 3.0, 10.0, fur, 0.85) # legs
	PixelDraw.px_rect(canvas, 4.0, -10.0, 3.0, 10.0, fur, 0.85)
	PixelDraw.px_rect(canvas, 16.0, -22.0, 9.0, 3.0, tusk, 0.95)  # tusks
	PixelDraw.px_rect(canvas, 20.0, -19.0, 5.0, 3.0, tusk, 0.95)
	# translucent ice prism glazing the whole thing
	var top := Color(0.82, 0.92, 0.98, 0.55)
	var lit := Color(0.66, 0.82, 0.92, 0.50)
	var sh := Color(0.50, 0.66, 0.80, 0.50)
	PixelDraw.iso_box(canvas, 0.0, 0.0, 22.0, 11.0, 40.0, top, lit, sh)
	# frosty highlight streaks on the lit edge
	PixelDraw.px_rect(canvas, -18.0, -36.0, 5.0, 32.0, Color(0.92, 0.97, 1.0), 0.22)
	PixelDraw.px_rect(canvas, 6.0, -30.0, 3.0, 24.0, Color(0.92, 0.97, 1.0), 0.16)
