extends RefCounted
class_name TerrainStyle
## All terrain COLOUR + tile-category logic in one place, so the world's art can be reworked
## (or swapped/data-driven) without touching the 3D render pipeline. Extracted from the
## world_render_3d monolith. Pure/static: (base colour, tile, grid pos, elev/slope/curve) ->
## final Color. See docs/ART_GUIDE.md. The world render only calls grade() + the is_* helpers.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

# Tile categories — the single source of truth (geometry + art both classify off these).
const PATH_TILES := ["dirt", "cobble", "mud", "gravel", "badland_clay"]
const ROCK_TILES := ["rock", "lava_rock", "ash", "peak_rock"]
const SNOW_TILES := ["snow", "frozen_grass", "peak_snow"]
const WATER_TILES := ["deep_water", "water", "shallow"]
const SAND_TILES := ["sand", "sand_dune", "desert_sand", "desert_dune"]
# Dead / corrupted / charred ground (hostile north). Kept OUT of the grass gradient so it stays
# bleak — only broad light variation is applied, never a green/orange/rock tint.
const HOSTILE_TILES := ["dead_grass", "scorched_earth", "obsidian", "blight_pool"]

# Alpine colour ramp (A Short Hike-style): grass -> olive -> ochre dirt -> warm rock -> cool
# high rock -> snow, as ONE continuous ramp so a mountain never reads as a flat single tone.
const ALPINE_SUMMIT := 44.0                      # ELEV_MAX_STEPS — height normaliser
const ALP_MEADOW := Color(0.42, 0.55, 0.31)      # grassy foothill green
const ALP_OLIVE := Color(0.53, 0.55, 0.33)       # dry mid-slope olive
const ALP_DIRT := Color(0.60, 0.47, 0.30)        # ochre worn earth / scree
const ALP_ROCK := Color(0.60, 0.53, 0.47)        # warm taupe stone
const ALP_ROCK_HI := Color(0.74, 0.73, 0.76)     # cool desaturated high rock
const SNOW_LIT := Color(0.91, 0.91, 1.00)        # soft lilac-white sunlit snow
const SNOW_SHADE := Color(0.61, 0.64, 0.88)      # periwinkle alpine shadow


static func is_path(tile: String) -> bool:
	return tile in PATH_TILES


static func is_rock(tile: String) -> bool:
	return tile in ROCK_TILES


static func is_snow(tile: String) -> bool:
	return tile in SNOW_TILES


## Coarse surface family for corner-colour blending: water/path/snow/rock/sand/grass.
static func surface_family(tile: String) -> String:
	if tile in WATER_TILES:
		return "water"
	if is_path(tile):
		return "path"
	if is_snow(tile):
		return "snow"
	if is_rock(tile):
		return "rock"
	if tile in SAND_TILES:
		return "sand"
	if tile in HOSTILE_TILES:
		return "rock"   # bleak ground blends as solid earth, never grass
	return "grass"


## Warm + enrich a terrain tile colour with BROAD low-frequency painterly variation, alpine
## elevation layering, snow shedding on steep faces, path/trail tinting, and the forest-grass
## gradient. (col, tile, gtx, gty, elev, slope, curve) -> final Color.
static func grade(col: Color, tile: String, gtx: int, gty: int, elev: int = 0, slope: int = 0, curve: int = 0) -> Color:
	var c := col
	var fx := float(gtx)
	var fz := float(gty)
	# Three broad low-frequency bands (no noise) -> painterly sunlit/shaded gradients.
	var bright := 0.5 + 0.5 * sin(fx * 0.07) * cos(fz * 0.06)
	var band2 := 0.5 + 0.5 * sin(fx * 0.13 + 1.2) * cos(fz * 0.115 - 0.7)
	var warm := clampf(sin((fx + fz) * 0.045 + 1.3), 0.0, 1.0)
	var hi := clampf(float(elev) / ALPINE_SUMMIT, 0.0, 1.0)   # 0 foot .. 1 summit
	var steep := clampf(float(slope) / 5.0, 0.0, 1.0)         # 0 flat shelf .. 1 cliff face
	var convex := clampf(float(curve) / 16.0, -1.0, 1.0)
	if tile in HOSTILE_TILES:
		# Dead/corrupted/charred ground: preserve the bleak raw colour; only broad low-frequency
		# light variation + a faint ashen mottle so it isn't a flat slab. No green/orange/rock.
		var bleak := c.darkened((1.0 - bright) * 0.16).lightened(band2 * 0.06)
		var mottle := 0.5 + 0.5 * sin(fx * 0.09 - fz * 0.07 + 1.1)
		return bleak.lerp(bleak.lightened(0.10), mottle * 0.12)
	if is_snow(tile):
		# Snow only holds on gentle, top-facing surfaces; steep faces shed it to bare rock.
		if steep > 0.5:
			return alpine_ramp(elev, bright, band2).lerp(ALP_ROCK_HI, 0.55)
		var snow_light := clampf(bright * 0.46 + hi * 0.32, 0.08, 0.82)
		var snow := SNOW_SHADE.lerp(SNOW_LIT, snow_light)
		var lavender_patch := 0.5 + 0.5 * sin(fx * 0.045 - fz * 0.038 + 0.7)
		return snow.lerp(Color(0.70, 0.68, 0.91), lavender_patch * 0.10)
	if is_path(tile) and elev <= 0:
		if tile == "cobble" or tile == "gravel":
			# Stone / gravel roads keep their cool grey base — only broad lighting, never the
			# warm dirt tint, so a paved road reads as stone instead of orange earth.
			c = c.lightened(bright * 0.12).darkened((1.0 - band2) * 0.06)
		else:
			var path_col := PixelPalette.pal("path_orange").lerp(PixelPalette.pal("path_light"), bright * 0.42)
			c = c.lerp(path_col, 0.94)
	elif is_rock(tile) or elev > 0:
		# Material follows LANDFORM first: steep/convex -> warm cliff mass; calm shelves keep
		# grass or ochre. A broad spatial bias keeps the zones off parallel elevation rings.
		var patch := sin(fx * 0.031 + fz * 0.019 + 0.8) * 0.11 \
			+ cos(fx * 0.017 - fz * 0.027 - 1.4) * 0.08
		var zone := clampf(hi + patch + convex * 0.08, 0.0, 1.0)
		var shelf := ALP_MEADOW.lerp(ALP_OLIVE, smoothstep(0.18, 0.62, zone))
		shelf = shelf.lerp(ALP_DIRT, smoothstep(0.52, 0.82, zone) * 0.72)
		var cliff := ALP_ROCK.lerp(ALP_ROCK_HI, smoothstep(0.58, 0.96, zone))
		cliff = cliff.lightened(bright * 0.08).darkened((1.0 - band2) * 0.06)
		var cliff_mass := smoothstep(0.20, 0.58, steep + maxf(convex, 0.0) * 0.24)
		var landform := shelf.lerp(cliff, cliff_mass)
		# One broad meandering trail crosses occasional gentle lower/mid shelves.
		var trail_wave := sin((fx + fz) * 0.020 + sin(fx * 0.011 - 0.6) * 1.4)
		var trail := (1.0 - smoothstep(0.025, 0.105, absf(trail_wave))) \
			* (1.0 - smoothstep(0.24, 0.46, steep)) \
			* smoothstep(0.10, 0.22, hi) * (1.0 - smoothstep(0.66, 0.80, hi))
		var trail_col := PixelPalette.pal("path_orange").lerp(PixelPalette.pal("path_light"), 0.28 + bright * 0.18)
		landform = landform.lerp(trail_col, trail * 0.72)
		c = c.lerp(landform, 0.94)
	elif tile in SAND_TILES:
		c = c.lerp(PixelPalette.pal("warm_stone"), 0.5)
	elif tile == "plank_floor":
		# Wooden bridge / boardwalk deck — warm planks, NEVER grass-tinted, with a faint
		# slat stripe so it reads as laid boards (A Short Hike-style plank crossing).
		var wood := c.lightened(bright * 0.14).darkened((1.0 - band2) * 0.08)
		var slat := 0.5 + 0.5 * sin((fx - fz) * 1.7)
		c = wood.darkened(smoothstep(0.55, 1.0, slat) * 0.16)
	elif tile == "plaza":
		# Paved stone plaza — keep the cool grey, just lit (not green).
		c = c.lightened(bright * 0.10).darkened((1.0 - band2) * 0.06)
	else:
		# Deep-forest grass gradient: mid foliage -> sunlit grass, drifting to leaf/forest
		# green in shade and a moss highlight elsewhere. No lime.
		var grass := PixelPalette.pal("mid_foliage").lerp(PixelPalette.pal("sunlit_grass"), bright)
		grass = grass.lerp(PixelPalette.pal("leaf_green"), (1.0 - band2) * 0.45)
		grass = grass.lerp(PixelPalette.pal("forest_green"), (1.0 - bright) * 0.2)
		grass = grass.lerp(PixelPalette.pal("moss_hi"), warm * 0.18)
		c = c.lerp(grass, 0.82)
	return c


## Continuous alpine fallback for snow shedding — softly graded, no horizontal striation.
static func alpine_ramp(elev: int, bright: float, band2: float) -> Color:
	var e := float(elev)
	var col: Color
	if e < 6.0:
		col = ALP_MEADOW
	elif e < 12.0:
		col = ALP_MEADOW.lerp(ALP_OLIVE, smoothstep(6.0, 12.0, e))
	elif e < 19.0:
		col = ALP_OLIVE.lerp(ALP_DIRT, smoothstep(12.0, 19.0, e))
	elif e < 28.0:
		col = ALP_DIRT.lerp(ALP_ROCK, smoothstep(19.0, 28.0, e))
	else:
		col = ALP_ROCK.lerp(ALP_ROCK_HI, smoothstep(28.0, 42.0, e))
	col = col.lightened(bright * 0.12).darkened((1.0 - band2) * 0.08)
	return col
