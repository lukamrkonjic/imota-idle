extends RefCounted
class_name GroundDecorArt
## Dispatches ground clutter (grass, sticks, shrubs, etc.) to per-kind modules.

const GrassDecorArt := preload("res://scripts/world/art/ground_decor/grass_decor.gd")
const FernDecorArt := preload("res://scripts/world/art/ground_decor/fern_decor.gd")
const FlowerDecorArt := preload("res://scripts/world/art/ground_decor/flower_decor.gd")
const ShrubDecorArt := preload("res://scripts/world/art/ground_decor/shrub_decor.gd")
const StickDecorArt := preload("res://scripts/world/art/ground_decor/stick_decor.gd")
const PebbleDecorArt := preload("res://scripts/world/art/ground_decor/pebble_decor.gd")
const ReedDecorArt := preload("res://scripts/world/art/ground_decor/reed_decor.gd")
const MushroomDecorArt := preload("res://scripts/world/art/ground_decor/mushroom_decor.gd")
const CactusDecorArt := preload("res://scripts/world/art/ground_decor/cactus_decor.gd")
const VineDecorArt := preload("res://scripts/world/art/ground_decor/vine_decor.gd")
const MossDecorArt := preload("res://scripts/world/art/ground_decor/moss_decor.gd")
const LichenDecorArt := preload("res://scripts/world/art/ground_decor/lichen_decor.gd")
const DriftwoodDecorArt := preload("res://scripts/world/art/ground_decor/driftwood_decor.gd")
const ShellDecorArt := preload("res://scripts/world/art/ground_decor/shell_decor.gd")
const BoneDecorArt := preload("res://scripts/world/art/ground_decor/bone_decor.gd")
const BrambleDecorArt := preload("res://scripts/world/art/ground_decor/bramble_decor.gd")
const RubbleDecorArt := preload("res://scripts/world/art/ground_decor/rubble_decor.gd")


static func draw(canvas: CanvasItem, kind: String, variant: int, tint: Color) -> void:
	match kind:
		"fern": FernDecorArt.draw(canvas, variant, tint)
		"flower": FlowerDecorArt.draw(canvas, variant, tint)
		"shrub": ShrubDecorArt.draw(canvas, variant, tint)
		"stick": StickDecorArt.draw(canvas, variant, tint)
		"pebble": PebbleDecorArt.draw(canvas, variant, tint)
		"reed": ReedDecorArt.draw(canvas, variant, tint)
		"mushroom": MushroomDecorArt.draw(canvas, variant, tint)
		"cactus": CactusDecorArt.draw(canvas, variant, tint)
		"vine": VineDecorArt.draw(canvas, variant, tint)
		"moss": MossDecorArt.draw(canvas, variant, tint)
		"lichen": LichenDecorArt.draw(canvas, variant, tint)
		"driftwood": DriftwoodDecorArt.draw(canvas, variant, tint)
		"shell": ShellDecorArt.draw(canvas, variant, tint)
		"bone": BoneDecorArt.draw(canvas, variant, tint)
		"bramble": BrambleDecorArt.draw(canvas, variant, tint)
		"rubble": RubbleDecorArt.draw(canvas, variant, tint)
		_: GrassDecorArt.draw(canvas, variant, tint)
