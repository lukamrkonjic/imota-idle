extends RefCounted
## Smooth stylized trees — round cloud canopies, species mapped by node name.

class_name TreeArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

static var _wind_t := 0.0


static func advance_wind(delta: float) -> void:
	_wind_t += delta


static func wind_time() -> float:
	return _wind_t


## Horizontal canopy sway in px — trunk stays pinned at origin.
static func canopy_sway(size: float, phase: float) -> Vector2:
	var a := _wind_t * 1.35 + phase
	return Vector2(
		sin(a) * size * 0.026 + sin(a * 2.17 + 1.4) * size * 0.007,
		sin(a * 0.85 + 0.6) * size * 0.004)


static func _with_canopy_sway(canvas: CanvasItem, size: float, phase: float, draw_canopy: Callable) -> void:
	var sway := canopy_sway(size, phase)
	canvas.draw_set_transform(sway, 0.0, Vector2.ONE)
	draw_canopy.call()
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _hash01(key: String) -> float:
	return float(absi(hash(key)) % 10000) / 10000.0


static func classify(name: String) -> String:
	var n := name.to_lower()
	if n.contains("willow"):
		return "willow"
	if n.contains("pine") or n.contains("yew") or n.contains("lunarwood") or n.contains("bitterpine"):
		return "fir"
	if n.contains("dune") or n.contains("suncoil"):
		return "palm"
	if n.contains("magic") or n.contains("aether") or n.contains("imbued"):
		return "magic"
	if n.contains("maple") or n.contains("rubra"):
		return "maple"
	if n.contains("dead"):
		return "dead"
	return "broadleaf"


static func tree_size(level: int, name: String) -> float:
	var base := 104.0 + float(level) * 0.16
	return base * lerpf(0.98, 1.14, _hash01(name + "|height"))


static func estimated_height(tree_type: String, size: float) -> float:
	match tree_type:
		"fir":
			return size * 1.35
		"palm":
			return size * 1.28
		"willow":
			return size * 1.15
		_:
			return size * 1.22


static func foliage_color(tree_type: String, tier: Color, name: String) -> Color:
	match tree_type:
		"maple":
			if name.to_lower().contains("red") or name.to_lower().contains("rubra"):
				return PixelPalette.pal("dirt_b")
			return PixelPalette.pal("gold")
		"fir":
			return PixelPalette.pal("fir_a")
		"magic":
			# Arcane purple with a hint of the tier color for higher trees.
			var arcane := PixelPalette.pal("outfit_a")
			return arcane.lerp(tier, 0.25) if tier.a > 0.01 else arcane
		"willow":
			return PixelPalette.pal("grass_b")
		"palm":
			return PixelPalette.pal("grass_a")
		_:
			if name.to_lower().contains("oak"):
				return PixelPalette.pal("grass_a")
			if name.to_lower().contains("eucalyptus"):
				return PixelPalette.pal("stone_b").lerp(PixelPalette.pal("grass_a"), 0.55)
			if name.to_lower().contains("teak"):
				return PixelPalette.pal("moss")
			# Natural green varied per species name — never the raw tier color,
			# which made low trees brown and high trees red.
			var t := _hash01(name + "|leaf")
			return PixelPalette.pal("grass_a").lerp(PixelPalette.pal("grass_b"), t * 0.42)


static func draw(canvas: CanvasItem, name: String, size: float, tier: Color, depleted: bool, t: float) -> void:
	var tree_type := classify(name)
	var s := size
	PixelDraw.draw_tree_shadow(canvas, s * 0.22, 0.10)
	match tree_type:
		"fir":
			_draw_fir(canvas, s, depleted, name.to_lower().contains("lunarwood"), t)
		"palm":
			_draw_palm(canvas, s, depleted, t)
		"willow":
			_draw_willow(canvas, s, foliage_color(tree_type, tier, name), depleted, t)
		"magic":
			_draw_magic(canvas, s, foliage_color(tree_type, tier, name), depleted, t)
		"maple", "broadleaf":
			var wide := 1.12 if name.to_lower().contains("oak") else 1.0
			_draw_roundtree(canvas, s, foliage_color(tree_type, tier, name), depleted, wide, t)
		"dead":
			_draw_dead(canvas, s)
		_:
			_draw_roundtree(canvas, s, foliage_color(tree_type, tier, name), depleted, 1.0, t)


static func _draw_stump(canvas: CanvasItem, s: float) -> void:
	PixelDraw.draw_ellipse(canvas, 0.0, -s * 0.06, s * 0.14, s * 0.08, PixelPalette.pal("trunk_b"))
	canvas.draw_rect(Rect2(-s * 0.10, -s * 0.22, s * 0.20, s * 0.16), PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.9))


## Concept-art broadleaf — rooted trunk, forked branches, layered canopy.
static func _draw_roundtree(canvas: CanvasItem, s: float, leaf: Color, depleted: bool, wide: float, phase: float) -> void:
	if depleted:
		_draw_stump(canvas, s)
		return
	leaf = PixelPalette.enrich_entity(leaf)
	var trunk_h := s * 0.44
	var trunk_w := s * 0.062 * wide
	_draw_ground_collar(canvas, s, wide)
	_draw_concept_trunk(canvas, trunk_w, trunk_h, wide)
	var fork_y := -trunk_h + s * 0.03
	_with_canopy_sway(canvas, s, phase, func() -> void:
		_draw_concept_branch(canvas, -trunk_w * 0.5, fork_y, -s * 0.18 * wide, fork_y - s * 0.09)
		_draw_concept_branch(canvas, trunk_w * 0.45, fork_y, s * 0.20 * wide, fork_y - s * 0.10)
		var canopy_base := fork_y - s * 0.05
		PixelDraw.draw_foliage_clump(canvas, -s * 0.18 * wide, canopy_base - s * 0.14, s * 0.26 * wide, s * 0.22, PixelPalette.shade(leaf, 0.88))
		PixelDraw.draw_foliage_clump(canvas, s * 0.16 * wide, canopy_base - s * 0.10, s * 0.24 * wide, s * 0.20, PixelPalette.shade(leaf, 0.92))
		PixelDraw.draw_foliage_clump(canvas, 0.0, canopy_base - s * 0.36, s * 0.34 * wide, s * 0.28, leaf)
		PixelDraw.draw_foliage_clump(canvas, -s * 0.05 * wide, canopy_base - s * 0.50, s * 0.22 * wide, s * 0.18, PixelPalette.shade(leaf, 1.12))
		PixelDraw.draw_foliage_clump(canvas, s * 0.06 * wide, canopy_base - s * 0.54, s * 0.18 * wide, s * 0.15, PixelPalette.shade(leaf, 1.16))
	)


static func _draw_ground_collar(canvas: CanvasItem, s: float, wide: float) -> void:
	var dirt := PixelPalette.pal("dirt_a")
	var grass := PixelPalette.pal("grass_a")
	var grass_d := PixelPalette.pal("grass_c")
	var px := float(PixelPalette.PX)
	PixelDraw.px_blob(canvas, 0.0, px * 0.8, s * 0.13 * wide, s * 0.045, dirt, 0.62)
	PixelDraw.px_blob(canvas, 0.0, px * 0.4, s * 0.09 * wide, s * 0.03, PixelPalette.shade(dirt, 0.88), 0.50)
	for i: int in range(5):
		var t := float(i) / 4.0
		var tx := lerpf(-s * 0.16 * wide, s * 0.16 * wide, t)
		var col := grass if i % 2 == 0 else grass_d
		PixelDraw.px_rect(canvas, tx - px, -px * 0.5, px, px * 1.5, col, 0.85)
		if i % 3 == 0:
			PixelDraw.px_rect(canvas, tx, -px * 1.2, px, px, PixelPalette.shade(col, 1.1), 0.7)


static func _draw_concept_trunk(canvas: CanvasItem, half_w: float, height: float, wide: float) -> void:
	var bark := PixelPalette.pal("trunk_a")
	var shadow := PixelPalette.pal("trunk_b")
	var px := float(PixelPalette.PX)
	var w := half_w * 0.78 * wide
	var top_y := -height
	var steps := maxi(4, int(height / (px * 2.5)))
	for i: int in range(steps):
		var t := (float(i) + 0.5) / float(steps)
		var row_y := top_y + t * height
		var row_w := lerpf(w * 0.62, w, t)
		var col := bark if i % 2 == 0 else PixelPalette.shade(bark, 0.95)
		PixelDraw.px_blob(canvas, 0.0, row_y, row_w, px * 1.15, col)
	PixelDraw.px_blob(canvas, w * 0.18, top_y + height * 0.38, w * 0.32, height * 0.34, shadow, 0.28)


static func _draw_concept_branch(canvas: CanvasItem, x0: float, y0: float, x1: float, y1: float) -> void:
	var bark := PixelPalette.pal("trunk_b")
	var px := float(PixelPalette.PX)
	var dist := Vector2(x1 - x0, y1 - y0).length()
	var steps := maxi(2, int(dist / px))
	for i: int in range(steps + 1):
		var p := Vector2(x0, y0).lerp(Vector2(x1, y1), float(i) / float(steps))
		PixelDraw.px_rect(canvas, p.x - px, p.y - px, px * 2.0, px * 2.0, bark)


## Conifer — smooth stacked ellipses tapering upward.
static func _draw_fir(canvas: CanvasItem, s: float, depleted: bool, snow: bool, phase: float) -> void:
	if depleted:
		_draw_stump(canvas, s * 0.8)
		return
	_draw_ground_collar(canvas, s, 0.85)
	_draw_concept_trunk(canvas, s * 0.05, s * 0.22, 0.85)
	var lit := PixelPalette.pal("fir_a")
	var dark := PixelPalette.pal("fir_b")
	_with_canopy_sway(canvas, s, phase, func() -> void:
		var y := -s * 0.22
		var layers: PackedFloat32Array = PackedFloat32Array([0.50, 0.42, 0.34, 0.26, 0.18])
		for i: int in range(layers.size()):
			var rx: float = s * layers[i] * 0.5
			var ry: float = s * 0.16
			var col := lit if i % 2 == 0 else dark
			PixelDraw.draw_ellipse(canvas, 0.0, y, rx, ry, col)
			if snow and i >= 2:
				var snow_c := PixelPalette.pal("snow_a")
				snow_c.a = 0.75
				PixelDraw.draw_ellipse(canvas, 0.0, y - ry * 0.35, rx * 0.55, ry * 0.28, snow_c)
			y -= s * 0.15
		PixelDraw.draw_ellipse(canvas, 0.0, y - s * 0.04, s * 0.06, s * 0.05, PixelPalette.shade(lit, 1.2))
	)


## Palm — curved trunk + fan of smooth leaf ellipses.
static func _draw_palm(canvas: CanvasItem, s: float, depleted: bool, phase: float) -> void:
	if depleted:
		_draw_stump(canvas, s * 0.7)
		return
	var h := s * 1.18
	var trunk := PixelPalette.pal("trunk_a")
	var trunk_d := PixelPalette.pal("trunk_b")
	for i: int in 6:
		var ty := -float(i) / 6.0 * h
		var bend := sin(float(i) / 6.0 * 0.9) * s * 0.04
		PixelDraw.draw_ellipse(canvas, bend, ty, s * 0.055, s * 0.07, trunk if i % 2 == 0 else trunk_d)
	var top := Vector2(sin(0.9) * s * 0.04, -h)
	var leaf := PixelPalette.pal("grass_a")
	_with_canopy_sway(canvas, s, phase, func() -> void:
		for i: int in 7:
			var a := -PI * 0.5 + float(i - 3) * 0.38
			var len := s * 0.42
			var end := top + Vector2(cos(a) * len, sin(a) * len * 0.55)
			var mid := top.lerp(end, 0.55)
			PixelDraw.draw_ellipse(canvas, mid.x, mid.y, s * 0.11, s * 0.05, leaf if i % 2 == 0 else PixelPalette.shade(leaf, 0.85))
			PixelDraw.draw_ellipse(canvas, end.x, end.y, s * 0.07, s * 0.04, PixelPalette.shade(leaf, 0.78))
		PixelDraw.draw_ellipse(canvas, top.x, top.y, s * 0.06, s * 0.05, trunk_d)
	)


## Willow — dome crown + smooth hanging drapes.
static func _draw_willow(canvas: CanvasItem, s: float, leaf: Color, depleted: bool, phase: float) -> void:
	if depleted:
		_draw_stump(canvas, s)
		return
	leaf = PixelPalette.enrich_entity(leaf)
	_draw_ground_collar(canvas, s, 1.0)
	_draw_concept_trunk(canvas, s * 0.06, s * 0.48, 1.0)
	var crown_y := -s * 0.48
	_with_canopy_sway(canvas, s, phase, func() -> void:
		PixelDraw.draw_foliage_clump(canvas, 0.0, crown_y, s * 0.34, s * 0.24, leaf)
		for i: int in 5:
			var ox := lerpf(-s * 0.28, s * 0.28, float(i) / 4.0)
			var drop_len := s * 0.32 + float(i % 2) * s * 0.06
			var hang := Color(leaf.r, leaf.g, leaf.b, 0.72)
			for j: int in 4:
				var frac := float(j + 1) / 4.0
				var py := crown_y + drop_len * frac
				var px := ox + sin(frac * PI) * s * 0.04
				PixelDraw.draw_ellipse(canvas, px, py, s * 0.045, s * 0.07, PixelPalette.shade(hang, 1.0 - frac * 0.15))
	)


## Magic — round tree + soft glowing orbs.
static func _draw_magic(canvas: CanvasItem, s: float, leaf: Color, depleted: bool, t: float) -> void:
	_draw_roundtree(canvas, s, leaf, depleted, 1.06, t)
	if depleted:
		return
	var pulse := 0.55 + 0.45 * sin(t * 2.8)
	var sway := canopy_sway(s, t)
	for i: int in 4:
		var a := float(i) / 4.0 * TAU + t * 0.5
		var dist := s * 0.26
		var c := leaf.lightened(0.35)
		c.a = 0.35 + pulse * 0.35
		PixelDraw.draw_ellipse(
			canvas,
			cos(a) * dist + sway.x,
			-s * 0.48 + sin(a) * dist * 0.3 + sway.y,
			s * 0.07, s * 0.07, c)


static func _draw_dead(canvas: CanvasItem, s: float) -> void:
	PixelDraw.draw_simple_trunk(canvas, s * 0.06, s * 0.36, PixelPalette.shade(PixelPalette.pal("trunk_b"), 1.05), PixelPalette.pal("trunk_b"))
	# Gnarled branches as stepped pixel runs (drawIsoDeadTree).
	var bark := PixelPalette.pal("trunk_b")
	var px := float(PixelPalette.PX)
	for pt: Vector2 in [Vector2(-s * 0.38, -s * 0.52), Vector2(s * 0.40, -s * 0.55), Vector2(-s * 0.22, -s * 0.68)]:
		var from := Vector2(0, -s * 0.36)
		var steps := maxi(2, int(from.distance_to(pt) / px))
		for i: int in steps + 1:
			var p := from.lerp(pt, float(i) / float(steps))
			PixelDraw.px_rect(canvas, p.x - px, p.y - px, px * 2.0, px * 2.0, bark)
		PixelDraw.px_rect(canvas, pt.x, pt.y - s * 0.1, px * 2.0, px * 2.0, PixelPalette.shade(bark, 1.08))
