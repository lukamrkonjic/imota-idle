extends RefCounted
class_name PixelPalette
## Grimbo palette + grid — one art pixel = PX screen pixels everywhere.

const PX := 4


static func snap(n: float) -> float:
	return round(n / PX) * PX


static func shade(c: Color, factor: float) -> Color:
	return Color(clampf(c.r * factor, 0.0, 1.0), clampf(c.g * factor, 0.0, 1.0), clampf(c.b * factor, 0.0, 1.0), c.a)


static func hex(h: int) -> Color:
	return Color(float((h >> 16) & 0xFF) / 255.0, float((h >> 8) & 0xFF) / 255.0, float(h & 0xFF) / 255.0)


const PAL := {
	"grass_a": 0x5A6B4A,
	"grass_b": 0x526040,
	"grass_c": 0x4A5A3C,
	"grass_dark": 0x465838,
	"hike_grass": 0x9FB62E,
	"hike_grass_b": 0x7E8E2B,
	"hike_grass_dark": 0x56682A,
	"hike_grass_light": 0xC4D83C,
	"moss": 0x5A6B4A,
	"dirt_a": 0x8A7558,
	"dirt_b": 0x7A684C,
	"path_orange": 0xC96E22,
	"path_light": 0xEA9331,
	"path_shadow": 0x8E4E22,
	"water_a": 0x4E5F78,
	"water_b": 0x3A4558,
	"water_c": 0x4AA7A8,
	"water_deep": 0x167EA0,
	"water_foam": 0x6A7A92,
	"water_spark": 0xA6DED8,
	"trunk_a": 0x8A7558,
	"trunk_b": 0x4A443C,
	"foliage_a": 0x5A6B4A,
	"foliage_b": 0x4A5A3C,
	"foliage_c": 0x6A7848,
	"leaf_gold": 0xF0D34C,
	"leaf_orange": 0xD55D2E,
	"leaf_red": 0xB9472F,
	"pine_mid": 0x496331,
	"pine_dark": 0x263F31,
	"stone_a": 0x6A7078,
	"stone_b": 0x5A6068,
	"cliff_warm": 0xA88981,
	"cliff_shadow": 0x6E504E,
	"cliff_light": 0xD0BAAA,
	"cliff_dark": 0x5C3D3D,
	"ore": 0xC4B08A,
	"shadow": 0x222228,
	"skin_a": 0xC4B08A,
	"hair": 0x4A443C,
	"outfit_a": 0x5A6068,
	"outfit_b": 0x222228,
	"gold": 0xC4B08A,
	"wood_light": 0xC98242,
	"cabin_wall": 0xE48772,
	"cabin_shadow": 0xB85C58,
	"cabin_roof": 0xF0774D,
	"roof_shadow": 0xB84A37,
	"cabin_trim": 0xFFE0AF,
	"wall_cream": 0xF0D2C2,
	"wall_blush": 0xD9A08F,
	"roof_purple": 0x58339A,
	"roof_purple_dark": 0x33215F,
	"roof_purple_light": 0x7250BF,
	"fire_red": 0xF04127,
	"fire_hot": 0xFFCA45,
	"fir_a": 0x4A5A3C,
	"fir_b": 0x222228,
	"snow_a": 0xD8E0DC,
	# Deep-forest theme (replaces the lime greens). Original nature palette.
	"forest_green": 0x2D4C2B,    # canopy shadows / dark background
	"leaf_green": 0x537B39,      # primary foliage / leaves
	"sunlit_grass": 0x93AB5C,    # bright lawn / illuminated ground
	"warm_stone": 0xBDBC98,      # paths / paving / light concrete
	"mid_foliage": 0x48723F,     # grass / shrubs / medium leaves
	"slate_blue": 0x444D58,      # buildings / fences / walls / rails
	"forest_teal": 0x193635,     # deepest gaps / foliage shadow
	"dark_bark": 0x353034,       # branches / trunk shadow
	"moss_hi": 0x6A8D4D,         # vegetation highlights
	"weathered_metal": 0x6A8084, # railings / blue-gray structural
	"bark_brown": 0x4B453C,      # wood / tree trunks
	"olive_wood": 0x696549,      # benches / lighter wooden details
}


static func pal(key: String) -> Color:
	return hex(PAL[key])


## Push saturation/value so props read clearly against terrain.
static func enrich_entity(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s * 1.12, 1.0), minf(c.v * 1.05, 1.0), c.a)


## Per-tile colour — keep hues from data; only tiny value shifts for depth.
static func enrich_tile(tile_id: String, c: Color) -> Color:
	match tile_id:
		"sand", "sand_dune", "snow", "cobble", "rock", "ash", "lava_rock":
			return c
		"water", "shallow", "deep_water":
			return shade(c, 1.02)
		"grass", "grass_dark", "marsh", "frozen_grass", "mud":
			return shade(c, 1.01)
		_:
			return c


## Pull tile colour slightly toward the biome family tint for cohesion.
static func harmonize_for_biome(c: Color, biome_id: String) -> Color:
	if biome_id.is_empty():
		return c
	var tint := _biome_tint(biome_id)
	return c.lerp(tint, 0.10)


static func _biome_tint(biome_id: String) -> Color:
	match biome_id:
		"desert", "beach":
			return hex(0xC4B08A)
		"forest", "plains", "swamp", "dense_forest", "flower_meadow", "marsh_pool", "oasis":
			return hex(0x5A6B4A)
		"tundra":
			return hex(0xD8E0DC)
		"rocky_hills", "rocky_clearing":
			return hex(0x6A7078)
		"volcanic":
			return hex(0x5A4840)
		"ocean":
			return hex(0x4E5F78)
		_:
			return hex(0x5A6B4A)
