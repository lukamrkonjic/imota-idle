extends RefCounted
class_name EnemyCreatureArt
## Species-specific pixel models for early-game enemies (levels 1–10).

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")


static func species_for_name(name: String) -> String:
	var n := name.to_lower()
	if n.contains("chicken"):
		return "chicken"
	if n.contains("cow"):
		return "cow"
	if n.contains("crab"):
		return "crab"
	if n.contains("bat"):
		return "bat"
	if n.contains("goblin"):
		return "goblin"
	if n.contains("goat"):
		return "goat"
	if n.contains("pig"):
		return "pig"
	if n.contains("sheep"):
		return "sheep"
	if n.contains("wolf"):
		return "wolf"
	if n.contains("brainbasher"):
		return "brainbasher"
	return ""


static func shadow_half_width(species: String, size: float, boss: bool) -> float:
	var scale := 1.18 if boss else 1.0
	match species:
		"cow", "pig", "sheep", "wolf":
			return size * 0.36 * scale
		"goat":
			return size * 0.30 * scale
		"chicken", "crab", "bat":
			return size * 0.22 * scale
		"goblin", "brainbasher":
			return size * 0.24 * scale
		_:
			return size * 0.28 * scale


static func variant_scale(name: String) -> float:
	var n := name.to_lower()
	if n.contains("mumma") or n.contains("momma"):
		return 1.24
	if n.contains("brawler"):
		return 1.14
	if n.contains("rider"):
		return 1.10
	if n.contains("hobgoblin"):
		return 1.08
	if n.contains("cave"):
		return 1.06
	return 1.0


static func draw(canvas: CanvasItem, name: String, size: float, tint: Color, boss: bool, t: float, facing: int = 1) -> void:
	var species := species_for_name(name)
	if species.is_empty():
		return
	var s := size * variant_scale(name)
	var bob := sin(t * 3.0) * 1.5
	# Negative facing mirrors the creature so it turns to face its target; art is
	# authored facing +x.
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.12 * float(facing), 1.12))
	PixelDraw.draw_tight_character_shadow(canvas, shadow_half_width(species, size, boss))
	match species:
		"chicken":
			_draw_chicken(canvas, s, bob, tint, name)
		"cow":
			_draw_cow(canvas, s, bob, tint, name)
		"crab":
			_draw_crab(canvas, s, bob, tint)
		"bat":
			_draw_bat(canvas, s, bob, tint, name, t)
		"goblin":
			_draw_goblin(canvas, s, bob, tint, name, boss)
		"goat":
			_draw_goat(canvas, s, bob, tint)
		"pig":
			_draw_pig(canvas, s, bob, tint, name)
		"sheep":
			_draw_sheep(canvas, s, bob, tint, name)
		"wolf":
			_draw_wolf(canvas, s, bob, tint, name)
		"brainbasher":
			_draw_brainbasher(canvas, s, bob, tint, t, boss)
	if boss:
		_draw_boss_crown(canvas, s, bob)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_chicken(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String) -> void:
	var body := Color(0.92, 0.88, 0.78)
	var wing := Color(0.82, 0.74, 0.62)
	var comb := Color(0.78, 0.18, 0.14)
	var beak := Color(0.92, 0.62, 0.18)
	var leg := Color(0.92, 0.52, 0.16)
	if name.to_lower().contains("mumma"):
		body = Color(0.86, 0.72, 0.58)
		comb = Color(0.62, 0.12, 0.10)
	PixelDraw.px_blob(canvas, -s * 0.04, -s * 0.22 + bob, s * 0.34, s * 0.26, body)
	PixelDraw.px_blob(canvas, -s * 0.28, -s * 0.34 + bob, s * 0.18, s * 0.16, body)
	PixelDraw.px_rect(canvas, -s * 0.34, -s * 0.46 + bob, s * 0.10, s * 0.06, comb)
	PixelDraw.px_rect(canvas, -s * 0.42, -s * 0.32 + bob, s * 0.08, s * 0.04, beak)
	PixelDraw.px_blob(canvas, s * 0.08, -s * 0.20 + bob, s * 0.12, s * 0.10, wing, 0.88)
	PixelDraw.px_rect(canvas, s * 0.14, -s * 0.16 + bob, s * 0.06, s * 0.05, Color(0.72, 0.58, 0.38))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.30, -s * 0.36 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
	PixelDraw.px_rect(canvas, -s * 0.14, -s * 0.02 + bob, 3.0, s * 0.10, leg)
	PixelDraw.px_rect(canvas, -s * 0.04, -s * 0.02 + bob, 3.0, s * 0.10, leg)


static func _draw_cow(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String) -> void:
	var hide := Color(0.68, 0.48, 0.34)
	var patch := Color(0.88, 0.84, 0.78)
	var belly := Color(0.78, 0.70, 0.62)
	var hoof := Color(0.28, 0.22, 0.20)
	var horn := Color(0.82, 0.78, 0.70)
	var snout := Color(0.92, 0.78, 0.72)
	if name.to_lower().contains("momma"):
		hide = Color(0.58, 0.38, 0.28)
	PixelDraw.px_blob(canvas, s * 0.02, -s * 0.28 + bob, s * 0.46, s * 0.28, hide)
	PixelDraw.px_blob(canvas, s * 0.08, -s * 0.22 + bob, s * 0.28, s * 0.18, patch)
	PixelDraw.px_blob(canvas, -s * 0.34, -s * 0.36 + bob, s * 0.20, s * 0.18, hide)
	PixelDraw.px_blob(canvas, -s * 0.44, -s * 0.30 + bob, s * 0.12, s * 0.10, snout)
	PixelDraw.px_rect(canvas, -s * 0.36, -s * 0.48 + bob, 4.0, 4.0, horn, 0.85)
	PixelDraw.px_rect(canvas, -s * 0.28, -s * 0.50 + bob, 4.0, 4.0, horn, 0.85)
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.38, -s * 0.34 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
		PixelDraw.px_rect(canvas, -s * 0.46, -s * 0.28 + bob, 3.0, 3.0, Color(0.18, 0.12, 0.12))
	PixelDraw.px_blob(canvas, s * 0.22, -s * 0.18 + bob, s * 0.06, s * 0.08, Color(0.52, 0.38, 0.32), 0.75)
	for lx: float in [-s * 0.22, -s * 0.08, s * 0.08, s * 0.20]:
		PixelDraw.px_rect(canvas, lx, -s * 0.04 + bob, 4.0, s * 0.12, belly)
		PixelDraw.px_rect(canvas, lx, s * 0.06 + bob, 4.0, 3.0, hoof)
	if not SilhouetteDraw.active and name.to_lower().contains("momma"):
		PixelDraw.px_rect(canvas, s * 0.04, -s * 0.08 + bob, 3.0, 3.0, Color(0.92, 0.62, 0.68))
		PixelDraw.px_rect(canvas, s * 0.10, -s * 0.08 + bob, 3.0, 3.0, Color(0.92, 0.62, 0.68))


static func _draw_crab(canvas: CanvasItem, s: float, bob: float, _tint: Color) -> void:
	var shell := Color(0.72, 0.28, 0.22)
	var shell_hi := Color(0.88, 0.42, 0.32)
	var claw := Color(0.82, 0.34, 0.26)
	var leg := Color(0.58, 0.22, 0.18)
	PixelDraw.px_blob(canvas, 0.0, -s * 0.18 + bob, s * 0.38, s * 0.16, shell)
	PixelDraw.px_blob(canvas, 0.0, -s * 0.22 + bob, s * 0.24, s * 0.08, shell_hi, 0.82)
	PixelDraw.px_blob(canvas, -s * 0.34, -s * 0.22 + bob, s * 0.14, s * 0.10, claw)
	PixelDraw.px_blob(canvas, s * 0.34, -s * 0.22 + bob, s * 0.14, s * 0.10, claw)
	PixelDraw.px_rect(canvas, -s * 0.40, -s * 0.28 + bob, s * 0.08, s * 0.04, claw, 0.88)
	PixelDraw.px_rect(canvas, s * 0.32, -s * 0.28 + bob, s * 0.08, s * 0.04, claw, 0.88)
	for i: int in 3:
		var off := float(i - 1) * s * 0.12
		PixelDraw.px_rect(canvas, off - 2.0, -s * 0.02 + bob, 3.0, s * 0.08, leg, 0.85)
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.06, -s * 0.20 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
		PixelDraw.px_rect(canvas, s * 0.02, -s * 0.20 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))


static func _draw_bat(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String, t: float) -> void:
	var body := Color(0.38, 0.32, 0.48) if not name.to_lower().contains("cave") else Color(0.28, 0.24, 0.34)
	var wing := Color(0.48, 0.40, 0.58) if not name.to_lower().contains("cave") else Color(0.36, 0.32, 0.44)
	var flap := sin(t * 8.0) * s * 0.06
	PixelDraw.px_blob(canvas, 0.0, -s * 0.34 + bob, s * 0.12, s * 0.12, body)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.52, -s * 0.28 + bob + flap),
		Vector2(-s * 0.08, -s * 0.34 + bob),
		Vector2(-s * 0.18, -s * 0.18 + bob),
	]), SilhouetteDraw.ink(wing))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(s * 0.52, -s * 0.28 + bob + flap),
		Vector2(s * 0.08, -s * 0.34 + bob),
		Vector2(s * 0.18, -s * 0.18 + bob),
	]), SilhouetteDraw.ink(wing))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.04, -s * 0.38 + bob, 3.0, 3.0, Color(0.88, 0.22, 0.22))
		PixelDraw.px_rect(canvas, s * 0.02, -s * 0.38 + bob, 3.0, 3.0, Color(0.88, 0.22, 0.22))
		PixelDraw.px_rect(canvas, -s * 0.06, -s * 0.46 + bob, 3.0, 4.0, Color(0.32, 0.28, 0.38))
		PixelDraw.px_rect(canvas, s * 0.02, -s * 0.46 + bob, 3.0, 4.0, Color(0.32, 0.28, 0.38))


static func _draw_goblin(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String, boss: bool) -> void:
	var n := name.to_lower()
	if n.contains("rider"):
		_draw_wolf_body(canvas, s, bob)
		_draw_goblin_rider(canvas, s, bob, name)
		return
	var skin := Color(0.42, 0.68, 0.34)
	var ear := Color(0.36, 0.58, 0.28)
	var cloth := Color(0.48, 0.34, 0.26)
	var is_hob := n.contains("hob")
	var is_brawler := n.contains("brawler")
	if is_hob:
		skin = Color(0.38, 0.58, 0.30)
	if is_brawler:
		skin = Color(0.44, 0.62, 0.32)
		cloth = Color(0.38, 0.28, 0.22)
	PixelDraw.px_rect(canvas, -s * 0.16, -s * 0.42 + bob, s * 0.32, s * 0.38, skin)
	PixelDraw.px_blob(canvas, 0.0, -s * 0.58 + bob, s * 0.18, s * 0.14, skin)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.22, -s * 0.62 + bob), Vector2(-s * 0.10, -s * 0.78 + bob), Vector2(-s * 0.02, -s * 0.58 + bob),
	]), SilhouetteDraw.ink(ear))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(s * 0.22, -s * 0.62 + bob), Vector2(s * 0.10, -s * 0.78 + bob), Vector2(s * 0.02, -s * 0.58 + bob),
	]), SilhouetteDraw.ink(ear))
	PixelDraw.px_rect(canvas, -s * 0.14, -s * 0.28 + bob, s * 0.28, s * 0.16, cloth)
	PixelDraw.px_rect(canvas, -s * 0.10, -s * 0.06 + bob, 4.0, s * 0.12, PixelPalette.shade(skin, 0.82))
	PixelDraw.px_rect(canvas, s * 0.04, -s * 0.06 + bob, 4.0, s * 0.12, PixelPalette.shade(skin, 0.82))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.08, -s * 0.54 + bob, 3.0, 3.0, Color(0.92, 0.82, 0.12))
		PixelDraw.px_rect(canvas, s * 0.04, -s * 0.54 + bob, 3.0, 3.0, Color(0.92, 0.82, 0.12))
		PixelDraw.px_rect(canvas, -s * 0.04, -s * 0.48 + bob, 4.0, 3.0, Color(0.18, 0.14, 0.12))
	if is_brawler:
		PixelDraw.px_rect(canvas, -s * 0.28, -s * 0.36 + bob, 8.0, 6.0, skin)
		PixelDraw.px_rect(canvas, s * 0.18, -s * 0.36 + bob, 8.0, 6.0, skin)
	elif not boss:
		PixelDraw.px_rect(canvas, s * 0.16, -s * 0.34 + bob, 4.0, s * 0.22, Color(0.52, 0.42, 0.32))


static func _draw_goblin_rider(canvas: CanvasItem, s: float, bob: float, _name: String) -> void:
	var skin := Color(0.42, 0.68, 0.34)
	PixelDraw.px_blob(canvas, -s * 0.04, -s * 0.58 + bob, s * 0.14, s * 0.12, skin)
	PixelDraw.px_rect(canvas, -s * 0.06, -s * 0.66 + bob, 4.0, 4.0, skin)
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, s * 0.06, -s * 0.52 + bob, s * 0.18, 3.0, Color(0.48, 0.36, 0.24))


static func _draw_goat(canvas: CanvasItem, s: float, bob: float, _tint: Color) -> void:
	var hide := Color(0.78, 0.78, 0.82)
	var belly := Color(0.88, 0.86, 0.84)
	var hoof := Color(0.28, 0.24, 0.22)
	var horn := Color(0.62, 0.58, 0.54)
	var beard := Color(0.72, 0.72, 0.76)
	PixelDraw.px_blob(canvas, s * 0.02, -s * 0.26 + bob, s * 0.36, s * 0.22, hide)
	PixelDraw.px_blob(canvas, -s * 0.30, -s * 0.34 + bob, s * 0.16, s * 0.14, hide)
	PixelDraw.px_blob(canvas, -s * 0.38, -s * 0.22 + bob, s * 0.08, s * 0.10, beard, 0.88)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.28, -s * 0.46 + bob), Vector2(-s * 0.18, -s * 0.62 + bob), Vector2(-s * 0.10, -s * 0.44 + bob),
	]), SilhouetteDraw.ink(horn))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.14, -s * 0.46 + bob), Vector2(-s * 0.04, -s * 0.60 + bob), Vector2(0.0, -s * 0.44 + bob),
	]), SilhouetteDraw.ink(horn))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.34, -s * 0.32 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
	for lx: float in [-s * 0.16, -s * 0.04, s * 0.08, s * 0.18]:
		PixelDraw.px_rect(canvas, lx, -s * 0.02 + bob, 3.0, s * 0.10, belly)
		PixelDraw.px_rect(canvas, lx, s * 0.06 + bob, 3.0, 3.0, hoof)


static func _draw_pig(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String) -> void:
	var hide := Color(0.92, 0.68, 0.72)
	var snout := Color(0.88, 0.58, 0.62)
	var hoof := Color(0.42, 0.32, 0.30)
	if name.to_lower().contains("momma"):
		hide = Color(0.82, 0.52, 0.58)
	PixelDraw.px_blob(canvas, s * 0.04, -s * 0.24 + bob, s * 0.40, s * 0.26, hide)
	PixelDraw.px_blob(canvas, -s * 0.32, -s * 0.28 + bob, s * 0.16, s * 0.14, hide)
	PixelDraw.px_blob(canvas, -s * 0.42, -s * 0.24 + bob, s * 0.10, s * 0.10, snout)
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.44, -s * 0.22 + bob, 3.0, 3.0, Color(0.62, 0.32, 0.38))
		PixelDraw.px_rect(canvas, -s * 0.40, -s * 0.26 + bob, 3.0, 3.0, Color(0.62, 0.32, 0.38))
		PixelDraw.px_rect(canvas, -s * 0.34, -s * 0.30 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
	PixelDraw.px_rect(canvas, s * 0.24, -s * 0.14 + bob, s * 0.06, s * 0.04, PixelPalette.shade(hide, 0.88), 0.8)
	for lx: float in [-s * 0.18, -s * 0.04, s * 0.08, s * 0.18]:
		PixelDraw.px_rect(canvas, lx, -s * 0.02 + bob, 4.0, s * 0.10, PixelPalette.shade(hide, 0.92))
		PixelDraw.px_rect(canvas, lx, s * 0.06 + bob, 4.0, 3.0, hoof)


static func _draw_sheep(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String) -> void:
	var wool := Color(0.92, 0.92, 0.90)
	var face := Color(0.22, 0.20, 0.22)
	var hoof := Color(0.28, 0.24, 0.22)
	if name.to_lower().contains("mumma"):
		wool = Color(0.86, 0.86, 0.84)
	PixelDraw.px_blob(canvas, s * 0.04, -s * 0.30 + bob, s * 0.40, s * 0.28, wool)
	PixelDraw.px_blob(canvas, s * 0.10, -s * 0.38 + bob, s * 0.28, s * 0.14, wool, 0.92)
	PixelDraw.px_blob(canvas, -s * 0.28, -s * 0.32 + bob, s * 0.14, s * 0.12, face)
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.32, -s * 0.30 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
	for lx: float in [-s * 0.14, -s * 0.02, s * 0.10, s * 0.20]:
		PixelDraw.px_rect(canvas, lx, -s * 0.02 + bob, 3.0, s * 0.10, face)
		PixelDraw.px_rect(canvas, lx, s * 0.06 + bob, 3.0, 3.0, hoof)


static func _draw_wolf(canvas: CanvasItem, s: float, bob: float, _tint: Color, name: String) -> void:
	if name.to_lower().contains("rider"):
		return
	_draw_wolf_body(canvas, s, bob)


static func _draw_wolf_body(canvas: CanvasItem, s: float, bob: float) -> void:
	var hide := Color(0.58, 0.58, 0.62)
	var belly := Color(0.78, 0.76, 0.74)
	var snout := Color(0.68, 0.66, 0.68)
	PixelDraw.px_blob(canvas, s * 0.02, -s * 0.24 + bob, s * 0.42, s * 0.22, hide)
	PixelDraw.px_blob(canvas, -s * 0.34, -s * 0.32 + bob, s * 0.18, s * 0.14, hide)
	PixelDraw.px_blob(canvas, -s * 0.44, -s * 0.26 + bob, s * 0.10, s * 0.08, snout)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.28, -s * 0.44 + bob), Vector2(-s * 0.20, -s * 0.58 + bob), Vector2(-s * 0.12, -s * 0.40 + bob),
	]), SilhouetteDraw.ink(hide))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-s * 0.14, -s * 0.44 + bob), Vector2(-s * 0.06, -s * 0.56 + bob), Vector2(0.0, -s * 0.40 + bob),
	]), SilhouetteDraw.ink(hide))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.38, -s * 0.30 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
	PixelDraw.px_rect(canvas, s * 0.24, -s * 0.10 + bob, s * 0.10, s * 0.04, PixelPalette.shade(hide, 0.88), 0.85)
	for lx: float in [-s * 0.16, -s * 0.04, s * 0.08, s * 0.18]:
		PixelDraw.px_rect(canvas, lx, -s * 0.02 + bob, 3.0, s * 0.10, belly)


static func _draw_brainbasher(canvas: CanvasItem, s: float, bob: float, _tint: Color, t: float, boss: bool) -> void:
	var skin := Color(0.62, 0.42, 0.72)
	var robe := Color(0.38, 0.28, 0.48)
	var brain := Color(0.92, 0.48, 0.58)
	var pulse := 0.65 + 0.35 * sin(t * 4.0)
	PixelDraw.px_rect(canvas, -s * 0.18, -s * 0.46 + bob, s * 0.36, s * 0.42, robe)
	PixelDraw.px_blob(canvas, 0.0, -s * 0.62 + bob, s * 0.22, s * 0.18, skin)
	PixelDraw.px_blob(canvas, 0.0, -s * 0.78 + bob, s * 0.18, s * 0.12, brain, pulse)
	PixelDraw.px_rect(canvas, -s * 0.10, -s * 0.06 + bob, 5.0, s * 0.12, PixelPalette.shade(robe, 0.82))
	PixelDraw.px_rect(canvas, s * 0.04, -s * 0.06 + bob, 5.0, s * 0.12, PixelPalette.shade(robe, 0.82))
	PixelDraw.px_rect(canvas, s * 0.14, -s * 0.38 + bob, 4.0, s * 0.28, Color(0.52, 0.38, 0.28))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -s * 0.08, -s * 0.58 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
		PixelDraw.px_rect(canvas, s * 0.04, -s * 0.58 + bob, 3.0, 3.0, Color(0.08, 0.08, 0.10))
		var glow := Color(0.72, 0.32, 0.88, 0.35 * pulse)
		PixelDraw.px_blob(canvas, s * 0.22, -s * 0.52 + bob, s * 0.10, s * 0.10, glow, glow.a)
	if boss:
		PixelDraw.px_rect(canvas, -s * 0.04, -s * 0.88 + bob, 4.0, 4.0, Color(0.92, 0.82, 0.28))


static func _draw_boss_crown(canvas: CanvasItem, s: float, bob: float) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -s * 1.08 + bob), Vector2(0, -s * 1.22 + bob), Vector2(10, -s * 1.08 + bob),
		Vector2(8, -s * 0.96 + bob), Vector2(-8, -s * 0.96 + bob),
	]), SilhouetteDraw.ink(PixelPalette.pal("gold")))
	if not SilhouetteDraw.active:
		PixelDraw.px_rect(canvas, -2.0, -s * 1.14 + bob, 4.0, 4.0, Color.WHITE, 0.8)
