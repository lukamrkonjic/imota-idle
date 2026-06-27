extends RefCounted
class_name TerrainStyle
## All terrain COLOUR + tile-category logic in one place, so the world's art can be reworked
## (or swapped/data-driven) without touching the 3D render pipeline. Extracted from the
## world_render_3d monolith. Pure/static: (base colour, tile, grid pos, elev/slope/curve) ->
## final Color. See docs/ART_GUIDE.md. The world render only calls grade() + the is_* helpers.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

# Tile categories — the single source of truth (geometry + art both classify off these).
const PATH_TILES := ["dirt", "cobble", "mud", "gravel", "badland_clay"]
const ROCK_TILES := ["rock", "lava_rock", "ash", "peak_rock"]
const SNOW_TILES := ["snow", "frozen_grass", "peak_snow"]
const WATER_TILES := ["deep_water", "water", "shallow"]
const SAND_TILES := ["sand", "sand_dune", "desert_sand", "desert_dune"]
# Dead / corrupted / charred ground (hostile north). Kept OUT of the grass gradient so it stays
# bleak — only broad light variation is applied, never a green/orange/rock tint.
const HOSTILE_TILES := ["dead_grass", "scorched_earth", "obsidian", "blight_pool"]
# BUILT surfaces that keep their own flat colour in the one-colour-per-biome look (they read as
# constructed, not as the surrounding biome). Natural earth tiles (dirt/mud/gravel/clay) instead
# take the biome's flat ground colour.
const BUILT_TILES := ["cobble", "plaza", "plank_floor", "plank"]
# Single flat tones for the cross-biome surfaces in the flat look (A Short Hike warm palette).
const SAND_FLAT := Color(0.902, 0.812, 0.475)   # warm yellow beach / desert sand
const SNOW_FLAT := Color(0.929, 0.953, 0.969)   # pale blue-white snow

# Alpine colour ramp (A Short Hike-style): grass -> olive -> ochre dirt -> warm rock -> cool
# high rock -> snow, as ONE continuous ramp so a mountain never reads as a flat single tone.
const ALPINE_SUMMIT := 128.0                     # = ELEV_MAX_STEPS — height normaliser (grass→rock→snow span)
const ALP_MEADOW := Color(0.502, 0.565, 0.306)      # grassy foothill green
const ALP_OLIVE := Color(0.541, 0.537, 0.322)       # dry mid-slope olive
const ALP_DIRT := Color(0.663, 0.467, 0.271)        # ochre worn earth / scree
const ALP_ROCK := Color(0.651, 0.616, 0.565)        # warm taupe stone
const ALP_ROCK_HI := Color(0.710, 0.706, 0.722)     # cool desaturated high rock
const SNOW_LIT := Color(0.957, 0.973, 0.984)        # bright, near-white sunlit snow (barely cool)
const SNOW_SHADE := Color(0.780, 0.847, 0.918)      # cool blue-white snow shadow — never periwinkle


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


## Shift a graded terrain colour toward its BIOME's tint so biomes read distinctly (a forest,
## a moor, a meadow and an old-growth stand stop looking like the same green). Applied strongly
## on grass/ground, lightly on rock/sand/snow and never on water, so mountains, beaches and
## coasts stay legible. Shared by the 3D mesher and both 2D maps so they always match.
static func biome_tinted(base: Color, tile: String, tint: Color, strength: float) -> Color:
	match surface_family(tile):
		"grass":
			return base.lerp(tint, strength)
		"sand", "rock", "snow":
			return base.lerp(tint, strength * 0.25)
		"water":
			return base
		_:
			return base.lerp(tint, strength * 0.5)


## A Short Hike-style painterly ground variation: a broad, soft, VALUE-ONLY brush texture — gentle
## sunlit/shaded sweeps of the SAME colour, never a hue/saturation shift. This is the key fix for
## the dark-green "splotches": the old version pushed shaded blobs toward a cooler, more-saturated
## green, so they read as a stray dark biome. Now it only lifts/drops brightness a few percent, so
## variation reads as light on one coherent ground. Low-frequency only; strength scales by surface
## family. Plus a rare, faint flower/lichen accent on living ground (flavour, not a patch).
static func terrain_patch(base: Color, tile: String, biome_id: String, gx: int, gy: int) -> Color:
	var fam := surface_family(tile)
	if fam == "water" or fam == "path":
		return base
	var amt := 0.0
	match fam:
		"grass": amt = 1.0
		"rock", "sand": amt = 0.7
		"snow": amt = 0.4
		_: amt = 0.7
	# One broad, soft brush field (~32-tile period) mapped to a small symmetric value swing.
	var brush := WG._smooth_val(0, gx, gy, 32.0, 700) * 0.8 + WG._smooth_val(0, gx, gy, 13.0, 701) * 0.2
	var v := 1.0 + (brush - 0.5) * 2.0 * 0.07 * amt   # at most ±7% brightness on grass
	var col := Color(clampf(base.r * v, 0.0, 1.0), clampf(base.g * v, 0.0, 1.0), clampf(base.b * v, 0.0, 1.0), base.a)
	# Rare, soft accent patches on living ground (heather / flowers / lichen / leaf-litter). Kept
	# faint and sparse so it's painterly flavour, never a dark island.
	if fam == "grass":
		var acc := WG._smooth_val(0, gx, gy, 6.5, 702)
		if acc > 0.88:
			var accent := _biome_accent(biome_id)
			if accent.a > 0.0:
				col = col.lerp(accent, clampf((acc - 0.88) * 4.0, 0.0, 1.0) * 0.24)
	return col


## A sparse rare-accent colour per biome family (transparent = no accent).
static func _biome_accent(biome_id: String) -> Color:
	match biome_id:
		"plains", "wheatfield", "sunlit_glade": return Color(0.86, 0.80, 0.34)        # dry yellow-green
		"wildflower_meadow", "flower_meadow", "alpine_flower_field", "highland_meadow": return Color(0.74, 0.52, 0.80)  # soft purple bloom
		"forest", "dense_forest", "grove", "jungle", "volcanic_jungle": return Color(0.50, 0.39, 0.25)  # brown leaf-litter
		"boreal_forest", "misty_pine_woods", "taiga": return Color(0.40, 0.34, 0.21)  # needle floor
		"heather_moor", "haunted_moor", "thorn_waste": return Color(0.56, 0.39, 0.62) # purple heather
		"swamp", "bog", "corrupted_bog", "marsh_pool", "salt_marsh", "tide_flats": return Color(0.33, 0.40, 0.24)  # dark moss / peat
		"rocky_hills", "alpine", "rocky_clearing", "badlands": return Color(0.56, 0.52, 0.46)  # grey stone
		"beach", "palm_beach": return Color(0.82, 0.75, 0.56)                          # pale sand / shell
		"desert", "savanna", "savanna_scrub", "cactus_plain", "dune_sea": return Color(0.76, 0.63, 0.36)  # ochre
		"tundra", "snowdrift", "lichen_field": return Color(0.60, 0.66, 0.56)          # lichen grey-green
		_: return Color(0, 0, 0, 0)


## ONE flat colour per biome (the clean, distinct-region look — no noise, bands, patches or
## biome-tint blending). `base` is the tile's raw palette colour (used only for BUILT surfaces);
## `biome_ground` is the biome's curated flat colour (WorldRegistry.biome_ground). Lowland natural
## ground = the biome colour; sand and snow are single flat tones; and raised/steep ground sheds to
## bare stone (then a snow dusting at the very tops) BY ELEVATION ONLY, so mountains still read as
## peaks. This is the sole source of within-biome variation. Used by the terrain mesher + bake.
static func flat_ground(base: Color, tile: String, biome_ground: Color, elev: int = 0, slope: int = 0, _curve: int = 0) -> Color:
	# Built surfaces (roads/boardwalks/plazas) keep their own flat colour.
	if tile in BUILT_TILES:
		return base
	# Sand (beaches, dunes, desert) is one flat tone everywhere.
	if tile in SAND_TILES:
		return SAND_FLAT
	# Snow is snow regardless of biome.
	if is_snow(tile):
		return SNOW_FLAT
	# Everything else (grass, dirt/mud/clay earth, marsh, scree, ash, dead/charred ground) takes the
	# biome's single flat colour. NO spatial noise / bands / patches.
	var ground := biome_ground
	if elev > 0:
		# Elevation read: steep faces + high ground shed to bare stone; the very tops dust with snow.
		# Flat lowland shelves keep the pure biome colour. Clean ramps, no noise.
		var h := clampf(float(elev) / ALPINE_SUMMIT, 0.0, 1.0)
		var steep := clampf(float(slope) / 5.0, 0.0, 1.0)
		var rock := ALP_ROCK.lerp(ALP_ROCK_HI, smoothstep(0.40, 0.95, h))
		var to_rock := smoothstep(0.30, 0.62, steep + maxf(h - 0.38, 0.0) * 0.7)
		ground = ground.lerp(rock, to_rock)
		var snow_cap := smoothstep(0.74, 0.96, h) * (1.0 - steep * 0.5)
		ground = ground.lerp(SNOW_FLAT, snow_cap * 0.85)
	return ground


# Patch-overlay tuning. BROAD SOFT WASHES — big calm painterly fields, NOT mottled procedural
# blobs. Large scales + a high, wide coverage band keep patches few, large and gently blurred;
# NEVER per-tile jitter or high-frequency noise.
const PATCH_WARP_SCALE := 170.0   # domain-warp field period (tiles) — organic, very gentle outlines
const PATCH_WARP_AMP := 64.0      # how far the sample is warped (tiles)
const PATCH_MASK_SCALE := 170.0   # coverage field period (tiles) — washes ~120-340 tiles wide
const PATCH_PICK_SCALE := 240.0   # colour-selection field period — each wash leans one colour
const PATCH_COVER_LO := 0.74      # mask band start (high = sparse, ~10% coverage)
const PATCH_COVER_HI := 0.96      # mask band full (very wide LO..HI = heavily blurred edges)
const PATCH_STRENGTH := 0.22      # max blend toward a (now ground-harmonised) patch colour — gentle


## Broad painterly PATCH SPLASHES (A Short Hike): the flat biome colour is the base, and ~15-20% of
## the area softly drifts toward one of the biome's own `patchColors` over big low-frequency blobs
## (~40-120 tiles), with blurred edges. DETERMINISTIC + baked (never animated, never sun/weather
## driven). NO per-tile jitter, NO high-frequency noise. Skips water + built surfaces. `patches` =
## WorldRegistry.biome_patches. Called by the mesher/bake AFTER flat_ground.
static func patch_overlay(ground: Color, tile: String, patches: Array, gx: int, gy: int, elev: int = 0, slope: int = 0) -> Color:
	# Patches are for LOWLAND VEGETATION only. Sand/snow/rock + water/built stay clean and flat
	# (beaches, shores, snowfields and cliffs read best as single tones).
	if patches.is_empty() or tile in WATER_TILES or tile in BUILT_TILES or tile in SAND_TILES \
			or is_snow(tile) or is_rock(tile):
		return ground
	# Patches are a LOWLAND vegetation feature: fade them out where elevation has turned the ground
	# to bare rock / snow (flat_ground), so a biome's green/heather patch never tints a white peak.
	var h := clampf(float(elev) / ALPINE_SUMMIT, 0.0, 1.0)
	var steep := clampf(float(slope) / 5.0, 0.0, 1.0)
	var lowland := (1.0 - smoothstep(0.18, 0.42, steep + maxf(h - 0.34, 0.0) * 0.8)) * (1.0 - smoothstep(0.66, 0.86, h))
	if lowland <= 0.0:
		return ground
	# Domain-warp the sample point so blob outlines are organic, not grid-aligned.
	var wx := gx + int((WG._smooth_val(0, gx, gy, PATCH_WARP_SCALE, 8810) - 0.5) * PATCH_WARP_AMP)
	var wy := gy + int((WG._smooth_val(0, gx, gy, PATCH_WARP_SCALE, 8820) - 0.5) * PATCH_WARP_AMP)
	# Coverage mask: only the upper band of a broad field drifts to a patch colour; smoothstep blurs
	# the edge so patches fade in over several tiles (no hard outline).
	var m := WG._smooth_val(0, wx, wy, PATCH_MASK_SCALE, 8830)
	var cover := smoothstep(PATCH_COVER_LO, PATCH_COVER_HI, m)
	if cover <= 0.0:
		return ground
	# Pick which patch colour over a BROAD field so each blob leans a single colour (no speckle).
	var p := WG._smooth_val(0, wx, wy, PATCH_PICK_SCALE, 8840)
	var idx := clampi(int(p * float(patches.size())), 0, patches.size() - 1)
	return ground.lerp(patches[idx], cover * PATCH_STRENGTH * lowland)


## Warm + enrich a terrain tile colour with BROAD low-frequency painterly variation, alpine
## elevation layering, snow shedding on steep faces, path/trail tinting, and the forest-grass
## gradient. (col, tile, gtx, gty, elev, slope, curve) -> final Color.
## NOTE: superseded for the 3D ground by flat_ground (one colour per biome); kept for the 2D map.
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
		# Faint cool mottle so the snow isn't a flat slab — a light blue-grey, never lavender/purple.
		var cool_patch := 0.5 + 0.5 * sin(fx * 0.045 - fz * 0.038 + 0.7)
		return snow.lerp(Color(0.84, 0.88, 0.93), cool_patch * 0.07)
	if is_path(tile):
		# Roads/paths keep their road surface colour at ANY elevation, so a road drawn up a hill
		# reads as a mountain road instead of vanishing into the rock/snow shading.
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
		# Grass stays in ONE coherent light-green family. A broad, soft value gradient between
		# mid-foliage and sunlit grass reads as gentle sun/shade across the meadow; a faint moss
		# highlight adds painterly life. We deliberately do NOT drift toward leaf/forest green
		# here — that band-driven darkening manufactured dark-green "splotches" that looked like
		# stray biomes. Forest depth comes from the biome tint (applied by the mesher), which only
		# darkens where a forest biome actually is, and fades smoothly at its edges.
		var lit := clampf(bright * 0.68 + band2 * 0.32, 0.0, 1.0)
		var grass := PixelPalette.pal("mid_foliage").lerp(PixelPalette.pal("sunlit_grass"), lit)
		grass = grass.lerp(PixelPalette.pal("moss_hi"), warm * 0.10)
		c = c.lerp(grass, 0.85)
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
