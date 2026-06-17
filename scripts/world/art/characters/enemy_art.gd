extends RefCounted
class_name EnemyArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const EnemyCreatureArt := preload("res://scripts/world/art/characters/enemy_creature_art.gd")


static func shape_for_name(name: String) -> String:
	if not EnemyCreatureArt.species_for_name(name).is_empty():
		return EnemyCreatureArt.species_for_name(name)
	var n := name.to_lower()
	for kw: String in ["skelet", "zomb", "ghost", "ghoul", "wraith", "bone", "undead", "shade", "spect", "lich", "crypt", "grave", "soul"]:
		if n.contains(kw):
			return "undead"
	for kw: String in ["drake", "dragon", "wyvern", "wyrm"]:
		if n.contains(kw):
			return "drake"
	for kw: String in ["wolf", "bear", "boar", "rat", "spider", "crab", "chicken", "cow", "goat", "pig", "sheep", "bat", "hound", "fox", "snake", "viper", "scorpion", "beetle", "lizard", "toad", "frog", "slug", "snail", "mole", "deer", "elk", "mush", "fish", "eel", "feeder", "craw"]:
		if n.contains(kw):
			return "beast"
	return "humanoid"


static func _shadow_half_width(shape: String, size: float, boss: bool) -> float:
	var scale := 1.18 if boss else 1.0
	match shape:
		"cow", "pig", "sheep", "wolf", "goat", "chicken", "crab", "bat", "goblin", "brainbasher":
			return EnemyCreatureArt.shadow_half_width(shape, size, boss)
		"beast":
			return size * 0.34 * scale
		"drake":
			return size * 0.30 * scale
		"undead":
			return size * 0.20 * scale
		_:
			return size * 0.22 * scale


static func draw(canvas: CanvasItem, name: String, shape: String, size: float, color: Color, boss: bool, t: float, facing: int = 1) -> void:
	if not EnemyCreatureArt.species_for_name(name).is_empty():
		EnemyCreatureArt.draw(canvas, name, size, color, boss, t, facing)
		return
	_draw_generic(canvas, shape, size, color, boss, t, facing)


static func _draw_generic(canvas: CanvasItem, shape: String, size: float, color: Color, boss: bool, t: float, facing: int = 1) -> void:
	if not SilhouetteDraw.active:
		color = PixelPalette.enrich_entity(color)
	# Negative facing mirrors the whole creature horizontally so it turns to face
	# its target (e.g. the player it's fighting); art is authored facing +x.
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.12 * float(facing), 1.12))
	PixelDraw.draw_tight_character_shadow(canvas, _shadow_half_width(shape, size, boss))
	var bob := sin(t * 3.0) * 1.5
	var s := size
	var dark_eye := Color(0.07, 0.09, 0.13)
	match shape:
		"beast":
			PixelDraw.px_blob(canvas, 0.0, -s * 0.15 + bob, s * 0.58, s * 0.32, color)
			PixelDraw.px_blob(canvas, s * 0.38, -s * 0.42 + bob, s * 0.24, s * 0.18, PixelPalette.shade(color, 0.9))
			if not SilhouetteDraw.active:
				PixelDraw.px_rect(canvas, s * 0.4, -s * 0.44 + bob, 3.0, 3.0, dark_eye)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(s * 0.28, -s * 0.52 + bob), Vector2(s * 0.38, -s * 0.72 + bob), Vector2(s * 0.5, -s * 0.5 + bob),
			]), SilhouetteDraw.ink(color))
			PixelDraw.px_rect(canvas, -s * 0.35, -s * 0.05 + bob, 6.0, 4.0, PixelPalette.shade(color, 0.75))
			PixelDraw.px_rect(canvas, s * 0.1, -s * 0.05 + bob, 6.0, 4.0, PixelPalette.shade(color, 0.75))
		"undead":
			PixelDraw.px_rect(canvas, -s * 0.18, -s * 0.5 + bob, s * 0.36, s * 0.5, color)
			PixelDraw.px_blob(canvas, 0.0, -s * 0.64 + bob, s * 0.2, s * 0.16, PixelPalette.shade(color, 0.95))
			if not SilhouetteDraw.active:
				PixelDraw.px_rect(canvas, -s * 0.07, -s * 0.66 + bob, 4.0, 4.0, Color8(0x88, 0xff, 0x88))
				PixelDraw.px_rect(canvas, s * 0.02, -s * 0.66 + bob, 4.0, 4.0, Color8(0x88, 0xff, 0x88))
				canvas.draw_line(Vector2(-s * 0.05, -s * 0.58 + bob), Vector2(0, -s * 0.52 + bob), Color(0.2, 0.2, 0.2), 2.0)
				canvas.draw_line(Vector2(0, -s * 0.52 + bob), Vector2(s * 0.05, -s * 0.58 + bob), Color(0.2, 0.2, 0.2), 2.0)
		"drake":
			PixelDraw.px_blob(canvas, 0.0, -s * 0.22 + bob, s * 0.42, s * 0.26, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(-s * 0.58, -s * 0.32 + bob), Vector2(-s * 0.12, -s * 0.18 + bob), Vector2(-s * 0.28, 2.0 + bob),
			]), SilhouetteDraw.ink(PixelPalette.shade(color, 0.85)))
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(s * 0.58, -s * 0.32 + bob), Vector2(s * 0.12, -s * 0.18 + bob), Vector2(s * 0.28, 2.0 + bob),
			]), SilhouetteDraw.ink(PixelPalette.shade(color, 0.85)))
			PixelDraw.px_blob(canvas, s * 0.3, -s * 0.48 + bob, s * 0.16, s * 0.12, color)
			if not SilhouetteDraw.active:
				PixelDraw.px_rect(canvas, s * 0.32, -s * 0.5 + bob, 4.0, 4.0, PixelPalette.pal("gold"))
			PixelDraw.px_rect(canvas, -s * 0.08, -s * 0.35 + bob, 6.0, 3.0, PixelPalette.shade(color, 1.1))
		_:
			PixelDraw.px_rect(canvas, -s * 0.2, -s * 0.55 + bob, s * 0.4, s * 0.55, color)
			PixelDraw.px_rect(canvas, s * 0.12, -s * 0.45 + bob, 4.0, s * 0.35, PixelPalette.shade(color, 0.82))
			PixelDraw.px_blob(canvas, 0.0, -s * 0.72 + bob, s * 0.22, s * 0.18, PixelPalette.shade(color, 1.05))
			if not SilhouetteDraw.active:
				PixelDraw.px_rect(canvas, -s * 0.08, -s * 0.74 + bob, 3.0, 3.0, dark_eye)
				PixelDraw.px_rect(canvas, s * 0.04, -s * 0.74 + bob, 3.0, 3.0, dark_eye)
			PixelDraw.px_rect(canvas, -s * 0.28, -s * 0.35 + bob, 8.0, 4.0, PixelPalette.shade(color, 0.88))
			PixelDraw.px_rect(canvas, s * 0.18, -s * 0.35 + bob, 8.0, 4.0, PixelPalette.shade(color, 0.88))
	if boss:
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(-10, -s * 1.08 + bob), Vector2(0, -s * 1.22 + bob), Vector2(10, -s * 1.08 + bob),
			Vector2(8, -s * 0.96 + bob), Vector2(-8, -s * 0.96 + bob),
		]), SilhouetteDraw.ink(PixelPalette.pal("gold")))
		if not SilhouetteDraw.active:
			PixelDraw.px_rect(canvas, -2.0, -s * 1.14 + bob, 4.0, 4.0, Color.WHITE, 0.8)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
