extends RefCounted
class_name PlayerEquipmentArt
## Paper-doll equipment overlays and held tools/weapons for the player avatar.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const SKILL_TOOL_SLOT := {
	"woodcutting": "Axe",
	"mining": "Pickaxe",
	"fishing": "Rod",
	"foraging": "Lens",
}

const TIER_COLORS := [
	{"keys": ["bronze", "copper"], "color": Color(0.72, 0.48, 0.28)},
	{"keys": ["iron", "steel"], "color": Color(0.58, 0.6, 0.66)},
	{"keys": ["mithril", "silver"], "color": Color(0.62, 0.72, 0.86)},
	{"keys": ["adamant", "adamantite"], "color": Color(0.42, 0.62, 0.38)},
	{"keys": ["rune", "runite"], "color": Color(0.48, 0.58, 0.78)},
	{"keys": ["dragon"], "color": Color(0.62, 0.22, 0.18)},
	{"keys": ["gold", "golden"], "color": Color(0.851, 0.761, 0.467)},  # pal gold #D9C277
	{"keys": ["cerulium", "aeronite", "necrosis", "sanguinite", "karinite", "taigite", "aurite", "phantom"], "color": Color(0.55, 0.42, 0.78)},
]


static func build_visuals(mode: String) -> Dictionary:
	var show_weapon := mode in ["idle", "run", "combat_melee", "combat_range", "combat_magic"]
	var show_shield := show_weapon
	var hand_slot := ""
	var hand_kind := ""
	if mode == "chop":
		hand_slot = "Axe"
		hand_kind = "axe"
	elif mode == "mine":
		hand_slot = "Pickaxe"
		hand_kind = "pickaxe"
	elif mode == "fish":
		hand_slot = "Rod"
		hand_kind = "rod"
	elif mode == "forage":
		hand_slot = "Lens"
		hand_kind = "lens"
	elif mode == "craft":
		hand_slot = _primary_tool_slot()
		hand_kind = _tool_kind(_slot_item_name(hand_slot))
	elif mode.begins_with("combat"):
		hand_slot = "Weapon"
		hand_kind = _weapon_kind(_slot_item_name("Weapon"), mode)
	elif show_weapon:
		hand_slot = "Weapon"
		hand_kind = _weapon_kind(_slot_item_name("Weapon"), "idle")

	return {
		"helm_id": _slot_item_id("Helm"),
		"body_id": _slot_item_id("Body"),
		"boots_id": _slot_item_id("Boots"),
		"gloves_id": _slot_item_id("Gloves"),
		"cape_id": _slot_item_id("Cape"),
		"shield_id": _slot_item_id("Shield") if show_shield else "",
		"hand_item_id": _slot_item_id(hand_slot),
		"hand_kind": hand_kind,
	}


static func outfit_tint(base: Color, body_id: String) -> Color:
	if body_id.is_empty():
		return base
	var name := DataRegistry.item_display_name(body_id).to_lower()
	return item_metal_color(name).lerp(base, 0.35)


static func item_metal_color(item_name: String) -> Color:
	var n := item_name.to_lower()
	for entry: Dictionary in TIER_COLORS:
		for key: String in entry["keys"]:
			if n.contains(key):
				return entry["color"]
	return PixelPalette.shade(PixelPalette.pal("stone_a"), 0.9)


static func draw_cape(canvas: CanvasItem, cape_id: String, walk: float, facing: int) -> void:
	if cape_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(cape_id))
	PixelDraw.px_rect(canvas, -10.0 * f, -18.0 + walk, 8.0, 16.0, PixelPalette.shade(col, 0.82), 0.92)
	PixelDraw.px_rect(canvas, -12.0 * f, -8.0 + walk, 4.0, 10.0, PixelPalette.shade(col, 0.68), 0.88)


static func draw_helm(canvas: CanvasItem, helm_id: String, walk: float, facing: int, hair: Color) -> void:
	if helm_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(helm_id))
	PixelDraw.px_rect(canvas, -8.0, -36.0 + walk, 16.0, 6.0, col)
	PixelDraw.px_rect(canvas, -9.0 * f, -34.0 + walk, 4.0, 4.0, PixelPalette.shade(col, 1.15))
	PixelDraw.px_rect(canvas, -8.0, -30.0 + walk, 16.0, 2.0, hair.darkened(0.25))


static func draw_body_armor(canvas: CanvasItem, body_id: String, walk: float, facing: int, outfit: Color) -> void:
	if body_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(body_id))
	PixelDraw.px_rect(canvas, -7.0 * f, -18.0 + walk, 4.0, 12.0, PixelPalette.shade(col, 1.08))
	PixelDraw.px_rect(canvas, 3.0 * f, -18.0 + walk, 4.0, 12.0, PixelPalette.shade(col, 0.95))
	PixelDraw.px_rect(canvas, -6.0 * f, -8.0 + walk, 12.0, 3.0, PixelPalette.shade(col, 0.78))
	PixelDraw.px_rect(canvas, -2.0 * f, -14.0 + walk, 4.0, 6.0, outfit.darkened(0.12))


static func draw_boots(canvas: CanvasItem, boots_id: String, leg_swing: float, facing: int) -> void:
	if boots_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(boots_id))
	PixelDraw.px_rect(canvas, -6.0 * f + leg_swing * 0.15, -2.0, 6.0, 4.0, col)
	PixelDraw.px_rect(canvas, 2.0 * f - leg_swing * 0.15, -2.0, 6.0, 4.0, PixelPalette.shade(col, 0.88))


static func draw_gloves(canvas: CanvasItem, gloves_id: String, walk: float, arm_swing: float, facing: int, skin: Color) -> void:
	if gloves_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(gloves_id)).lerp(skin, 0.25)
	PixelDraw.px_rect(canvas, -15.0 * f, -6.0 + arm_swing * 8.0, 4.0, 4.0, col)
	PixelDraw.px_rect(canvas, 10.0 * f, -6.0 - arm_swing * 6.0, 4.0, 4.0, col)


static func draw_shield(canvas: CanvasItem, shield_id: String, walk: float, arm_swing: float, facing: int) -> void:
	if shield_id.is_empty():
		return
	var f := float(facing)
	var col := item_metal_color(DataRegistry.item_display_name(shield_id))
	var sx := -18.0 * f
	var sy := -14.0 + walk + arm_swing * 4.0
	PixelDraw.px_rect(canvas, sx, sy, 6.0, 10.0, col)
	PixelDraw.px_rect(canvas, sx + 1.0 * f, sy + 2.0, 4.0, 6.0, PixelPalette.shade(col, 1.12))


static func draw_hand_item(
	canvas: CanvasItem,
	kind: String,
	item_id: String,
	walk: float,
	arm_swing: float,
	facing: int,
	mode: String,
	t: float,
) -> void:
	if kind.is_empty() or item_id.is_empty():
		return
	var metal := item_metal_color(DataRegistry.item_display_name(item_id))
	var f := float(facing)
	var hx := 10.0 * f
	var hy := -8.0 + walk - arm_swing * 6.0
	match kind:
		"axe":
			var phase := sin(t * 9.0) if mode == "chop" else arm_swing
			hx += phase * 4.0 * f
			hy += phase * 3.0
			PixelDraw.px_rect(canvas, hx - 2.0 * f, hy, 4.0, 12.0, PixelPalette.pal("trunk_a"))
			PixelDraw.px_rect(canvas, hx - 8.0 * f + phase * 3.0 * f, hy - 8.0, 8.0, 4.0, metal)
			PixelDraw.px_rect(canvas, hx - 10.0 * f + phase * 4.0 * f, hy - 14.0, 4.0, 6.0, PixelPalette.shade(metal, 0.82))
		"pickaxe":
			var swing := sin(t * 7.5) if mode == "mine" else arm_swing
			hx += swing * 3.0 * f
			hy += swing * 5.0
			PixelDraw.px_rect(canvas, hx - 2.0 * f, hy - 4.0, 4.0, 14.0, PixelPalette.pal("trunk_b"))
			PixelDraw.px_rect(canvas, hx - 10.0 * f, hy - 10.0 + swing * 2.0, 12.0, 4.0, metal)
			PixelDraw.px_rect(canvas, hx + 4.0 * f, hy - 12.0 + swing * 2.0, 4.0, 4.0, metal)
		"rod":
			var bob := sin(t * 4.0) * 2.0 if mode == "fish" else 0.0
			PixelDraw.px_rect(canvas, hx, hy + bob, 16.0 * f, 3.0, PixelPalette.pal("trunk_a"))
			PixelDraw.px_rect(canvas, hx + 14.0 * f, hy - 2.0 + bob, 4.0, 8.0, PixelPalette.pal("water_a"))
		"lens":
			PixelDraw.px_rect(canvas, hx - 2.0 * f, hy - 2.0, 8.0, 3.0, PixelPalette.pal("trunk_b"))
			PixelDraw.px_diamond(canvas, hx + 6.0 * f, hy, 5.0, 5.0, Color(0.72, 0.86, 0.95, 0.85))
		"sword":
			var slash := sin(t * 8.0) if mode.begins_with("combat") else arm_swing * 0.5
			hx += slash * 5.0 * f
			hy += slash * 4.0
			PixelDraw.px_rect(canvas, hx, hy - 14.0 + slash * 2.0, 3.0, 14.0, metal)
			PixelDraw.px_rect(canvas, hx - 2.0 * f, hy + 2.0, 7.0, 3.0, PixelPalette.pal("trunk_a"))
		"bow":
			var pull := (sin(t * 6.0) * 0.5 + 0.5) if mode == "combat_range" else 0.2
			PixelDraw.px_rect(canvas, hx - 10.0 * f, hy - 6.0, 12.0 * f, 3.0, PixelPalette.pal("trunk_a"))
			PixelDraw.px_rect(canvas, hx - 12.0 * f, hy - 10.0, 3.0, 12.0, metal)
			PixelDraw.px_rect(canvas, hx - 4.0 * f - pull * 4.0 * f, hy - 2.0, 2.0, 2.0, PixelPalette.pal("trunk_b"))
		"staff":
			var pulse := sin(t * 5.0) if mode == "combat_magic" else 0.0
			PixelDraw.px_rect(canvas, hx - 2.0 * f, hy - 18.0, 4.0, 20.0, PixelPalette.pal("trunk_b"))
			PixelDraw.px_diamond(canvas, hx, hy - 20.0 + pulse * 2.0, 4.0, 4.0, Color(0.55, 0.75, 1.0, 0.9))
		_:
			PixelDraw.px_rect(canvas, hx, hy, 6.0, 6.0, metal)


static func _slot_item_id(slot: String) -> String:
	if slot.is_empty():
		return ""
	return str(GameState.equipment.get(slot, ""))


static func _slot_item_name(slot: String) -> String:
	var item_id := _slot_item_id(slot)
	if item_id.is_empty():
		return ""
	return DataRegistry.item_display_name(item_id)


static func _primary_tool_slot() -> String:
	for skill: String in SKILL_TOOL_SLOT:
		var slot: String = SKILL_TOOL_SLOT[skill]
		if GameState.equipment.has(slot):
			return slot
	return ""


static func _tool_kind(item_name: String) -> String:
	var n := item_name.to_lower()
	if n.contains("pickaxe"):
		return "pickaxe"
	if n.contains("axe"):
		return "axe"
	if n.contains("rod"):
		return "rod"
	if n.contains("lens"):
		return "lens"
	return ""


static func _weapon_kind(item_name: String, mode: String) -> String:
	if item_name.is_empty():
		return ""
	var n := item_name.to_lower()
	if mode == "combat_range" or n.contains("bow"):
		return "bow"
	if mode == "combat_magic" or n.contains("staff"):
		return "staff"
	if n.contains("sword") or n.contains("dagger") or n.contains("scimitar") or n.contains("reaver"):
		return "sword"
	return "sword"
