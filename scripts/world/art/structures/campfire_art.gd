extends RefCounted
class_name CampfireArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 3.0)
	for i: int in 7:
		var a := float(i) / 7.0 * TAU
		PixelDraw.px_rect(canvas, cos(a) * 18.0 - 3.0, sin(a) * 5.0 - 2.0, 6.0, 5.0,
			PixelPalette.pal("stone_a") if i % 2 == 1 else PixelPalette.pal("stone_b"))
	var px := float(PixelPalette.PX)
	for log: Array in [[Vector2(-12, -2), Vector2(12, -6), PixelPalette.pal("trunk_a")], [Vector2(-12, -6), Vector2(12, -2), PixelPalette.pal("trunk_b")]]:
		var from: Vector2 = log[0]
		var to: Vector2 = log[1]
		for i: int in 7:
			var p := from.lerp(to, float(i) / 6.0)
			PixelDraw.px_rect(canvas, p.x - px, p.y - px, px * 2.0, px * 2.0, log[2])
	var flick := 1.0 + sin(t * 9.0) * 0.18
	var flame_h := PixelPalette.snap(22.0 * flick)
	var row := 0.0
	while row < flame_h:
		var t_row := row / flame_h
		var half := PixelPalette.snap(7.0 * (1.0 - t_row * 0.72))
		var y := -2.0 - row
		PixelDraw.px_row(canvas, 0.0, y, half,
			Color8(0xff, 0x7a, 0x1a) if row < flame_h * 0.55 else Color8(0xff, 0xd2, 0x4a))
		if row < flame_h * 0.35:
			PixelDraw.px_row(canvas, 0.0, y, half * 0.45, Color8(0xff, 0xe9, 0xa0), 0.75)
		row += PixelPalette.PX


