extends RefCounted
class_name NatureDecorArtCatalog

const AppleTreeDecorArt := preload("res://scripts/world/art/decor/nature/apple_tree_decor_art.gd")
const AutumnTreeDecorArt := preload("res://scripts/world/art/decor/nature/autumn_tree_decor_art.gd")
const BerryBushBlueDecorArt := preload("res://scripts/world/art/decor/nature/berry_bush_blue_decor_art.gd")
const BerryShrubDecorArt := preload("res://scripts/world/art/decor/nature/berry_shrub_decor_art.gd")
const BoulderPileDecorArt := preload("res://scripts/world/art/decor/nature/boulder_pile_decor_art.gd")
const BrightOakTreeDecorArt := preload("res://scripts/world/art/decor/nature/bright_oak_tree_decor_art.gd")
const BucketDecorArt := preload("res://scripts/world/art/decor/nature/bucket_decor_art.gd")
const CanvasBannerDecorArt := preload("res://scripts/world/art/decor/nature/canvas_banner_decor_art.gd")
const ChestDecorArt := preload("res://scripts/world/art/decor/nature/chest_decor_art.gd")
const ConiferTreeDecorArt := preload("res://scripts/world/art/decor/nature/conifer_tree_decor_art.gd")
const CrystalClusterDecorArt := preload("res://scripts/world/art/decor/nature/crystal_cluster_decor_art.gd")
const DecoratedPineDecorArt := preload("res://scripts/world/art/decor/nature/decorated_pine_decor_art.gd")
const DenseTreeDecorArt := preload("res://scripts/world/art/decor/nature/dense_tree_decor_art.gd")
const FenceDecorArt := preload("res://scripts/world/art/decor/nature/fence_decor_art.gd")
const FernDecorArt := preload("res://scripts/world/art/decor/nature/fern_decor_art.gd")
const FloweringTreeDecorArt := preload("res://scripts/world/art/decor/nature/flowering_tree_decor_art.gd")
const FruitBushDecorArt := preload("res://scripts/world/art/decor/nature/fruit_bush_decor_art.gd")
const GiantLeafTreeDecorArt := preload("res://scripts/world/art/decor/nature/giant_leaf_tree_decor_art.gd")
const GrassTuftDecorArt := preload("res://scripts/world/art/decor/nature/grass_tuft_decor_art.gd")
const LadderDecorArt := preload("res://scripts/world/art/decor/nature/ladder_decor_art.gd")
const LeafyPlantDecorArt := preload("res://scripts/world/art/decor/nature/leafy_plant_decor_art.gd")
const LilyPadsDecorArt := preload("res://scripts/world/art/decor/nature/lily_pads_decor_art.gd")
const LogPileDecorArt := preload("res://scripts/world/art/decor/nature/log_pile_decor_art.gd")
const MatureOakTreeDecorArt := preload("res://scripts/world/art/decor/nature/mature_oak_tree_decor_art.gd")
const MossRockDecorArt := preload("res://scripts/world/art/decor/nature/moss_rock_decor_art.gd")
const MushroomClusterDecorArt := preload("res://scripts/world/art/decor/nature/mushroom_cluster_decor_art.gd")
const OrangeFlowersDecorArt := preload("res://scripts/world/art/decor/nature/orange_flowers_decor_art.gd")
const PalmTreeDecorArt := preload("res://scripts/world/art/decor/nature/palm_tree_decor_art.gd")
const PineRockClusterDecorArt := preload("res://scripts/world/art/decor/nature/pine_rock_cluster_decor_art.gd")
const PricklyPearDecorArt := preload("res://scripts/world/art/decor/nature/prickly_pear_decor_art.gd")
const RockDecorArt := preload("res://scripts/world/art/decor/nature/rock_decor_art.gd")
const RootTreeDecorArt := preload("res://scripts/world/art/decor/nature/root_tree_decor_art.gd")
const ScarecrowDecorArt := preload("res://scripts/world/art/decor/nature/scarecrow_decor_art.gd")
const SmallSproutDecorArt := preload("res://scripts/world/art/decor/nature/small_sprout_decor_art.gd")
const SpikyPalmDecorArt := preload("res://scripts/world/art/decor/nature/spiky_palm_decor_art.gd")
const StumpDecorArt := preload("res://scripts/world/art/decor/nature/stump_decor_art.gd")
const SucculentDecorArt := preload("res://scripts/world/art/decor/nature/succulent_decor_art.gd")
const TallCactusDecorArt := preload("res://scripts/world/art/decor/nature/tall_cactus_decor_art.gd")
const TwistedTreeDecorArt := preload("res://scripts/world/art/decor/nature/twisted_tree_decor_art.gd")
const UprightLogDecorArt := preload("res://scripts/world/art/decor/nature/upright_log_decor_art.gd")
const VineColumnDecorArt := preload("res://scripts/world/art/decor/nature/vine_column_decor_art.gd")
const WellDecorArt := preload("res://scripts/world/art/decor/nature/well_decor_art.gd")
const WhiteFlowerPatchDecorArt := preload("res://scripts/world/art/decor/nature/white_flower_patch_decor_art.gd")
const WoodPlanksDecorArt := preload("res://scripts/world/art/decor/nature/wood_planks_decor_art.gd")

const DEFAULT_ID := "tree_bright_oak_00"
static var IDS := PackedStringArray(["tree_bright_oak_00", "ladder_tall_01", "tree_dark_conifer_02", "chest_03", "conifer_rock_cluster_04", "pine_rocks_left_05", "pine_rocks_right_06", "mossy_stump_07", "wood_bucket_08", "leafy_plant_09", "moss_rock_10", "upright_log_11", "wood_planks_12", "berry_bush_blue_13", "fence_long_14", "rock_gray_15", "fence_short_16", "herb_sprout_17", "stump_round_18", "flowers_yellow_19", "mushroom_small_20", "canvas_banner_left_21", "canvas_banner_right_22", "tree_summer_slim_23", "wood_planks_vertical_24", "oak_mature_large_25", "dense_tree_small_26", "log_pile_27", "autumn_tree_28", "apple_tree_ladder_29", "apple_tree_30", "well_31", "vine_column_32", "mushroom_tiny_33", "stone_face_34", "mushrooms_red_35", "mushroom_tiny_red_36", "mushroom_yellow_37", "mushroom_spot_38", "mushroom_small_pair_39", "mushroom_cluster_40", "tree_bright_tall_41", "decorated_pine_42", "flowering_tree_43", "succulent_rosette_44", "white_flowers_45", "palm_tree_46", "melon_47", "seedpod_48", "lily_pad_49", "grass_tuft_50", "small_conifer_51", "white_flower_52", "cactus_tall_53", "lily_pad_blue_54", "prickly_pear_55", "crystal_cluster_56", "white_flower_patch_57", "rock_small_58", "shell_spiral_59", "giant_leaf_tree_60", "twisted_tree_61", "spiky_palm_62", "root_tree_63", "berries_orange_64", "scarecrow_65", "fruit_bush_66", "orange_flowers_67", "mossy_rock_68", "rock_pebble_69", "boulders_70", "moss_stone_71", "berry_shrub_72", "lily_pads_73", "berry_cluster_74", "tiny_weed_75", "leafy_shrub_76", "grass_blade_77", "tiny_sprout_78", "tiny_flower_79", "tiny_plant_80", "tiny_seed_81", "tiny_stem_82", "fern_decor"])

static var ITEMS := {
	"tree_bright_oak_00": {"art": BrightOakTreeDecorArt, "variant": 0},
	"ladder_tall_01": {"art": LadderDecorArt, "variant": 0},
	"tree_dark_conifer_02": {"art": ConiferTreeDecorArt, "variant": 0},
	"chest_03": {"art": ChestDecorArt, "variant": 0},
	"conifer_rock_cluster_04": {"art": PineRockClusterDecorArt, "variant": 0},
	"pine_rocks_left_05": {"art": PineRockClusterDecorArt, "variant": 1},
	"pine_rocks_right_06": {"art": PineRockClusterDecorArt, "variant": 2},
	"mossy_stump_07": {"art": StumpDecorArt, "variant": 0},
	"wood_bucket_08": {"art": BucketDecorArt, "variant": 0},
	"leafy_plant_09": {"art": LeafyPlantDecorArt, "variant": 0},
	"moss_rock_10": {"art": MossRockDecorArt, "variant": 0},
	"upright_log_11": {"art": UprightLogDecorArt, "variant": 0},
	"wood_planks_12": {"art": WoodPlanksDecorArt, "variant": 0},
	"berry_bush_blue_13": {"art": BerryBushBlueDecorArt, "variant": 0},
	"fence_long_14": {"art": FenceDecorArt, "variant": 0},
	"rock_gray_15": {"art": RockDecorArt, "variant": 0},
	"fence_short_16": {"art": FenceDecorArt, "variant": 1},
	"herb_sprout_17": {"art": SmallSproutDecorArt, "variant": 0},
	"stump_round_18": {"art": StumpDecorArt, "variant": 1},
	"flowers_yellow_19": {"art": OrangeFlowersDecorArt, "variant": 2},
	"mushroom_small_20": {"art": MushroomClusterDecorArt, "variant": 1},
	"canvas_banner_left_21": {"art": CanvasBannerDecorArt, "variant": 0},
	"canvas_banner_right_22": {"art": CanvasBannerDecorArt, "variant": 1},
	"tree_summer_slim_23": {"art": BrightOakTreeDecorArt, "variant": 1},
	"wood_planks_vertical_24": {"art": WoodPlanksDecorArt, "variant": 1},
	"oak_mature_large_25": {"art": MatureOakTreeDecorArt, "variant": 0},
	"dense_tree_small_26": {"art": DenseTreeDecorArt, "variant": 0},
	"log_pile_27": {"art": LogPileDecorArt, "variant": 0},
	"autumn_tree_28": {"art": AutumnTreeDecorArt, "variant": 0},
	"apple_tree_ladder_29": {"art": AppleTreeDecorArt, "variant": 1},
	"apple_tree_30": {"art": AppleTreeDecorArt, "variant": 0},
	"well_31": {"art": WellDecorArt, "variant": 0},
	"vine_column_32": {"art": VineColumnDecorArt, "variant": 0},
	"mushroom_tiny_33": {"art": MushroomClusterDecorArt, "variant": 2},
	"stone_face_34": {"art": RockDecorArt, "variant": 2},
	"mushrooms_red_35": {"art": MushroomClusterDecorArt, "variant": 3},
	"mushroom_tiny_red_36": {"art": MushroomClusterDecorArt, "variant": 4},
	"mushroom_yellow_37": {"art": MushroomClusterDecorArt, "variant": 5},
	"mushroom_spot_38": {"art": MushroomClusterDecorArt, "variant": 6},
	"mushroom_small_pair_39": {"art": MushroomClusterDecorArt, "variant": 7},
	"mushroom_cluster_40": {"art": MushroomClusterDecorArt, "variant": 8},
	"tree_bright_tall_41": {"art": BrightOakTreeDecorArt, "variant": 2},
	"decorated_pine_42": {"art": DecoratedPineDecorArt, "variant": 0},
	"flowering_tree_43": {"art": FloweringTreeDecorArt, "variant": 0},
	"succulent_rosette_44": {"art": SucculentDecorArt, "variant": 0},
	"white_flowers_45": {"art": WhiteFlowerPatchDecorArt, "variant": 0},
	"palm_tree_46": {"art": PalmTreeDecorArt, "variant": 0},
	"melon_47": {"art": LilyPadsDecorArt, "variant": 3},
	"seedpod_48": {"art": SmallSproutDecorArt, "variant": 4},
	"lily_pad_49": {"art": LilyPadsDecorArt, "variant": 0},
	"grass_tuft_50": {"art": GrassTuftDecorArt, "variant": 0},
	"small_conifer_51": {"art": ConiferTreeDecorArt, "variant": 3},
	"white_flower_52": {"art": WhiteFlowerPatchDecorArt, "variant": 1},
	"cactus_tall_53": {"art": TallCactusDecorArt, "variant": 0},
	"lily_pad_blue_54": {"art": LilyPadsDecorArt, "variant": 1},
	"prickly_pear_55": {"art": PricklyPearDecorArt, "variant": 0},
	"crystal_cluster_56": {"art": CrystalClusterDecorArt, "variant": 0},
	"white_flower_patch_57": {"art": WhiteFlowerPatchDecorArt, "variant": 2},
	"rock_small_58": {"art": RockDecorArt, "variant": 1},
	"shell_spiral_59": {"art": RockDecorArt, "variant": 3},
	"giant_leaf_tree_60": {"art": GiantLeafTreeDecorArt, "variant": 0},
	"twisted_tree_61": {"art": TwistedTreeDecorArt, "variant": 0},
	"spiky_palm_62": {"art": SpikyPalmDecorArt, "variant": 0},
	"root_tree_63": {"art": RootTreeDecorArt, "variant": 0},
	"berries_orange_64": {"art": BerryShrubDecorArt, "variant": 2},
	"scarecrow_65": {"art": ScarecrowDecorArt, "variant": 0},
	"fruit_bush_66": {"art": FruitBushDecorArt, "variant": 0},
	"orange_flowers_67": {"art": OrangeFlowersDecorArt, "variant": 0},
	"mossy_rock_68": {"art": MossRockDecorArt, "variant": 1},
	"rock_pebble_69": {"art": RockDecorArt, "variant": 4},
	"boulders_70": {"art": BoulderPileDecorArt, "variant": 0},
	"moss_stone_71": {"art": MossRockDecorArt, "variant": 2},
	"berry_shrub_72": {"art": BerryShrubDecorArt, "variant": 0},
	"lily_pads_73": {"art": LilyPadsDecorArt, "variant": 2},
	"berry_cluster_74": {"art": BerryShrubDecorArt, "variant": 1},
	"tiny_weed_75": {"art": GrassTuftDecorArt, "variant": 1},
	"leafy_shrub_76": {"art": LeafyPlantDecorArt, "variant": 1},
	"grass_blade_77": {"art": GrassTuftDecorArt, "variant": 2},
	"tiny_sprout_78": {"art": SmallSproutDecorArt, "variant": 1},
	"tiny_flower_79": {"art": WhiteFlowerPatchDecorArt, "variant": 3},
	"tiny_plant_80": {"art": SmallSproutDecorArt, "variant": 2},
	"tiny_seed_81": {"art": SmallSproutDecorArt, "variant": 3},
	"tiny_stem_82": {"art": SmallSproutDecorArt, "variant": 5},
	"fern_decor": {"art": FernDecorArt, "variant": 0},
}


static func has_id(id: String) -> bool:
	return ITEMS.has(id)


static func draw_id(canvas: CanvasItem, id: String, variant: int = 0, tint: Color = Color(0, 0, 0, 0)) -> void:
	var item: Dictionary = ITEMS.get(id, ITEMS[DEFAULT_ID])
	var art = item["art"]
	art.draw(canvas, int(item["variant"]) + variant, tint)


static func get_variant(id: String) -> int:
	var item: Dictionary = ITEMS.get(id, ITEMS[DEFAULT_ID])
	return int(item["variant"])


static func random_id(rng: RandomNumberGenerator) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return IDS[rng.randi_range(0, IDS.size() - 1)]
