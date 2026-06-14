extends RefCounted
class_name ChestArt
## A treasure chest built as an isometric box with pixel-art wood texture: a
## dithered coffer + overhanging lid, iron straps wrapping the faces, a vertical
## plank seam and a gold lock. `depleted` greys it to spent stone.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, size: float, color: Color, depleted: bool) -> void:
	var hw := size * 0.46
	var hh := hw * 0.5
	var body_h := size * 0.30
	var lid_h := size * 0.16
	PixelDraw.draw_foot_shadow(canvas, hw + 4.0, hh + 1.0, 0.3, body_h + lid_h)
	var c := PixelPalette.pal("stone_b") if depleted else color
	var iron := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.5)
	var px := float(PixelPalette.PX)
	# dithered wooden coffer + overhanging lid
	PixelDraw.iso_block_tex(canvas, 0.0, 0.0, hw, hh, body_h, c, 0)
	PixelDraw.iso_block_tex(canvas, 0.0, -body_h, hw + 1.0, hh + 0.5, lid_h, PixelPalette.shade(c, 1.06), 2)
	var cr := PixelDraw.iso_corners(0.0, 0.0, hw, hh)
	# iron straps + plank seams on the coffer faces
	for face: Array in [[cr[0], cr[1]], [cr[1], cr[2]]]:
		var a: Vector2 = face[0]
		var b: Vector2 = face[1]
		PixelDraw.iso_face_quad(canvas, a, b, body_h, 0.0, 1.0, 0.16, 0.30, iron, 0.85)
		PixelDraw.iso_face_quad(canvas, a, b, body_h, 0.0, 1.0, 0.66, 0.80, iron, 0.85)
		PixelDraw.iso_face_quad(canvas, a, b, body_h, 0.48, 0.52, 0.0, 1.0, PixelPalette.shade(c, 0.72), 0.5)
	if not depleted:
		# gold lock plate on the front seam
		PixelDraw.px_rect(canvas, -px, -body_h * 0.5, px * 2.0, px * 2.5, PixelPalette.pal("gold"))
		PixelDraw.px_rect(canvas, 0.0, -body_h * 0.5 + px, px, px, PixelPalette.pal("trunk_b"))
