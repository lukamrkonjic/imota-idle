extends RefCounted
class_name RuinArt
## Crumbled stonework for wilderness POIs: broken towers, wall runs, lone
## pillars, and standing stones. Deterministic per variant so every ruin has
## its own damage pattern. Two-tone stone with moss creeping up the base.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


static func draw(canvas: CanvasItem, kind: String, size: float, variant: int) -> void:
	match kind:
		"ruin_tower": _tower(canvas, size, variant)
		"ruin_wall": _wall(canvas, size, variant)
		"ruin_pillar": _pillar(canvas, size, variant)
		"ruin_stone": _stone(canvas, size, variant)
		_: _pillar(canvas, size, variant)


static func _r01(variant: int, salt: int) -> float:
	return float(absi(hash(variant * 31 + salt * 977)) % 1000) / 1000.0


static func _tower(canvas: CanvasItem, s: float, variant: int) -> void:
	var px := float(PixelPalette.PX)
	var lit := PixelPalette.pal("stone_a")
	var dark := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("moss")
	var w := PixelPalette.snap(s * 0.44)
	var hgt := PixelPalette.snap(s * 1.05)
	PixelDraw.draw_foot_shadow(canvas, w * 1.15, 6.0, 0.32)
	# Jagged broken top: per-column height loss, taller damage on one side.
	var cols := maxi(4, int(w * 2.0 / px))
	var ragged_side := 1.0 if _r01(variant, 1) > 0.5 else -1.0
	for ci: int in cols:
		var cx := -w + (float(ci) + 0.5) * px
		var edge := (cx / w) * ragged_side  # -1 far side .. +1 ragged side
		var loss := _r01(variant, 10 + ci) * 0.18 + maxf(0.0, edge) * 0.34
		var col_h := hgt * (1.0 - loss)
		var shade_col := lit if cx < 0.0 else dark
		PixelDraw.px_rect(canvas, cx - px * 0.5, -col_h, px, col_h, shade_col)
		# Brick seams.
		var y := px * 3.0
		while y < col_h:
			if int((y / px + float(ci % 2) * 2.0)) % 4 == 0:
				PixelDraw.px_rect(canvas, cx - px * 0.5, -y, px, px, PixelPalette.shade(shade_col, 0.86), 0.6)
			y += px
	# Dark window holes.
	PixelDraw.px_rect(canvas, -w * 0.55, -hgt * 0.68, px * 2.0, px * 3.0, Color(0.09, 0.09, 0.12))
	PixelDraw.px_rect(canvas, w * 0.15, -hgt * 0.42, px * 2.0, px * 3.0, Color(0.09, 0.09, 0.12))
	# Doorway at the foot.
	PixelDraw.px_rect(canvas, -px * 1.5, -px * 4.0, px * 3.0, px * 4.0, Color(0.07, 0.07, 0.10))
	# Moss and rubble at the base.
	PixelDraw.px_row(canvas, -w * 0.4, -px, w * 0.34, moss, 0.8)
	PixelDraw.px_blob(canvas, w * 1.05, 0.0, px * 2.2, px * 1.2, dark, 0.9)
	PixelDraw.px_blob(canvas, -w * 1.15, px * 0.5, px * 1.6, px, PixelPalette.shade(lit, 0.92), 0.9)


static func _wall(canvas: CanvasItem, s: float, variant: int) -> void:
	var px := float(PixelPalette.PX)
	var lit := PixelPalette.pal("stone_a")
	var dark := PixelPalette.pal("stone_b")
	var w := PixelPalette.snap(s * 0.8)
	var hgt := PixelPalette.snap(s * 0.30)
	PixelDraw.draw_foot_shadow(canvas, w * 0.9, 5.0, 0.28)
	var cols := maxi(5, int(w * 2.0 / px))
	for ci: int in cols:
		var cx := -w + (float(ci) + 0.5) * px
		var roll := _r01(variant, 30 + ci)
		if roll > 0.86:
			continue  # collapsed gap
		var col_h := hgt * (0.55 + roll * 0.55)
		PixelDraw.px_rect(canvas, cx - px * 0.5, -col_h, px, col_h, lit if ci % 3 != 0 else dark)
	PixelDraw.px_row(canvas, 0.0, -px, w * 0.5, PixelPalette.pal("moss"), 0.55)


static func _pillar(canvas: CanvasItem, s: float, variant: int) -> void:
	var px := float(PixelPalette.PX)
	var lit := PixelPalette.pal("stone_a")
	var dark := PixelPalette.pal("stone_b")
	var w := PixelPalette.snap(maxf(s * 0.14, px * 2.0))
	var hgt := PixelPalette.snap(s * (0.5 + _r01(variant, 50) * 0.30))
	PixelDraw.draw_foot_shadow(canvas, w * 1.6, 4.0, 0.3)
	PixelDraw.px_rect(canvas, -w * 0.5, -hgt, w * 0.5, hgt, lit)
	PixelDraw.px_rect(canvas, 0.0, -hgt, w * 0.5, hgt, dark)
	# Broken slanted top.
	PixelDraw.px_rect(canvas, -w * 0.5, -hgt - px, w * 0.6, px, PixelPalette.shade(lit, 1.08))
	# Base plinth + moss.
	PixelDraw.px_rect(canvas, -w * 0.8, -px * 2.0, w * 1.6, px * 2.0, dark)
	PixelDraw.px_row(canvas, 0.0, -px, w * 0.7, PixelPalette.pal("moss"), 0.6)


static func _stone(canvas: CanvasItem, s: float, variant: int) -> void:
	var px := float(PixelPalette.PX)
	var lit := PixelPalette.pal("stone_a")
	var dark := PixelPalette.pal("stone_b")
	var hgt := PixelPalette.snap(s * (0.52 + _r01(variant, 70) * 0.18))
	var base_w := PixelPalette.snap(s * 0.20)
	PixelDraw.draw_foot_shadow(canvas, base_w * 1.5, 4.0, 0.3)
	var y := 0.0
	while y < hgt:
		var t := y / hgt
		var half := base_w * (1.0 - t * 0.45)
		var lean := sin(_r01(variant, 71) * TAU) * t * s * 0.05
		PixelDraw.px_row(canvas, lean, -y, half, lit if int(y / px) % 3 != 0 else dark)
		y += px
	PixelDraw.px_row(canvas, 0.0, -px, base_w * 0.8, PixelPalette.pal("moss"), 0.6)
