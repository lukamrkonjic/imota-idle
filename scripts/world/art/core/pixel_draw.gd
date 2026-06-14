extends RefCounted
class_name PixelDraw

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")


static func px_rect(canvas: Variant, x: float, y: float, w: float, h: float, color: Color, alpha: float = 1.0) -> void:
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


static func px_diamond(canvas: Variant, cx: float, cy: float, hw: float, hh: float, color: Color, alpha: float = 1.0) -> void:
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


# --- Face-space painting (pixel-art texture on iso faces) ------------------
# A vertical face is the parallelogram swept from base edge a->b up by height h.
# `u` runs 0..1 along a->b; `v` runs 0..1 from the base (0) to the top (1). These
# let props paint masonry courses, planks, panels and dithering ONTO an iso face
# so it reads as chunky hand-drawn pixel art instead of a flat smooth polygon —
# matching the terrain dither and the tree/canopy texturing.
const _BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func iso_face_pt(a: Vector2, b: Vector2, h: float, u: float, v: float) -> Vector2:
	return a.lerp(b, u) - Vector2(0.0, h * v)


static func iso_face_quad(canvas: CanvasItem, a: Vector2, b: Vector2, h: float, u0: float, u1: float, v0: float, v1: float, col: Color, alpha: float = 1.0) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([
		iso_face_pt(a, b, h, u0, v0), iso_face_pt(a, b, h, u1, v0),
		iso_face_pt(a, b, h, u1, v1), iso_face_pt(a, b, h, u0, v1),
	]), SilhouetteDraw.ink(col, alpha))


## Ordered-dither one face into chunky pixel cells around `base` — a couple of
## tones, PX-sized, skewed with the face. The cheap way to give any iso solid the
## dithered pixel-grain the rest of the world has.
static func iso_face_dither(canvas: CanvasItem, a: Vector2, b: Vector2, h: float, base: Color, salt: int = 0) -> void:
	var face_len := a.distance_to(b)
	var cols := maxi(2, int(round(face_len / float(PixelPalette.PX))))
	var rows := maxi(2, int(round(h / float(PixelPalette.PX))))
	var lo := PixelPalette.shade(base, 0.9)
	var hi := PixelPalette.shade(base, 1.08)
	for r: int in rows:
		for c: int in cols:
			var b4: int = _BAYER[(r % 4) * 4 + ((c + salt) % 4)]
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			if b4 < 5:
				iso_face_quad(canvas, a, b, h, u0, u1, v0, v1, lo, 0.45)
			elif b4 > 11:
				iso_face_quad(canvas, a, b, h, u0, u1, v0, v1, hi, 0.30)


## Ordered-dither a TRIANGULAR face (base edge ba->bb up to `apex`) into chunky
## pixel cells — the pyramid-face equivalent of iso_face_dither, for tents/roofs.
static func iso_tri_dither(canvas: CanvasItem, ba: Vector2, bb: Vector2, apex: Vector2, base: Color, salt: int = 0) -> void:
	var rows := maxi(3, int(ba.lerp(bb, 0.5).distance_to(apex) / (float(PixelPalette.PX) * 1.6)))
	var lo := PixelPalette.shade(base, 0.86)
	var hi := PixelPalette.shade(base, 1.12)
	for r: int in rows:
		var t0 := float(r) / float(rows)
		var t1 := float(r + 1) / float(rows)
		var a0 := ba.lerp(apex, t0)
		var b0 := bb.lerp(apex, t0)
		var a1 := ba.lerp(apex, t1)
		var b1 := bb.lerp(apex, t1)
		var cols := maxi(1, int(a0.distance_to(b0) / float(PixelPalette.PX)))
		for c: int in cols:
			var b4: int = _BAYER[(r % 4) * 4 + ((c + salt) % 4)]
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			if b4 < 6:
				canvas.draw_colored_polygon(PackedVector2Array([
					a0.lerp(b0, u0), a0.lerp(b0, u1), a1.lerp(b1, u1), a1.lerp(b1, u0)]),
					SilhouetteDraw.ink(lo, 0.5))
			elif b4 > 10:
				canvas.draw_colored_polygon(PackedVector2Array([
					a0.lerp(b0, u0), a0.lerp(b0, u1), a1.lerp(b1, u1), a1.lerp(b1, u0)]),
					SilhouetteDraw.ink(hi, 0.34))


## Solid pixel-grid fill for a TRIANGULAR face — every PX cell is drawn and
## Bayer-varied between lo/mid/hi tones. Use this (instead of a smooth polygon +
## iso_tri_dither) when you want the face to read as pure chunky pixel art, the
## same way iso_block_tex makes solid blocks look hand-drawn. `alpha` lets the
## whole face fade (for roof-fade on buildings/tents).
static func iso_tri_solid(canvas: CanvasItem, ba: Vector2, bb: Vector2, apex: Vector2, base: Color, salt: int = 0, alpha: float = 1.0) -> void:
	var px := float(PixelPalette.PX)
	var rows := maxi(3, int(ba.lerp(bb, 0.5).distance_to(apex) / px))
	var lo := PixelPalette.shade(base, 0.80)
	var hi := PixelPalette.shade(base, 1.18)
	for r: int in rows:
		var t0 := float(r) / float(rows)
		var t1 := float(r + 1) / float(rows)
		var a0 := ba.lerp(apex, t0)
		var b0 := bb.lerp(apex, t0)
		var a1 := ba.lerp(apex, t1)
		var b1 := bb.lerp(apex, t1)
		var cols := maxi(1, int(a0.distance_to(b0) / px))
		for c: int in cols:
			var b4: int = _BAYER[(r % 4) * 4 + ((c + salt) % 4)]
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var col := lo if b4 < 6 else (hi if b4 > 10 else base)
			canvas.draw_colored_polygon(PackedVector2Array([
				a0.lerp(b0, u0), a0.lerp(b0, u1), a1.lerp(b1, u1), a1.lerp(b1, u0)
			]), SilhouetteDraw.ink(col, alpha))


## The three silhouette base points of an iso block (right, front, left).
static func iso_corners(cx: float, cy: float, hw: float, hh: float) -> Array:
	return [Vector2(cx + hw, cy), Vector2(cx, cy + hh), Vector2(cx - hw, cy)]


## An iso block with dithered faces — the pixel-art default for solid props. Same
## signature spirit as iso_block, plus a `salt` so neighbouring blocks dither
## differently.
static func iso_block_tex(canvas: CanvasItem, cx: float, cy: float, hw: float, hh: float, h: float, base: Color, salt: int = 0, light: float = 1.18, shade: float = 0.62) -> void:
	iso_block(canvas, cx, cy, hw, hh, h, base, light, shade)
	var c := iso_corners(cx, cy, hw, hh)
	iso_face_dither(canvas, c[0], c[1], h, PixelPalette.shade(base, light), salt)      # SE lit
	iso_face_dither(canvas, c[1], c[2], h, PixelPalette.shade(base, shade), salt + 2)  # SW shadow


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


## A "planted" ground collar at an object's foot: a soft dirt contact scuff plus
## (optionally) a sparse ring of grass tufts. This is the tree-art trick that
## makes a thing read as nestled INTO the world rather than pasted flat on the
## tile — share it across structures/props so the whole world sits the same way.
## `radius` is the footprint half-width in px; `grass` off (e.g. on city paving)
## leaves just the dirt scuff. Call it AFTER the shadow, BEFORE the body.
static func draw_ground_collar(canvas: CanvasItem, radius: float, grass: bool = true, tufts: int = 5, alpha: float = 1.0) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var px := float(PixelPalette.PX)
	var dirt := PixelPalette.pal("dirt_a")
	px_blob(canvas, 0.0, px * 0.8, radius * 0.82, radius * 0.28, dirt, 0.55 * alpha)
	px_blob(canvas, 0.0, px * 0.4, radius * 0.56, radius * 0.18, PixelPalette.shade(dirt, 0.88), 0.45 * alpha)
	if not grass or tufts <= 1:
		return
	var grass_a := PixelPalette.pal("grass_a")
	var grass_c := PixelPalette.pal("grass_c")
	for i: int in range(tufts):
		var t := float(i) / float(tufts - 1)
		var tx := lerpf(-radius, radius, t)
		var col := grass_a if i % 2 == 0 else grass_c
		px_rect(canvas, tx - px, -px * 0.5, px, px * 1.5, col, 0.85 * alpha)
		if i % 3 == 0:
			px_rect(canvas, tx, -px * 1.2, px, px, PixelPalette.shade(col, 1.1), 0.7 * alpha)


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
