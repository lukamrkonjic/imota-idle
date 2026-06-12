extends RefCounted
# Archived structure draw implementations for tools/split_structure_art.py

static func draw_tent(canvas: CanvasItem, size: float, color: Color) -> void:
	var w := PixelPalette.snap(size)
	var hgt := PixelPalette.snap(size * 0.95)
	PixelDraw.draw_foot_shadow(canvas, w * 0.85)
	var row := 0.0
	while row < hgt:
		var t := row / hgt
		var half := PixelPalette.snap(w * (1.0 - t))
		PixelDraw.px_row(canvas, 0.0, -row, half, PixelPalette.shade(color, 1.05 - t * 0.12))
		PixelDraw.px_row(canvas, 0.0, -row, half * 0.42, PixelPalette.shade(color, 0.78 - t * 0.08), 0.85)
		row += PixelPalette.PX
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -px * 2.0, -px * 2.0, px * 4.0, px * 4.0, Color(0.16, 0.11, 0.07), 0.85)
	PixelDraw.px_rect(canvas, -w - px * 2.0, 0.0, px * 2.0, px * 3.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, w, 0.0, px * 2.0, px * 3.0, PixelPalette.pal("trunk_b"))


static func draw_campfire(canvas: CanvasItem, t: float) -> void:
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


static func draw_lantern(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 7.0, 2.0)
	var lantern := PixelPalette.hex(0xF0C848)
	PixelDraw.px_rect(canvas, -1.0, -2.0, 2.0, 10.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, -6.0, -14.0, 12.0, 12.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -5.0, -13.0, 10.0, 10.0, lantern, 0.9)
	PixelDraw.px_rect(canvas, -3.0, -11.0, 6.0, 6.0, Color8(0xff, 0xf0, 0xa0), 0.55)
	PixelDraw.px_rect(canvas, -1.0, -9.0, 2.0, 2.0, Color.WHITE, 0.7)
	PixelDraw.px_rect(canvas, -8.0, -12.0, 2.0, 2.0, lantern, 0.25)
	PixelDraw.px_rect(canvas, 6.0, -10.0, 2.0, 2.0, lantern, 0.2)


static func draw_sign(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 12.0, 3.0)
	var wood_a := PixelPalette.hex(0x8A6848)
	var wood_b := PixelPalette.hex(0x6A4830)
	var sand_a := PixelPalette.hex(0xC4A060)
	PixelDraw.px_rect(canvas, -2.0, -16.0, 4.0, 16.0, wood_b)
	PixelDraw.px_rect(canvas, -18.0, -22.0, 36.0, 12.0, wood_a)
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 8.0, sand_a)
	PixelDraw.px_rect(canvas, -14.0, -18.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -14.0, -14.0, 28.0, 2.0, PixelPalette.pal("trunk_b"), 0.6)
	PixelDraw.px_rect(canvas, -15.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, 13.0, -19.0, 2.0, 2.0, PixelPalette.pal("stone_b"))


static func draw_chest(canvas: CanvasItem, size: float, color: Color, depleted: bool) -> void:
	PixelDraw.draw_foot_shadow(canvas, size * 0.52, 4.0)
	var w := PixelPalette.snap(size * 0.72)
	var h := PixelPalette.snap(size * 0.48)
	var c := PixelPalette.pal("stone_b") if depleted else color
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, -w, -h, w * 2.0, h, c)
	PixelDraw.px_rect(canvas, w - px * 2.0, -h + px, px * 2.0, h - px, PixelPalette.shade(c, 0.72))
	PixelDraw.px_rect(canvas, -w, -h, px * 2.0, h, PixelPalette.shade(c, 1.1))
	PixelDraw.px_rect(canvas, -w, -h, w * 2.0, px * 3.0, PixelPalette.shade(c, 1.08))
	PixelDraw.px_rect(canvas, -w, -h * 0.55, w * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -w, -h * 0.15, w * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))
	if not depleted:
		PixelDraw.px_rect(canvas, -px * 3.0, -h * 0.42, px * 6.0, px * 4.0, PixelPalette.pal("gold"))
		PixelDraw.px_rect(canvas, -px, -h * 0.38, px * 2.0, px * 2.0, PixelPalette.pal("trunk_b"))


static func draw_anvil(canvas: CanvasItem, t: float) -> void:
	PixelDraw.draw_foot_shadow(canvas, 20.0, 3.0)
	var iron := Color(0.30, 0.30, 0.34)
	var iron_hi := Color(0.42, 0.42, 0.47)
	PixelDraw.px_rect(canvas, -10.0, -10.0, 20.0, 10.0, PixelPalette.pal("stone_b"))
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 10.0, iron)
	PixelDraw.px_rect(canvas, -16.0, -20.0, 32.0, 3.0, iron_hi)
	PixelDraw.px_rect(canvas, 16.0, -18.0, 8.0, 5.0, iron)
	var glow := 0.5 + sin(t * 5.0) * 0.25
	PixelDraw.px_rect(canvas, -4.0, -24.0, 6.0, 4.0, Color8(0xff, 0x66, 0x22), glow)


static func draw_altar(canvas: CanvasItem, t: float, glow_color: Color) -> void:
	PixelDraw.draw_foot_shadow(canvas, 22.0, 4.0)
	var stone := PixelPalette.pal("stone_b")
	var stone_hi := PixelPalette.pal("stone_a")
	PixelDraw.px_rect(canvas, -18.0, -10.0, 36.0, 10.0, stone)
	PixelDraw.px_rect(canvas, -14.0, -22.0, 28.0, 12.0, stone_hi)
	PixelDraw.px_rect(canvas, -14.0, -22.0, 28.0, 3.0, PixelPalette.shade(stone_hi, 1.18))
	var pulse := 0.55 + sin(t * 2.2) * 0.25
	PixelDraw.px_rect(canvas, -8.0, -28.0, 16.0, 6.0, glow_color, pulse)
	PixelDraw.px_rect(canvas, -3.0, -32.0, 6.0, 4.0, glow_color.lightened(0.3), pulse * 0.8)


static func draw_obelisk(canvas: CanvasItem, t: float, attuned: bool) -> void:
	PixelDraw.draw_foot_shadow(canvas, 16.0, 4.0)
	var stone := Color(0.36, 0.34, 0.44)
	var edge := Color(0.48, 0.46, 0.58)
	PixelDraw.px_rect(canvas, -12.0, -8.0, 24.0, 8.0, PixelPalette.shade(stone, 0.8))
	PixelDraw.px_rect(canvas, -8.0, -52.0, 16.0, 44.0, stone)
	PixelDraw.px_rect(canvas, -8.0, -52.0, 4.0, 44.0, edge)
	PixelDraw.px_rect(canvas, -4.0, -60.0, 8.0, 8.0, stone)
	var glow := Color(0.85, 0.4, 0.9) if attuned else Color(0.4, 0.5, 0.6)
	var pulse := 0.5 + sin(t * 3.0) * 0.3
	PixelDraw.px_rect(canvas, -2.0, -46.0 + sin(t * 2.0) * 3.0, 4.0, 4.0, glow, pulse)
	PixelDraw.px_rect(canvas, -2.0, -34.0 + sin(t * 2.0 + 1.7) * 3.0, 4.0, 4.0, glow, pulse * 0.8)


static func draw_cave_mouth(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 26.0, 5.0)
	var rock_a := PixelPalette.pal("stone_a")
	var rock_b := PixelPalette.pal("stone_b")
	PixelDraw.px_blob(canvas, 0.0, -14.0, 28.0, 18.0, rock_b)
	PixelDraw.px_blob(canvas, -6.0, -20.0, 18.0, 12.0, rock_a)
	PixelDraw.px_rect(canvas, -10.0, -16.0, 20.0, 16.0, Color(0.06, 0.05, 0.08))
	PixelDraw.px_rect(canvas, -6.0, -20.0, 12.0, 4.0, Color(0.06, 0.05, 0.08))
	PixelDraw.px_rect(canvas, 12.0, -8.0, 6.0, 6.0, rock_a, 0.8)
	PixelDraw.px_rect(canvas, -18.0, -6.0, 5.0, 5.0, rock_a, 0.7)


static func draw_ladder(canvas: CanvasItem, up: bool) -> void:
	var wood := PixelPalette.hex(0x8A6848)
	var dark := PixelPalette.pal("trunk_b")
	if up:
		PixelDraw.draw_foot_shadow(canvas, 12.0, 3.0)
		PixelDraw.px_rect(canvas, -8.0, -34.0, 3.0, 34.0, wood)
		PixelDraw.px_rect(canvas, 5.0, -34.0, 3.0, 34.0, wood)
		var y := -30.0
		while y < -2.0:
			PixelDraw.px_rect(canvas, -8.0, y, 16.0, 2.0, dark)
			y += 8.0
	else:
		PixelDraw.px_blob(canvas, 0.0, 0.0, 16.0, 9.0, Color(0.06, 0.05, 0.08))
		PixelDraw.px_rect(canvas, -7.0, -10.0, 3.0, 12.0, wood)
		PixelDraw.px_rect(canvas, 4.0, -10.0, 3.0, 12.0, wood)
		PixelDraw.px_rect(canvas, -7.0, -8.0, 14.0, 2.0, dark)
		PixelDraw.px_rect(canvas, -7.0, -2.0, 14.0, 2.0, dark)


static func draw_stall(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 20.0, 4.0)
	var wood := PixelPalette.hex(0x8A6848)
	var red := Color8(0xc0, 0x4a, 0x3a)
	var cream := Color8(0xe8, 0xdc, 0xc0)
	PixelDraw.px_rect(canvas, -16.0, -14.0, 3.0, 14.0, wood)
	PixelDraw.px_rect(canvas, 13.0, -14.0, 3.0, 14.0, wood)
	PixelDraw.px_rect(canvas, -14.0, -12.0, 28.0, 6.0, PixelPalette.shade(wood, 1.1))
	var x := -20.0
	var i := 0
	while x < 20.0:
		PixelDraw.px_rect(canvas, x, -26.0, 5.0, 10.0, red if i % 2 == 0 else cream)
		x += 5.0
		i += 1
	PixelDraw.px_rect(canvas, -20.0, -28.0, 40.0, 3.0, PixelPalette.shade(red, 0.8))
	PixelDraw.px_rect(canvas, -10.0, -10.0, 6.0, 4.0, Color8(0xf0, 0xd0, 0x50))
	PixelDraw.px_rect(canvas, 2.0, -10.0, 5.0, 4.0, Color8(0xe0, 0x80, 0xa0))


static func draw_meteor(canvas: CanvasItem, t: float) -> void:
	var rim := PixelPalette.pal("dirt_b")
	PixelDraw.px_blob(canvas, 0.0, 0.0, 34.0, 16.0, PixelPalette.shade(rim, 0.7))
	PixelDraw.px_blob(canvas, 0.0, -2.0, 26.0, 11.0, Color(0.12, 0.1, 0.12))
	PixelDraw.px_blob(canvas, 0.0, -4.0, 14.0, 8.0, Color(0.22, 0.18, 0.24))
	var pulse := 0.5 + sin(t * 1.6) * 0.3
	PixelDraw.px_rect(canvas, -6.0, -8.0, 8.0, 5.0, Color8(0x66, 0xe0, 0xc8), pulse)
	PixelDraw.px_rect(canvas, 2.0, -5.0, 4.0, 3.0, Color8(0xa0, 0xff, 0xe0), pulse * 0.8)
	PixelDraw.px_rect(canvas, -30.0, -4.0, 6.0, 4.0, rim, 0.8)
	PixelDraw.px_rect(canvas, 24.0, -2.0, 7.0, 4.0, rim, 0.8)


static func draw_mammoth(canvas: CanvasItem) -> void:
	PixelDraw.draw_foot_shadow(canvas, 30.0, 6.0)
	var ice := Color8(0xa8, 0xd0, 0xe8)
	var ice_hi := Color8(0xd0, 0xec, 0xf8)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 52.0, 40.0, ice, 0.92)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 6.0, 40.0, ice_hi, 0.9)
	PixelDraw.px_rect(canvas, -26.0, -40.0, 52.0, 4.0, ice_hi, 0.9)
	PixelDraw.px_blob(canvas, 2.0, -22.0, 16.0, 11.0, Color(0.28, 0.2, 0.16), 0.85)
	PixelDraw.px_blob(canvas, 14.0, -30.0, 8.0, 6.0, Color(0.28, 0.2, 0.16), 0.85)
	PixelDraw.px_rect(canvas, 16.0, -22.0, 8.0, 3.0, Color8(0xf0, 0xea, 0xd8), 0.9)
	PixelDraw.px_rect(canvas, 20.0, -19.0, 4.0, 3.0, Color8(0xf0, 0xea, 0xd8), 0.9)
	PixelDraw.px_rect(canvas, -12.0, -10.0, 3.0, 10.0, Color(0.28, 0.2, 0.16), 0.7)
	PixelDraw.px_rect(canvas, 6.0, -10.0, 3.0, 10.0, Color(0.28, 0.2, 0.16), 0.7)
