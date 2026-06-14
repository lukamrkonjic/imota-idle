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
const RuinArchArt := preload("res://scripts/world/art/structures/ruin_arch_art.gd")
const RuinPillarArt := preload("res://scripts/world/art/structures/ruin_pillar_art.gd")
const BrokenWallArt := preload("res://scripts/world/art/structures/broken_wall_art.gd")
const RubblePileArt := preload("res://scripts/world/art/structures/rubble_pile_art.gd")
const BrokenStatueArt := preload("res://scripts/world/art/structures/broken_statue_art.gd")
const HouseArt := preload("res://scripts/world/art/structures/house_art.gd")
const BuildingArt := preload("res://scripts/world/art/structures/building_art.gd")
const FountainArt := preload("res://scripts/world/art/structures/fountain_art.gd")
const CityWallArt := preload("res://scripts/world/art/structures/city_wall_art.gd")
const BridgeArt := preload("res://scripts/world/art/structures/bridge_art.gd")
const CityPropArt := preload("res://scripts/world/art/structures/city_prop_art.gd")
const MountainArt := preload("res://scripts/world/art/structures/mountain_art.gd")


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


static func draw_player(canvas: CanvasItem, skin: Color, outfit: Color, hair: Color, mode: String, t: float, facing: int, cast_local: Vector2 = Vector2.ZERO) -> void:
	PlayerArt.draw(canvas, skin, outfit, hair, mode, t, facing, cast_local)


static func draw_enemy(canvas: CanvasItem, name: String, shape: String, size: float, color: Color, boss: bool, t: float) -> void:
	EnemyArt.draw(canvas, name, shape, size, color, boss, t)


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


static func draw_ruin_arch(canvas: CanvasItem, variant: int) -> void:
	RuinArchArt.draw(canvas, variant)


static func draw_ruin_pillar(canvas: CanvasItem, variant: int) -> void:
	RuinPillarArt.draw(canvas, variant)


static func draw_broken_wall(canvas: CanvasItem, variant: int) -> void:
	BrokenWallArt.draw(canvas, variant)


static func draw_rubble_pile(canvas: CanvasItem, variant: int) -> void:
	RubblePileArt.draw(canvas, variant)


static func draw_broken_statue(canvas: CanvasItem, variant: int) -> void:
	BrokenStatueArt.draw(canvas, variant)


static func draw_house_body(canvas: CanvasItem, variant: int, accent: Color) -> void:
	HouseArt.draw_body(canvas, variant, accent)


static func draw_house_roof(canvas: CanvasItem, variant: int, roof_color: Color, alpha: float) -> void:
	HouseArt.draw_roof(canvas, variant, roof_color, alpha)


static func house_height(variant: int) -> float:
	return HouseArt.total_height(variant)


static func draw_fountain(canvas: CanvasItem, t: float) -> void:
	FountainArt.draw(canvas, t)


static func draw_city_wall(canvas: CanvasItem, piece: int) -> void:
	CityWallArt.draw(canvas, piece)


static func draw_bridge(canvas: CanvasItem) -> void:
	BridgeArt.draw(canvas)


static func draw_building_body(canvas: CanvasItem, foot: float, variant: int, accent: Color) -> void:
	BuildingArt.draw_body(canvas, foot, variant, accent)


static func draw_building_roof(canvas: CanvasItem, foot: float, variant: int, roof_color: Color, alpha: float) -> void:
	BuildingArt.draw_roof(canvas, foot, variant, roof_color, alpha)


static func building_height(foot: float, variant: int) -> float:
	return BuildingArt.total_height(foot, variant)


static func draw_mountain(canvas: CanvasItem, foot: float, variant: int, snow: float) -> void:
	MountainArt.draw(canvas, foot, variant, snow)


static func mountain_height(foot: float, variant: int) -> float:
	return MountainArt.height_for(foot, variant)


static func draw_city_prop(canvas: CanvasItem, prop: String, variant: int, t: float) -> void:
	CityPropArt.draw(canvas, prop, variant, t)
