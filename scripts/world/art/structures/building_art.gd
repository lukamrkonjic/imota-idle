extends RefCounted
class_name BuildingArt
## Large hall redrawn at the same low source resolution as the cottage and the
## chest/barrel set: big plaster wall regions over a chunky stone base, a roof of
## a few broad stepped tonal bands (no slats), and large blocky windows/doors.
## Bigger than the cottage means BIGGER shapes — not more tiny detail.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const PLASTERS := [
	Color(0.82, 0.76, 0.62),
	Color(0.78, 0.71, 0.58),
	Color(0.86, 0.82, 0.72),
	Color(0.74, 0.69, 0.58),
	Color(0.80, 0.73, 0.61),
]


static func _ext(foot: float) -> Vector2:
	var hw := foot * float(WG.ISO_HW) * 0.78
	return Vector2(hw, hw * 0.50)


static func wall_height(foot: float, variant: int) -> float:
	return 42.0 + foot * 1.8 + float(variant % 3) * 7.0


static func roof_height(foot: float, variant: int) -> float:
	return 44.0 + foot * 1.9 + float((variant / 3) % 2) * 8.0


static func total_height(foot: float, variant: int) -> float:
	return wall_height(foot, variant) + roof_height(foot, variant) + 18.0


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
		PixelPalette.hex(0x8E6B45),
		PixelPalette.hex(0x724D36),
	]
	return color.lerp(clay[variant % clay.size()], 0.88)


static func _plaster(variant: int, salt: int, light: float) -> Color:
	return PixelPalette.shade(PLASTERS[(variant + salt) % PLASTERS.size()], light)


## One wall face: chunky stone base, big plaster field with two broad tonal
## clusters, fat corner beams + top plate, and two big blocky lit windows.
static func _wall_face(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		light: float, variant: int, salt: int, alpha: float, windows: bool) -> void:
	var stone := PixelPalette.shade(PixelPalette.pal("stone_b"), light * 0.92)
	var plaster := _plaster(variant, salt, light)
	var beam := PixelPalette.shade(PixelPalette.pal("trunk_b"), light * 0.86)
	var base_v := 0.26

	_face_quad(canvas, a, b, h, 0.0, 1.0, base_v, 1.0, plaster, alpha)
	_face_quad(canvas, a, b, h, 0.0, 1.0, 0.0, base_v, stone, alpha)
	_face_quad(canvas, a, b, h, 0.08, 0.40, base_v + 0.08, 0.72,
		PixelPalette.shade(plaster, 1.10), alpha * 0.30)
	_face_quad(canvas, a, b, h, 0.58, 0.94, base_v + 0.06, 0.86,
		PixelPalette.shade(plaster, 0.86), alpha * 0.34)
	_face_quad(canvas, a, b, h, 0.0, 0.07, base_v, 1.0, beam, alpha)
	_face_quad(canvas, a, b, h, 0.93, 1.0, base_v, 1.0, beam, alpha)
	_face_quad(canvas, a, b, h, 0.0, 1.0, 0.93, 1.0, beam, alpha)

	if windows:
		var glow := PixelPalette.pal("gold").lerp(PixelPalette.pal("snow_a"), 0.18)
		for u: float in [0.30, 0.70]:
			_face_quad(canvas, a, b, h, u - 0.10, u + 0.10, 0.40, 0.74, beam, alpha)
			_face_quad(canvas, a, b, h, u - 0.075, u + 0.075, 0.44, 0.70, glow, alpha)
			_face_quad(canvas, a, b, h, u - 0.012, u + 0.012, 0.44, 0.70, beam, alpha * 0.9)


static func _gable(canvas: CanvasItem, left: Vector2, right: Vector2, apex: Vector2,
		variant: int, salt: int, light: float, alpha: float) -> void:
	var plaster := _plaster(variant, salt, light)
	var beam := PixelPalette.shade(PixelPalette.pal("trunk_b"), light * 0.86)
	_poly(canvas, PackedVector2Array([left, right, apex]), plaster, alpha)
	_poly(canvas, PackedVector2Array([
		left.lerp(right, 0.52), right, apex.lerp(right, 0.45)
	]), PixelPalette.shade(plaster, 0.84), alpha * 0.5)
	var px := float(PixelPalette.PX)
	var mid := left.lerp(right, 0.5)
	_poly(canvas, PackedVector2Array([
		mid - Vector2(px * 1.5, 0.0), mid + Vector2(px * 1.5, 0.0),
		apex + Vector2(px * 1.5, 0.0), apex - Vector2(px * 1.5, 0.0)
	]), beam, alpha * 0.9)
	# One big round gable window.
	var wc := mid.lerp(apex, 0.42)
	PixelDraw.px_rect(canvas, wc.x - px * 2.0, wc.y - px * 1.5, px * 4.0, px * 3.0, beam, alpha)
	PixelDraw.px_rect(canvas, wc.x - px * 1.2, wc.y - px * 0.8, px * 2.4, px * 1.8, PixelPalette.pal("gold"), alpha * 0.8)


static func _roof_plane(canvas: CanvasItem, a0: Vector2, b0: Vector2, a1: Vector2, b1: Vector2,
		color: Color, alpha: float) -> void:
	var bands := 4
	for r: int in range(bands):
		var t0 := float(r) / float(bands)
		var t1 := float(r + 1) / float(bands)
		var ra := a0.lerp(a1, t0)
		var rb := b0.lerp(b1, t0)
		var ta := a0.lerp(a1, t1)
		var tb := b0.lerp(b1, t1)
		var tone := 0.76 + t0 * 0.38
		_poly(canvas, PackedVector2Array([ra, rb, tb, ta]),
			PixelPalette.shade(color, tone), alpha)


static func _door(canvas: CanvasItem, a: Vector2, b: Vector2, h: float, u: float, alpha: float) -> void:
	var dark := PixelPalette.hex(0x17120E)
	var frame := PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.9)
	var w := 0.12
	_face_quad(canvas, a, b, h, u - w * 1.3, u + w * 1.3, 0.0, 0.62, frame, alpha)
	_face_quad(canvas, a, b, h, u - w, u + w, 0.0, 0.54, dark, alpha)
	var knob := _face_pt(a, b, h, u + w * 0.55, 0.26)
	var px := float(PixelPalette.PX)
	PixelDraw.px_rect(canvas, knob.x - px * 0.5, knob.y - px * 0.5, px, px, PixelPalette.pal("gold"), alpha)


static func _chimney(canvas: CanvasItem, pos: Vector2, alpha: float, smoke: bool) -> void:
	var px := float(PixelPalette.PX)
	var stone := PixelPalette.pal("stone_a")
	PixelDraw.px_rect(canvas, pos.x - px * 1.5, pos.y - px * 6.0, px * 3.4, px * 6.4, PixelPalette.shade(stone, 0.86), alpha)
	PixelDraw.px_rect(canvas, pos.x - px * 1.8, pos.y - px * 6.8, px * 4.0, px * 1.2, PixelPalette.shade(stone, 1.12), alpha)
	if smoke:
		var smoke_col := PixelPalette.pal("stone_a").lerp(PixelPalette.pal("snow_a"), 0.50)
		PixelDraw.px_rect(canvas, pos.x + px * 1.4, pos.y - px * 9.0, px * 1.5, px * 2.4, smoke_col, alpha * 0.18)
		PixelDraw.px_rect(canvas, pos.x + px * 2.4, pos.y - px * 11.5, px * 1.5, px * 2.2, smoke_col, alpha * 0.13)


## Interior floor as a few broad low-res tonal groupings, not even stripes.
static func _draw_plank_floor(canvas: CanvasItem, extent: Vector2) -> void:
	var floor_c := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.86)
	PixelDraw.px_diamond(canvas, 0.0, 0.0, extent.x * 0.96, extent.y * 0.96, floor_c)
	# Two broad chunky patches suggest worn boards without fine lines.
	PixelDraw.px_diamond(canvas, -extent.x * 0.28, -extent.y * 0.10, extent.x * 0.40, extent.y * 0.40,
		PixelPalette.shade(floor_c, 1.08), 0.5)
	PixelDraw.px_diamond(canvas, extent.x * 0.26, extent.y * 0.16, extent.x * 0.38, extent.y * 0.34,
		PixelPalette.shade(floor_c, 0.80), 0.5)


static func draw_body(canvas: CanvasItem, foot: float, variant: int, _accent: Color,
		_style: String = "medieval") -> void:
	var extent := _ext(foot)
	var h := wall_height(foot, variant)
	var w := Vector2(-extent.x, 0.0)
	var n := Vector2(0.0, -extent.y)
	var east := Vector2(extent.x, 0.0)
	var s := Vector2(0.0, extent.y)
	ShadowProjector.cast_silhouette(canvas,
		PackedVector2Array([w, n, east, s]), total_height(foot, variant), 0.66)
	PixelDraw.draw_ground_collar(canvas, extent.x * 0.96, true, 10)
	_draw_plank_floor(canvas, extent)
	_wall_face(canvas, w, n, h, 0.84, variant, 1, 1.0, true)
	_wall_face(canvas, n, east, h, 1.04, variant, 2, 1.0, true)


static func draw_roof(canvas: CanvasItem, foot: float, variant: int, roof_color: Color,
		alpha: float, _style: String = "medieval") -> void:
	if alpha <= 0.02:
		return
	var extent := _ext(foot)
	var h := wall_height(foot, variant)
	var rh := roof_height(foot, variant)
	var roof := _roof_color(roof_color, variant)
	var w := Vector2(-extent.x, 0.0)
	var n := Vector2(0.0, -extent.y)
	var east := Vector2(extent.x, 0.0)
	var s := Vector2(0.0, extent.y)

	_wall_face(canvas, w, s, h, 0.80, variant, 3, alpha, false)
	_wall_face(canvas, s, east, h, 0.98, variant, 4, alpha, true)
	_door(canvas, w, s, h, 0.48, alpha)

	var px := float(PixelPalette.PX)
	var top := Vector2(0.0, -h)
	var ov := 7.0 + foot * 0.55
	var e_w := w + top + Vector2(-ov, ov * 0.35)
	var e_n := n + top + Vector2(0.0, -ov * 0.30)
	var e_e := east + top + Vector2(ov, ov * 0.35)
	var e_s := s + top + Vector2(0.0, ov * 0.48)
	var ridge_a := (e_w + e_n) * 0.5 + Vector2(0.0, -rh * 1.08)
	var ridge_b := (e_s + e_e) * 0.5 + Vector2(0.0, -rh * 1.08)

	_gable(canvas, e_w, e_n, ridge_a, variant, 5, 0.84, alpha * 0.84)
	_roof_plane(canvas, e_w, e_s, ridge_a, ridge_b, PixelPalette.shade(roof, 0.74), alpha)
	_roof_plane(canvas, e_n, e_e, ridge_a, ridge_b, PixelPalette.shade(roof, 1.12), alpha)
	_gable(canvas, e_s, e_e, ridge_b, variant, 6, 1.00, alpha)
	# Fat ridge cap.
	_poly(canvas, PackedVector2Array([
		ridge_a + Vector2(0.0, -px * 1.5), ridge_b + Vector2(0.0, -px * 1.5),
		ridge_b + Vector2(0.0, px * 1.5), ridge_a + Vector2(0.0, px * 1.5)
	]), PixelPalette.shade(roof, 1.30), alpha)

	_chimney(canvas, Vector2(-extent.x * 0.34, -h - rh * 0.48), alpha, true)
