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
	"moss": 0x5A6B4A,
	"dirt_a": 0x8A7558,
	"dirt_b": 0x7A684C,
	"water_a": 0x4E5F78,
	"water_b": 0x3A4558,
	"water_foam": 0x6A7A92,
	"trunk_a": 0x8A7558,
	"trunk_b": 0x4A443C,
	"foliage_a": 0x5A6B4A,
	"foliage_b": 0x4A5A3C,
	"foliage_c": 0x6A7848,
	"stone_a": 0x6A7078,
	"stone_b": 0x5A6068,
	"ore": 0xC4B08A,
	"shadow": 0x222228,
	"skin_a": 0xC4B08A,
	"hair": 0x4A443C,
	"outfit_a": 0x5A6068,
	"outfit_b": 0x222228,
	"gold": 0xC4B08A,
	"fir_a": 0x4A5A3C,
	"fir_b": 0x222228,
	"snow_a": 0xD8E0DC,
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
