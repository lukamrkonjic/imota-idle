extends RefCounted
class_name PixelDraw

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")


static func px_rect(canvas: CanvasItem, x: float, y: float, w: float, h: float, color: Color, alpha: float = 1.0) -> void:
	var c := SilhouetteDraw.ink(color, alpha)
	canvas.draw_rect(
		Rect2(PixelPalette.snap(x), PixelPalette.snap(y),
			maxf(PixelPalette.PX, PixelPalette.snap(w)),
			maxf(PixelPalette.PX, PixelPalette.snap(h))),
		c)


static func px_row(canvas: CanvasItem, cx: float, y: float, half_w: float, color: Color, alpha: float = 1.0) -> void:
	if half_w <= 0.0:
		return
	px_rect(canvas, cx - half_w, y, half_w * 2.0, PixelPalette.PX, color, alpha)


static func px_blob(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, alpha: float = 1.0) -> void:
	var steps := maxi(3, int(rx / PixelPalette.PX))
	for i: int in range(-steps, steps + 1):
		var t := float(i) / float(steps)
		var w := sqrt(maxf(0.0, 1.0 - t * t)) * rx
		px_rect(canvas, cx - w, cy + t * ry - PixelPalette.PX, w * 2.0, PixelPalette.PX * 2.0, color, alpha)


static func px_diamond(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, color: Color, alpha: float = 1.0) -> void:
	var c := SilhouetteDraw.ink(color, alpha)
	var pts := PackedVector2Array([
		Vector2(PixelPalette.snap(cx), PixelPalette.snap(cy - hh)),
		Vector2(PixelPalette.snap(cx + hw), PixelPalette.snap(cy)),
		Vector2(PixelPalette.snap(cx), PixelPalette.snap(cy + hh)),
		Vector2(PixelPalette.snap(cx - hw), PixelPalette.snap(cy)),
	])
	canvas.draw_colored_polygon(pts, c)


# --- Isometric solids ------------------------------------------------------
# A rectangular block drawn in true 2:1 isometric projection: a diamond top
# plus the two camera-facing vertical faces (lit south-east, shadowed
# south-west). Base centre is (cx, cy) on the ground; the block rises `h` px.
# `hw`/`hh` are the half-width/half-height of the diamond footprint (use
# hh ~= hw*0.5 for a square tile-aligned base). Props built from these read as
# solid 3D pieces that sit in the isometric world instead of flat billboards.
static func iso_box(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, top: Color, lit: Color, shadow: Color) -> void:
	var e := Vector2(cx + hw, cy)
	var s := Vector2(cx, cy + hh)
	var w := Vector2(cx - hw, cy)
	var up := Vector2(0.0, -h)
	# south-west face (away from the sun -> shaded)
	canvas.draw_colored_polygon(PackedVector2Array([s, w, w + up, s + up]), SilhouetteDraw.ink(shadow))
	# south-east face (toward the upper-right sun -> lit)
	canvas.draw_colored_polygon(PackedVector2Array([e, s, s + up, e + up]), SilhouetteDraw.ink(lit))
	# top diamond
	px_diamond(canvas, cx, cy - h, hw, hh, top)


## Convenience: an iso block from a single base colour, auto-shading the faces
## (top brightest, SE lit, SW shadowed). `light`/`shade` tune the contrast.
static func iso_block(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, base: Color, light: float = 1.18, shade: float = 0.62) -> void:
	iso_box(canvas, cx, cy, hw, hh, h,
		PixelPalette.shade(base, light + 0.12), PixelPalette.shade(base, light), PixelPalette.shade(base, shade))


# --- Directional ground shadows -------------------------------------------
# These three helpers are the whole game's shadow API: every prop, character,
# tree and structure casts through one of them, so routing them through the
# shared ShadowProjector/WorldLighting gives the entire world ONE consistent,
# directional, pixel-snapped, desaturated sun. The per-call `alpha` is now only
# a RELATIVE weight (vs each helper's baseline); the master strength lives in
# WorldLighting.shadow_opacity. `height` drives the shadow's length.

## Generic prop/structure shadow — one tapering directional blade + contact.
static func draw_foot_shadow(canvas: CanvasItem, radius_x: float, radius_y: float = 5.0, alpha: float = 0.3, height: float = -1.0) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var h := height if height >= 0.0 else radius_x * 1.2
	var scale := clampf(alpha / 0.3, 0.5, 1.4)
	ShadowProjector.cast_blade(canvas, radius_x, maxf(radius_x * 0.3, 2.0), h, scale)


## Character/creature shadow — short subtle blade anchored at the feet.
static func draw_tight_character_shadow(canvas: CanvasItem, half_width: float, _y: float = 4.0, alpha: float = 0.58, height: float = -1.0) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var h := height if height >= 0.0 else half_width * 2.0
	var scale := clampf(alpha / 0.58, 0.5, 1.2)
	ShadowProjector.cast_blade(canvas, half_width * 0.85, half_width * 0.4, h, scale)


## Tree/vegetation shadow — narrow trunk blade + broad canopy disc + contact.
static func draw_tree_shadow(canvas: CanvasItem, radius_x: float, alpha: float = 0.22) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var scale := clampf(alpha / 0.22, 0.5, 1.4)
	ShadowProjector.cast_tree(canvas, radius_x * 0.45, radius_x * 1.1, radius_x * 3.0, scale)


static func draw_ellipse(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	px_blob(canvas, cx, cy, maxf(rx, PixelPalette.PX), maxf(ry, PixelPalette.PX), color)


static func draw_foliage_clump(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if SilhouetteDraw.active:
		px_blob(canvas, cx, cy, rx, ry, color, 0.95)
		return
	var hi := PixelPalette.shade(color, 1.28)
	var lo := PixelPalette.shade(color, 0.68)
	px_blob(canvas, cx, cy, rx, ry, color)
	px_blob(canvas, cx - rx * 0.28, cy - ry * 0.32, rx * 0.58, ry * 0.48, hi, 0.82)
	px_blob(canvas, cx + rx * 0.22, cy + ry * 0.12, rx * 0.52, ry * 0.38, lo, 0.55)
	var px := float(PixelPalette.PX)
	px_rect(canvas, PixelPalette.snap(cx - rx * 0.35), PixelPalette.snap(cy - ry * 0.4), px * 2.0, px * 2.0, hi, 0.9)
	px_rect(canvas, PixelPalette.snap(cx - rx * 0.15), PixelPalette.snap(cy - ry * 0.5), px, px, PixelPalette.shade(hi, 1.1), 0.85)


static func draw_cloud_clump(canvas: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	draw_foliage_clump(canvas, cx, cy, rx, ry, color)


static func draw_trunk_base(canvas: CanvasItem, half_w: float, height: float, color: Color = PixelPalette.pal("trunk_a"), shadow: Color = PixelPalette.pal("trunk_b")) -> void:
	var px := float(PixelPalette.PX)
	var w := PixelPalette.snap(maxf(px * 2.0, half_w))
	var h := PixelPalette.snap(maxf(px * 2.0, height))
	px_rect(canvas, -w - px, -px, w * 2.0 + px * 2.0, px, PixelPalette.shade(shadow, 0.85))
	px_rect(canvas, -w - px * 2.0, -px, px * 2.0, px, shadow)
	px_rect(canvas, w, -px, px * 2.0, px, shadow)
	px_rect(canvas, -w, -h, w * 2.0, h, color)
	px_rect(canvas, w - px, -h + px, px, h - px, shadow)
	px_rect(canvas, -w, -h, px, h, PixelPalette.shade(color, 1.14))
	var ly := -h + px * 2.0
	while ly < -px:
		px_rect(canvas, -w + px, ly, w * 2.0 - px * 2.0, px, PixelPalette.shade(shadow, 0.35), 0.45)
		ly += px * 3.0


static func draw_simple_trunk(canvas: CanvasItem, half_w: float, height: float, color: Color = PixelPalette.pal("trunk_a"), shadow: Color = PixelPalette.pal("trunk_b")) -> void:
	draw_trunk_base(canvas, half_w, height, color, shadow)
