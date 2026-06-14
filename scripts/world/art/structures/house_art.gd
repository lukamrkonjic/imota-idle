extends RefCounted
class_name HouseArt
## Small cottage redrawn low-res to sit beside the chest/barrel/pillar set: walls
## are big light/shadow plaster regions over a chunky stone base, the roof is a
## few broad stepped tonal bands (no parallel slats), and doors/windows are large
## blocky iconic shapes. Form comes from value steps, not thin linework.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")

const PLASTERS := [
	Color(0.82, 0.76, 0.62),
	Color(0.86, 0.82, 0.72),
	Color(0.78, 0.71, 0.58),
	Color(0.80, 0.73, 0.61),
]


static func body_half_width(variant: int) -> float:
	return 22.0 + float(variant % 3) * 3.0


static func wall_height(variant: int) -> float:
	return 27.0 + float((variant / 3) % 3) * 4.0


static func roof_height(variant: int) -> float:
	return 30.0 + float(variant % 3) * 3.0


static func total_height(variant: int) -> float:
	return wall_height(variant) + roof_height(variant) + 9.0


static func _poly(canvas: CanvasItem, pts: PackedVector2Array, color: Color, alpha: float = 1.0) -> void:
	canvas.draw_colored_polygon(pts, SilhouetteDraw.ink(color, alpha))


static func _face_pt(a: Vector2, b: Vector2, h: float, u: float, v: float) -> Vector2:
	return a.lerp(b, u) - Vector2(0.0, h * v)


static func _face_quad(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		u0: float, u1: float, v0: float, v1: float, color: Color, alpha: float = 1.0) -> void:
	_poly(canvas, PackedVector2Array([
		_face_pt(a, b, h, u0, v0),
		_face_pt(a, b, h, u1, v0),
		_face_pt(a, b, h, u1, v1),
		_face_pt(a, b, h, u0, v1),
	]), color, alpha)


static func _roof_color(color: Color, variant: int) -> Color:
	var clay: Array[Color] = [
		PixelPalette.hex(0x9B5D38),
		PixelPalette.hex(0xA87542),
		PixelPalette.hex(0x86543A),
		PixelPalette.hex(0x8A6848),
	]
	return color.lerp(clay[variant % clay.size()], 0.88)


## One wall face: a chunky stone base band, a big plaster region broken only by
## two broad tonal clusters, two fat corner beams, and an optional big window.
static func _wall_face(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		light: float, variant: int, salt: int, alpha: float, window: bool) -> void:
	var stone := PixelPalette.shade(PixelPalette.pal("stone_b"), light * 0.90)
	var plaster := PixelPalette.shade(PLASTERS[(variant + salt) % PLASTERS.size()], light)
	var beam := PixelPalette.shade(PixelPalette.pal("trunk_b"), light * 0.86)
	var base_v := 0.24

	# Big plaster wall, then the stone footing band over it.
	_face_quad(canvas, a, b, h, 0.0, 1.0, base_v, 1.0, plaster, alpha)
	_face_quad(canvas, a, b, h, 0.0, 1.0, 0.0, base_v, stone, alpha)
	# Two broad value clusters give low-res volume without thin detail.
	_face_quad(canvas, a, b, h, 0.10, 0.40, base_v + 0.08, 0.74,
		PixelPalette.shade(plaster, 1.10), alpha * 0.32)
	_face_quad(canvas, a, b, h, 0.58, 0.92, base_v + 0.06, 0.86,
		PixelPalette.shade(plaster, 0.86), alpha * 0.34)
	# Fat corner beams + a top plate. Three bold timbers, no fine framing.
	_face_quad(canvas, a, b, h, 0.0, 0.10, base_v, 1.0, beam, alpha)
	_face_quad(canvas, a, b, h, 0.90, 1.0, base_v, 1.0, beam, alpha)
	_face_quad(canvas, a, b, h, 0.0, 1.0, 0.92, 1.0, beam, alpha)

	if window:
		var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("snow_a"), 0.16)
		_face_quad(canvas, a, b, h, 0.36, 0.64, 0.42, 0.74, beam, alpha)
		_face_quad(canvas, a, b, h, 0.40, 0.60, 0.46, 0.70, glow, alpha)
		# One thick mullion cross — chunky, iconic.
		_face_quad(canvas, a, b, h, 0.485, 0.515, 0.46, 0.70, beam, alpha * 0.9)


static func _gable(canvas: CanvasItem, left: Vector2, right: Vector2, apex: Vector2,
		variant: int, light: float, alpha: float) -> void:
	var plaster := PixelPalette.shade(PLASTERS[variant % PLASTERS.size()], light)
	var beam := PixelPalette.shade(PixelPalette.pal("trunk_b"), light * 0.86)
	# Solid plaster triangle; one broad shadow cluster; one fat king-post beam.
	_poly(canvas, PackedVector2Array([left, right, apex]), plaster, alpha)
	_poly(canvas, PackedVector2Array([
		left.lerp(right, 0.52), right, apex.lerp(right, 0.45)
	]), PixelPalette.shade(plaster, 0.84), alpha * 0.5)
	var px := float(PixelPalette.PX)
	var mid := left.lerp(right, 0.5)
	_poly(canvas, PackedVector2Array([
		mid - Vector2(px, 0.0), mid + Vector2(px, 0.0),
		apex + Vector2(px, 0.0), apex - Vector2(px, 0.0)
	]), beam, alpha * 0.9)


## A pitched roof plane drawn as a few broad stepped tonal bands — chunky low-res
## shading clusters instead of parallel slats.
static func _roof_plane(canvas: CanvasItem, a0: Vector2, b0: Vector2, a1: Vector2, b1: Vector2,
		color: Color, alpha: float) -> void:
	var bands := 3
	for r: int in range(bands):
		var t0 := float(r) / float(bands)
		var t1 := float(r + 1) / float(bands)
		var ra := a0.lerp(a1, t0)
		var rb := b0.lerp(b1, t0)
		var ta := a0.lerp(a1, t1)
		var tb := b0.lerp(b1, t1)
		# Each band a distinct value step; eave darkest, ridge lightest.
		var tone := 0.78 + t0 * 0.34
		_poly(canvas, PackedVector2Array([ra, rb, tb, ta]),
			PixelPalette.shade(color, tone), alpha)


static func _door(canvas: CanvasItem, a: Vector2, b: Vector2, h: float, u: float, alpha: float) -> void:
	var dark := PixelPalette.hex(0x17120E)
	var frame := PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.9)
	var w := 0.14
	_face_quad(canvas, a, b, h, u - w * 1.25, u + w * 1.25, 0.0, 0.64, frame, alpha)
	_face_quad(canvas, a, b, h, u - w, u + w, 0.0, 0.56, dark, alpha)
	var knob := _face_pt(a, b, h, u + w * 0.55, 0.26)
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, knob.x - px * 0.5, knob.y - px * 0.5, px, px, PixelPalette.pal("gold"), alpha)


static func draw_body(canvas: CanvasItem, variant: int, _accent: Color) -> void:
	var w := body_half_width(variant)
	var h := wall_height(variant)
	var extent := Vector2(w, w * 0.50)
	var west := Vector2(-extent.x, 0.0)
	var north := Vector2(0.0, -extent.y)
	var east := Vector2(extent.x, 0.0)
	PixelDraw.draw_foot_shadow(canvas, extent.x + 5.0, extent.y + 2.0, 0.3, total_height(variant))
	PixelDraw.draw_ground_collar(canvas, extent.x, true, 7)
	PixelDraw.px_diamond(canvas, 0.0, -1.0, extent.x * 0.94, extent.y * 0.90,
		PixelPalette.shade(PixelPalette.pal("dirt_a"), 0.92))
	_wall_face(canvas, west, north, h, 0.84, variant, 1, 1.0, true)
	_wall_face(canvas, north, east, h, 1.04, variant, 2, 1.0, false)


static func draw_roof(canvas: CanvasItem, variant: int, roof_color: Color, alpha: float) -> void:
	if alpha <= 0.02:
		return
	var w := body_half_width(variant)
	var h := wall_height(variant)
	var rh := roof_height(variant)
	var extent := Vector2(w, w * 0.50)
	var west := Vector2(-extent.x, 0.0)
	var south := Vector2(0.0, extent.y)
	var east := Vector2(extent.x, 0.0)
	var roof := _roof_color(roof_color, variant)

	_wall_face(canvas, west, south, h, 0.80, variant, 3, alpha, false)
	_wall_face(canvas, south, east, h, 0.98, variant, 4, alpha, false)
	_door(canvas, west, south, h, 0.52, alpha)

	var px := float(PixelPalette.PX)
	var top := Vector2(0.0, -h)
	var ov := 6.0
	var e_w := west + top + Vector2(-ov, ov * 0.35)
	var e_n := Vector2(0.0, -extent.y) + top + Vector2(0.0, -ov * 0.25)
	var e_e := east + top + Vector2(ov, ov * 0.35)
	var e_s := south + top + Vector2(0.0, ov * 0.48)
	var ridge_a := (e_w + e_n) * 0.5 + Vector2(0.0, -rh)
	var ridge_b := (e_s + e_e) * 0.5 + Vector2(0.0, -rh)
	_gable(canvas, e_w, e_n, ridge_a, variant + 1, 0.84, alpha * 0.88)
	_roof_plane(canvas, e_w, e_s, ridge_a, ridge_b, PixelPalette.shade(roof, 0.74), alpha)
	_roof_plane(canvas, e_n, e_e, ridge_a, ridge_b, PixelPalette.shade(roof, 1.12), alpha)
	_gable(canvas, e_s, e_e, ridge_b, variant + 2, 1.0, alpha)
	# Fat ridge cap.
	_poly(canvas, PackedVector2Array([
		ridge_a + Vector2(0.0, -px), ridge_b + Vector2(0.0, -px),
		ridge_b + Vector2(0.0, px), ridge_a + Vector2(0.0, px)
	]), PixelPalette.shade(roof, 1.28), alpha)

	if variant % 3 != 0:
		var cx := extent.x * (0.36 if variant % 2 == 0 else -0.36)
		var cy := -h - rh * 0.56
		var stone := PixelPalette.pal("stone_a")
		PixelDraw.px_rect(canvas, cx - px * 1.5, cy - px * 6.0, px * 3.5, px * 6.5, PixelPalette.shade(stone, 0.84), alpha)
		PixelDraw.px_rect(canvas, cx - px * 1.8, cy - px * 6.5, px * 4.2, px * 1.5, PixelPalette.shade(stone, 1.12), alpha)
