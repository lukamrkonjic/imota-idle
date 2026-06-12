extends RefCounted
## Smooth stylized trees — round cloud canopies, species mapped by node name.

class_name TreeArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")


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
	var base := 74.0 + float(level) * 0.14
	return base * lerpf(0.94, 1.10, _hash01(name + "|height"))


static func estimated_height(tree_type: String, size: float) -> float:
	match tree_type:
		"fir":
			return size * 1.05
		"palm":
			return size * 1.12
		"willow":
			return size * 0.95
		_:
			return size * 0.92


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
	PixelDraw.draw_tree_shadow(canvas, s * 0.52, 0.20)
	match tree_type:
		"fir":
			_draw_fir(canvas, s, depleted, name.to_lower().contains("lunarwood"))
		"palm":
			_draw_palm(canvas, s, depleted)
		"willow":
			_draw_willow(canvas, s, foliage_color(tree_type, tier, name), depleted)
		"magic":
			_draw_magic(canvas, s, foliage_color(tree_type, tier, name), depleted, t)
		"maple", "broadleaf":
			var wide := 1.12 if name.to_lower().contains("oak") else 1.0
			_draw_roundtree(canvas, s, foliage_color(tree_type, tier, name), depleted, wide)
		"dead":
			_draw_dead(canvas, s)
		_:
			_draw_roundtree(canvas, s, foliage_color(tree_type, tier, name), depleted, 1.0)


static func _draw_stump(canvas: CanvasItem, s: float) -> void:
	PixelDraw.draw_ellipse(canvas, 0.0, -s * 0.06, s * 0.14, s * 0.08, PixelPalette.pal("trunk_b"))
	canvas.draw_rect(Rect2(-s * 0.10, -s * 0.22, s * 0.20, s * 0.16), PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.9))


## Classic round tree — 3 soft cloud puffs + simple trunk (Aldenfall reference style).
static func _draw_roundtree(canvas: CanvasItem, s: float, leaf: Color, depleted: bool, wide: float) -> void:
	if depleted:
		_draw_stump(canvas, s)
		return
	var trunk_w := s * 0.07 * wide
	var trunk_h := s * 0.30
	PixelDraw.draw_simple_trunk(canvas, trunk_w, trunk_h)
	var base_y := -trunk_h
	PixelDraw.draw_cloud_clump(canvas, -s * 0.12 * wide, base_y - s * 0.18, s * 0.30 * wide, s * 0.24, PixelPalette.shade(leaf, 0.88))
	PixelDraw.draw_cloud_clump(canvas, s * 0.14 * wide, base_y - s * 0.14, s * 0.26 * wide, s * 0.22, PixelPalette.shade(leaf, 0.92))
	PixelDraw.draw_cloud_clump(canvas, 0.0, base_y - s * 0.36, s * 0.34 * wide, s * 0.30, leaf)


## Conifer — smooth stacked ellipses tapering upward.
static func _draw_fir(canvas: CanvasItem, s: float, depleted: bool, snow: bool) -> void:
	if depleted:
		_draw_stump(canvas, s * 0.8)
		return
	PixelDraw.draw_simple_trunk(canvas, s * 0.05, s * 0.14, PixelPalette.pal("trunk_b"), PixelPalette.shade(PixelPalette.pal("trunk_b"), 0.85))
	var lit := PixelPalette.pal("fir_a")
	var dark := PixelPalette.pal("fir_b")
	var y := -s * 0.14
	var layers: PackedFloat32Array = PackedFloat32Array([0.46, 0.38, 0.30, 0.22])
	for i: int in range(layers.size()):
		var rx: float = s * layers[i] * 0.5
		var ry: float = s * 0.16
		var col := lit if i % 2 == 0 else dark
		PixelDraw.draw_ellipse(canvas, 0.0, y, rx, ry, col)
		if snow and i >= 2:
			var snow_c := PixelPalette.pal("snow_a")
			snow_c.a = 0.75
			PixelDraw.draw_ellipse(canvas, 0.0, y - ry * 0.35, rx * 0.55, ry * 0.28, snow_c)
		y -= s * 0.17
	PixelDraw.draw_ellipse(canvas, 0.0, y - s * 0.04, s * 0.06, s * 0.05, PixelPalette.shade(lit, 1.2))


## Palm — curved trunk + fan of smooth leaf ellipses.
static func _draw_palm(canvas: CanvasItem, s: float, depleted: bool) -> void:
	if depleted:
		_draw_stump(canvas, s * 0.7)
		return
	var h := s * 0.95
	var trunk := PixelPalette.pal("trunk_a")
	var trunk_d := PixelPalette.pal("trunk_b")
	for i: int in 6:
		var ty := -float(i) / 6.0 * h
		var bend := sin(float(i) / 6.0 * 0.9) * s * 0.04
		PixelDraw.draw_ellipse(canvas, bend, ty, s * 0.055, s * 0.07, trunk if i % 2 == 0 else trunk_d)
	var top := Vector2(sin(0.9) * s * 0.04, -h)
	var leaf := PixelPalette.pal("grass_a")
	for i: int in 7:
		var a := -PI * 0.5 + float(i - 3) * 0.38
		var len := s * 0.42
		var end := top + Vector2(cos(a) * len, sin(a) * len * 0.55)
		var mid := top.lerp(end, 0.55)
		PixelDraw.draw_ellipse(canvas, mid.x, mid.y, s * 0.11, s * 0.05, leaf if i % 2 == 0 else PixelPalette.shade(leaf, 0.85))
		PixelDraw.draw_ellipse(canvas, end.x, end.y, s * 0.07, s * 0.04, PixelPalette.shade(leaf, 0.78))
	PixelDraw.draw_ellipse(canvas, top.x, top.y, s * 0.06, s * 0.05, trunk_d)


## Willow — dome crown + smooth hanging drapes.
static func _draw_willow(canvas: CanvasItem, s: float, leaf: Color, depleted: bool) -> void:
	if depleted:
		_draw_stump(canvas, s)
		return
	PixelDraw.draw_simple_trunk(canvas, s * 0.06, s * 0.38)
	var crown_y := -s * 0.38
	PixelDraw.draw_cloud_clump(canvas, 0.0, crown_y, s * 0.32, s * 0.22, leaf)
	for i: int in 5:
		var ox := lerpf(-s * 0.28, s * 0.28, float(i) / 4.0)
		var drop_len := s * 0.32 + float(i % 2) * s * 0.06
		var hang := Color(leaf.r, leaf.g, leaf.b, 0.72)
		for j: int in 4:
			var frac := float(j + 1) / 4.0
			var py := crown_y + drop_len * frac
			var px := ox + sin(frac * PI) * s * 0.04
			PixelDraw.draw_ellipse(canvas, px, py, s * 0.045, s * 0.07, PixelPalette.shade(hang, 1.0 - frac * 0.15))


## Magic — round tree + soft glowing orbs.
static func _draw_magic(canvas: CanvasItem, s: float, leaf: Color, depleted: bool, t: float) -> void:
	_draw_roundtree(canvas, s, leaf, depleted, 1.06)
	if depleted:
		return
	var pulse := 0.55 + 0.45 * sin(t * 2.8)
	for i: int in 4:
		var a := float(i) / 4.0 * TAU + t * 0.5
		var dist := s * 0.26
		var c := leaf.lightened(0.35)
		c.a = 0.35 + pulse * 0.35
		PixelDraw.draw_ellipse(canvas, cos(a) * dist, -s * 0.48 + sin(a) * dist * 0.3, s * 0.07, s * 0.07, c)


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
