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
	"grass_a": 0x44523A,
	"grass_b": 0x3C4830,
	"grass_c": 0x35422E,
	"grass_dark": 0x2E3C28,
	"hike_grass": 0x5E7A2E,
	"hike_grass_b": 0x4E632A,
	"hike_grass_dark": 0x36461F,
	"hike_grass_light": 0x7A9438,
	"moss": 0x44523A,
	"dirt_a": 0x6B5740,
	"dirt_b": 0x5A4C38,
	"path_orange": 0x7E5A33,
	"path_light": 0x9A7544,
	"path_shadow": 0x4E3A22,
	"water_a": 0x4E5F78,
	"water_b": 0x3A4558,
	"water_c": 0x3A8688,
	"water_deep": 0x125E78,
	"water_foam": 0x6A7A92,
	"water_spark": 0xA6DED8,
	"trunk_a": 0x6B5740,
	"trunk_b": 0x33302A,
	"foliage_a": 0x3E4A32,
	"foliage_b": 0x313B28,
	"foliage_c": 0x495331,
	"leaf_gold": 0xCDA94A,
	"leaf_orange": 0xB05330,
	"leaf_red": 0x923A2A,
	"pine_mid": 0x33471F,
	"pine_dark": 0x18281C,
	"stone_a": 0x565A62,
	"stone_b": 0x44484F,
	"cliff_warm": 0x6E5E58,
	"cliff_shadow": 0x463838,
	"cliff_light": 0x8E7E74,
	"cliff_dark": 0x3A2C2C,
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
	"fir_a": 0x313D28,
	"fir_b": 0x1A1A1F,
	"snow_a": 0xD8E0DC,
	# Deep-forest theme (replaces the lime greens). Original nature palette.
	# Drastically darkened: moody-cozy dark forest — deep greens, earthy browns.
	"forest_green": 0x1B2E18,    # canopy shadows / dark background
	"leaf_green": 0x2E481F,      # primary foliage / leaves
	"sunlit_grass": 0x5E7C3A,    # brightest lit ground (still deep)
	"warm_stone": 0x8C8A70,      # paths / paving / light concrete
	"mid_foliage": 0x3C5628,     # grass / shrubs / medium leaves
	"slate_blue": 0x363E48,      # buildings / fences / walls / rails
	"forest_teal": 0x122017,     # deepest gaps / foliage shadow
	"dark_bark": 0x282430,       # branches / trunk shadow
	"moss_hi": 0x4C6630,         # vegetation highlights
	"weathered_metal": 0x4E6064, # railings / blue-gray structural
	"bark_brown": 0x3A352D,      # wood / tree trunks
	"olive_wood": 0x4E4B38,      # benches / lighter wooden details
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
