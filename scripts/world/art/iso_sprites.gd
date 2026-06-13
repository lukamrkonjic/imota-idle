extends RefCounted
class_name IsoSprites
## Public facade for procedural world art. Implementation lives in art/* modules.

const GatherNodeArt := preload("res://scripts/world/art/nodes/gather_node_art.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const PlayerArt := preload("res://scripts/world/art/characters/player_art.gd")
const EnemyArt := preload("res://scripts/world/art/characters/enemy_art.gd")
const TentArt := preload("res://scripts/world/art/structures/tent_art.gd")
const CampfireArt := preload("res://scripts/world/art/structures/campfire_art.gd")
const LanternArt := preload("res://scripts/world/art/structures/lantern_art.gd")
const SignArt := preload("res://scripts/world/art/structures/sign_art.gd")
const ChestArt := preload("res://scripts/world/art/structures/chest_art.gd")
const AnvilArt := preload("res://scripts/world/art/structures/anvil_art.gd")
const AltarArt := preload("res://scripts/world/art/structures/altar_art.gd")
const ObeliskArt := preload("res://scripts/world/art/structures/obelisk_art.gd")
const CaveMouthArt := preload("res://scripts/world/art/structures/cave_mouth_art.gd")
const LadderArt := preload("res://scripts/world/art/structures/ladder_art.gd")
const StallArt := preload("res://scripts/world/art/structures/stall_art.gd")
const MeteorArt := preload("res://scripts/world/art/structures/meteor_art.gd")
const MammothArt := preload("res://scripts/world/art/structures/mammoth_art.gd")
const RuinArt := preload("res://scripts/world/art/structures/ruin_art.gd")


static func node_size(kind: String) -> float:
	return GatherNodeArt.node_size(kind)


static func estimated_height(kind: String, size: float, label: String = "") -> float:
	return GatherNodeArt.estimated_height(kind, size, label)


static func draw_prop(
	canvas: CanvasItem,
	kind: String,
	size: float,
	tier_color: Color,
	variant: int,
	depleted: bool,
	t: float,
	label: String = "",
) -> void:
	GatherNodeArt.draw_prop(canvas, kind, size, tier_color, variant, depleted, t, label)


static func draw_player(canvas: CanvasItem, skin: Color, outfit: Color, hair: Color, mode: String, t: float, facing: int) -> void:
	PlayerArt.draw(canvas, skin, outfit, hair, mode, t, facing)


static func draw_enemy(canvas: CanvasItem, shape: String, size: float, color: Color, boss: bool, t: float) -> void:
	EnemyArt.draw(canvas, shape, size, color, boss, t)


static func enemy_shape(name: String) -> String:
	return EnemyArt.shape_for_name(name)


static func draw_tent(canvas: CanvasItem, size: float, color: Color) -> void:
	TentArt.draw(canvas, size, color)


static func draw_campfire(canvas: CanvasItem, t: float) -> void:
	CampfireArt.draw(canvas, t)


static func draw_lantern(canvas: CanvasItem) -> void:
	LanternArt.draw(canvas)


static func draw_sign(canvas: CanvasItem) -> void:
	SignArt.draw(canvas)


static func draw_chest(canvas: CanvasItem, size: float, color: Color, depleted: bool) -> void:
	ChestArt.draw(canvas, size, color, depleted)


static func draw_anvil(canvas: CanvasItem, t: float) -> void:
	AnvilArt.draw(canvas, t)


static func draw_altar(canvas: CanvasItem, t: float, glow_color: Color) -> void:
	AltarArt.draw(canvas, t, glow_color)


static func draw_obelisk(canvas: CanvasItem, t: float, attuned: bool) -> void:
	ObeliskArt.draw(canvas, t, attuned)


static func draw_cave_mouth(canvas: CanvasItem) -> void:
	CaveMouthArt.draw(canvas)


static func draw_ladder(canvas: CanvasItem, up: bool) -> void:
	LadderArt.draw(canvas, up)


static func draw_stall(canvas: CanvasItem) -> void:
	StallArt.draw(canvas)


static func draw_meteor(canvas: CanvasItem, t: float) -> void:
	MeteorArt.draw(canvas, t)


static func draw_mammoth(canvas: CanvasItem) -> void:
	MammothArt.draw(canvas)


static func draw_ruin(canvas: CanvasItem, kind: String, size: float, variant: int) -> void:
	RuinArt.draw(canvas, kind, size, variant)
