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
	"grass_a": 0x596E47,
	"grass_b": 0x647551,
	"grass_c": 0x4E6044,
	"grass_dark": 0x38453A,
	"moss": 0x596E47,
	"dirt_a": 0xC17B5C,
	"dirt_b": 0x85444A,
	"water_a": 0x7687AB,
	"water_b": 0x444A65,
	"water_foam": 0xA9BBCC,
	"trunk_a": 0xC17B5C,
	"trunk_b": 0x4A363C,
	"foliage_a": 0x596E47,
	"foliage_b": 0x38453A,
	"foliage_c": 0x9BA15F,
	"stone_a": 0xA9BBCC,
	"stone_b": 0x7687AB,
	"ore": 0xD9C277,
	"shadow": 0x222228,
	"skin_a": 0xD9C277,
	"hair": 0x4A363C,
	"outfit_a": 0x444A65,
	"outfit_b": 0x222228,
	"gold": 0xD9C277,
	"fir_a": 0x38453A,
	"fir_b": 0x222228,
	"snow_a": 0xDFE6E0,
}


static func pal(key: String) -> Color:
	return hex(PAL[key])
