extends RefCounted
class_name AmbienceArt
## Subtle drifting particles keyed to the player's macro biome.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const COUNT := 14


static func mode_for(biome_id: String) -> String:
	match biome_id:
		"forest", "dense_forest", "swamp":
			return "leaf"
		"desert", "beach", "volcanic":
			return "dust"
		"tundra":
			return "snow"
		_:
			return ""


static func draw(canvas: CanvasItem, biome_id: String, t: float, spread: Vector2) -> void:
	var mode := mode_for(biome_id)
	if mode.is_empty():
		return
	for i: int in COUNT:
		var s := _seed01(i)
		var sx := (_frac(s * 17.31) - 0.5) * spread.x * 1.05
		var sy := (_frac(s * 31.73) - 0.5) * spread.y * 1.05
		match mode:
			"leaf":
				_draw_leaf(canvas, sx, sy, s, t)
			"dust":
				_draw_dust(canvas, sx, sy, s, t)
			"snow":
				_draw_snow(canvas, sx, sy, s, t)


static func _draw_leaf(canvas: CanvasItem, sx: float, sy: float, s: float, t: float) -> void:
	var speed := 0.07 + s * 0.05
	var life := fmod(t * speed + s, 1.0)
	var drift := Vector2(-24.0 - s * 14.0, 28.0 + s * 10.0)
	var p := Vector2(sx, sy) + drift * life - drift * 0.5
	var wobble := sin(t * 1.4 + s * 9.0) * 6.0
	p.x += wobble
	var col := PixelPalette.pal("grass_b") if s > 0.55 else PixelPalette.pal("dirt_a")
	col.a = 0.16 + sin(life * PI) * 0.12
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, p.x, p.y, px, px, col, col.a)
	if s > 0.72:
		PixelDraw.px_rect(canvas, p.x + px, p.y, px, px, PixelPalette.shade(col, 0.9), col.a * 0.7)


static func _draw_dust(canvas: CanvasItem, sx: float, sy: float, s: float, t: float) -> void:
	var speed := 0.05 + s * 0.04
	var life := fmod(t * speed + s * 0.37, 1.0)
	var drift := Vector2(34.0 + s * 20.0, sin(s * 11.0) * 4.0)
	var p := Vector2(sx, sy) + drift * life - drift * 0.5
	p.y += sin(t * 0.9 + s * 6.0) * 3.0
	var col := PixelPalette.pal("gold") if s > 0.4 else PixelPalette.shade(PixelPalette.pal("dirt_a"), 1.08)
	col.a = 0.10 + sin(life * PI) * 0.08
	PixelDraw.px_blob(canvas, p.x, p.y, 5.0 + s * 4.0, 3.0, col, col.a)


static func _draw_snow(canvas: CanvasItem, sx: float, sy: float, s: float, t: float) -> void:
	var speed := 0.04 + s * 0.03
	var life := fmod(t * speed + s * 0.21, 1.0)
	var drift := Vector2(sin(t * 0.6 + s * 8.0) * 10.0, 26.0 + s * 8.0)
	var p := Vector2(sx, sy) + drift * life - drift * 0.5
	var col := PixelPalette.pal("snow_a")
	col.a = 0.18 + sin(life * PI) * 0.14
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, p.x, p.y, px * 0.75, px * 0.75, col, col.a)


static func _seed01(i: int) -> float:
	return float(absi(hash("amb|%d" % i)) % 10000) / 10000.0


static func _frac(v: float) -> float:
	return v - floor(v)
