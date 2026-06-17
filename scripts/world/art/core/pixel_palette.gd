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
	"hike_grass": 0x6E8A36,
	"hike_grass_b": 0x5C7430,
	"hike_grass_dark": 0x3E5226,
	"hike_grass_light": 0x8AA848,
	"moss": 0x5A6B4A,
	"dirt_a": 0x8A7558,
	"dirt_b": 0x7A684C,
	"path_orange": 0x916C40,
	"path_light": 0xAE8C58,
	"path_shadow": 0x55402C,
	"water_a": 0x4E5F78,
	"water_b": 0x3A4558,
	"water_c": 0x4AA7A8,
	"water_deep": 0x167EA0,
	"water_foam": 0x6A7A92,
	"water_spark": 0xA6DED8,
	"trunk_a": 0x8A7558,
	"trunk_b": 0x4A443C,
	"foliage_a": 0x44533A,
	"foliage_b": 0x37452E,
	"foliage_c": 0x515E38,
	"leaf_gold": 0xF0D34C,
	"leaf_orange": 0xD55D2E,
	"leaf_red": 0xB9472F,
	"pine_mid": 0x3A5028,
	"pine_dark": 0x1E3326,
	"stone_a": 0x6B6D7A,
	"stone_b": 0x4E505A,
	"cliff_warm": 0x7C7E8C,
	"cliff_shadow": 0x44424F,
	"cliff_light": 0xB2B4C0,
	"cliff_dark": 0x2C2B38,
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
	"roof_purple": 0x5A5570,        # muted slate (was vivid purple — let flowers be the purple accent)
	"roof_purple_dark": 0x3A364A,
	"roof_purple_light": 0x726E88,
	"wildflower": 0xAB8FCB,        # muted violet meadow flowers (natural accent)
	"wildflower_deep": 0x7E60AE,
	"fire_red": 0xF04127,
	"fire_hot": 0xFFCA45,
	"fir_a": 0x4A5A3C,
	"fir_b": 0x222228,
	"snow_a": 0xD8E0DC,
	# Dark forest theme: deep mossy greens, moody and low-key (ref: dark woodland).
	"forest_green": 0x213620,    # canopy shadows / dark background
	"leaf_green": 0x3E5E2A,      # primary foliage / leaves
	"sunlit_grass": 0x6E9042,    # brightest lawn / illuminated ground (still deep)
	"warm_stone": 0x86857A,      # paths / paving / light concrete (darker, cooler)
	"mid_foliage": 0x47672F,     # grass / shrubs / medium leaves
	"slate_blue": 0x333A47,      # buildings / fences / walls / rails
	"forest_teal": 0x162619,     # deepest gaps / foliage shadow
	"dark_bark": 0x26222C,       # branches / trunk shadow
	"moss_hi": 0x5A7838,         # vegetation highlights
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
