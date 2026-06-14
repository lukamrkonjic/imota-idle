extends RefCounted
class_name BuildingArt
## Isometric medieval building drawn in pixel-art style.
## Pixel grid: PX=4, all geometry snaps to the 4-px grid via PixelPalette.snap().
## Walls: stone masonry base (8-px courses, staggered joints) + timber-frame plaster upper.
## Roofs: hip or gabled, drawn as many PX-spaced shingle rows for a tiled look.
##
## `foot` = footprint half-width in tiles (~6-9). `variant` seeds all visual choices.
##
## To add a new settlement style (e.g. "desert", "ruin"):
##   1. Create  scripts/world/art/structures/settlements/<style>_building_art.gd
##   2. Match the same  draw_body / draw_roof  static interface.
##   3. In this file add a  match style:  arm in draw_body / draw_roof.
##   4. Set  WorldEntity.building_style  in world_entity_spawner for that settlement.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw    := preload("res://scripts/world/art/core/pixel_draw.gd")
const ShadowProjector := preload("res://scripts/world/art/core/shadow_projector.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const PLASTERS := [Color(0.82, 0.76, 0.62), Color(0.78, 0.71, 0.58),
	Color(0.86, 0.82, 0.72), Color(0.70, 0.66, 0.56), Color(0.80, 0.74, 0.64)]


# ──────────────────────────────────────────────── geometry ────────────────────

static func _ext(foot: float) -> Vector2:
	return Vector2(foot * float(WG.ISO_HW), foot * float(WG.ISO_HH))

static func wall_height(foot: float, variant: int) -> float:
	return 40.0 + foot * 1.5 + float(variant % 3) * 12.0

static func roof_height(foot: float, variant: int) -> float:
	return 26.0 + foot * 1.5 + float((variant / 3) % 3) * 10.0

static func total_height(foot: float, variant: int) -> float:
	return wall_height(foot, variant) + roof_height(foot, variant) + 16.0


# ──────────────────────────────────────────── face-space helpers ──────────────
# `a`/`b` are the bottom-left and bottom-right corners of the wall face (screen).
# `v` values are fractions of wall height h (0 = foot, 1 = top).
# `u` values are fractions along the bottom edge a→b (0 = left, 1 = right).

static func _band(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		v0: float, v1: float, col: Color, alpha: float) -> void:
	var c := col; c.a *= alpha
	canvas.draw_colored_polygon(PackedVector2Array([
		a + Vector2(0, -h * v0), b + Vector2(0, -h * v0),
		b + Vector2(0, -h * v1), a + Vector2(0, -h * v1)]), c)

static func _panel(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		u0: float, u1: float, v0: float, v1: float, col: Color, alpha: float) -> void:
	var la := a.lerp(b, u0); var lb := a.lerp(b, u1)
	var c := col; c.a *= alpha
	canvas.draw_colored_polygon(PackedVector2Array([
		la + Vector2(0, -h * v0), lb + Vector2(0, -h * v0),
		lb + Vector2(0, -h * v1), la + Vector2(0, -h * v1)]), c)

static func _tri(canvas: CanvasItem, p: PackedVector2Array, col: Color, alpha: float) -> void:
	var c := col; c.a *= alpha
	canvas.draw_colored_polygon(p, c)


# ──────────────────────────────────────────── pixel-art wall face ─────────────

## One masonry + timber wall face. Stone base built from 8-px courses with
## staggered vertical joints; upper floor has corner posts, studs, mid-rail,
## windowed panes and optionally a door. All detail snaps to PX=4.
static func _wall_face(canvas: CanvasItem, a: Vector2, b: Vector2, h: float,
		light: float, variant: int, salt: int, door: bool, alpha: float) -> void:
	var px      := float(PixelPalette.PX)           # 4 screen pixels
	var stone   := PixelPalette.shade(PixelPalette.pal("stone_b"), light)
	var stone_hi:= PixelPalette.shade(PixelPalette.pal("stone_a"), light)
	var mortar  := PixelPalette.shade(stone, 0.63)
	var plaster : Color = PLASTERS[(variant + salt) % PLASTERS.size()]
	plaster     = PixelPalette.shade(plaster, light)
	var beam    := PixelPalette.shade(PixelPalette.pal("trunk_b"), light * 0.95)
	var beam_hi := PixelPalette.shade(PixelPalette.pal("trunk_a"), light)
	var glow    := Color(0.92, 0.85, 0.62)
	var base_frac := 0.34 + float((variant / 2) % 3) * 0.08
	var face_len  := a.distance_to(b)
	# 2-pixel-wide beam expressed as a u-space fraction
	var bw := (px * 2.0) / maxf(face_len, 1.0)

	# ── STONE BASE ─────────────────────────────────────────────────────────────
	_band(canvas, a, b, h, 0.0, base_frac, stone, alpha)
	var base_h   := base_frac * h
	var course_h := px * 2.0          # 8 px per course
	var row_idx  := 0
	var cy       := course_h
	while cy <= base_h + px * 0.5:
		var v_top := minf(cy / h, base_frac)
		var v_bot := maxf(0.0, (cy - course_h) / h)
		# Horizontal mortar line (1 PX tall)
		if v_top - px / h > v_bot:
			_band(canvas, a, b, h, v_top - px / h, v_top, mortar, alpha)
		# Staggered vertical joints (1 PX wide)
		var num_blocks := maxi(2, int(face_len / (px * 3.5)))
		var stagger    := float(row_idx % 2) * 0.42
		for j in range(1, num_blocks):
			var u := fmod(float(j) / float(num_blocks) + stagger, 1.0)
			if u < bw * 0.5 or u > 1.0 - bw * 0.5:
				continue
			var jw := px / maxf(face_len, 1.0)
			_panel(canvas, a, b, h, u - jw, u + jw, v_bot, v_top - px / h, mortar, alpha * 0.65)
		# Subtle per-block lightness variation
		for j in range(num_blocks):
			var u0 := fmod(float(j) / float(num_blocks) + stagger * float(j % 2), 1.0)
			var u1 := minf(u0 + 1.0 / float(num_blocks) * 0.88, 1.0)
			if WG.r01(variant * 7 + salt + row_idx, j, 0, 53) < 0.35:
				var vf := WG.r01(variant + salt, j, row_idx, 37) * 0.07 - 0.035
				_panel(canvas, a, b, h, u0, u1, v_bot, v_top - px / h,
					PixelPalette.shade(stone, 1.0 + vf), alpha * 0.5)
		row_idx += 1
		cy += course_h
	# Stone top cap highlight
	_band(canvas, a, b, h, base_frac - px / h, base_frac, stone_hi, alpha * 0.6)

	# ── PLASTER + TIMBER UPPER ─────────────────────────────────────────────────
	_band(canvas, a, b, h, base_frac, 1.0, plaster, alpha)
	# Sill plate (2 PX tall)
	_band(canvas, a, b, h, base_frac, base_frac + (px * 2.0) / h, beam, alpha)
	# Top plate (2 PX tall, lighter)
	_band(canvas, a, b, h, 1.0 - (px * 2.0) / h, 1.0, beam_hi, alpha)
	# Corner posts (3 PX wide each)
	_panel(canvas, a, b, h, 0.0, bw * 1.5, base_frac, 1.0, beam, alpha)
	_panel(canvas, a, b, h, 1.0 - bw * 1.5, 1.0, base_frac, 1.0, beam, alpha)
	# Interior studs
	var studs := 2 + (variant % 2)
	for s in range(1, studs + 1):
		var u := float(s) / float(studs + 1)
		_panel(canvas, a, b, h, u - bw * 0.75, u + bw * 0.75,
			base_frac, 1.0 - (px * 2.0) / h, beam, alpha)
	# Mid rail
	if (variant / 4) % 2 == 0:
		var mv := (base_frac + 1.0) * 0.5
		_band(canvas, a, b, h, mv, mv + (px * 1.5) / h, beam, alpha)
	# Door
	if door:
		_panel(canvas, a, b, h, 0.38, 0.62, 0.0, 0.48, PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.58), alpha)
		_panel(canvas, a, b, h, 0.38, 0.62, 0.46, 0.50, beam_hi, alpha)
		_panel(canvas, a, b, h, 0.55, 0.60, 0.20, 0.28, PixelPalette.pal("gold"), alpha)
	# Windows: outer frame, glass pane, cross divider
	var win_bot := base_frac + (px * 3.0) / h
	var win_top := base_frac + (h * 0.30 + px * 3.0) / h
	win_top = minf(win_top, 1.0 - (px * 4.0) / h)
	for s in range(1, studs + 1):
		var u := float(s) / float(studs + 1)
		if door and absf(u - 0.5) < 0.22:
			continue
		if WG.r01(variant * 7 + salt, s, 0, 31) < 0.78:
			var ww := bw * 2.2
			_panel(canvas, a, b, h, u - ww, u + ww, win_bot - px / h, win_top + px / h, beam, alpha)
			_panel(canvas, a, b, h, u - ww * 0.68, u + ww * 0.68, win_bot, win_top, glow, alpha * 0.86)
			# Horizontal cross bar
			var wmid := (win_bot + win_top) * 0.5
			_band(canvas, a, b, h, wmid - px / h, wmid, beam, alpha * 0.45)
	# Moss patch
	if (variant + salt) % 3 == 0:
		var mu := WG.r01(variant, salt, 0, 41)
		_panel(canvas, a, b, h, mu, mu + 0.12, 0.0, base_frac * 0.7,
			PixelPalette.pal("grass_a").lerp(PixelPalette.pal("stone_b"), 0.45), alpha * 0.42)


# ──────────────────────────────────────────── pixel-art roof ──────────────────

## Draws a triangular roof face (eave fa→fb up to apex) as horizontal shingle
## rows spaced 2*PX apart. Rows lighten slightly toward the ridge.
static func _shingle_tri(canvas: CanvasItem, fa: Vector2, fb: Vector2, apex: Vector2,
		col: Color, alpha: float) -> void:
	var px      := float(PixelPalette.PX)
	var eave_c  := (fa + fb) * 0.5
	var slope_h := eave_c.distance_to(apex)
	var num_rows := maxi(3, int(slope_h / (px * 2.0)))
	var dark    := PixelPalette.shade(col, 0.58)

	for r in range(num_rows):
		var t0 := float(r) / float(num_rows)
		var t1 := float(r + 1) / float(num_rows)
		var ra := fa.lerp(apex, t0)
		var rb := fb.lerp(apex, t0)
		var ta := fa.lerp(apex, t1)
		var tb := fb.lerp(apex, t1)
		var row_col := PixelPalette.shade(col, 1.0 + float(r) / float(num_rows) * 0.22)
		row_col.a   = alpha
		if t1 >= 1.0 or ta.distance_to(apex) < px:
			canvas.draw_colored_polygon(PackedVector2Array([ra, rb, apex]), row_col)
		else:
			canvas.draw_colored_polygon(PackedVector2Array([ra, rb, tb, ta]), row_col)
		# Dark shingle-edge line at bottom of each row
		if (rb - ra).length() > px * 2.0:
			var lc := dark; lc.a = alpha * 0.55
			canvas.draw_colored_polygon(PackedVector2Array([
				ra, rb, rb + Vector2(0.0, px), ra + Vector2(0.0, px)]), lc)
	# Ridge highlight
	var rc := PixelPalette.shade(col, 1.4); rc.a = alpha * 0.7
	canvas.draw_colored_polygon(PackedVector2Array([
		fa.lerp(apex, 0.90), fb.lerp(apex, 0.90),
		apex + Vector2(2.0, 0.0), apex - Vector2(2.0, 0.0)]), rc)


## Draws a quadrilateral roof face (parallelogram) as shingle rows.
## a0/b0 = bottom edge, a1/b1 = top edge.
static func _shingle_quad(canvas: CanvasItem, a0: Vector2, b0: Vector2, a1: Vector2,
		b1: Vector2, col: Color, alpha: float) -> void:
	var px      := float(PixelPalette.PX)
	var bot_c   := (a0 + b0) * 0.5
	var top_c   := (a1 + b1) * 0.5
	var slope_h := bot_c.distance_to(top_c)
	var num_rows := maxi(3, int(slope_h / (px * 2.0)))
	var dark    := PixelPalette.shade(col, 0.58)

	for r in range(num_rows):
		var t0 := float(r) / float(num_rows)
		var t1 := float(r + 1) / float(num_rows)
		var ra := a0.lerp(a1, t0); var rb := b0.lerp(b1, t0)
		var ta := a0.lerp(a1, t1); var tb := b0.lerp(b1, t1)
		var row_col := PixelPalette.shade(col, 1.0 + float(r) / float(num_rows) * 0.22)
		row_col.a = alpha
		canvas.draw_colored_polygon(PackedVector2Array([ra, rb, tb, ta]), row_col)
		if (rb - ra).length() > px * 2.0:
			var lc := dark; lc.a = alpha * 0.5
			canvas.draw_colored_polygon(PackedVector2Array([
				ra, rb, rb + Vector2(0.0, px), ra + Vector2(0.0, px)]), lc)


# ──────────────────────────────────────────────── public API ──────────────────

## Floor + back walls (NW, NE) — always visible. Includes architectural shadow.
static func draw_body(canvas: CanvasItem, foot: float, variant: int, _accent: Color,
		_style: String = "medieval") -> void:
	var px := float(PixelPalette.PX)
	var e  := _ext(foot)
	var w  := Vector2(-e.x, 0.0)
	var n  := Vector2(0.0, -e.y)
	var s_pt := Vector2(0.0, e.y)
	var east := Vector2(e.x, 0.0)
	var h  := wall_height(foot, variant)

	# Building shadow: footprint + a smaller offset roof diamond hulled into one
	# leaning house silhouette (not a swept slab). Length is clamped in WorldLighting.
	ShadowProjector.cast_silhouette(canvas,
		PackedVector2Array([w, n, east, s_pt]), total_height(foot, variant), 0.6)

	# Floor diamond — stone/plank colour, pixel-snapped
	var floor_c := PixelPalette.shade(PixelPalette.pal("stone_b"), 0.88)
	PixelDraw.px_diamond(canvas, 0.0, 0.0, e.x, e.y, floor_c)

	# Isometric floor planks — lines stay inside the diamond by using the
	# diamond's actual width at each screen-y level (avoids the old overshoot bug).
	var seam_c := PixelPalette.shade(floor_c, 0.82)
	var ky := PixelPalette.snap(-e.y + px * 2.0)
	while ky < e.y - px:
		# Diamond half-width at screen-y ky: hw = e.x * (1 - |ky| / e.y)
		var t  := absf(ky) / e.y
		var hw := e.x * (1.0 - t) - px * 2.0
		if hw > px:
			PixelDraw.px_rect(canvas, PixelPalette.snap(-hw), PixelPalette.snap(ky),
				PixelPalette.snap(hw * 2.0), px, seam_c)
		ky += px * 2.0

	# Back walls: NW (w→n) and NE (n→east)
	_wall_face(canvas, w, n,    h, 0.86, variant, 1, false, 1.0)
	_wall_face(canvas, n, east, h, 1.04, variant, 2, false, 1.0)

	# Optional interior partition
	if variant % 3 != 0:
		var mid := w.lerp(east, 0.5)
		var pf  := 0.4 + float(variant % 3) * 0.12
		_wall_face(canvas, mid, n.lerp(s_pt, pf), h * 0.6, 0.92, variant, 5, false, 1.0)

	_furnish(canvas, foot, variant)


## Front walls + roof — fade as the player steps inside.
static func draw_roof(canvas: CanvasItem, foot: float, variant: int, roof_color: Color,
		alpha: float, _style: String = "medieval") -> void:
	if alpha <= 0.02:
		return
	var e    := _ext(foot)
	var w    := Vector2(-e.x, 0.0)
	var n    := Vector2(0.0, -e.y)
	var s_pt := Vector2(0.0, e.y)
	var east := Vector2(e.x, 0.0)
	var h    := wall_height(foot, variant)

	# Front walls: SW (w→s) and SE (s→east) with door at south corner
	_wall_face(canvas, w,    s_pt, h, 0.78, variant, 3, false, alpha)
	_wall_face(canvas, s_pt, east, h, 0.98, variant, 4, false, alpha)
	var door := PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.62)
	var door_top := PixelPalette.shade(PixelPalette.pal("trunk_a"), 0.85)
	_panel(canvas, w,    s_pt, h, 0.80, 1.00, 0.0, 0.46, door,     alpha)
	_panel(canvas, s_pt, east, h, 0.00, 0.20, 0.0, 0.46, door,     alpha)
	_panel(canvas, w,    s_pt, h, 0.80, 1.00, 0.44, 0.48, door_top, alpha)
	_panel(canvas, s_pt, east, h, 0.00, 0.20, 0.44, 0.48, door_top, alpha)

	_draw_roof(canvas, foot, variant, roof_color, alpha)


# ──────────────────────────────────────────────── roof geometry ───────────────

static func _draw_roof(canvas: CanvasItem, foot: float, variant: int,
		roof_color: Color, alpha: float) -> void:
	var px := float(PixelPalette.PX)
	var e  := _ext(foot)
	var h  := wall_height(foot, variant)
	var rh := roof_height(foot, variant)
	var ov := 5.0 + foot * 0.6   # eave overhang

	var top  := Vector2(0.0, -h)
	var W    := Vector2(-e.x, 0.0) + top
	var N    := Vector2(0.0, -e.y) + top
	var E    := Vector2(e.x, 0.0) + top
	var S    := Vector2(0.0, e.y) + top
	var eW   := W + Vector2(-ov, ov * 0.40)
	var eE   := E + Vector2( ov, ov * 0.40)
	var eN   := N + Vector2(0.0, -ov * 0.35)
	var eS   := S + Vector2(0.0,  ov * 0.50)

	var hi   := PixelPalette.shade(roof_color, 1.18)
	var mid  := roof_color
	var lo   := PixelPalette.shade(roof_color, 0.74)
	var dark := PixelPalette.shade(roof_color, 0.55)
	var rtype := variant % 3

	if rtype == 0:
		# ── Hip roof ──────────────────────────────────────────────────────────
		var apex := Vector2(0.0, -h - rh)
		# Back faces (lower detail — viewer faces away)
		_tri(canvas, PackedVector2Array([eW, eN, apex]), lo,  alpha * 0.92)
		_tri(canvas, PackedVector2Array([eN, eE, apex]), mid, alpha * 0.92)
		# Front faces — full shingle rows
		_shingle_tri(canvas, eW, eS, apex, dark, alpha)
		_shingle_tri(canvas, eS, eE, apex, hi,   alpha)
	else:
		# ── Gabled roof ───────────────────────────────────────────────────────
		var ridge_a: Vector2
		var ridge_b: Vector2
		if rtype == 1:
			ridge_a = (eW + eN) * 0.5 + Vector2(0.0, -rh)
			ridge_b = (eS + eE) * 0.5 + Vector2(0.0, -rh)
		else:
			ridge_a = (eN + eE) * 0.5 + Vector2(0.0, -rh)
			ridge_b = (eW + eS) * 0.5 + Vector2(0.0, -rh)

		var plaster: Color = PLASTERS[variant % PLASTERS.size()]
		# Gable-end triangles (plaster-filled, no shingles)
		if rtype == 1:
			_tri(canvas, PackedVector2Array([eW, eN, ridge_a]), plaster, alpha)
			_tri(canvas, PackedVector2Array([eS, eE, ridge_b]), plaster, alpha)
			_shingle_quad(canvas, eW, eS, ridge_a, ridge_b, lo, alpha)
			_shingle_quad(canvas, eN, eE, ridge_a, ridge_b, hi, alpha)
		else:
			_tri(canvas, PackedVector2Array([eN, eE, ridge_a]), plaster, alpha)
			_tri(canvas, PackedVector2Array([eW, eS, ridge_b]), plaster, alpha)
			_shingle_quad(canvas, eN, eW, ridge_a, ridge_b, hi, alpha)
			_shingle_quad(canvas, eE, eS, ridge_a, ridge_b, lo, alpha)
		# Ridge beam — pixel-snapped thick bar
		var rc := PixelPalette.shade(roof_color, 1.32); rc.a = alpha
		var rp := px
		canvas.draw_colored_polygon(PackedVector2Array([
			ridge_a + Vector2(-rp, -rp), ridge_b + Vector2(rp, -rp),
			ridge_b + Vector2(rp,  rp),  ridge_a + Vector2(-rp, rp)]), rc)

	# Chimney — pixel-art stone stack with courses
	if variant % 4 != 0:
		var cx  := e.x * (0.4 if variant % 2 == 0 else -0.4)
		var cb  := Vector2(cx, -h - rh * 0.45)
		var st  := PixelPalette.pal("stone_a")
		PixelDraw.px_rect(canvas, cb.x - 4.0, cb.y - 20.0, 10.0, 22.0, PixelPalette.shade(st, 0.86), alpha)
		PixelDraw.px_rect(canvas, cb.x - 5.0, cb.y - 22.0, 12.0,  4.0, PixelPalette.shade(st, 1.1),  alpha)
		# Chimney coursing (2 lines)
		PixelDraw.px_rect(canvas, cb.x - 4.0, cb.y - 14.0, 10.0, float(PixelPalette.PX), PixelPalette.shade(st, 0.70), alpha * 0.6)
		PixelDraw.px_rect(canvas, cb.x - 4.0, cb.y -  7.0, 10.0, float(PixelPalette.PX), PixelPalette.shade(st, 0.70), alpha * 0.6)


# ──────────────────────────────────────────────── interior ────────────────────

## Small isometric prop box at tile-offset (dx, dy) from the building centre.
static func _box(canvas: CanvasItem, dx: float, dy: float, half: float, tall: float,
		top: Color, side: Color) -> void:
	var sx := (dx - dy) * float(WG.ISO_HW)
	var sy := (dx + dy) * float(WG.ISO_HH)
	PixelDraw.px_blob(canvas, sx, sy + 1.0, half * 1.05, half * 0.5, PixelPalette.pal("shadow"), 0.20)
	PixelDraw.px_rect(canvas, sx - half, sy - tall, half * 2.0, tall, side)
	PixelDraw.px_diamond(canvas, sx, sy - tall, half, half * 0.5, top)


## Interior furniture keyed to the building role (variant % 4).
static func _furnish(canvas: CanvasItem, foot: float, variant: int) -> void:
	var ex    := foot * 0.5 - 1.5
	var wood  := PixelPalette.pal("trunk_a")
	var wood_d:= PixelPalette.pal("trunk_b")
	var cloth := PixelPalette.pal("outfit_a")
	var stone := PixelPalette.pal("stone_a")
	var green := PixelPalette.pal("grass_b")
	var role  := variant % 4
	var rug   := (cloth if role == 0 else PixelPalette.pal("water_a")).lerp(wood_d, 0.3)
	PixelDraw.px_diamond(canvas, 0.0, 0.0, foot * 3.4, foot * 1.7, rug, 0.48)
	match role:
		0:  # home
			_box(canvas, -ex * 0.75, -ex * 0.75, 18.0, 9.0, cloth, PixelPalette.shade(cloth, 0.7))
			_box(canvas, -ex * 0.75, -ex * 0.55, 6.0,  6.0, Color(0.9, 0.88, 0.82), cloth)
			_box(canvas,  ex * 0.15, -ex * 0.15, 14.0, 9.0, wood, wood_d)
			_box(canvas,  ex * 0.15 - 3.0, -ex * 0.15 + 3.0, 6.0, 8.0, wood_d, wood_d)
			_box(canvas,  ex * 0.45, -ex * 0.40, 6.0,  8.0, wood_d, wood_d)
			_box(canvas,  ex * 0.80,  ex * 0.20, 11.0, 18.0, stone, PixelPalette.shade(stone, 0.7))
			_box(canvas, -ex * 0.70,  ex * 0.70, 8.0,  11.0, green, PixelPalette.shade(green, 0.7))
			_box(canvas, -ex * 0.20,  ex * 0.70, 12.0, 14.0, wood, wood_d)
		1:  # shop
			_box(canvas,  0.0,        ex * 0.60, foot * 1.1, 10.0, wood, wood_d)
			_box(canvas, -ex * 0.80, -ex * 0.70, 18.0, 22.0, wood_d, PixelPalette.shade(wood_d, 0.8))
			_box(canvas,  ex * 0.70, -ex * 0.70, 18.0, 22.0, wood_d, PixelPalette.shade(wood_d, 0.8))
			_box(canvas, -ex * 0.40,  ex * 0.05, 10.0, 12.0, PixelPalette.shade(wood, 0.9), wood_d)
			_box(canvas,  ex * 0.35, -ex * 0.15, 9.0,  13.0, wood, wood_d)
		2:  # workshop
			_box(canvas, -ex * 0.25, -ex * 0.50, foot * 0.8, 11.0, wood_d, PixelPalette.shade(wood_d, 0.8))
			_box(canvas,  ex * 0.60, -ex * 0.40, 11.0, 16.0, stone, PixelPalette.shade(stone, 0.7))
			_box(canvas, -ex * 0.70,  ex * 0.40, 9.0,  14.0, wood, wood_d)
			_box(canvas, -ex * 0.40,  ex * 0.60, 9.0,  14.0, wood, wood_d)
			_box(canvas,  ex * 0.55,  ex * 0.50, 10.0, 13.0, PixelPalette.shade(wood, 0.85), wood_d)
		_:  # inn / hall
			for t in 3:
				var u := (float(t) - 1.0) * ex * 0.7
				_box(canvas, u, -u * 0.35 - ex * 0.2, 12.0, 9.0, wood, wood_d)
				_box(canvas, u - 3.0, -u * 0.35 - ex * 0.2 + 3.0, 6.0, 8.0, wood_d, wood_d)
			_box(canvas, -ex * 0.75, ex * 0.55, 9.0, 14.0, wood, wood_d)
			_box(canvas,  ex * 0.75, ex * 0.55, 9.0, 14.0, wood, wood_d)
			_box(canvas,  ex * 0.80, -ex * 0.60, 11.0, 18.0, stone, PixelPalette.shade(stone, 0.7))
	# Scattered clutter
	for i in 3 + (variant % 3):
		var rx := (WG.r01(variant, i, 0, 51) - 0.5) * 2.0 * ex * 0.85
		var ry := (WG.r01(variant, i, 1, 0) - 0.5) * 2.0 * ex * 0.85
		var crate := i % 2 == 0
		_box(canvas, rx, ry, 7.0 if crate else 8.0, 9.0 if crate else 12.0,
			PixelPalette.shade(wood, 0.92) if crate else wood, wood_d)
