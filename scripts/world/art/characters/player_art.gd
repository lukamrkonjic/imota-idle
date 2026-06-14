extends RefCounted
class_name PlayerArt

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const PlayerEquipmentArt := preload("res://scripts/world/art/characters/player_equipment_art.gd")


static func draw(
	canvas: CanvasItem,
	skin: Color,
	outfit: Color,
	hair: Color,
	mode: String,
	t: float,
	facing: int,
	cast_local: Vector2 = Vector2.ZERO,
) -> void:
	var f := float(facing)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.14, 1.14))
	var visuals := PlayerEquipmentArt.build_visuals(mode)
	outfit = PixelPalette.enrich_entity(PlayerEquipmentArt.outfit_tint(outfit, visuals["body_id"]))
	skin = PixelPalette.enrich_entity(skin)
	var walk := 0.0
	var leg_swing := 0.0
	var arm_swing := 0.25
	match mode:
		"run":
			walk = sin(t * 10.0) * 3.0
			leg_swing = sin(t * 10.0) * 6.0
			arm_swing = sin(t * 10.0) * 0.4
		"chop":
			walk = sin(t * 2.0) * 0.4
			arm_swing = sin(t * 9.0) * 1.1
		"mine":
			walk = sin(t * 3.0) * 1.0
			arm_swing = sin(t * 7.5) * 1.0
		"fish":
			walk = sin(t * 2.0) * 0.5
			arm_swing = sin(t * 4.0) * 0.35
		"forage":
			walk = sin(t * 2.5) * 0.6
			arm_swing = sin(t * 5.0) * 0.4
		"craft":
			walk = sin(t * 5.0) * 1.5
			arm_swing = -sin(t * 5.0) * 0.7
		"combat_melee", "combat_range", "combat_magic":
			walk = sin(t * 4.0) * 1.2
			arm_swing = sin(t * 8.0) * 0.9
		"pickup", "gather":
			walk = sin(t * 6.0) * 2.0
			arm_swing = -sin(t * 6.0) * 0.8
		_:
			walk = sin(t * 2.0) * 0.8

	PixelDraw.draw_tight_character_shadow(canvas, 14.0)
	PlayerEquipmentArt.draw_cape(canvas, visuals["cape_id"], walk, facing)
	PixelDraw.px_rect(canvas, -5.0 * f + leg_swing * 0.15, -10.0, 5.0, 12.0, PixelPalette.shade(outfit, 0.65))
	PixelDraw.px_rect(canvas, 2.0 * f - leg_swing * 0.15, -10.0, 5.0, 12.0, PixelPalette.shade(outfit, 0.72))
	if visuals["boots_id"].is_empty():
		PixelDraw.px_rect(canvas, -6.0 * f, 0.0, 6.0, 4.0, PixelPalette.pal("trunk_b"))
		PixelDraw.px_rect(canvas, 3.0 * f, 0.0, 6.0, 4.0, PixelPalette.pal("trunk_b"))
	else:
		PlayerEquipmentArt.draw_boots(canvas, visuals["boots_id"], leg_swing, facing)
	PixelDraw.px_rect(canvas, -8.0 * f, -20.0 + walk, 16.0, 20.0, outfit)
	PlayerEquipmentArt.draw_body_armor(canvas, visuals["body_id"], walk, facing, outfit)
	PixelDraw.px_rect(canvas, 6.0 * f, -18.0 + walk, 4.0, 16.0, PixelPalette.shade(outfit, 0.78))
	PixelDraw.px_rect(canvas, -7.0 * f, -18.0 + walk, 3.0, 14.0, PixelPalette.shade(outfit, 1.12))
	PixelDraw.px_rect(canvas, -2.0 * f, -16.0 + walk, 4.0, 8.0, PixelPalette.shade(outfit, 0.55))
	PixelDraw.px_rect(canvas, -8.0 * f, -6.0 + walk, 16.0, 3.0, PixelPalette.pal("trunk_b"))
	PixelDraw.px_rect(canvas, -14.0 * f, -16.0 + walk + arm_swing * 6.0, 6.0, 12.0, PixelPalette.shade(outfit, 0.88))
	PixelDraw.px_rect(canvas, 8.0 * f, -16.0 + walk - arm_swing * 5.0, 6.0, 12.0, PixelPalette.shade(outfit, 0.92))
	PixelDraw.px_rect(canvas, -15.0 * f, -6.0 + arm_swing * 8.0, 4.0, 4.0, skin)
	PixelDraw.px_rect(canvas, 10.0 * f, -6.0 - arm_swing * 6.0, 4.0, 4.0, skin)
	PlayerEquipmentArt.draw_gloves(canvas, visuals["gloves_id"], walk, arm_swing, facing, skin)
	PixelDraw.px_rect(canvas, -7.0, -30.0 + walk, 14.0, 12.0, skin)
	PixelDraw.px_rect(canvas, 5.0 * f, -28.0 + walk, 3.0, 10.0, PixelPalette.shade(skin, 0.88))
	PixelDraw.px_rect(canvas, -8.0, -34.0 + walk, 16.0, 8.0, hair)
	PlayerEquipmentArt.draw_helm(canvas, visuals["helm_id"], walk, facing, hair)
	PixelDraw.px_rect(canvas, -3.0 * f, -28.0 + walk, 3.0, 3.0, Color(0.1, 0.06, 0.06))
	PixelDraw.px_rect(canvas, 3.0 * f, -28.0 + walk, 3.0, 3.0, Color(0.1, 0.06, 0.06))
	var row := 0.0
	while row < 18.0:
		var hw := PixelPalette.snap(5.0 + row * 0.35)
		PixelDraw.px_row(canvas, -10.0 * f, -18.0 + walk + row, hw, PixelPalette.shade(outfit, 0.5), 0.9)
		row += PixelPalette.PX
	PlayerEquipmentArt.draw_shield(canvas, visuals["shield_id"], walk, arm_swing, facing)
	PlayerEquipmentArt.draw_hand_item(
		canvas,
		visuals["hand_kind"],
		visuals["hand_item_id"],
		walk,
		arm_swing,
		facing,
		mode,
		t,
		cast_local,
	)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
