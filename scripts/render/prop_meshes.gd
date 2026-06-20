extends RefCounted
## Shared 3D mesh + toon-material library for the 3D pixel-art port. Exposes each
## prop/decor kind as a list of PARTS ({mesh, mat, off, scl}); the renderer batches
## identical parts into per-(mesh,material) MultiMeshInstance3D groups, so hundreds
## of trees/tufts/rocks cost a handful of draw calls. Movers (player/enemies) are
## built as individual nodes via build_node().
##
## Meshes and materials are cached statically and SHARED across every instance.

const TOON := preload("res://shaders/toon_world.gdshader")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const EquipLoadout := preload("res://scripts/render/equip_loadout.gd")

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _shadow_material: StandardMaterial3D = null
static var _shadow_tex_cache: ImageTexture = null
static var _part_cache: Dictionary = {}


# --------------------------------------------------------------- part lists ----

## Static (batchable) parts for a world entity, or [] if it should not be batched
## (movers like enemies, or unmapped kinds rendered by the terrain).
# Soft warm canopy variety (A Short Hike vibe): mostly greens with autumn
# accents. Original colors — not copied from any game.
const CANOPY := [
	Color8(46, 72, 34), Color8(40, 62, 32), Color8(58, 84, 40),    # deep forest greens (weighted)
	Color8(46, 72, 34), Color8(34, 54, 28), Color8(28, 46, 24),
	Color8(70, 90, 40), Color8(150, 96, 52), Color8(54, 78, 36)]    # mostly green, one warm accent

static func entity_parts(e: Node) -> Array:
	match str(e.kind):
		"tree", "landmark_tree":
			var species := TreeArt.classify(str(e.get("label")))
			var th := absi(hash(str(e.get("label")) + str(int(e.position.x)) + "," + str(int(e.position.y))))
			if species == "fir":
				# Conifers split into firs (full cone) and pines (tall, bare trunk).
				return _pine_parts() if (th % 5) < 2 else _conifer_parts()
			if species == "maple":
				return _maple_parts(_maple_mat())
			# Sprinkle occasional warm maples through the generic broadleaf as accents.
			if species == "broadleaf" and th % 6 == 0:
				return _maple_parts(_maple_mat())
			return _tree_parts(_canopy_mat(e))
		"npc":
			# A robed humanoid NPC (Slayer Master etc.) — reuse the figure model with a
			# distinct robe/skin so it reads as a person, not a monster.
			return figure_parts(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a"))
		"rock":
			return _rock_parts()
		"bush", "node":
			return _bush_parts()
		"fish":
			return _fish_parts()
		"house", "building":
			return _house_parts(e)
		"stall":
			return _stall_parts()
		"tent":
			return _tent_parts(e)
		"campfire":
			return _campfire_parts()
		"chest":
			return _chest_parts()
		"sign":
			return _sign_parts()
		"lantern":
			return _city_prop_parts("lantern")
		"anvil":
			return _anvil_parts()
		"altar":
			return _altar_parts(e)
		"obelisk":
			return _obelisk_parts(e)
		"cave", "ladder_down":
			return _cave_parts()
		"ladder_up":
			return _ladder_parts()
		"burrow":
			return _burrow_parts()
		"meteor":
			return _meteor_parts()
		"mammoth":
			return _mammoth_parts()
		"ruin_arch":
			return _ruin_arch_parts()
		"ruin_pillar":
			return _ruin_pillar_parts()
		"broken_wall":
			return _broken_wall_parts()
		"rubble_pile":
			return _rubble_parts()
		"broken_statue":
			return _broken_statue_parts()
		"mountain":
			return _mountain_parts(e)
		"fountain":
			return _fountain_parts()
		"city_wall":
			return _city_wall_parts(int(e.get("variant")))
		"bridge":
			return _bridge_parts()
		"city_prop":
			return _city_prop_parts(str(e.get("prop_kind")))
		"decor":
			# A single ground-clutter model placed as a standalone entity (so the world
			# editor can drop any decor kind — mushroom, fern, reeds, flowers, …). Same
			# meshes the procedural ground scatter uses.
			return decor_parts(str(e.get("prop_kind")))
		_:
			return []


static func is_moving(e: Node) -> bool:
	return str(e.kind) == "enemy"


static func decor_parts(kind: String) -> Array:
	match kind:
		"alpine_pine":
			# Small visual-only pines arrive in deterministic clusters from the
			# elevated decor pass; snow-covered crowns belong on these cold shelves.
			return _hike_conifer_parts(2, true)
		"alpine_boulder":
			return _hike_boulder_parts()
		"flower":
			return [
				_part(_sphere("d_ftuft", 0.16), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.12, 0), Vector3(1.0, 0.7, 1.0)),
				_part(_sphere("d_fhead", 0.1), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.34, 0))]
		"grass":
			# A fan of slender blades in fresh lush green, leaning outward like a real tuft.
			var blade := _mat("moss_hi", "leaf_green", "sunlit_grass")
			return [
				_part(_cone("d_gb0", 0.045, 0.008, 0.44), blade, Vector3(0.0, 0.21, 0.0), Vector3.ONE, Vector3(0.08, 0.0, 0.05)),
				_part(_cone("d_gb1", 0.045, 0.008, 0.37), blade, Vector3(0.09, 0.17, 0.04), Vector3.ONE, Vector3(0.0, 0.0, -0.55)),
				_part(_cone("d_gb2", 0.045, 0.008, 0.35), blade, Vector3(-0.1, 0.16, -0.03), Vector3.ONE, Vector3(0.0, 0.0, 0.6)),
				_part(_cone("d_gb3", 0.04, 0.008, 0.31), blade, Vector3(0.03, 0.15, -0.11), Vector3.ONE, Vector3(0.55, 0.0, 0.08)),
				_part(_cone("d_gb4", 0.04, 0.008, 0.3), blade, Vector3(-0.04, 0.15, 0.1), Vector3.ONE, Vector3(-0.5, 0.0, -0.1))]
		"reed":
			return _reed_parts()
		"fern", "vine":
			return _fern_parts()
		"moss", "lichen":
			return [_part(_sphere("d_moss", 0.2), _mat("foliage_b", "grass_dark", "foliage_c"), Vector3(0, 0.08, 0), Vector3(1.35, 0.35, 1.0))]
		"shrub", "bramble", "shrubbery":
			return [_part(_sphere("d_bush", 0.3), _mat("foliage_b", "grass_dark", "foliage_a"), Vector3(0, 0.22, 0), Vector3(1.1, 0.8, 1.1))]
		"mushroom":
			return [
				_part(_cyl("d_mstalk", 0.05, 0.07, 0.22), _mat("snow_a", "stone_b", "snow_a"), Vector3(0, 0.11, 0)),
				_part(_sphere("d_mcap", 0.14), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 0.26, 0), Vector3(1.0, 0.6, 1.0))]
		"cactus":
			return [_part(_cone("d_cact", 0.16, 0.12, 0.6), _mat("fir_a", "fir_b", "foliage_c"), Vector3(0, 0.3, 0))]
		# Biome canopy species — full-size ambient forest trees, batched like any decor.
		"canopy_fir", "canopy_spruce":
			return _conifer_parts()
		"canopy_snow_fir", "canopy_snow_spruce":
			return _snowy_conifer_parts()
		"canopy_pine":
			return _pine_parts()
		"canopy_maple":
			return _maple_parts(_maple_mat())
		"canopy_broadleaf", "canopy_oak":
			return _tree_parts(_foliage_mat(PixelPalette.pal("mid_foliage")))
		"canopy_birch":
			return _tree_parts(_mat("leaf_gold", "forest_green", "snow_a"))
		"canopy_palm":
			return _palm_parts()
		"canopy_saguaro":
			return _saguaro_parts()
		"canopy_deadtree":
			return _deadtree_parts()
		"canopy_acacia":
			return _acacia_parts()
		"pebble", "rubble", "shell", "stone":
			return [_part(_sphere("d_peb", 0.16), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.06, 0), Vector3(1.3, 0.55, 1.1))]
		"stick", "driftwood", "bone":
			return [_part(_box("d_stick", Vector3(0.5, 0.07, 0.09)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.05, 0))]
		_:  # grass, fern, reed, vine, moss, lichen, ... -> green tuft
			return [_part(_sphere("d_tuft", 0.22), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.16, 0), Vector3(1.0, 0.7, 1.0))]


static func water_decor_parts(kind: String) -> Array:
	match kind:
		"fish_school":
			return [
				_part(_sphere("w_fish0", 0.08), _mat("water_spark", "water_b", "snow_a"), Vector3(-0.18, 0.02, 0.0), Vector3(1.6, 0.45, 0.75)),
				_part(_sphere("w_fish1", 0.07), _mat("water_spark", "water_b", "snow_a"), Vector3(0.12, 0.02, 0.1), Vector3(1.4, 0.4, 0.7)),
				_part(_sphere("w_ripple", 0.22), _mat("water_spark", "water_c", "snow_a"), Vector3(0, 0.0, 0), Vector3(1.4, 0.08, 0.75))]
		_: # lily / fallback
			return [
				_part(_sphere("w_lily", 0.18), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.02, 0), Vector3(1.4, 0.08, 1.0)),
				_part(_sphere("w_lily_flower", 0.06), _mat("snow_a", "water_b", "gold"), Vector3(0.08, 0.08, 0.02), Vector3(1.0, 0.55, 1.0))]


## Visual-only hiking-diorama dressing parts. These are original Imota meshes
## tuned toward the readable cozy low-poly language, not copied reference assets.
static func dressing_parts(kind: String, variant := 0) -> Array:
	var ck := "dress:%s:%d" % [kind, int(variant) % 16]
	if _part_cache.has(ck):
		return _part_cache[ck]
	var parts: Array = []
	match kind:
		"hike_path":
			parts = _hike_path_parts()
		"hike_cabin":
			parts = _hike_cabin_parts()
		"hike_lodge":
			parts = _hike_lodge_parts()
		"hike_conifer":
			# Replace the old dressing conifer with the real fir/pine models (mixed).
			parts = _pine_parts() if variant % 2 == 0 else _conifer_parts()
		"hike_deciduous":
			# A few camp broadleaves become warm maple accents; the rest stay green.
			parts = _maple_parts(_maple_mat()) if variant % 4 == 0 else _hike_deciduous_parts(variant)
		"hike_fence":
			parts = _hike_fence_parts()
		"hike_cliff":
			parts = _hike_cliff_parts()
		"hike_boulder":
			parts = _hike_boulder_parts()
		"hike_pool":
			parts = _hike_pool_parts()
		"hike_campfire":
			parts = _hike_campfire_parts()
		"hike_sign":
			parts = _hike_sign_parts()
		"hike_flower":
			parts = _hike_flower_parts(variant)
		"hike_log":
			parts = _hike_log_parts()
		"hike_bench":
			parts = _hike_bench_parts()
		"hike_stump":
			parts = _hike_stump_parts()
		"hike_grass":
			parts = _hike_grass_parts(variant)
		"hike_leaf_litter":
			parts = _hike_leaf_litter_parts(variant)
		"hike_mushroom":
			parts = _hike_mushroom_parts(variant)
		"hike_pebbles":
			parts = _hike_pebble_parts()
		_:
			parts = []
	_part_cache[ck] = parts
	return parts


static func warm_static_caches() -> void:
	for kind: String in [
		"hike_path", "hike_cabin", "hike_lodge", "hike_conifer",
		"hike_deciduous", "hike_fence", "hike_cliff", "hike_boulder",
		"hike_pool", "hike_campfire", "hike_sign", "hike_flower",
		"hike_log", "hike_bench", "hike_stump", "hike_grass",
		"hike_leaf_litter", "hike_mushroom", "hike_pebbles"]:
		for variant: int in range(4):
			dressing_parts(kind, variant)


static func _canopy_mat(e: Node) -> ShaderMaterial:
	var h := absi(hash(str(e.get("label")) + str(int(e.position.x)) + "," + str(int(e.position.y))))
	var col: Color = CANOPY[h % CANOPY.size()]
	return _foliage_mat(col)


## A foliage material (toon bands derived from one canopy color) with wind on.
static func _foliage_mat(base: Color) -> ShaderMaterial:
	var ck := "fol|%s" % base
	if not _mat_cache.has(ck):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("shadow_color", base.darkened(0.34))
		m.set_shader_parameter("light_color", base.lightened(0.2))
		m.set_shader_parameter("wind", 0.11)
		_mat_cache[ck] = m
	return _mat_cache[ck]


static func _tree_parts(leaf: ShaderMaterial) -> Array:
	# Fuller, rounder canopy (A Short Hike-ish): a big central mass + side lobes;
	# the toon bands do the soft shading and the per-tree color adds variety.
	return [
		_shadow_part(1.05),
		_part(_cyl("trunk", 0.16, 0.26, 1.5), _mat("bark_brown", "dark_bark", "olive_wood"), Vector3(0, 0.75, 0)),
		_part(_sphere("can_main", 1.35), leaf, Vector3(0, 2.05, 0), Vector3(1.05, 0.9, 1.05)),
		_part(_sphere("can_l", 0.95), leaf, Vector3(-0.78, 1.85, 0.32), Vector3(1, 0.85, 1)),
		_part(_sphere("can_r", 0.9), leaf, Vector3(0.8, 1.9, -0.24), Vector3(1, 0.85, 1)),
		_part(_sphere("can_f", 0.85), leaf, Vector3(0.1, 1.8, 0.7), Vector3(1, 0.85, 1)),
		_part(_sphere("can_top", 1.0), leaf, Vector3(0.05, 2.75, -0.05), Vector3(1, 0.85, 1)),
		_part(_cyl("sap_trunk", 0.07, 0.1, 0.72), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(-1.05, 0.36, -0.48)),
		_part(_sphere("sap_leaf", 0.48), leaf, Vector3(-1.05, 0.92, -0.48), Vector3(1.0, 0.82, 1.0)),
		_part(_sphere("tree_under", 0.38), leaf, Vector3(0.92, 0.38, 0.56), Vector3(1.35, 0.42, 1.0))]


static func _conifer_parts() -> Array:
	# Four full bell-shaped bough tiers: pinched neck, curved flare, drooping rim.
	# The brighter moss ramp keeps the tiers readable without leaving the shared palette.
	return _conifer_parts_with_material(_mat("mid_foliage", "forest_teal", "moss_hi"))


static func _conifer_parts_with_material(needles: Material) -> Array:
	var bark := _mat("trunk_a", "trunk_b", "wood_light")
	# Soft "puffy" conifer — NO cone/tier geometry at all. A tall, pointed column of
	# overlapping rounded foliage clumps (like the round broadleaf trees, but spruce
	# shaped): a tapering central spine of spheres + a few low skirt lobes, each nudged
	# off-axis so the silhouette is bumpy and organic, not a smooth cone.
	var p: Array = [
		_shadow_part(1.0),
		_part(_cyl("fir_trunk", 0.13, 0.22, 1.1), bark, Vector3(0, 0.5, 0))]
	# central spine: clumps shrinking from a broad base to a small crown tip
	var spine: Array = [
		[1.18, 1.26], [1.60, 1.18], [2.00, 1.07], [2.38, 0.96],
		[2.74, 0.84], [3.08, 0.72], [3.40, 0.60], [3.70, 0.49],
		[3.98, 0.38], [4.24, 0.28], [4.48, 0.18]]
	for i: int in spine.size():
		var s: Array = spine[i]
		var jx: float = 0.08 if i % 2 == 0 else -0.08
		var jz: float = -0.06 if i % 3 == 0 else 0.06
		p.append(_part(_sphere("fir_clump%d" % i, float(s[1])), needles, Vector3(jx, float(s[0]), jz), Vector3(1.0, 0.95, 1.0)))
	# a fuller, slightly flattened skirt of low side clumps around the base
	var skirt: Array = [
		Vector3(0.74, 1.16, 0.12), Vector3(-0.72, 1.24, -0.14),
		Vector3(0.2, 1.1, 0.74), Vector3(-0.22, 1.18, -0.72)]
	for i: int in skirt.size():
		p.append(_part(_sphere("fir_skirt%d" % i, 0.62), needles, skirt[i], Vector3(1.06, 0.78, 1.06)))
	return p


## Snow-region fir: off-white faceted branch tiers with a tight cool shadow
## ramp, matching the fully snow-loaded silhouettes in the reference.
static func _snowy_conifer_parts() -> Array:
	var snow_base := PixelPalette.pal("snow_a")
	var snow := _mat_from(snow_base, snow_base.darkened(0.12), snow_base.lightened(0.08))
	return _conifer_parts_with_material(snow)


## Pine: the treeline's TALL one — a long bare trunk lifting a slender clustered crown.
## Same soft "puffy" clumped foliage as the fir, but narrower and elongated and raised
## on a bare stem, so it stays distinct (tall slim pine vs full broad fir).
static func _pine_parts() -> Array:
	var needle := _mat("pine_dark", "forest_teal", "pine_mid")
	var bark := _mat("trunk_a", "trunk_b", "bark_brown")
	var p: Array = [
		_shadow_part(0.66),
		_part(_cyl("pine_trunk", 0.13, 0.22, 3.0), bark, Vector3(0, 1.5, 0))]
	# Slender crown spine of overlapping clumps, high up, tapering to a point.
	var spine: Array = [
		[2.55, 0.96], [2.96, 0.92], [3.34, 0.84], [3.68, 0.74],
		[3.99, 0.63], [4.27, 0.52], [4.53, 0.41], [4.77, 0.30],
		[4.98, 0.20], [5.16, 0.12]]
	for i: int in spine.size():
		var s: Array = spine[i]
		var jx: float = 0.07 if i % 2 == 0 else -0.07
		var jz: float = -0.05 if i % 3 == 0 else 0.05
		p.append(_part(_sphere("pine_clump%d" % i, float(s[1])), needle, Vector3(jx, float(s[0]), jz), Vector3(1.0, 0.96, 1.0)))
	# A small collar of clumps where the crown meets the bare trunk.
	var collar: Array = [Vector3(0.6, 2.5, 0.08), Vector3(-0.58, 2.58, -0.1), Vector3(0.1, 2.46, 0.6)]
	for i: int in collar.size():
		p.append(_part(_sphere("pine_collar%d" % i, 0.5), needle, collar[i], Vector3(1.05, 0.82, 1.05)))
	return p


## Maple: a broad, slightly flattened dome on a stout trunk — warm autumnal
## foliage so it reads as a cozy accent among the dark firs/pines.
static func _maple_parts(leaf: ShaderMaterial) -> Array:
	var bark := _mat("bark_brown", "dark_bark", "trunk_a")
	return [
		_shadow_part(1.15),
		_part(_cyl("maple_trunk", 0.18, 0.3, 1.45), bark, Vector3(0, 0.72, 0)),
		_part(_sphere("maple_dome", 1.5), leaf, Vector3(0, 1.95, 0), Vector3(1.3, 0.74, 1.3)),
		_part(_sphere("maple_l", 1.02), leaf, Vector3(-0.96, 1.66, 0.22), Vector3(1.1, 0.7, 1.1)),
		_part(_sphere("maple_r", 1.0), leaf, Vector3(0.96, 1.72, -0.2), Vector3(1.1, 0.7, 1.1)),
		_part(_sphere("maple_top", 0.92), leaf, Vector3(0.04, 2.46, -0.02), Vector3(1.1, 0.82, 1.1)),
		_part(_sphere("maple_under", 0.52), leaf, Vector3(0.62, 0.66, 0.5), Vector3(1.3, 0.4, 1.0))]


## Warm russet/gold canopy for maples (the cozy warm pop in the dark forest).
static func _maple_mat() -> ShaderMaterial:
	return _mat("leaf_orange", "leaf_red", "leaf_gold")


# ---- biome canopy species (ambient forest trees, placed as batched decor) ----

## Desert/jungle palm: a slim trunk topped with a crown of radiating fronds + a coconut.
static func _palm_parts() -> Array:
	var trunk := _mat("trunk_a", "trunk_b", "bark_brown")
	var frond := _mat("fir_a", "fir_b", "leaf_green")
	var out: Array = [
		_shadow_part(0.72),
		_part(_cyl("palm_t0", 0.14, 0.2, 1.7), trunk, Vector3(0, 0.85, 0)),
		_part(_cyl("palm_t1", 0.1, 0.14, 1.6), trunk, Vector3(0.16, 2.4, 0))]
	for i: int in 6:
		var a: float = float(i) / 6.0 * TAU
		out.append(_part(_cone("palm_fr", 0.16, 0.01, 1.5), frond,
			Vector3(0.16 + cos(a) * 0.42, 3.05, sin(a) * 0.42), Vector3.ONE, Vector3(1.15, -a, 0)))
	out.append(_part(_sphere("palm_co", 0.12), trunk, Vector3(0.16, 3.1, 0)))
	return out


## Saguaro cactus: a tall ribbed green column with a pair of upturned arms.
static func _saguaro_parts() -> Array:
	var green := _mat("forest_green", "pine_dark", "leaf_green")
	return [
		_shadow_part(0.5),
		_part(_cyl("sag_body", 0.24, 0.3, 2.6), green, Vector3(0, 1.3, 0)),
		_part(_sphere("sag_top", 0.26), green, Vector3(0, 2.6, 0)),
		_part(_cyl("sag_arm_l", 0.13, 0.16, 0.9), green, Vector3(-0.42, 1.5, 0), Vector3.ONE, Vector3(0, 0, 0.5)),
		_part(_cyl("sag_arm_lv", 0.12, 0.14, 0.7), green, Vector3(-0.6, 2.0, 0)),
		_part(_cyl("sag_arm_r", 0.13, 0.16, 0.8), green, Vector3(0.4, 1.7, 0), Vector3.ONE, Vector3(0, 0, -0.5)),
		_part(_cyl("sag_arm_rv", 0.12, 0.14, 0.6), green, Vector3(0.56, 2.15, 0))]


## Bare dead tree: a pale forked trunk and a few leafless branches (swamp/badlands/volcanic).
static func _deadtree_parts() -> Array:
	var wood := _mat("trunk_b", "dark_bark", "stone_a")
	return [
		_shadow_part(0.7),
		_part(_cyl("dead_trunk", 0.12, 0.22, 2.2), wood, Vector3(0, 1.1, 0)),
		_part(_cone("dead_b0", 0.06, 0.01, 1.1), wood, Vector3(-0.4, 2.0, 0.1), Vector3.ONE, Vector3(0, 0, 0.7)),
		_part(_cone("dead_b1", 0.06, 0.01, 1.0), wood, Vector3(0.42, 2.1, -0.1), Vector3.ONE, Vector3(0, 0, -0.6)),
		_part(_cone("dead_b2", 0.05, 0.01, 0.9), wood, Vector3(0.05, 2.5, 0.2), Vector3.ONE, Vector3(0.5, 0, 0.1))]


## Savanna acacia: a bare trunk under a wide, flat umbrella canopy.
static func _acacia_parts() -> Array:
	var bark := _mat("bark_brown", "dark_bark", "trunk_a")
	var leaf := _mat("fir_b", "pine_dark", "leaf_gold")
	return [
		_shadow_part(1.3),
		_part(_cyl("aca_trunk", 0.16, 0.26, 1.9), bark, Vector3(0, 0.95, 0)),
		_part(_sphere("aca_can", 1.7), leaf, Vector3(0, 2.3, 0), Vector3(1.5, 0.34, 1.5)),
		_part(_sphere("aca_can2", 1.2), leaf, Vector3(0.5, 2.5, 0.2), Vector3(1.3, 0.3, 1.3))]


static func _bush_parts() -> Array:
	var leaf := _foliage_mat(PixelPalette.pal("mid_foliage"))
	return [
		_part(_sphere("bush_m", 0.55), leaf, Vector3(0, 0.4, 0), Vector3(1.1, 0.85, 1.1)),
		_part(_sphere("bush_l", 0.38), leaf, Vector3(-0.4, 0.32, 0.12), Vector3(1.1, 0.8, 1.1)),
		_part(_sphere("bush_r", 0.36), leaf, Vector3(0.4, 0.3, -0.1), Vector3(1.1, 0.8, 1.1))]


static func _rock_parts() -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	return [
		_part(_octa("rock_big"), stone, Vector3(0, 0.34, 0), Vector3(0.95, 0.72, 1.05)),
		_part(_octa("rock_chip_a"), stone, Vector3(-0.42, 0.16, 0.18), Vector3(0.38, 0.32, 0.42)),
		_part(_octa("rock_chip_b"), stone, Vector3(0.42, 0.12, -0.24), Vector3(0.32, 0.26, 0.36))]


## A half-timbered medieval cottage: stone footing, cream plaster walls crossed by
## dark timber framing (corner posts, a mid rail, diagonal braces), a steep
## overhanging roof, a stone-and-brick chimney, a plank door and shuttered windows.
static func _house_parts(e: Node) -> Array:
	var ss := 1.0
	if str(e.kind) == "building":
		ss = clampf(float(e.get("display_size")) / 6.0, 0.85, 1.7)
	var roof: Color = e.get("roof_color")
	var roof_col: Color = roof.lerp(Color(0.34, 0.27, 0.2), 0.55)   # medieval thatch/shingle
	var roof_mat := _mat_from(roof_col, roof_col.darkened(0.4), roof_col.lightened(0.2))
	var plaster := _mat_from(Color(0.91, 0.86, 0.74), Color(0.71, 0.65, 0.53), Color(0.97, 0.94, 0.85))
	var timber := _mat("dark_bark", "trunk_b", "trunk_a")
	var stone := _mat("stone_a", "stone_b", "warm_stone")
	var window := _mat("water_b", "slate_blue", "water_foam")
	var brick := _mat_from(Color(0.5, 0.28, 0.22), Color(0.34, 0.18, 0.14), Color(0.62, 0.38, 0.3))
	var hx := 1.28 * ss
	var hz := 0.98 * ss
	var parts: Array = [
		_shadow_part(1.7 * ss, 1.15),
		_part(_box("med_found", Vector3(2.9, 0.32, 2.3)), stone, Vector3(0, 0.16, 0), Vector3(ss, 1.0, ss)),
		_part(_box("med_wall", Vector3(2.55, 1.45, 1.96)), plaster, Vector3(0, 1.05, 0), Vector3(ss, 1.0, ss)),
		_part(_box("med_rail", Vector3(2.62, 0.13, 2.02)), timber, Vector3(0, 1.05, 0), Vector3(ss, 1.0, ss))]
	# Corner posts of the timber frame.
	for cx: int in [-1, 1]:
		for cz: int in [-1, 1]:
			parts.append(_part(_box("med_post", Vector3(0.17, 1.55, 0.17)), timber, Vector3(hx * cx, 1.05, hz * cz)))
	# Diagonal braces on the front face.
	parts.append(_part(_box("med_brace", Vector3(0.12, 1.05, 0.1)), timber, Vector3(-0.5 * ss, 1.05, hz), Vector3.ONE, Vector3(0, 0, 0.5)))
	parts.append(_part(_box("med_brace", Vector3(0.12, 1.05, 0.1)), timber, Vector3(0.5 * ss, 1.05, hz), Vector3.ONE, Vector3(0, 0, -0.5)))
	# Steep, overhanging roof + ridge beam.
	parts.append(_part(_prism("med_roof", Vector3(3.5, 1.65, 3.1)), roof_mat, Vector3(0, 2.35, 0), Vector3(ss, 1.0, ss)))
	parts.append(_part(_box("med_ridge", Vector3(0.16, 0.16, 3.15)), timber, Vector3(0, 3.15, 0), Vector3(ss, 1.0, ss)))
	# Stone chimney with a brick crown.
	parts.append(_part(_box("med_chim", Vector3(0.44, 1.4, 0.44)), stone, Vector3(0.82 * ss, 2.7, -0.45 * ss)))
	parts.append(_part(_box("med_chim_top", Vector3(0.52, 0.22, 0.52)), brick, Vector3(0.82 * ss, 3.42, -0.45 * ss)))
	# Plank door + frame.
	parts.append(_part(_box("med_door", Vector3(0.62, 0.98, 0.12)), timber, Vector3(0, 0.56, hz + 0.05)))
	parts.append(_part(_box("med_door_arch", Vector3(0.72, 0.12, 0.1)), stone, Vector3(0, 1.06, hz + 0.04)))
	# Shuttered windows (timber frame behind, glass in front), front + side.
	for wx: int in [-1, 1]:
		parts.append(_part(_box("med_winf", Vector3(0.52, 0.5, 0.06)), timber, Vector3(0.78 * ss * wx, 1.12, hz + 0.02)))
		parts.append(_part(_box("med_win", Vector3(0.42, 0.4, 0.1)), window, Vector3(0.78 * ss * wx, 1.12, hz + 0.05)))
	return parts


static func _tent_parts(e: Node) -> Array:
	var cloth: Color = e.get("tent_color")
	var cloth_mat := _mat_from(cloth, cloth.darkened(0.36), cloth.lightened(0.22))
	return [
		_part(_prism("tent", Vector3(1.9, 1.22, 1.75)), cloth_mat, Vector3(0, 0.62, 0), Vector3(1.0, 0.94, 1.0)),
		_part(_box("tent_door", Vector3(0.48, 0.62, 0.08)), _mat("outfit_b", "shadow", "outfit_a"), Vector3(-0.36, 0.34, 0.9)),
		_part(_cyl("tent_pole", 0.035, 0.045, 1.25), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0.78, 0.62, 0.0), Vector3(1, 1, 1))]


static func _stall_parts() -> Array:
	return [
		_part(_box("stall_table", Vector3(1.8, 0.34, 0.9)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.42, 0)),
		_part(_prism("stall_awning", Vector3(2.1, 0.55, 1.05)), _mat("outfit_a", "outfit_b", "water_foam"), Vector3(0, 1.0, 0)),
		_part(_box("stall_post", Vector3(0.08, 0.85, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(-0.78, 0.55, 0.36)),
		_part(_box("stall_post", Vector3(0.08, 0.85, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0.78, 0.55, 0.36))]


## Public accessor for the campfire model (reused by the firemaking fire effect).
static func campfire_parts() -> Array:
	return _campfire_parts()


static func _campfire_parts() -> Array:
	return [
		_part(_sphere("fire_coals", 0.24), _mat("trunk_b", "shadow", "dirt_a"), Vector3(0, 0.08, 0), Vector3(1.2, 0.35, 1.0)),
		_part(_cone("fire_flame_a", 0.24, 0.02, 0.55), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.38, 0)),
		_part(_cone("fire_flame_b", 0.16, 0.02, 0.42), _mat("dirt_a", "trunk_b", "gold"), Vector3(0.08, 0.42, 0.03))]


static func _chest_parts() -> Array:
	return [
		_part(_box("chest_base", Vector3(1.0, 0.48, 0.72)), _mat("trunk_a", "trunk_b", "gold"), Vector3(0, 0.24, 0)),
		_part(_prism("chest_lid", Vector3(1.04, 0.34, 0.76)), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 0.58, 0)),
		_part(_box("chest_lock", Vector3(0.16, 0.16, 0.08)), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.38, 0.39))]


static func _sign_parts() -> Array:
	return [
		_part(_cyl("sign_post", 0.05, 0.06, 0.9), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.45, 0)),
		_part(_box("sign_board", Vector3(0.9, 0.42, 0.08)), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 0.88, 0.03))]


static func _anvil_parts() -> Array:
	return [
		_part(_box("anvil_base", Vector3(0.58, 0.26, 0.5)), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 0.18, 0)),
		_part(_box("anvil_top", Vector3(1.05, 0.24, 0.42)), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.44, 0)),
		_part(_cone("anvil_horn", 0.22, 0.04, 0.5), _mat("stone_a", "stone_b", "ore"), Vector3(0.56, 0.44, 0), Vector3(0.7, 0.7, 0.7))]


static func _altar_parts(e: Node) -> Array:
	var glow: Color = e.get("glow_color")
	return [
		_part(_box("altar_base", Vector3(1.15, 0.35, 0.9)), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.18, 0)),
		_part(_box("altar_top", Vector3(0.9, 0.35, 0.7)), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 0.52, 0)),
		_part(_sphere("altar_glow", 0.2), _mat_from(glow, glow.darkened(0.3), glow.lightened(0.35)), Vector3(0, 0.88, 0), Vector3(1.0, 0.55, 1.0))]


static func _obelisk_parts(e: Node) -> Array:
	var light := PixelPalette.pal("water_foam") if bool(e.get("attuned")) else PixelPalette.pal("stone_a")
	return [
		_part(_box("obelisk_plinth", Vector3(0.82, 0.25, 0.82)), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.13, 0)),
		_part(_cone("obelisk_shaft", 0.36, 0.18, 2.25), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 1.26, 0)),
		_part(_sphere("obelisk_core", 0.14), _mat_from(light, light.darkened(0.35), light.lightened(0.3)), Vector3(0, 1.65, 0.26), Vector3(1.0, 0.55, 1.0))]


static func _cave_parts() -> Array:
	return [
		_part(_sphere("cave_rock_l", 0.55), _mat("stone_b", "shadow", "stone_a"), Vector3(-0.28, 0.32, 0), Vector3(1.1, 0.8, 0.9)),
		_part(_sphere("cave_rock_r", 0.46), _mat("stone_a", "stone_b", "ore"), Vector3(0.32, 0.26, 0.04), Vector3(1.0, 0.72, 0.86)),
		_part(_box("cave_mouth", Vector3(0.72, 0.5, 0.08)), _mat("outfit_b", "shadow", "stone_b"), Vector3(0.03, 0.22, 0.44))]


static func _ladder_parts() -> Array:
	return [
		_part(_box("ladder_rail", Vector3(0.06, 0.08, 0.9)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(-0.18, 0.04, 0)),
		_part(_box("ladder_rail", Vector3(0.06, 0.08, 0.9)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0.18, 0.04, 0)),
		_part(_box("ladder_rung", Vector3(0.5, 0.07, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.08, -0.26)),
		_part(_box("ladder_rung", Vector3(0.5, 0.07, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.08, 0.24))]


static func _burrow_parts() -> Array:
	return [
		_part(_sphere("burrow_mound", 0.55), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 0.13, 0), Vector3(1.25, 0.32, 0.9)),
		_part(_box("burrow_hole", Vector3(0.58, 0.22, 0.08)), _mat("outfit_b", "shadow", "trunk_b"), Vector3(0.0, 0.1, 0.42))]


static func _meteor_parts() -> Array:
	return [_part(_octa("meteor"), _mat("ore", "stone_b", "snow_a"), Vector3(0, 0.18, 0), Vector3(0.65, 0.42, 0.8))]


static func _mammoth_parts() -> Array:
	return [
		_part(_sphere("mammoth_body", 0.65), _mat("dirt_b", "trunk_b", "dirt_a"), Vector3(0, 0.72, 0), Vector3(1.45, 0.88, 0.85)),
		_part(_sphere("mammoth_head", 0.36), _mat("dirt_a", "trunk_b", "gold"), Vector3(0.82, 0.74, 0.05), Vector3(1.0, 0.85, 0.85)),
		_part(_cone("mammoth_tusk", 0.08, 0.01, 0.42), _mat("snow_a", "stone_b", "snow_a"), Vector3(1.1, 0.52, -0.18), Vector3(0.7, 0.7, 0.7)),
		_part(_cone("mammoth_tusk", 0.08, 0.01, 0.42), _mat("snow_a", "stone_b", "snow_a"), Vector3(1.1, 0.52, 0.22), Vector3(0.7, 0.7, 0.7))]


static func _ruin_arch_parts() -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	return [
		_part(_box("ruin_leg", Vector3(0.32, 1.55, 0.34)), stone, Vector3(-0.52, 0.78, 0)),
		_part(_box("ruin_leg", Vector3(0.32, 1.35, 0.34)), stone, Vector3(0.52, 0.68, 0)),
		_part(_box("ruin_cap", Vector3(1.38, 0.32, 0.36)), stone, Vector3(0, 1.52, 0))]


static func _ruin_pillar_parts() -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	return [
		_part(_box("pillar_base", Vector3(0.52, 0.22, 0.52)), stone, Vector3(0, 0.11, 0)),
		_part(_cyl("pillar_shaft", 0.18, 0.22, 1.35), stone, Vector3(0, 0.78, 0)),
		_part(_box("pillar_cap", Vector3(0.45, 0.18, 0.45)), stone, Vector3(0.08, 1.52, 0.02))]


static func _broken_wall_parts() -> Array:
	return [
		_part(_box("wall_low", Vector3(1.45, 0.46, 0.36)), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.23, 0)),
		_part(_box("wall_chunk", Vector3(0.48, 0.28, 0.34)), _mat("stone_b", "shadow", "stone_a"), Vector3(-0.38, 0.6, 0))]


static func _rubble_parts() -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	return [
		_part(_octa("rubble_a"), stone, Vector3(-0.22, 0.08, 0.06), Vector3(0.26, 0.18, 0.24)),
		_part(_octa("rubble_b"), stone, Vector3(0.14, 0.1, -0.1), Vector3(0.32, 0.22, 0.28)),
		_part(_octa("rubble_c"), stone, Vector3(0.36, 0.06, 0.18), Vector3(0.22, 0.16, 0.2))]


static func _broken_statue_parts() -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	return [
		_part(_box("statue_base", Vector3(0.62, 0.22, 0.52)), stone, Vector3(0, 0.11, 0)),
		_part(_capsule("statue_body", 0.22, 0.92), stone, Vector3(0, 0.68, 0)),
		_part(_sphere("statue_head", 0.16), stone, Vector3(0.08, 1.2, 0.02), Vector3(1.0, 0.7, 1.0))]


static func _mountain_parts(e: Node) -> Array:
	var snow: float = float(e.get("mountain_snow"))
	var s := clampf(float(e.get("display_size")) / 3.0, 0.8, 2.0)
	return [
		_part(_cone("mountain_mass", 1.5, 0.25, 2.15), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 1.08, 0), Vector3(s, 1.0, s)),
		_part(_cone("mountain_snow", 0.58, 0.08, 0.72), _mat("snow_a", "stone_a", "snow_a"), Vector3(0, 2.12, 0), Vector3(s * maxf(snow, 0.18), 1.0, s * maxf(snow, 0.18)))]


static func _fountain_parts() -> Array:
	return [
		_part(_cyl("fountain_basin", 0.66, 0.78, 0.22), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.11, 0)),
		_part(_cyl("fountain_core", 0.24, 0.32, 0.5), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 0.42, 0)),
		_part(_sphere("fountain_water", 0.46), _mat("water_a", "water_b", "water_foam"), Vector3(0, 0.32, 0), Vector3(1.0, 0.14, 1.0))]


static func _city_wall_parts(piece: int) -> Array:
	var stone := _mat("stone_a", "stone_b", "ore")
	if piece == 1:
		return [
			_part(_box("gate_tower", Vector3(0.52, 1.45, 0.62)), stone, Vector3(-0.58, 0.72, 0)),
			_part(_box("gate_tower", Vector3(0.52, 1.45, 0.62)), stone, Vector3(0.58, 0.72, 0)),
			_part(_box("gate_beam", Vector3(1.45, 0.28, 0.4)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.8, 0.06))]
	if piece == 2:
		return [
			_part(_cyl("wall_tower", 0.48, 0.58, 1.55), stone, Vector3(0, 0.78, 0)),
			_part(_cone("wall_roof", 0.64, 0.1, 0.62), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 1.72, 0))]
	return [
		_part(_box("city_wall", Vector3(1.65, 0.82, 0.48)), stone, Vector3(0, 0.42, 0)),
		_part(_box("city_wall_cap", Vector3(1.8, 0.18, 0.55)), stone, Vector3(0, 0.9, 0))]


static func _bridge_parts() -> Array:
	return [
		_part(_box("bridge_deck", Vector3(1.7, 0.16, 0.85)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.08, 0)),
		_part(_box("bridge_rail", Vector3(1.75, 0.14, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.32, -0.44)),
		_part(_box("bridge_rail", Vector3(1.75, 0.14, 0.08)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.32, 0.44))]


static func _city_prop_parts(prop: String) -> Array:
	match prop:
		"lamp", "lantern":
			return [
				_part(_cyl("lamp_post", 0.045, 0.055, 1.15), _mat("trunk_b", "shadow", "stone_b"), Vector3(0, 0.58, 0)),
				_part(_sphere("lamp_glow", 0.16), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 1.22, 0), Vector3(1.0, 0.8, 1.0))]
		"well":
			return [
				_part(_cyl("well_ring", 0.62, 0.72, 0.34), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.17, 0)),
				_part(_prism("well_roof", Vector3(1.35, 0.46, 1.1)), _mat("dirt_a", "trunk_b", "gold"), Vector3(0, 1.04, 0))]
		"barrel":
			return [_part(_cyl("barrel", 0.3, 0.34, 0.72), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.36, 0))]
		"cart":
			return [
				_part(_box("cart_body", Vector3(1.1, 0.38, 0.72)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.34, 0)),
				_part(_cyl("cart_wheel", 0.16, 0.16, 0.08), _mat("trunk_b", "shadow", "dirt_a"), Vector3(-0.46, 0.16, 0.4)),
				_part(_cyl("cart_wheel", 0.16, 0.16, 0.08), _mat("trunk_b", "shadow", "dirt_a"), Vector3(0.46, 0.16, 0.4))]
		"hay":
			return [_part(_sphere("hay", 0.42), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.22, 0), Vector3(1.25, 0.55, 0.85))]
		"flowerbox":
			return [
				_part(_box("flowerbox", Vector3(0.92, 0.22, 0.32)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.11, 0)),
				_part(_sphere("flowerbox_bloom", 0.11), _mat("gold", "dirt_a", "snow_a"), Vector3(-0.24, 0.28, 0)),
				_part(_sphere("flowerbox_bloom", 0.11), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0.2, 0.27, 0.02))]
		_: # crate fallback
			return [_part(_box("crate", Vector3(0.62, 0.62, 0.62)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.31, 0))]


static func _hike_path_parts() -> Array:
	return [
		_part(_sphere("hike_path_blob", 0.72), _mat("path_orange", "dirt_b", "path_light"), Vector3(0, 0.035, 0), Vector3(1.75, 0.055, 1.05)),
		_part(_sphere("hike_path_warm_edge", 0.42), _mat("path_light", "path_orange", "gold"), Vector3(-0.48, 0.04, 0.2), Vector3(1.15, 0.035, 0.75))]


static func _hike_cabin_parts() -> Array:
	var wall := _mat("cabin_wall", "cabin_shadow", "cabin_trim")
	var roof := _mat("cabin_roof", "roof_shadow", "path_light")
	var wood := _mat("wood_light", "trunk_b", "path_light")
	var dark := _mat("outfit_b", "shadow", "stone_b")
	return [
		_part(_box("hike_cabin_found", Vector3(3.35, 0.22, 2.5)), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(0, 0.11, 0)),
		_part(_box("hike_cabin_body", Vector3(3.0, 1.75, 2.18)), wall, Vector3(0, 1.0, 0)),
		_part(_prism("hike_cabin_roof", Vector3(3.85, 1.18, 2.85)), roof, Vector3(0.0, 2.18, 0.0)),
		_part(_box("hike_cabin_roof_rib", Vector3(0.08, 0.055, 2.72)), _mat("path_light", "roof_shadow", "cabin_roof"), Vector3(-1.08, 2.52, 0.0)),
		_part(_box("hike_cabin_roof_rib", Vector3(0.08, 0.055, 2.72)), _mat("path_light", "roof_shadow", "cabin_roof"), Vector3(-0.36, 2.52, 0.0)),
		_part(_box("hike_cabin_roof_rib", Vector3(0.08, 0.055, 2.72)), _mat("path_light", "roof_shadow", "cabin_roof"), Vector3(0.36, 2.52, 0.0)),
		_part(_box("hike_cabin_roof_rib", Vector3(0.08, 0.055, 2.72)), _mat("path_light", "roof_shadow", "cabin_roof"), Vector3(1.08, 2.52, 0.0)),
		_part(_box("hike_cabin_front", Vector3(3.12, 0.24, 0.18)), _mat("cabin_shadow", "trunk_b", "cabin_wall"), Vector3(0, 1.12, 1.16)),
		_part(_box("hike_cabin_porch", Vector3(2.52, 0.18, 1.2)), wood, Vector3(-0.18, 0.28, 1.62)),
		_part(_box("hike_cabin_step0", Vector3(2.1, 0.16, 0.48)), wood, Vector3(-0.18, 0.16, 2.16)),
		_part(_box("hike_cabin_step1", Vector3(1.65, 0.14, 0.42)), wood, Vector3(-0.18, 0.08, 2.5)),
		_part(_box("hike_cabin_door", Vector3(0.62, 1.0, 0.12)), dark, Vector3(-0.72, 0.76, 1.22)),
		_part(_box("hike_cabin_win_l", Vector3(0.54, 0.42, 0.12)), dark, Vector3(0.42, 1.08, 1.22)),
		_part(_box("hike_cabin_win_r", Vector3(0.48, 0.38, 0.12)), dark, Vector3(1.06, 1.0, 1.22)),
		_part(_box("hike_cabin_post", Vector3(0.12, 1.12, 0.12)), wood, Vector3(-1.34, 0.82, 1.98)),
		_part(_box("hike_cabin_post", Vector3(0.12, 1.12, 0.12)), wood, Vector3(1.06, 0.82, 1.98)),
		_part(_box("hike_cabin_flowerbox", Vector3(0.76, 0.18, 0.18)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0.78, 0.78, 1.3)),
		_part(_sphere("hike_cabin_flower_a", 0.1), _mat("leaf_gold", "dirt_b", "gold"), Vector3(0.55, 0.95, 1.36), Vector3(1.0, 0.65, 1.0)),
		_part(_sphere("hike_cabin_flower_b", 0.1), _mat("leaf_orange", "leaf_red", "path_light"), Vector3(0.92, 0.95, 1.36), Vector3(1.0, 0.65, 1.0))]


static func _hike_lodge_parts() -> Array:
	var wall := _mat("wall_cream", "wall_blush", "cabin_trim")
	var roof := _mat("roof_purple", "roof_purple_dark", "roof_purple_light")
	var wood := _mat("wood_light", "trunk_b", "path_light")
	var dark := _mat("roof_purple_dark", "shadow", "roof_purple")
	return [
		_part(_box("hike_lodge_found", Vector3(3.8, 0.26, 2.95)), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(0, 0.13, 0)),
		_part(_box("hike_lodge_body", Vector3(3.45, 1.95, 2.55)), wall, Vector3(0, 1.12, 0)),
		_part(_prism("hike_lodge_roof", Vector3(4.3, 1.34, 3.22)), roof, Vector3(0, 2.46, 0)),
		_part(_box("hike_lodge_roof_band_a", Vector3(4.1, 0.1, 0.22)), _mat("roof_purple_light", "roof_purple_dark", "roof_purple_light"), Vector3(0, 2.78, 0.7)),
		_part(_box("hike_lodge_roof_band_b", Vector3(3.5, 0.1, 0.22)), _mat("roof_purple_dark", "shadow", "roof_purple"), Vector3(0, 2.26, -0.82)),
		_part(_box("hike_lodge_door", Vector3(0.66, 1.08, 0.12)), dark, Vector3(-0.74, 0.82, 1.34)),
		_part(_box("hike_lodge_win_a", Vector3(0.5, 0.44, 0.12)), dark, Vector3(0.36, 1.2, 1.34)),
		_part(_box("hike_lodge_win_b", Vector3(0.5, 0.44, 0.12)), dark, Vector3(1.08, 1.12, 1.34)),
		_part(_box("hike_lodge_deck", Vector3(2.9, 0.2, 1.28)), wood, Vector3(-0.08, 0.3, 1.86)),
		_part(_box("hike_lodge_step0", Vector3(2.24, 0.18, 0.48)), wood, Vector3(-0.08, 0.18, 2.42)),
		_part(_box("hike_lodge_step1", Vector3(1.72, 0.15, 0.42)), wood, Vector3(-0.08, 0.08, 2.78))]


static func _hike_conifer_parts(variant: int, snowy: bool = false) -> Array:
	var leaf := _mat("pine_mid", "pine_dark", "foliage_c")
	if variant % 3 == 1:
		leaf = _mat("fir_a", "pine_dark", "foliage_c")
	elif variant % 3 == 2:
		leaf = _mat("pine_dark", "shadow", "pine_mid")
	if snowy:
		var snow_base := PixelPalette.pal("snow_a")
		leaf = _mat_from(snow_base, snow_base.darkened(0.12), snow_base.lightened(0.08))
	return [
		_part(_cyl("hike_pine_trunk", 0.15, 0.22, 1.35), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.68, 0)),
		_part(_cone("hike_pine_filled_core", 0.44, 0.02, 2.9), leaf, Vector3(0, 2.08, 0)),
		_part(_fir_bough("hike_pine_skirt", 1.05, 1.02, 8, 0.16), leaf, Vector3(0, 1.18, 0)),
		_part(_fir_bough("hike_pine_mid", 0.82, 1.02, 8, 0.13), leaf, Vector3(0.05, 1.88, 0.02)),
		_part(_fir_bough("hike_pine_top", 0.56, 1.04, 7, 0.10), leaf, Vector3(-0.03, 2.58, -0.02)),
		_part(_fir_bough("hike_pine_tip", 0.3, 0.78, 7, 0.06), leaf, Vector3(0.02, 3.18, 0.01))]


static func _hike_deciduous_parts(variant: int) -> Array:
	var leaf := _hike_leaf_mat(variant)
	return [
		_part(_cyl("hike_tree_trunk", 0.18, 0.28, 1.55), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.78, 0)),
		_part(_sphere("hike_leaf_main", 1.18), leaf, Vector3(0, 2.02, 0), Vector3(1.1, 0.86, 1.08)),
		_part(_sphere("hike_leaf_left", 0.82), leaf, Vector3(-0.76, 1.86, 0.18), Vector3(1.0, 0.78, 1.0)),
		_part(_sphere("hike_leaf_right", 0.82), leaf, Vector3(0.76, 1.88, -0.12), Vector3(1.0, 0.78, 1.0)),
		_part(_sphere("hike_leaf_front", 0.76), leaf, Vector3(0.08, 1.72, 0.68), Vector3(1.1, 0.72, 0.92)),
		_part(_sphere("hike_leaf_top", 0.86), leaf, Vector3(0.02, 2.6, 0.0), Vector3(0.96, 0.72, 0.96))]


static func _hike_fence_parts() -> Array:
	var wood := _mat("wood_light", "trunk_b", "path_light")
	return [
		_part(_box("hike_fence_post", Vector3(0.16, 0.78, 0.16)), wood, Vector3(-0.72, 0.39, 0)),
		_part(_box("hike_fence_post", Vector3(0.16, 0.72, 0.16)), wood, Vector3(0.72, 0.36, 0)),
		_part(_box("hike_fence_rail_a", Vector3(1.62, 0.14, 0.12)), wood, Vector3(0, 0.58, 0.02)),
		_part(_box("hike_fence_rail_b", Vector3(1.52, 0.12, 0.1)), wood, Vector3(0, 0.34, -0.02))]


static func _hike_cliff_parts() -> Array:
	var stone := _mat("cliff_warm", "cliff_shadow", "cliff_light")
	var dark := _mat("cliff_shadow", "shadow", "cliff_warm")
	return [
		_part(_box("hike_cliff_back", Vector3(2.35, 1.35, 0.58)), stone, Vector3(0, 0.78, -0.18)),
		_part(_box("hike_cliff_shelf", Vector3(2.1, 0.34, 0.88)), stone, Vector3(-0.08, 1.48, 0.08)),
		_part(_box("hike_cliff_shadow", Vector3(1.9, 0.22, 0.18)), dark, Vector3(0.1, 0.76, 0.15)),
		_part(_octa("hike_cliff_chip_a"), stone, Vector3(-0.82, 0.24, 0.38), Vector3(0.42, 0.28, 0.34)),
		_part(_octa("hike_cliff_chip_b"), stone, Vector3(0.72, 0.18, 0.44), Vector3(0.36, 0.24, 0.32))]


static func _hike_boulder_parts() -> Array:
	var stone := _mat("cliff_warm", "cliff_shadow", "cliff_light")
	return [
		_part(_octa("hike_boulder_big"), stone, Vector3(0, 0.34, 0), Vector3(0.88, 0.64, 0.98)),
		_part(_octa("hike_boulder_flat"), stone, Vector3(0.48, 0.16, 0.18), Vector3(0.52, 0.24, 0.46)),
		_part(_octa("hike_boulder_chip"), stone, Vector3(-0.42, 0.1, -0.22), Vector3(0.28, 0.18, 0.24))]


static func _hike_pool_parts() -> Array:
	return [
		_part(_sphere("hike_pool_water", 0.92), _mat("water_c", "water_a", "water_spark"), Vector3(0, 0.055, 0), Vector3(1.85, 0.08, 1.22)),
		_part(_sphere("hike_pool_foam_l", 0.42), _mat("water_spark", "water_c", "snow_a"), Vector3(-0.84, 0.1, -0.1), Vector3(1.2, 0.04, 0.35)),
		_part(_sphere("hike_pool_foam_r", 0.34), _mat("water_spark", "water_c", "snow_a"), Vector3(0.76, 0.1, 0.16), Vector3(0.95, 0.04, 0.3)),
		_part(_octa("hike_pool_rock_a"), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(-1.25, 0.18, 0.46), Vector3(0.34, 0.22, 0.28)),
		_part(_octa("hike_pool_rock_b"), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(1.18, 0.16, -0.36), Vector3(0.3, 0.2, 0.26))]


static func _hike_campfire_parts() -> Array:
	var parts := _campfire_parts()
	parts.append(_part(_box("hike_fire_log_a", Vector3(0.72, 0.12, 0.16)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(-0.12, 0.1, 0.18)))
	parts.append(_part(_box("hike_fire_log_b", Vector3(0.16, 0.12, 0.72)), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0.18, 0.1, -0.08)))
	parts.append(_part(_octa("hike_fire_rock_a"), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(-0.48, 0.12, 0.05), Vector3(0.2, 0.16, 0.18)))
	parts.append(_part(_octa("hike_fire_rock_b"), _mat("cliff_warm", "cliff_shadow", "cliff_light"), Vector3(0.44, 0.12, -0.08), Vector3(0.18, 0.14, 0.18)))
	return parts


static func _hike_sign_parts() -> Array:
	return [
		_part(_cyl("hike_sign_post", 0.055, 0.075, 1.05), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.53, 0)),
		_part(_box("hike_sign_face", Vector3(1.05, 0.46, 0.1)), _mat("path_light", "trunk_b", "cabin_trim"), Vector3(0.06, 0.98, 0.03)),
		_part(_box("hike_sign_mark", Vector3(0.58, 0.12, 0.12)), _mat("cabin_roof", "roof_shadow", "path_light"), Vector3(0.08, 1.0, 0.1))]


static func _hike_flower_parts(variant: int) -> Array:
	var bloom := _mat("leaf_gold", "dirt_b", "gold")
	if variant % 3 == 1:
		bloom = _mat("leaf_orange", "leaf_red", "path_light")
	elif variant % 3 == 2:
		bloom = _mat("cabin_trim", "gold", "snow_a")
	return [
		_part(_sphere("hike_flower_leaf", 0.18), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.1, 0), Vector3(1.2, 0.32, 0.9)),
		_part(_sphere("hike_flower_bloom", 0.09), bloom, Vector3(-0.08, 0.28, 0.02), Vector3(1.0, 0.68, 1.0)),
		_part(_sphere("hike_flower_bloom_b", 0.075), bloom, Vector3(0.12, 0.25, -0.05), Vector3(1.0, 0.65, 1.0))]


static func _hike_log_parts() -> Array:
	var bark := _mat("trunk_a", "trunk_b", "wood_light")
	var cut := _mat("wood_light", "trunk_b", "path_light")
	return [
		_part(_box("hike_log_body", Vector3(1.25, 0.34, 0.42)), bark, Vector3(0, 0.24, 0)),
		_part(_box("hike_log_cut_l", Vector3(0.12, 0.28, 0.36)), cut, Vector3(-0.68, 0.24, 0)),
		_part(_box("hike_log_cut_r", Vector3(0.12, 0.28, 0.36)), cut, Vector3(0.68, 0.24, 0)),
		_part(_box("hike_log_shadow", Vector3(1.08, 0.08, 0.08)), _mat("trunk_b", "shadow", "trunk_a"), Vector3(-0.04, 0.39, 0.22))]


static func _hike_bench_parts() -> Array:
	var wood := _mat("cabin_roof", "roof_shadow", "path_light")
	var dark := _mat("trunk_b", "shadow", "trunk_a")
	return [
		_part(_box("hike_bench_seat", Vector3(1.45, 0.22, 0.52)), wood, Vector3(0, 0.5, 0)),
		_part(_box("hike_bench_back", Vector3(1.45, 0.18, 0.2)), wood, Vector3(0, 0.86, -0.34)),
		_part(_box("hike_bench_leg", Vector3(0.16, 0.54, 0.16)), dark, Vector3(-0.5, 0.28, 0.18)),
		_part(_box("hike_bench_leg", Vector3(0.16, 0.54, 0.16)), dark, Vector3(0.5, 0.28, 0.18))]


static func _hike_stump_parts() -> Array:
	return [
		_part(_cyl("hike_stump", 0.32, 0.38, 0.52), _mat("trunk_a", "trunk_b", "wood_light"), Vector3(0, 0.26, 0)),
		_part(_cyl("hike_stump_top", 0.3, 0.3, 0.05), _mat("wood_light", "trunk_b", "path_light"), Vector3(0, 0.55, 0)),
		_part(_sphere("hike_stump_moss", 0.16), _mat("hike_grass_b", "hike_grass_dark", "hike_grass_light"), Vector3(-0.16, 0.58, 0.05), Vector3(1.2, 0.22, 0.8))]


static func _hike_grass_parts(variant: int) -> Array:
	var mat := _mat("hike_grass", "hike_grass_dark", "hike_grass_light")
	if variant % 3 == 1:
		mat = _mat("hike_grass_b", "hike_grass_dark", "hike_grass_light")
	return [
		_part(_cone("hike_grass_a", 0.18, 0.02, 0.42), mat, Vector3(-0.16, 0.2, 0.02), Vector3(0.65, 0.9, 0.75)),
		_part(_cone("hike_grass_b", 0.14, 0.02, 0.34), mat, Vector3(0.08, 0.16, -0.08), Vector3(0.55, 0.8, 0.7)),
		_part(_cone("hike_grass_c", 0.12, 0.02, 0.28), mat, Vector3(0.22, 0.14, 0.1), Vector3(0.55, 0.78, 0.65))]


static func _hike_leaf_litter_parts(variant: int) -> Array:
	var leaf := _hike_leaf_mat(variant)
	return [
		_part(_sphere("hike_leaf_patch_a", 0.24), leaf, Vector3(-0.18, 0.045, 0.02), Vector3(1.45, 0.08, 0.9)),
		_part(_sphere("hike_leaf_patch_b", 0.2), leaf, Vector3(0.22, 0.05, -0.06), Vector3(1.2, 0.08, 0.82)),
		_part(_sphere("hike_leaf_patch_c", 0.16), leaf, Vector3(0.05, 0.055, 0.22), Vector3(1.0, 0.08, 0.7))]


static func _hike_mushroom_parts(variant: int) -> Array:
	var cap := _mat("leaf_orange", "leaf_red", "path_light") if variant % 2 == 0 else _mat("cabin_trim", "gold", "snow_a")
	return [
		_part(_cyl("hike_mush_stem", 0.04, 0.055, 0.22), _mat("wall_cream", "wall_blush", "cabin_trim"), Vector3(0, 0.11, 0)),
		_part(_sphere("hike_mush_cap", 0.14), cap, Vector3(0, 0.27, 0), Vector3(1.05, 0.48, 1.05)),
		_part(_cyl("hike_mush_stem_b", 0.035, 0.045, 0.18), _mat("wall_cream", "wall_blush", "cabin_trim"), Vector3(0.18, 0.09, -0.04)),
		_part(_sphere("hike_mush_cap_b", 0.11), cap, Vector3(0.18, 0.22, -0.04), Vector3(1.0, 0.48, 1.0))]


static func _hike_pebble_parts() -> Array:
	var stone := _mat("cliff_warm", "cliff_shadow", "cliff_light")
	return [
		_part(_octa("hike_pebble_a"), stone, Vector3(-0.18, 0.06, 0.02), Vector3(0.18, 0.12, 0.16)),
		_part(_octa("hike_pebble_b"), stone, Vector3(0.12, 0.05, -0.12), Vector3(0.14, 0.1, 0.14)),
		_part(_octa("hike_pebble_c"), stone, Vector3(0.26, 0.04, 0.14), Vector3(0.12, 0.08, 0.12))]


static func _hike_leaf_mat(variant: int) -> ShaderMaterial:
	# Deep-forest greens (moody). Warm autumn now lives only on the maple accents.
	match variant % 4:
		0:
			return _mat("leaf_green", "forest_green", "moss_hi")
		1:
			return _mat("mid_foliage", "forest_teal", "leaf_green")
		2:
			return _mat("forest_green", "forest_teal", "mid_foliage")
		_:
			return _mat("foliage_c", "grass_dark", "moss_hi")


static func _fish_parts() -> Array:
	return [_part(_sphere("fish_site", 0.18), _mat("water_foam", "water_b", "snow_a"), Vector3(0, 0.08, 0), Vector3(1.65, 0.5, 0.75))]


static func _reed_parts() -> Array:
	return [
		_part(_cyl("reed_a", 0.025, 0.035, 0.58), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(-0.08, 0.29, 0)),
		_part(_cyl("reed_b", 0.025, 0.035, 0.48), _mat("foliage_b", "grass_dark", "foliage_c"), Vector3(0.08, 0.24, 0.04)),
		_part(_sphere("reed_tip", 0.05), _mat("dirt_a", "trunk_b", "gold"), Vector3(0.08, 0.52, 0.04), Vector3(0.7, 1.2, 0.7))]


static func _fern_parts() -> Array:
	return [
		_part(_cone("fern_a", 0.22, 0.02, 0.42), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(-0.1, 0.2, 0.04), Vector3(0.55, 0.8, 0.85)),
		_part(_cone("fern_b", 0.2, 0.02, 0.36), _mat("foliage_b", "grass_dark", "foliage_c"), Vector3(0.12, 0.18, -0.02), Vector3(0.55, 0.75, 0.8))]


## Blocky humanoid matching the 2D player silhouette (legs/torso/arms/head/hair),
## ported to the 3D toon style. body = outfit color, head = skin color.
static func figure_parts(body: Color, head: Color) -> Array:
	var outfit := _mat_from(body, body.darkened(0.35), body.lightened(0.18))
	var legm := _mat_from(body.darkened(0.28), body.darkened(0.5), body.lightened(0.05))
	var armm := _mat_from(body.darkened(0.12), body.darkened(0.4), body.lightened(0.12))
	var skin := _mat_from(head, head.darkened(0.28), head.lightened(0.18))
	var hairc: Color = PixelPalette.pal("hair")
	var hairm := _mat_from(hairc, hairc.darkened(0.3), hairc.lightened(0.18))
	return [
		_part(_box("fig_leg", Vector3(0.17, 0.52, 0.19)), legm, Vector3(-0.12, 0.26, 0)),
		_part(_box("fig_leg", Vector3(0.17, 0.52, 0.19)), legm, Vector3(0.12, 0.26, 0)),
		_part(_box("fig_torso", Vector3(0.46, 0.6, 0.3)), outfit, Vector3(0, 0.8, 0)),
		_part(_box("fig_arm", Vector3(0.13, 0.48, 0.16)), armm, Vector3(-0.33, 0.82, 0)),
		_part(_box("fig_arm", Vector3(0.13, 0.48, 0.16)), armm, Vector3(0.33, 0.82, 0)),
		_part(_box("fig_head", Vector3(0.4, 0.38, 0.38)), skin, Vector3(0, 1.3, 0)),
		_part(_box("fig_hair", Vector3(0.44, 0.18, 0.42)), hairm, Vector3(0, 1.53, 0))]


# ----------------------------------------------------------- node (movers) ----

## Build an individual Node3D from a part list (used for the player and enemies).
static func build_node(parts: Array) -> Node3D:
	var root := Node3D.new()
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = p["mat"]
		mi.position = p["off"]
		mi.scale = p["scl"]
		mi.rotation = p.get("rot", Vector3.ZERO)
		root.add_child(mi)
	return root


## Articulated low-poly human with natural proportions (a normal-sized squared
## head, not a chibi ball): tousled hair, a casual shirt with rolled sleeves —
## bare-skin forearms — over dark trousers and boots. Each leg/arm hangs off a
## named pivot (leg_l/leg_r/arm_l/arm_r) for the walk + attack anim. body = shirt
## colour, head = skin. (cape kept for API compat; the player no longer uses it.)
## Faces +Z.
static func figure_rig(body: Color, head: Color, cape := Color(0, 0, 0, 0)) -> Node3D:
	var shirt := _mat_from(body, body.darkened(0.4), body.lightened(0.22))
	var pants := _mat_from(Color(0.22, 0.22, 0.27), Color(0.13, 0.13, 0.17), Color(0.32, 0.32, 0.38))
	var boot := _mat_from(Color(0.26, 0.17, 0.1), Color(0.15, 0.09, 0.05), Color(0.38, 0.27, 0.16))
	var skin := _mat_from(head, head.darkened(0.3), head.lightened(0.2))
	var hairc: Color = PixelPalette.pal("hair")
	var hairm := _mat_from(hairc, hairc.darkened(0.4), hairc.lightened(0.18))
	var eyed := _mat_from(Color(0.1, 0.1, 0.14), Color(0.05, 0.05, 0.07), Color(0.18, 0.18, 0.22))
	var root := Node3D.new()
	# Legs: dark trousers over a knee joint + boots (so the knee can flex when walking).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.13 * side, 0.9, 0), Vector3(0.19, 0.42, 0.21), Vector3(0.17, 0.4, 0.19), pants, "hleg")
		_attach(knee, _box("hum_boot", Vector3(0.21, 0.16, 0.28)), boot, Vector3(0, -0.46, 0.04))
	_attach(root, _box("hum_hips", Vector3(0.42, 0.18, 0.27)), pants, Vector3(0, 0.92, 0))
	# Everything above the hips hangs off a `spine` pivot at the waist, so the pose
	# code can curl the upper back forward into a natural stoop (legs stay vertical).
	# Child Y offsets are spine-local (world Y minus the 0.95 pivot height).
	var spine := _limb(root, "spine", Vector3(0, 0.95, 0))
	# Torso: a casual shirt with a slightly broader shoulder yoke + a small collar.
	_attach(spine, _box("hum_chest", Vector3(0.46, 0.52, 0.28)), shirt, Vector3(0, 0.29, 0))
	_attach(spine, _box("hum_yoke", Vector3(0.52, 0.14, 0.31)), shirt, Vector3(0, 0.51, 0))
	_attach(spine, _box("hum_collar", Vector3(0.12, 0.12, 0.08)), skin, Vector3(0, 0.51, 0.14))
	# Neck + a squared, natural-sized head.
	_attach(spine, _box("hum_neck", Vector3(0.14, 0.12, 0.15)), skin, Vector3(0, 0.6, 0))
	_attach(spine, _box("hum_head", Vector3(0.32, 0.36, 0.32)), skin, Vector3(0, 0.79, 0))
	# Tousled hair: a crown block, a swept-up front fringe, and short sides.
	_attach(spine, _box("hum_hair", Vector3(0.35, 0.16, 0.35)), hairm, Vector3(0, 0.95, -0.01))
	_attach(spine, _box("hum_fringe", Vector3(0.33, 0.1, 0.13)), hairm, Vector3(0.02, 0.91, 0.16), Vector3.ONE, Vector3(-0.35, 0, 0.1))
	_attach(spine, _box("hum_side", Vector3(0.36, 0.16, 0.3)), hairm, Vector3(0, 0.85, -0.06))
	# Subtle eyes set into the face (+Z).
	for ex: int in [-1, 1]:
		_attach(spine, _box("hum_eye", Vector3(0.05, 0.06, 0.04)), eyed, Vector3(0.08 * ex, 0.79, 0.16))
	# Optional cape/strap kept for API compatibility.
	if cape.a > 0.0:
		var capem := _mat_from(Color(cape.r, cape.g, cape.b), cape.darkened(0.34), cape.lightened(0.22))
		_attach(spine, _box("hum_cape", Vector3(0.34, 0.6, 0.07)), capem, Vector3(0, 0.15, -0.17), Vector3.ONE, Vector3(0.2, 0, 0))
	# Arms: shirt sleeve (upper) over an elbow joint, bare-skin forearm + hand. Weapon
	# sockets ride the forearm so a held weapon follows the hand and bends at the elbow.
	for side2: int in [-1, 1]:
		var el := _biped_arm(spine, side2, Vector3(0.3 * side2, 0.47, 0), Vector3(0.14, 0.26, 0.16), Vector3(0.12, 0.26, 0.14), shirt, skin, "harm")
		_attach(el, _box("hum_hand", Vector3(0.13, 0.13, 0.15)), skin, Vector3(0, -0.34, 0))
		_socket(el, "socket_mainhand" if side2 > 0 else "socket_offhand", Vector3(0.04 * side2, -0.42, 0.16), Vector3(-0.1, 0, -0.08 * side2))
	# Worn-gear sockets (see equip_profile): the renderer attaches armor/weapons here.
	# Upper-body sockets ride the spine; leg armor stays on the (vertical) root.
	_socket(spine, "socket_head", Vector3(0, 0.79, 0))
	_socket(spine, "socket_body", Vector3(0, 0.29, 0))
	_socket(root, "socket_legs", Vector3(0, 0.95, 0))
	_socket(spine, "socket_back", Vector3(0, 0.39, -0.16))
	root.set_meta("body_profile", {
		"torso": Vector3(0.5, 0.56, 0.32), "head": Vector3(0.36, 0.42, 0.36),
		"shoulder": 0.6, "hips": Vector3(0.42, 0.18, 0.27)})
	return root


## The player's bare adventurer body — a more sculpted low-poly figure than the
## generic enemy humanoid: a bearded head with a jaw/brow/nose and pointed ears,
## swept hair, a linen shirt with rolled sleeves, teal tartan breeches and cuffed
## boots. The OUTFIT (jerkin, belt, cape, weapons) is NOT baked in — it layers on
## via the equipment sockets (EquipLoadout.player_default), so armor and weapons
## can be swapped independently of the body. Same pivots/sockets as figure_rig.
static func player_rig(skin_col: Color) -> Node3D:
	var skin := _mat_from(skin_col, skin_col.darkened(0.3), skin_col.lightened(0.2))
	var skin_sh := _mat_from(skin_col.darkened(0.14), skin_col.darkened(0.42), skin_col.lightened(0.08))
	var linen := _mat_from(Color(0.82, 0.78, 0.66), Color(0.6, 0.56, 0.46), Color(0.92, 0.89, 0.8))
	var teal := _mat_from(Color(0.26, 0.42, 0.4), Color(0.16, 0.28, 0.27), Color(0.38, 0.56, 0.52))
	var teal2 := _mat_from(Color(0.36, 0.52, 0.48), Color(0.24, 0.36, 0.34), Color(0.48, 0.64, 0.6))
	var boot := _mat_from(Color(0.36, 0.24, 0.14), Color(0.22, 0.14, 0.08), Color(0.5, 0.36, 0.22))
	var cuff := _mat_from(Color(0.47, 0.33, 0.18), Color(0.3, 0.2, 0.1), Color(0.6, 0.46, 0.28))
	var hairc: Color = PixelPalette.pal("hair")
	var hairm := _mat_from(hairc, hairc.darkened(0.42), hairc.lightened(0.16))
	var beardm := _mat_from(hairc.lightened(0.06), hairc.darkened(0.4), hairc.lightened(0.22))
	var eyed := _mat_from(Color(0.1, 0.1, 0.14), Color(0.05, 0.05, 0.07), Color(0.18, 0.18, 0.22))
	var root := Node3D.new()
	# Legs: tartan breeches over a knee joint + cuffed boots (boots ride the shin).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.13 * side, 0.9, 0), Vector3(0.21, 0.42, 0.23), Vector3(0.18, 0.4, 0.21), teal, "pleg")
		_attach(knee, _box("p_stripe", Vector3(0.045, 0.4, 0.22)), teal2, Vector3(0.06, -0.2, 0.0))
		_attach(knee, _box("p_boot", Vector3(0.21, 0.3, 0.28)), boot, Vector3(0, -0.36, 0.02))
		_attach(knee, _box("p_bootcuff", Vector3(0.24, 0.09, 0.3)), cuff, Vector3(0, -0.24, 0.02))
		_attach(knee, _box("p_sole", Vector3(0.22, 0.06, 0.33)), cuff, Vector3(0, -0.52, 0.05))
	_attach(root, _box("p_hips", Vector3(0.44, 0.2, 0.28)), teal, Vector3(0, 0.9, 0))
	# Torso: a plain linen shirt — the jerkin/armor layers over it (body socket).
	_attach(root, _box("p_chest", Vector3(0.46, 0.54, 0.28)), linen, Vector3(0, 1.24, 0))
	_attach(root, _box("p_yoke", Vector3(0.52, 0.16, 0.31)), linen, Vector3(0, 1.48, 0))
	# Sculpted head: skull + jaw + brow + nose, beard, pointed ears, swept hair, eyes.
	_attach(root, _box("p_neck", Vector3(0.15, 0.12, 0.16)), skin, Vector3(0, 1.56, 0))
	_attach(root, _box("p_skull", Vector3(0.32, 0.3, 0.32)), skin, Vector3(0, 1.79, 0))
	_attach(root, _box("p_jaw", Vector3(0.27, 0.16, 0.29)), skin, Vector3(0, 1.65, 0.02))
	_attach(root, _box("p_brow", Vector3(0.3, 0.06, 0.05)), skin_sh, Vector3(0, 1.8, 0.16))
	_attach(root, _box("p_nose", Vector3(0.08, 0.1, 0.09)), skin, Vector3(0, 1.73, 0.18))
	# Beard hangs off a pivot at the jaw so the hair-physics sway swings it.
	var beard := _limb(root, "beard", Vector3(0, 1.62, 0.07))
	_attach(beard, _box("p_beard", Vector3(0.31, 0.22, 0.18)), beardm, Vector3(0, -0.02, 0.0))
	_attach(beard, _box("p_beard2", Vector3(0.2, 0.14, 0.11)), beardm, Vector3(0, -0.13, 0.05))
	for sx: int in [-1, 1]:
		_attach(root, _prism("p_ear", Vector3(0.08, 0.18, 0.09)), skin, Vector3(0.18 * sx, 1.82, 0.0), Vector3.ONE, Vector3(0, 0, -0.35 * sx))
	# Swept hair hangs off a crown pivot so it bounces/leans with movement.
	var hair := _limb(root, "hair", Vector3(0, 1.82, 0))
	_attach(hair, _box("p_hair_top", Vector3(0.36, 0.18, 0.36)), hairm, Vector3(0, 0.14, -0.01))
	_attach(hair, _box("p_hair_back", Vector3(0.35, 0.34, 0.16)), hairm, Vector3(0, -0.04, -0.15))
	_attach(hair, _box("p_hair_fr", Vector3(0.34, 0.12, 0.12)), hairm, Vector3(0.03, 0.1, 0.15), Vector3.ONE, Vector3(-0.5, 0, 0.12))
	for ex: int in [-1, 1]:
		_attach(root, _box("p_eye", Vector3(0.05, 0.06, 0.04)), eyed, Vector3(0.08 * ex, 1.77, 0.17))
	# Arms: linen sleeve (upper) over an elbow joint with a bare-skin forearm + hand;
	# weapon sockets ride the forearm (elbow) so a held weapon follows the hand.
	for s2: int in [-1, 1]:
		var el := _biped_arm(root, s2, Vector3(0.3 * s2, 1.42, 0), Vector3(0.16, 0.24, 0.18), Vector3(0.12, 0.26, 0.14), linen, skin, "parm")
		_attach(el, _box("p_hand", Vector3(0.13, 0.13, 0.15)), skin, Vector3(0, -0.34, 0))
		_socket(el, "socket_mainhand" if s2 > 0 else "socket_offhand", Vector3(0.04 * s2, -0.42, 0.16), Vector3(-0.1, 0, -0.08 * s2))
	_socket(root, "socket_head", Vector3(0, 1.79, 0))
	_socket(root, "socket_body", Vector3(0, 1.24, 0))
	_socket(root, "socket_legs", Vector3(0, 0.9, 0))
	_socket(root, "socket_back", Vector3(0, 1.36, -0.16))
	# Body profile: the bounding boxes worn armor is sized FROM so a piece always
	# wraps this body (never crops). Read by apply_equipment -> equip_parts.
	root.set_meta("body_profile", {
		"torso": Vector3(0.5, 0.6, 0.32), "head": Vector3(0.36, 0.42, 0.36),
		"shoulder": 0.66, "hips": Vector3(0.46, 0.22, 0.3)})
	# Posture: the player stands near-upright but relaxed (a touch of lean + arms
	# resting slightly forward), not ramrod-straight. Read by _pose_humanoid.
	root.set_meta("lean", 0.04)
	root.set_meta("arm_rest", 0.1)
	root.set_meta("crouch", 0.17)   # slightly bent knees — an athletic stance, not locked
	return root


## A static attachment point (worn gear / held weapons) — a named empty the
## renderer parents equipment meshes under. See apply_equipment / equip_profile.
static func _socket(parent: Node3D, sname: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var s := Node3D.new()
	s.name = sname
	s.position = pos
	s.rotation = rot
	parent.add_child(s)
	return s


# -------------------------------------------------------------- equipment ----
# Visible worn armor + held weapons. A rig exposes named sockets (socket_mainhand,
# socket_offhand, socket_head, socket_body, socket_legs, socket_back); apply_equipment
# attaches gear meshes to the ones a loadout fills. A rig that lacks a socket simply
# can't show that slot — that's the capability gate (a chicken has no sockets, so it
# wears nothing). See docs/render_spike/MODELS_AND_EQUIPMENT.md.

const EQUIP_SLOTS := ["socket_mainhand", "socket_offhand", "socket_head", "socket_body", "socket_legs", "socket_back"]


## Which worn slots a rig actually supports (the sockets it was built with).
static func equip_profile(rig: Node3D) -> Array:
	var out: Array = []
	for s: String in EQUIP_SLOTS:
		if rig.get_node_or_null(NodePath(s)) != null:
			out.append(s.trim_prefix("socket_"))
	return out


## Attach a loadout to a rig. loadout = {slot: {kind, material, tint?}} with slot in
## mainhand/offhand/head/body/legs/back. Clears any previously-applied gear first so
## re-applying (e.g. the player changing equipment) is clean. Slots the rig can't
## support are skipped.
static func apply_equipment(rig: Node3D, loadout: Dictionary) -> void:
	for s: String in EQUIP_SLOTS:
		var sock: Node = rig.get_node_or_null(NodePath(s))
		if sock == null:
			continue
		var old: Node = sock.get_node_or_null(^"equip")
		if old != null:
			old.free()
	# A long robe replaces the visible legs — hide them so they don't poke through
	# the skirt (the wearer glides). Reset first so unequipping shows them again.
	var hide_legs := loadout.has("legs") and str(Dictionary(loadout.get("legs", {})).get("kind", "")) == "robe_bottom"
	for legn: String in ["leg_l", "leg_r"]:
		var lp: Node = rig.get_node_or_null(NodePath(legn))
		if lp != null:
			(lp as Node3D).visible = not hide_legs
	# A full helm encloses the head — hide the hair/beard so they don't poke out the
	# back of it (the black square). A soft hood keeps them. Reset when bare-headed.
	var hide_hair := loadout.has("head") and str(Dictionary(loadout.get("head", {})).get("kind", "")) == "helm"
	for hn: String in ["hair", "beard"]:
		var hp: Node = rig.get_node_or_null(NodePath(hn))
		if hp == null:
			hp = rig.find_child(hn, true, false)
		if hp != null:
			(hp as Node3D).visible = not hide_hair
	var profile: Dictionary = rig.get_meta("body_profile", {})
	for slot: String in loadout:
		var sock2: Node3D = rig.get_node_or_null(NodePath("socket_" + slot))
		if sock2 == null:
			continue
		var spec: Dictionary = loadout[slot]
		var kind := str(spec.get("kind", ""))
		var holder: Node3D
		if kind == "cape":
			# A cape is a segmented chain so the renderer can ripple a cheap wave down
			# it (real flow, not a rigid plank swing) — see _flow_cloth.
			holder = build_cape(equip_material(str(spec.get("material", "cloth")), spec.get("tint", Color(0, 0, 0, 0))), profile)
		else:
			var parts := equip_parts(slot, kind, str(spec.get("material", "iron")), spec.get("tint", Color(0, 0, 0, 0)), profile)
			if parts.is_empty():
				continue
			holder = build_node(parts)
		holder.name = "equip"
		# Flag flowing cloth pieces so the renderer can sway them (cheap procedural
		# secondary motion — no physics). Skirts and capes are the big flowy ones.
		holder.set_meta("cloth", kind in ["robe_bottom", "robe_top", "cape", "hood"])
		for mi: Node in holder.get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sock2.add_child(holder)


## Palette for an equipment material tier; `tint` overrides cloth/gem colour.
static func equip_material(mat_key: String, tint := Color(0, 0, 0, 0)) -> ShaderMaterial:
	var base: Color
	match mat_key:
		"cloth": base = tint if tint.a > 0.0 else Color(0.52, 0.52, 0.58)
		"leather": base = Color(0.44, 0.3, 0.18)
		"bronze": base = Color(0.72, 0.5, 0.28)
		"iron": base = Color(0.54, 0.55, 0.6)
		"steel": base = Color(0.72, 0.74, 0.8)
		"mithril": base = Color(0.34, 0.46, 0.74)
		"adamant": base = Color(0.3, 0.55, 0.46)
		"rune": base = Color(0.34, 0.64, 0.72)
		"gold": base = Color(0.86, 0.7, 0.26)
		"wood": base = Color(0.46, 0.32, 0.18)
		"bone": base = Color(0.9, 0.86, 0.73)        # horns / ivory trim
		"gem": base = tint if tint.a > 0.0 else Color(0.45, 0.74, 0.95)
		_: base = Color(0.52, 0.52, 0.58)
	return _mat_from(base, base.darkened(0.4), base.lightened(0.3))


## Build the meshes for one equipped piece. Weapons are built extending +Y from the
## grip so they swing naturally from the hand socket; armor wraps its socket centre.
static func equip_parts(slot: String, kind: String, mat_key: String, tint: Color, profile := {}) -> Array:
	var m := equip_material(mat_key, tint)
	var gold := equip_material("gold")
	var dark := equip_material("leather")
	# Body dimensions this armor must wrap (so it never crops the model it's worn on).
	# Falls back to a generic humanoid when a rig declares no profile.
	var torso: Vector3 = profile.get("torso", Vector3(0.5, 0.56, 0.32))
	var headb: Vector3 = profile.get("head", Vector3(0.36, 0.4, 0.36))
	var shoulder: float = float(profile.get("shoulder", 0.64))
	match kind:
		"staff":
			var wood := equip_material("wood")
			return [
				_part(_cyl("eq_staff", 0.035, 0.05, 1.5), wood, Vector3(0, 0.52, 0.04)),
				_part(_box("eq_staff_bind", Vector3(0.09, 0.07, 0.09)), gold, Vector3(0, 1.18, 0.04)),
				_part(_sphere("eq_staff_gem", 0.11), equip_material("gem", tint), Vector3(0, 1.32, 0.04))]
		"raven_staff":
			# Tall gnarled staff with a raven perched on top, planted forward (+Z) of
			# the body so it stays visible whichever way the wearer turns to face.
			var wd := equip_material("wood")
			var rav := _mat_from(Color(0.12, 0.12, 0.15), Color(0.06, 0.06, 0.08), Color(0.24, 0.24, 0.3))
			# Planted vertically out to the side of the hand (not in front), so the
			# staff clears the body silhouette from most camera angles, and long enough
			# that its bottom rests on the ground.
			var sx := 0.16
			var fz := 0.14
			return [
				_part(_cyl("eq_rstaff_g", 0.05, 0.06, 2.7), wd, Vector3(sx, 0.0, fz)),
				_part(_box("eq_rstaff_knot", Vector3(0.11, 0.12, 0.11)), wd, Vector3(sx, 0.78, fz)),
				_part(_box("eq_rstaff_perch", Vector3(0.22, 0.05, 0.06)), wd, Vector3(sx, 1.3, fz)),
				_part(_sphere("eq_raven_body", 0.11), rav, Vector3(sx, 1.41, fz), Vector3(1.0, 1.05, 1.5)),
				_part(_sphere("eq_raven_head", 0.07), rav, Vector3(sx, 1.52, fz + 0.1)),
				_part(_cone("eq_raven_beak", 0.028, 0.002, 0.11), gold, Vector3(sx, 1.52, fz + 0.2), Vector3.ONE, Vector3(1.5708, 0, 0)),
				_part(_box("eq_raven_tail", Vector3(0.07, 0.04, 0.22)), rav, Vector3(sx, 1.39, fz - 0.16), Vector3.ONE, Vector3(0.4, 0, 0)),
				_part(_box("eq_raven_wing", Vector3(0.04, 0.14, 0.18)), rav, Vector3(sx + 0.08, 1.41, fz))]
		"wand":
			return [
				_part(_cyl("eq_wand", 0.03, 0.04, 0.6), equip_material("wood"), Vector3(0, 0.24, 0.04)),
				_part(_sphere("eq_wand_tip", 0.07), equip_material("gem", tint), Vector3(0, 0.56, 0.04))]
		"sword":
			return [
				_part(_box("eq_blade_" + mat_key, Vector3(0.07, 0.7, 0.025)), m, Vector3(0, 0.52, 0.04)),
				_part(_box("eq_guard", Vector3(0.24, 0.05, 0.07)), gold, Vector3(0, 0.16, 0.04)),
				_part(_box("eq_grip", Vector3(0.05, 0.18, 0.05)), dark, Vector3(0, 0.05, 0.04)),
				_part(_box("eq_pommel", Vector3(0.07, 0.06, 0.06)), gold, Vector3(0, -0.05, 0.04))]
		"dagger":
			return [
				_part(_box("eq_dblade_" + mat_key, Vector3(0.06, 0.34, 0.02)), m, Vector3(0, 0.3, 0.04)),
				_part(_box("eq_dguard", Vector3(0.16, 0.04, 0.06)), gold, Vector3(0, 0.12, 0.04)),
				_part(_box("eq_dgrip", Vector3(0.05, 0.14, 0.05)), dark, Vector3(0, 0.03, 0.04))]
		"axe":
			return [
				_part(_cyl("eq_haft", 0.03, 0.04, 0.8), equip_material("wood"), Vector3(0, 0.3, 0.04)),
				_part(_box("eq_axehead_" + mat_key, Vector3(0.06, 0.26, 0.22)), m, Vector3(0.1, 0.6, 0.04))]
		"mace":
			return [
				_part(_cyl("eq_macehaft", 0.035, 0.045, 0.7), dark, Vector3(0, 0.28, 0.04)),
				_part(_sphere("eq_macehead_" + mat_key, 0.13), m, Vector3(0, 0.64, 0.04))]
		"spear":
			return [
				_part(_cyl("eq_spearhaft", 0.03, 0.035, 1.6), equip_material("wood"), Vector3(0, 0.5, 0.04)),
				_part(_cone("eq_spearpt_" + mat_key, 0.07, 0.005, 0.28), m, Vector3(0, 1.42, 0.04))]
		"bow":
			var wood2 := equip_material("wood")
			return [
				_part(_box("eq_bow_u", Vector3(0.04, 0.5, 0.06)), wood2, Vector3(0, 0.28, 0.06), Vector3.ONE, Vector3(-0.32, 0, 0)),
				_part(_box("eq_bow_l", Vector3(0.04, 0.5, 0.06)), wood2, Vector3(0, -0.28, 0.06), Vector3.ONE, Vector3(0.32, 0, 0)),
				_part(_box("eq_bowstr", Vector3(0.012, 1.0, 0.012)), equip_material("cloth", Color(0.9, 0.9, 0.85)), Vector3(0, 0, -0.02))]
		"shield":
			return [
				_part(_box("eq_shield_" + mat_key, Vector3(0.36, 0.46, 0.06)), m, Vector3(0, 0, 0.04)),
				_part(_box("eq_shield_boss", Vector3(0.12, 0.12, 0.04)), gold, Vector3(0, 0, 0.09))]
		"helm":
			# Epic horned great-helm, sized to wrap the head (never crops). A full dome,
			# a brow ridge over a dark visor slit, a crest fin, and two big curved horns.
			var bone := equip_material("bone")
			var hw := headb.x
			var hh := headb.y
			var hd := headb.z
			var ph: Array = [
				_part(_box("eq_gh_dome", Vector3(hw + 0.1, hh + 0.08, hd + 0.1)), m, Vector3(0, 0.06, 0)),
				# Tapered face mask (narrower at the chin) so it reads as a forged helm.
				_part(_box("eq_gh_face", Vector3(hw - 0.04, hh * 0.5, hd + 0.06)), m, Vector3(0, -hh * 0.22, 0.03)),
				_part(_box("eq_gh_brow", Vector3(hw + 0.12, 0.08, hd + 0.07)), gold, Vector3(0, hh * 0.18, 0.02)),
				_part(_box("eq_gh_visor", Vector3(hw * 0.72, 0.06, 0.05)), dark, Vector3(0, hh * 0.04, hd * 0.5 + 0.07)),
				_part(_box("eq_gh_nasal", Vector3(0.07, hh * 0.34, 0.05)), gold, Vector3(0, -hh * 0.16, hd * 0.5 + 0.06)),
				_part(_box("eq_gh_crest", Vector3(0.07, 0.2, hd * 0.95)), gold, Vector3(0, hh * 0.58 + 0.04, 0))]
			# Cheek guards angling in toward the chin.
			for cs: int in [-1, 1]:
				ph.append(_part(_box("eq_gh_cheek", Vector3(0.06, hh * 0.4, hd * 0.5)), m, Vector3((hw * 0.5 - 0.01) * cs, -hh * 0.14, hd * 0.3), Vector3.ONE, Vector3(0, 0, 0.18 * cs)))
			# Two heavy horns: a thick base sweeping outward, then curling up to a point.
			for hsd: int in [-1, 1]:
				var bx := (hw * 0.5) * hsd
				ph.append(_part(_cone("eq_horn_b", 0.09, 0.062, 0.24), bone, Vector3(bx, hh * 0.18, 0.0), Vector3.ONE, Vector3(0, 0, -0.5 * hsd)))
				ph.append(_part(_cone("eq_horn_m", 0.062, 0.04, 0.28), bone, Vector3(bx + 0.15 * hsd, hh * 0.44, 0.0), Vector3.ONE, Vector3(0, 0, -0.9 * hsd)))
				ph.append(_part(_cone("eq_horn_t", 0.04, 0.004, 0.3), bone, Vector3(bx + 0.3 * hsd, hh * 0.82, -0.01), Vector3.ONE, Vector3(0, 0, -0.4 * hsd)))
			return ph
		"hood":
			# Sized from the head box so the cowl always covers it.
			var hw := headb.x
			var hh := headb.y
			var hd := headb.z
			return [
				_part(_box("eq_hood", Vector3(hw + 0.1, hh + 0.0, hd + 0.1)), m, Vector3(0, 0.04, -0.02)),
				_part(_box("eq_hood_pt", Vector3(0.16, 0.22, 0.16)), m, Vector3(0, hh * 0.55, -0.1), Vector3.ONE, Vector3(-0.5, 0, 0)),
				_part(_box("eq_hood_drape", Vector3(hw, hh * 0.9, 0.08)), m, Vector3(0, -hh * 0.5, -hd * 0.55))]
		"wizard_hat":
			# Tall pointed witch hat: a wide drooping brim that shadows the face, a
			# cone that bends forward at the tip, and a buckled hat band.
			var band := equip_material("leather")
			return [
				_part(_cone("eq_what_brim", 0.45, 0.34, 0.1), m, Vector3(0, 0.04, 0.02)),
				_part(_cone("eq_what_cone", 0.3, 0.13, 0.42), m, Vector3(0, 0.3, 0)),
				_part(_cone("eq_what_tip", 0.13, 0.01, 0.34), m, Vector3(0, 0.52, 0.16), Vector3.ONE, Vector3(0.7, 0, 0)),
				_part(_box("eq_what_band", Vector3(0.35, 0.08, 0.35)), band, Vector3(0, 0.12, 0)),
				_part(_box("eq_what_buckle", Vector3(0.11, 0.1, 0.04)), gold, Vector3(0, 0.12, 0.19))]
		"chest":
			# Epic full plate, sized to wrap the torso (never crops): a full back/side
			# shell, a sculpted domed breastplate + abs, layered faulds over the hips, a
			# gorget closing the neck, gold trim, and big spiked pauldrons on the shoulders.
			var trimm := equip_material("gold")
			var w := torso.x
			var hh := torso.y
			var d := torso.z
			var pc: Array = [
				_part(_box("eq_pl_shell_" + mat_key, Vector3(w + 0.12, hh + 0.02, d + 0.14)), m, Vector3(0, 0, -0.01)),
				_part(_box("eq_pl_chest_" + mat_key, Vector3(w + 0.09, hh * 0.5, d + 0.18)), m, Vector3(0, hh * 0.16, 0.03)),
				_part(_box("eq_pl_ab_" + mat_key, Vector3(w - 0.02, hh * 0.32, d + 0.14)), m, Vector3(0, -hh * 0.12, 0.03)),
				_part(_box("eq_pl_fauld1_" + mat_key, Vector3(w + 0.06, hh * 0.18, d + 0.16)), m, Vector3(0, -hh * 0.4, 0.0)),
				_part(_box("eq_pl_fauld2_" + mat_key, Vector3(w - 0.04, hh * 0.18, d + 0.12)), m, Vector3(0, -hh * 0.54, 0.0)),
				_part(_box("eq_pl_gorget_" + mat_key, Vector3(w * 0.64, 0.16, d * 0.94)), m, Vector3(0, hh * 0.46, 0.0)),
				_part(_box("eq_pl_collar", Vector3(w * 0.82, 0.08, d + 0.1)), trimm, Vector3(0, hh * 0.33, 0.03)),
				_part(_box("eq_pl_ridge", Vector3(0.06, hh * 0.48, 0.05)), trimm, Vector3(0, hh * 0.02, d * 0.5 + 0.07)),
				_part(_box("eq_pl_emblem", Vector3(0.2, 0.22, 0.05)), trimm, Vector3(0, -hh * 0.02, d * 0.5 + 0.08)),
				_part(_box("eq_pl_belt", Vector3(w + 0.02, 0.09, d + 0.1)), trimm, Vector3(0, -hh * 0.3, 0.0))]
			# Big layered pauldrons: a broad dome + a lower lame skirt, gold rim, big spike.
			for ssd: int in [-1, 1]:
				var px := (shoulder * 0.5) * ssd
				pc.append(_part(_sphere("eq_pauld_dome", 0.27), m, Vector3(px, hh * 0.44, 0.0), Vector3(1.3, 1.0, 1.35)))
				pc.append(_part(_sphere("eq_pauld_lame", 0.23), m, Vector3(px + 0.02 * ssd, hh * 0.28, 0.0), Vector3(1.35, 0.62, 1.4)))
				pc.append(_part(_box("eq_pauld_lip", Vector3(0.42, 0.07, 0.46)), trimm, Vector3(px, hh * 0.2, 0.0)))
				pc.append(_part(_cone("eq_pauld_spike", 0.09, 0.003, 0.42), trimm, Vector3(px + 0.07 * ssd, hh * 0.72, 0.0), Vector3.ONE, Vector3(0, 0, -0.3 * ssd)))
			return pc
		"jerkin":
			# Adventurer's leather vest, sized to wrap the torso (no crop): a jerkin +
			# shoulder yoke, a diagonal bandolier strap, a buckled waist belt and a pouch.
			var hide := equip_material("leather")
			var strap := _mat_from(Color(0.3, 0.2, 0.12), Color(0.18, 0.11, 0.06), Color(0.44, 0.31, 0.18))
			var buckle := equip_material("gold")
			var w := torso.x
			var hh := torso.y
			var d := torso.z
			return [
				_part(_box("eq_jerkin", Vector3(w + 0.06, hh + 0.0, d + 0.06)), hide, Vector3(0, 0.0, 0)),
				_part(_box("eq_jerkin_yoke", Vector3(w + 0.16, 0.16, d + 0.1)), hide, Vector3(0, hh * 0.44, 0)),
				_part(_box("eq_baldric", Vector3(0.09, hh + 0.12, d + 0.06)), strap, Vector3(0, 0.0, 0.0), Vector3.ONE, Vector3(0, 0, 0.5)),
				_part(_box("eq_belt", Vector3(w + 0.1, 0.1, d + 0.08)), strap, Vector3(0, -hh * 0.42, 0)),
				_part(_box("eq_belt_buckle", Vector3(0.1, 0.1, 0.04)), buckle, Vector3(0, -hh * 0.42, d * 0.5 + 0.05)),
				_part(_box("eq_pouch", Vector3(0.13, 0.14, 0.08)), hide, Vector3(0.18, -hh * 0.5, d * 0.5 + 0.03))]
		"robe_top":
			# A full robe that encloses the torso, a shoulder mantle + high collar that
			# hide the neck gap, a red scarf, and a couple of belt straps for layering.
			var trim := equip_material(mat_key, tint.darkened(0.22) if tint.a > 0.0 else Color(0, 0, 0, 0))
			var scarf := _mat_from(Color(0.74, 0.16, 0.14), Color(0.5, 0.08, 0.08), Color(0.86, 0.32, 0.26))
			# Sized to wrap the torso generously (cloth drapes a touch looser than plate).
			var w := torso.x + 0.1
			var hh := torso.y + 0.08
			var d := torso.z + 0.1
			return [
				_part(_box("eq_robetop", Vector3(w, hh, d)), m, Vector3(0, 0.02, 0)),
				_part(_box("eq_robe_mantle", Vector3(w + 0.1, 0.2, d + 0.06)), trim, Vector3(0, hh * 0.44, 0)),
				_part(_box("eq_robe_collar", Vector3(0.26, 0.2, 0.26)), trim, Vector3(0, hh * 0.62, 0)),
				_part(_box("eq_robe_scarf", Vector3(0.14, 0.24, 0.1)), scarf, Vector3(0, hh * 0.15, d * 0.5 + 0.01)),
				_part(_box("eq_robe_strap1", Vector3(w + 0.02, 0.05, d + 0.02)), trim, Vector3(0, -hh * 0.18, 0)),
				_part(_box("eq_robe_strap2", Vector3(w + 0.02, 0.05, d + 0.02)), trim, Vector3(0, -hh * 0.36, 0))]
		"robe_bottom":
			# Long, wide skirt that fully covers the legs to the ground, with a darker
			# layered hem, a waist band, and little curled boot tips peeking out front.
			var hem := equip_material(mat_key, tint.darkened(0.24) if tint.a > 0.0 else Color(0, 0, 0, 0))
			var boot := equip_material("leather")
			return [
				_part(_cone("eq_robebot", 0.52, 0.26, 1.0), m, Vector3(0, -0.5, 0)),
				_part(_cone("eq_robe_hem", 0.56, 0.5, 0.13), hem, Vector3(0, -0.97, 0)),
				_part(_cone("eq_robe_waist", 0.4, 0.34, 0.1), hem, Vector3(0, -0.04, 0)),
				_part(_box("eq_robe_boot", Vector3(0.13, 0.1, 0.2)), boot, Vector3(-0.12, -0.97, 0.15)),
				_part(_box("eq_robe_boot", Vector3(0.13, 0.1, 0.2)), boot, Vector3(0.12, -0.97, 0.15))]
		"cape":
			# Hangs from the shoulders (socket_back) and drapes down past the hips, as
			# wide as the shoulders — scales to the wearer so it never sits oddly.
			var cw := shoulder * 0.92
			var cl := torso.y + 0.55
			return [
				_part(_box("eq_cape", Vector3(cw, cl, 0.05)), m, Vector3(0, -cl * 0.36, -0.03), Vector3.ONE, Vector3(0.16, 0, 0)),
				_part(_box("eq_cape_clasp", Vector3(cw * 0.5, 0.08, 0.06)), equip_material("gold"), Vector3(0, 0.16, -0.02))]
		_:
			return []


## A cape built as a short vertical CHAIN of segment pivots (cape_seg0 -> cape_seg1
## -> ...), each holding one plate, hung from the shoulders. The renderer ripples a
## cheap traveling sine wave down the chain (a few sin() calls, no physics, no
## per-vertex work) so the cape billows and trails — cheap enough for potato builds.
## Sized to the wearer (shoulder width, torso length) so it drapes right on any rig.
static func build_cape(m: Material, profile: Dictionary) -> Node3D:
	var shoulder: float = float(profile.get("shoulder", 0.64))
	var cw := shoulder * 1.02
	# A long, full cape: enough links to reach the ground and pool/drag behind the
	# heels. The renderer's _flow_cape curves it down (gravity) and ripples it gently.
	var segs := 6
	var seg_len := 0.3
	var root := Node3D.new()
	# Static gold clasp at the collar.
	var clasp := MeshInstance3D.new()
	clasp.mesh = _box("eq_cape_clasp", Vector3(cw * 0.5, 0.08, 0.06))
	clasp.material_override = equip_material("gold")
	clasp.position = Vector3(0, 0.12, -0.02)
	clasp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(clasp)
	# The chain: each segment hangs off the bottom of the previous one. A gentle flare
	# toward the hem so it reads as a full, heavy, majestic cape.
	var parent := root
	for i: int in segs:
		var pivot := Node3D.new()
		pivot.name = "cape_seg%d" % i
		pivot.position = Vector3(0, 0.06, -0.05) if i == 0 else Vector3(0, -seg_len, 0)
		parent.add_child(pivot)
		var width := cw * (0.94 + 0.04 * float(i))
		var mi := MeshInstance3D.new()
		mi.mesh = _box("eq_cape_seg%d" % i, Vector3(width, seg_len + 0.03, 0.05))
		mi.material_override = m
		mi.position = Vector3(0, -seg_len * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		parent = pivot
	root.set_meta("cape_segments", segs)
	return root


## Beast-folk biped (gnolls): a hunched, muscular hyena-man with a snouted head,
## perked ears, a fur body + loincloth, and long arms. Uses the humanoid leg_l/r
## + arm_l/r pivots so it walks and swings like a biped. Faces +Z.
static func beastman_rig(spec: Dictionary) -> Node3D:
	var fur: Color = spec.get("fur", Color(0.55, 0.45, 0.32))
	var furm := _mat_from(fur, fur.darkened(0.38), fur.lightened(0.2))
	var furd := _mat_from(fur.darkened(0.3), fur.darkened(0.52), fur.darkened(0.1))
	var light := _mat_from(fur.lightened(0.24), fur.darkened(0.1), fur.lightened(0.4))
	var cloth := _mat_from(Color(0.34, 0.27, 0.19), Color(0.2, 0.15, 0.1), Color(0.46, 0.37, 0.26))
	var claw := _mat_from(Color(0.16, 0.14, 0.13), Color(0.08, 0.07, 0.06), Color(0.26, 0.23, 0.2))
	var eyec := _mat_from(Color(0.95, 0.55, 0.12), Color(0.7, 0.32, 0.05), Color(1.0, 0.78, 0.3))
	var root := Node3D.new()
	# Powerful digitigrade legs with a knee joint (so they bend into a sneaky crouch).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.16 * side, 0.86, 0), Vector3(0.22, 0.4, 0.24), Vector3(0.16, 0.36, 0.18), furm, "gnleg")
		_attach(knee, _box("gn_paw", Vector3(0.2, 0.12, 0.3)), claw, Vector3(0, -0.4, 0.08))
	_attach(root, _box("gn_loin", Vector3(0.48, 0.28, 0.32)), cloth, Vector3(0, 0.84, 0))
	# The whole brute torso+head hangs off a `spine` pivot at the hips so it can curl
	# into a heavy hunched back (legs stay planted). Child Y is spine-local (world-0.88).
	var spine := _limb(root, "spine", Vector3(0, 0.88, 0))
	# Broad bare torso; lighter belly fur.
	_attach(spine, _box("gn_chest", Vector3(0.52, 0.46, 0.34)), furm, Vector3(0, 0.32, 0.06))
	_attach(spine, _box("gn_belly", Vector3(0.4, 0.3, 0.28)), light, Vector3(0, 0.12, 0.1))
	_attach(spine, _box("gn_shoulders", Vector3(0.64, 0.2, 0.36)), furm, Vector3(0, 0.54, 0.02))
	# Mane on a pivot so the hair-sway swings it down the back of the neck.
	var mane := _limb(spine, "mane", Vector3(0, 0.68, -0.06))
	_attach(mane, _box("gn_mane", Vector3(0.16, 0.34, 0.2)), furd, Vector3(0, -0.06, -0.06), Vector3.ONE, Vector3(0.3, 0, 0))
	# Forward-thrust neck + a hyena head with a long snout and a dark nose.
	_attach(spine, _box("gn_neck", Vector3(0.22, 0.22, 0.26)), furm, Vector3(0, 0.62, 0.12))
	_attach(spine, _box("gn_skull", Vector3(0.3, 0.3, 0.32)), furm, Vector3(0, 0.74, 0.18))
	_attach(spine, _box("gn_snout", Vector3(0.18, 0.16, 0.24)), light, Vector3(0, 0.68, 0.4))
	_attach(spine, _box("gn_nose", Vector3(0.1, 0.09, 0.07)), claw, Vector3(0, 0.7, 0.53))
	_attach(spine, _box("gn_jaw", Vector3(0.16, 0.06, 0.2)), furd, Vector3(0, 0.61, 0.42))
	# Perked, pointed ears + fierce orange eyes.
	for sx: int in [-1, 1]:
		_attach(spine, _cone("gn_ear", 0.08, 0.01, 0.2), furm, Vector3(0.12 * sx, 0.94, 0.12), Vector3.ONE, Vector3(-0.2, 0, 0.3 * sx))
		_attach(spine, _box("gn_eye", Vector3(0.05, 0.05, 0.05)), eyec, Vector3(0.08 * sx, 0.76, 0.34))
	# Long, heavy arms with an elbow joint: fur upper, darker forearm, clawed hand.
	for side2: int in [-1, 1]:
		var el := _biped_arm(spine, side2, Vector3(0.34 * side2, 0.54, 0.02), Vector3(0.17, 0.32, 0.19), Vector3(0.15, 0.3, 0.16), furm, furd, "gnarm")
		_attach(el, _box("gn_hand", Vector3(0.17, 0.15, 0.2)), claw, Vector3(0, -0.34, 0.02))
		_socket(el, "socket_mainhand" if side2 > 0 else "socket_offhand", Vector3(0.04 * side2, -0.42, 0.12), Vector3(-0.1, 0, -0.08 * side2))
	_socket(spine, "socket_head", Vector3(0, 0.74, 0.18))
	_socket(spine, "socket_body", Vector3(0, 0.32, 0.06))
	_socket(root, "socket_legs", Vector3(0, 0.86, 0))
	_socket(spine, "socket_back", Vector3(0, 0.46, -0.14))
	root.set_meta("body_profile", {
		"torso": Vector3(0.58, 0.62, 0.42), "head": Vector3(0.36, 0.36, 0.4),
		"shoulder": 0.72, "hips": Vector3(0.48, 0.28, 0.32)})
	return root


# ---------------------------------------------------------------- shadows ----

## A soft round blob shadow (A Short Hike style): a flat ground quad with a radial
## dark-to-clear gradient, dropped under each mover so it reads as grounded. The
## renderer scales/orients it per creature and keeps it pinned to the ground.
static func blob_shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shadow_quad()
	mi.material_override = _shadow_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ground-plane offset a static prop's shadow is dropped at — pushed down-light
## (away from the warm upper-right sun) so it falls down-left, matching movers.
const SHADOW_DROP := Vector2(-0.28, -0.34)

## A blob-shadow PART for static raised props (trees/houses): a flat soft quad on
## the ground, pushed down-light. Batches with all other prop shadows into one
## MultiMesh. `radius` ~ the prop's ground footprint; `lon` stretches it a touch
## along the shadow's fall for a longer afternoon cast.
static func _shadow_part(radius: float, lon := 1.25, extra := Vector2.ZERO) -> Dictionary:
	var off := SHADOW_DROP + extra
	return _part(_shadow_quad(), _shadow_mat(), Vector3(off.x, 0.03, off.y), Vector3(radius * 2.0, 1.0, radius * 2.0 * lon))


static func _shadow_quad() -> Mesh:
	if not _mesh_cache.has("blob_shadow"):
		var m := PlaneMesh.new()
		m.size = Vector2.ONE
		_mesh_cache["blob_shadow"] = m
	return _mesh_cache["blob_shadow"]


static func _shadow_mat() -> StandardMaterial3D:
	if _shadow_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# MULTIPLY blend: the shadow darkens whatever ground colour it sits on (rather
		# than compositing a fixed dark tint), so after the palette snap it reads as a
		# DARKER SHADE OF THE SAME HUE — natural green/brown shadows, never a muddy
		# pink. The radial texture's alpha shapes a soft round blob (clear at the rim).
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.albedo_texture = _shadow_texture()
		m.albedo_color = Color(0.38, 0.4, 0.34, 1.0)   # multiply factor at the blob centre
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shadow_material = m
	return _shadow_material


## Radial alpha falloff (opaque centre -> clear rim) so the blob has soft edges.
static func _shadow_texture() -> ImageTexture:
	if _shadow_tex_cache == null:
		var n := 48
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := float(n) * 0.5
		for y: int in n:
			for x: int in n:
				var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_shadow_tex_cache = ImageTexture.create_from_image(img)
	return _shadow_tex_cache


# -------------------------------------------------------- enemy creatures ----
# Real per-species rigs for the early-game enemies, built from two reusable
# templates (a four-legged beast + a two-legged bird) plus the humanoid figure.
# Each rig faces +Z (the mover's travel direction) and tags itself with a
# "body3d" meta so the renderer drives the matching gait, and a "base_scale" the
# animator multiplies its squash by (size + boss bump survive per-frame scaling).

## Map an enemy name to one of the body templates. Mirrors the 2D species art so
## a Wolf is a wolf in both renderers. Order matters: wolf-mounts read as wolves.
static func enemy_body_type(name: String) -> String:
	var n := name.to_lower()
	for kw: String in ["wolf", "hound", "dog", "fox", "amaruq", "jackal"]:
		if n.contains(kw):
			return "wolf"
	for kw: String in ["boar", "hog", "pig", "swine"]:
		if n.contains(kw):
			return "boar"
	if n.contains("cow") or n.contains("ox") or n.contains("bull") or n.contains("cattle") or n.contains("calf"):
		return "cow"
	if n.contains("sheep") or n.contains("ram") or n.contains("lamb"):
		return "sheep"
	if n.contains("goat") or n.contains("kid"):
		return "goat"
	if n.contains("mole"):
		return "mole"
	if n.contains("chicken") or n.contains("hen") or n.contains("rooster") or n.contains("fowl") or n.contains("chick"):
		return "bird"
	return "humanoid"


## Build the right rig for an enemy node and tag it for animation.
static func enemy_rig(e: Node) -> Node3D:
	var name := str(e.get("label"))
	if name.is_empty():
		name = str(Dictionary(e.get("action")).get("name", ""))
	var type := enemy_body_type(name)
	var n := name.to_lower()
	var boss := bool(e.get("is_boss"))
	var rider := n.contains("rider")
	# Per-species base size (a human ≈ 1.0): cows tower, chickens and moles are small.
	var size := 1.0
	var node: Node3D
	match type:
		"wolf":
			var dark := n.contains("black") or n.contains("toxic") or n.contains("cave")
			var hide := Color(0.30, 0.31, 0.34) if dark else Color(0.55, 0.55, 0.60)
			node = quadruped_rig({"hide": hide, "belly": hide.lightened(0.32), "ears": "perk", "tail": "bushy", "snout": 0.28})
			size = 1.2 if n.contains("amaruq") else 1.0
		"boar":
			var pinkish := n.contains("pig")
			var hide := Color(0.90, 0.66, 0.70) if pinkish else Color(0.40, 0.31, 0.27)
			node = quadruped_rig({
				"hide": hide, "belly": hide.darkened(0.12), "ears": "perk", "tail": "short",
				"snout": 0.22, "tusks": not pinkish, "humped": not pinkish, "snout_pink": pinkish})
			size = 0.9 if pinkish else 1.05
		"cow":
			node = quadruped_rig({"hide": Color(0.66, 0.46, 0.32), "belly": Color(0.84, 0.81, 0.76), "ears": "floppy", "horns": "cow", "tail": "tuft", "snout": 0.2})
			size = 1.4
		"sheep":
			node = quadruped_rig({"hide": Color(0.92, 0.91, 0.88), "belly": Color(0.88, 0.87, 0.84), "ears": "floppy", "tail": "short", "snout": 0.14, "wool": true, "head_dark": true})
			size = 0.98
		"goat":
			node = quadruped_rig({"hide": Color(0.80, 0.78, 0.80), "belly": Color(0.88, 0.87, 0.86), "ears": "perk", "horns": "goat", "tail": "short", "snout": 0.16, "beard": true})
			size = 0.9
		"mole":
			node = quadruped_rig({"hide": Color(0.34, 0.27, 0.31), "belly": Color(0.46, 0.39, 0.42), "ears": "none", "tail": "short", "snout": 0.22})
			size = 0.6
		"bird":
			var brown := n.contains("mumma") or n.contains("momma")
			node = bird_rig({"body": Color(0.84, 0.72, 0.58) if brown else Color(0.93, 0.89, 0.80)})
			size = 0.62
		_:
			type = "humanoid"
			if n.contains("gnoll"):
				var dark_gn := n.contains("toxic") or n.contains("dark")
				node = beastman_rig({"fur": Color(0.42, 0.45, 0.36) if dark_gn else Color(0.58, 0.47, 0.33)})
				size = 1.02
			elif n.contains("goblin") or n.contains("hob"):
				node = figure_rig(Color(0.40, 0.31, 0.23), Color(0.44, 0.66, 0.34))
				size = 0.86
			elif n.contains("skelet") or n.contains("bone"):
				node = figure_rig(Color(0.62, 0.60, 0.56), Color(0.86, 0.85, 0.80))
			else:
				node = figure_rig(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a"))
	size *= _variant_size(n)
	if rider and type == "wolf":
		_add_rider(node)
	node.set_meta("body3d", type)
	node.set_meta("base_scale", size * (1.22 if boss else 1.0))
	# Characteristic posture: goblins stoop forward with arms hanging low; gnolls
	# (beastman) are hunched brutes; skeletons lurch a little; others stand looser.
	# Posture is a curved BACK (hunch at the spine), not a whole-body forward tilt:
	# `lean` stays near-zero so they don't look like they're falling forward; `hunch`
	# rounds the upper spine for a natural stoop.
	if type == "humanoid":
		if n.contains("goblin") or n.contains("hob"):
			# Goblins get their own twitchy-skulk gait (see _pose_goblin); the lean/
			# hunch/crouch metas are only used by the fallback humanoid pose.
			node.set_meta("gait", "goblin")
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.42)
			node.set_meta("arm_rest", 0.34)
			node.set_meta("crouch", 0.3)
		elif n.contains("skelet") or n.contains("bone"):
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.16)
			node.set_meta("arm_rest", 0.12)
			node.set_meta("crouch", 0.18)
		else:
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.12)
			node.set_meta("arm_rest", 0.12)
			node.set_meta("crouch", 0.14)
		if n.contains("gnoll"):   # beastman gets its own predatory-prowl gait (_pose_gnoll)
			node.set_meta("gait", "gnoll")
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.5)
			node.set_meta("arm_rest", 0.28)
			node.set_meta("crouch", 0.5)
	# Visible gear from the enemy's combat archetype (skipped on rigs without the
	# matching sockets — beasts/birds just show nothing).
	var loadout := EquipLoadout.for_enemy(name, int(Dictionary(e.get("action")).get("level", 1)))
	apply_equipment(node, loadout)
	# A staff-wielder grips its planted staff (mainhand reaches forward-down).
	var mainhand: Dictionary = loadout.get("mainhand", {})
	if str(mainhand.get("kind", "")) in ["staff", "raven_staff", "wand"]:
		node.set_meta("pose", "staff")
	return node


## Name-based size multiplier layered on the per-species base: 'Giant'/'Mega'/
## 'Dire' tower, 'Mumma'/'Momma'/'Alpha' are bigger parents, young ones shrink.
static func _variant_size(n: String) -> float:
	for kw: String in ["giant", "mega", "great", "elder", "ancient", "king", "dire"]:
		if n.contains(kw):
			return 1.35
	for kw2: String in ["mumma", "momma", "mother", "queen", "alpha"]:
		if n.contains(kw2):
			return 1.24
	for kw3: String in ["brawler", "brute", "big"]:
		if n.contains(kw3):
			return 1.12
	for kw4: String in ["baby", "young", "pup", "runt", "mini", "tiny"]:
		if n.contains(kw4):
			return 0.72
	return 1.0


## Reusable four-legged beast. Legs hang off hip pivots (leg_fl/leg_fr/leg_bl/
## leg_br) and the tail off `tail`, so the gait can swing them. spec keys: hide,
## belly (Color), snout (len), ears (perk|floppy|none), horns (cow|goat|none),
## tail (short|bushy|tuft|none), and flags wool/humped/tusks/beard/head_dark.
static func quadruped_rig(spec: Dictionary) -> Node3D:
	var hide: Color = spec.get("hide", Color(0.6, 0.5, 0.4))
	var belly: Color = spec.get("belly", hide.lightened(0.2))
	var snout_len: float = float(spec.get("snout", 0.2))
	var hidem := _mat_from(hide, hide.darkened(0.34), hide.lightened(0.2))
	var bellym := _mat_from(belly, belly.darkened(0.3), belly.lightened(0.18))
	var darkm := _mat_from(hide.darkened(0.42), hide.darkened(0.6), hide.darkened(0.16))
	var eyem := _mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.12, 0.12, 0.14))
	var head_dark: bool = bool(spec.get("head_dark", false))
	var headm := darkm if head_dark else hidem
	var root := Node3D.new()
	# Torso — a fluffy sphere for woolly beasts, a chunky box otherwise.
	if bool(spec.get("wool", false)):
		_attach(root, _sphere("q_wool", 0.44), hidem, Vector3(0, 0.66, -0.02), Vector3(1.2, 1.0, 1.4))
	else:
		_attach(root, _box("q_body", Vector3(0.46, 0.44, 0.96)), hidem, Vector3(0, 0.62, 0))
		_attach(root, _box("q_belly", Vector3(0.4, 0.2, 0.84)), bellym, Vector3(0, 0.47, 0))
	if bool(spec.get("humped", false)):
		# A subtle shoulder rise (boar), blended into the back rather than a saddle.
		_attach(root, _sphere("q_hump", 0.26), hidem, Vector3(0, 0.74, 0.2), Vector3(1.04, 0.62, 0.9))
	# Neck + head at the front (+Z), with a snout, eyes, optional features.
	_attach(root, _box("q_neck", Vector3(0.26, 0.3, 0.3)), hidem, Vector3(0, 0.66, 0.5))
	_attach(root, _box("q_head", Vector3(0.34, 0.34, 0.36)), headm, Vector3(0, 0.78, 0.66))
	if snout_len > 0.0:
		var snm := _mat_from(Color(0.9, 0.62, 0.66), Color(0.7, 0.42, 0.46), Color(0.95, 0.74, 0.78)) if bool(spec.get("snout_pink", false)) else headm
		_attach(root, _box("q_snout_%d" % int(snout_len * 100), Vector3(0.22, 0.16, snout_len)), snm, Vector3(0, 0.71, 0.82 + snout_len * 0.4))
	_attach(root, _box("q_eye", Vector3(0.05, 0.05, 0.05)), eyem, Vector3(0.1, 0.84, 0.82))
	_attach(root, _box("q_eye", Vector3(0.05, 0.05, 0.05)), eyem, Vector3(-0.1, 0.84, 0.82))
	match str(spec.get("ears", "none")):
		"perk":
			for sx: int in [-1, 1]:
				_attach(root, _cone("q_ear_perk", 0.09, 0.01, 0.18), headm, Vector3(0.13 * sx, 0.98, 0.58), Vector3.ONE, Vector3(-0.2, 0, 0.3 * sx))
		"floppy":
			for sx2: int in [-1, 1]:
				_attach(root, _box("q_ear_flop", Vector3(0.08, 0.2, 0.1)), headm, Vector3(0.2 * sx2, 0.78, 0.62), Vector3.ONE, Vector3(0, 0, 0.5 * sx2))
	match str(spec.get("horns", "none")):
		"cow":
			var hornm := _mat_from(Color(0.86, 0.82, 0.72), Color(0.62, 0.58, 0.5), Color(0.95, 0.92, 0.84))
			for sx3: int in [-1, 1]:
				_attach(root, _cone("q_horn_cow", 0.06, 0.01, 0.2), hornm, Vector3(0.16 * sx3, 0.96, 0.6), Vector3.ONE, Vector3(0, 0, 0.7 * sx3))
		"goat":
			var hornm2 := _mat_from(Color(0.55, 0.5, 0.46), Color(0.36, 0.32, 0.3), Color(0.68, 0.63, 0.58))
			for sx4: int in [-1, 1]:
				_attach(root, _cone("q_horn_goat", 0.05, 0.01, 0.28), hornm2, Vector3(0.1 * sx4, 0.96, 0.52), Vector3.ONE, Vector3(1.1, 0, 0.15 * sx4))
	if bool(spec.get("tusks", false)):
		var tuskm := _mat_from(Color(0.9, 0.88, 0.8), Color(0.7, 0.68, 0.6), Color(0.96, 0.95, 0.9))
		for sx5: int in [-1, 1]:
			_attach(root, _cone("q_tusk", 0.03, 0.005, 0.12), tuskm, Vector3(0.09 * sx5, 0.66, 0.9), Vector3.ONE, Vector3(-0.6, 0, 0))
	if bool(spec.get("beard", false)):
		_attach(root, _box("q_beard", Vector3(0.1, 0.18, 0.06)), bellym, Vector3(0, 0.6, 0.78))
	_add_tail(root, str(spec.get("tail", "none")), hidem, darkm)
	# Four legs at the corners, each with a knee joint so the trot flexes the legs
	# instead of swinging stiff posts. hip pivots leg_fl/fr/bl/br, knees knee_fl/...
	for ld: Array in [["leg_fl", "knee_fl", -0.2, 0.32], ["leg_fr", "knee_fr", 0.2, 0.32], ["leg_bl", "knee_bl", -0.2, -0.32], ["leg_br", "knee_br", 0.2, -0.32]]:
		var knee := _joint_limb(root, str(ld[0]), str(ld[1]), Vector3(float(ld[2]), 0.46, float(ld[3])), Vector3(0.14, 0.24, 0.16), Vector3(0.13, 0.22, 0.14), hidem, "qleg")
		_attach(knee, _box("q_hoof", Vector3(0.15, 0.1, 0.17)), darkm, Vector3(0, -0.24, 0.02))
	# Beasts only support a body slot (barding/saddle) — no hands/head gear.
	_socket(root, "socket_body", Vector3(0, 0.66, 0))
	return root


static func _add_tail(root: Node3D, style: String, hidem: Material, darkm: Material) -> void:
	if style == "none":
		return
	var tail := _limb(root, "tail", Vector3(0, 0.66, -0.5))
	match style:
		"short":
			_attach(tail, _box("q_tail_s", Vector3(0.1, 0.1, 0.24)), hidem, Vector3(0, -0.02, -0.1), Vector3.ONE, Vector3(0.5, 0, 0))
		"bushy":
			_attach(tail, _cone("q_tail_b", 0.13, 0.03, 0.4), hidem, Vector3(0, 0.0, -0.2), Vector3.ONE, Vector3(2.3, 0, 0))
		"tuft":
			_attach(tail, _box("q_tail_t", Vector3(0.06, 0.34, 0.06)), hidem, Vector3(0, -0.16, 0))
			_attach(tail, _sphere("q_tail_tuft", 0.08), darkm, Vector3(0, -0.32, 0))


static func _add_rider(node: Node3D) -> void:
	var rskin := _mat_from(Color(0.44, 0.66, 0.34), Color(0.3, 0.5, 0.24), Color(0.56, 0.78, 0.42))
	var rcloth := _mat_from(Color(0.4, 0.3, 0.22), Color(0.28, 0.2, 0.14), Color(0.52, 0.42, 0.3))
	_attach(node, _box("r_torso", Vector3(0.26, 0.32, 0.22)), rcloth, Vector3(0, 1.06, -0.04))
	_attach(node, _box("r_head", Vector3(0.22, 0.22, 0.22)), rskin, Vector3(0, 1.32, -0.04))
	for sx: int in [-1, 1]:
		_attach(node, _cone("r_ear", 0.05, 0.005, 0.13), rskin, Vector3(0.15 * sx, 1.34, -0.04), Vector3.ONE, Vector3(0, 0, 0.6 * sx))


## Reusable two-legged bird (chicken). Legs hang off leg_l/leg_r hip pivots.
static func bird_rig(spec: Dictionary) -> Node3D:
	var body: Color = spec.get("body", Color(0.93, 0.89, 0.8))
	var comb: Color = spec.get("comb", Color(0.8, 0.2, 0.16))
	var beak: Color = spec.get("beak", Color(0.92, 0.62, 0.18))
	var bodym := _mat_from(body, body.darkened(0.3), body.lightened(0.16))
	var combm := _mat_from(comb, comb.darkened(0.3), comb.lightened(0.2))
	var beakm := _mat_from(beak, beak.darkened(0.3), beak.lightened(0.2))
	var legm := _mat_from(Color(0.9, 0.55, 0.18), Color(0.6, 0.35, 0.1), Color(0.95, 0.7, 0.3))
	var eyem := _mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.12, 0.12, 0.14))
	var root := Node3D.new()
	_attach(root, _sphere("b_body", 0.26), bodym, Vector3(0, 0.36, -0.02), Vector3(1.0, 1.05, 1.25))
	_attach(root, _sphere("b_head", 0.17), bodym, Vector3(0, 0.56, 0.14))
	_attach(root, _cone("b_beak", 0.07, 0.005, 0.16), beakm, Vector3(0, 0.55, 0.32), Vector3.ONE, Vector3(1.5708, 0, 0))
	_attach(root, _box("b_comb", Vector3(0.06, 0.11, 0.16)), combm, Vector3(0, 0.72, 0.12))
	_attach(root, _box("b_wattle", Vector3(0.05, 0.08, 0.04)), combm, Vector3(0, 0.47, 0.27))
	_attach(root, _box("b_eye", Vector3(0.04, 0.04, 0.04)), eyem, Vector3(0.09, 0.58, 0.24))
	_attach(root, _box("b_eye", Vector3(0.04, 0.04, 0.04)), eyem, Vector3(-0.09, 0.58, 0.24))
	_attach(root, _box("b_tail", Vector3(0.2, 0.16, 0.1)), bodym, Vector3(0, 0.46, -0.26), Vector3.ONE, Vector3(-0.5, 0, 0))
	_attach(root, _box("b_wing", Vector3(0.07, 0.18, 0.26)), bodym, Vector3(0.24, 0.4, -0.02))
	_attach(root, _box("b_wing", Vector3(0.07, 0.18, 0.26)), bodym, Vector3(-0.24, 0.4, -0.02))
	for sx: int in [-1, 1]:
		var leg := _limb(root, "leg_l" if sx < 0 else "leg_r", Vector3(0.1 * sx, 0.24, 0))
		_attach(leg, _box("b_leg", Vector3(0.05, 0.24, 0.05)), legm, Vector3(0, -0.12, 0))
		_attach(leg, _box("b_foot", Vector3(0.14, 0.04, 0.16)), legm, Vector3(0, -0.24, 0.03))
	return root


static func _attach(parent: Node3D, mesh: Mesh, mat: Material, off: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = off
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)


static func _limb(parent: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pivot_name
	n.position = pos
	parent.add_child(n)
	return n


## A two-segment limb: an upper bone on a named pivot + a lower bone on a named
## joint pivot nested under it, so the renderer can flex the joint (knee/elbow/hock).
## Returns the joint node so the caller attaches the foot/hand below it.
static func _joint_limb(root: Node3D, pivot: String, joint: String, base: Vector3, upper: Vector3, lower: Vector3, mat: Material, key: String) -> Node3D:
	var p := _limb(root, pivot, base)
	_attach(p, _box(key + "_up", upper), mat, Vector3(0, -upper.y * 0.5, 0))
	var j := _limb(p, joint, Vector3(0, -upper.y, 0))
	_attach(j, _box(key + "_lo", lower), mat, Vector3(0, -lower.y * 0.5, 0.01))
	return j


## A two-segment leg (thigh on a leg_l/leg_r hip pivot + shin on a knee_l/knee_r
## pivot) for the bent-leg walk and crouch. Returns the knee node for the foot/boot.
static func _biped_leg(root: Node3D, side: int, hip: Vector3, thigh: Vector3, shin: Vector3, mat: Material, key: String) -> Node3D:
	return _joint_limb(root, "leg_l" if side < 0 else "leg_r", "knee_l" if side < 0 else "knee_r", hip, thigh, shin, mat, key)


## A two-segment arm: an upper arm on a shoulder pivot (arm_l/arm_r) + a forearm on
## an elbow pivot (elbow_l/elbow_r) so the renderer can bend the elbow. Returns the
## elbow node so the caller attaches the hand and (for the main hand) a weapon socket.
static func _biped_arm(root: Node3D, side: int, shoulder: Vector3, upper: Vector3, fore: Vector3, upper_mat: Material, fore_mat: Material, key: String) -> Node3D:
	var sh := _limb(root, "arm_l" if side < 0 else "arm_r", shoulder)
	_attach(sh, _box(key + "_up", upper), upper_mat, Vector3(0, -upper.y * 0.5, 0))
	var el := _limb(sh, "elbow_l" if side < 0 else "elbow_r", Vector3(0, -upper.y, 0))
	_attach(el, _box(key + "_fo", fore), fore_mat, Vector3(0, -fore.y * 0.5, 0))
	return el


# ------------------------------------------------------------------ helpers ----

static func _part(mesh: Mesh, mat: Material, off: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> Dictionary:
	return {"mesh": mesh, "mat": mat, "off": off, "scl": scl, "rot": rot}


static func _cyl(key: String, top: float, bot: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bot
		m.height = h
		m.radial_segments = 7
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cone(key: String, bot: float, top: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bot
		m.height = h
		m.radial_segments = 8
		_mesh_cache[key] = m
	return _mesh_cache[key]


## A bell-shaped fir whorl. Several radial rings form a gently concave cone that
## pinches at the neck, swells through the branch mass, then flares into a soft
## drooping brim. Smooth-group normals keep the broad low-poly facets while
## avoiding the old stack of flat diamond plates.
static func _fir_bough(key: String, radius: float, height: float, tips: int, droop: float) -> Mesh:
	if not _mesh_cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		var ring_specs := [
			[0.035, 0.55],
			[0.16, 0.28],
			[0.50, 0.02],
			[0.86, -0.20],
			[1.00, -0.32],
		]
		var rings: Array = []
		for ri: int in ring_specs.size():
			var spec: Array = ring_specs[ri]
			var ring: Array[Vector3] = []
			for i: int in tips:
				var a := float(i) / float(tips) * TAU
				var tip_scale := 1.0
				var y := height * float(spec[1])
				if ri == ring_specs.size() - 1:
					tip_scale = 1.0 if i % 2 == 0 else 0.9
					y -= droop if i % 2 == 0 else droop * 0.45
				var rr := radius * float(spec[0]) * tip_scale
				ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			rings.append(ring)
		for ri: int in range(rings.size() - 1):
			var upper: Array = rings[ri]
			var lower: Array = rings[ri + 1]
			for i: int in tips:
				var n := (i + 1) % tips
				st.add_vertex(upper[i])
				st.add_vertex(lower[n])
				st.add_vertex(lower[i])
				st.add_vertex(upper[i])
				st.add_vertex(upper[n])
				st.add_vertex(lower[n])
		var rim: Array = rings.back()
		var lower_rim: Array[Vector3] = []
		for i: int in tips:
			var a := float(i) / float(tips) * TAU
			var tip_scale := 0.88 if i % 2 == 0 else 0.81
			var y := -height * 0.43 - (droop * 0.72 if i % 2 == 0 else droop * 0.32)
			lower_rim.append(Vector3(cos(a) * radius * tip_scale, y, sin(a) * radius * tip_scale))
		# Fold the brim down and inward so the foliage tier has visible thickness
		# at its silhouette instead of ending in a paper-thin polygon edge.
		for i: int in tips:
			var n := (i + 1) % tips
			st.add_vertex(rim[i])
			st.add_vertex(lower_rim[n])
			st.add_vertex(lower_rim[i])
			st.add_vertex(rim[i])
			st.add_vertex(rim[n])
			st.add_vertex(lower_rim[n])
		var hub := Vector3(0, -height * 0.48, 0)
		for i: int in tips:
			var n := (i + 1) % tips
			st.add_vertex(hub)
			st.add_vertex(lower_rim[i])
			st.add_vertex(lower_rim[n])
		st.generate_normals()
		_mesh_cache[key] = st.commit()
	return _mesh_cache[key]


static func _sphere(key: String, r: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 1.7
		m.radial_segments = 9
		m.rings = 5
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _capsule(key: String, r: float, h: float) -> Mesh:
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 3
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _box(key: String, size: Vector3) -> Mesh:
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _prism(key: String, size: Vector3) -> Mesh:
	if not _mesh_cache.has(key):
		var m := PrismMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _octa(key: String) -> Mesh:
	if not _mesh_cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, -0.6, 0)]
		var f := [[4, 0, 2], [4, 2, 1], [4, 1, 3], [4, 3, 0], [5, 2, 0], [5, 1, 2], [5, 3, 1], [5, 0, 3]]
		for tri: Array in f:
			for vi: int in tri:
				st.add_vertex(v[vi] as Vector3)
		st.generate_normals()
		_mesh_cache[key] = st.commit()
	return _mesh_cache[key]


static func _mat(base_key: String, shadow_key: String, light_key: String) -> ShaderMaterial:
	var ck := base_key + "|" + shadow_key + "|" + light_key
	if not _mat_cache.has(ck):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("base_color", PixelPalette.pal(base_key))
		m.set_shader_parameter("shadow_color", PixelPalette.pal(shadow_key))
		m.set_shader_parameter("light_color", PixelPalette.pal(light_key))
		# Foliage + grass sway in the wind; trunks/stone/walls stay put.
		if base_key.begins_with("foliage") or base_key.begins_with("fir") or base_key.begins_with("leaf") or base_key.begins_with("pine") or base_key.begins_with("hike_grass") or base_key.begins_with("grass") or base_key.begins_with("fern") or base_key.begins_with("reed"):
			m.set_shader_parameter("wind", 0.11)
		_mat_cache[ck] = m
	return _mat_cache[ck]


static func _mat_from(base: Color, shadow: Color, light: Color) -> ShaderMaterial:
	var ck := "%s|%s|%s" % [base, shadow, light]
	if not _mat_cache.has(ck):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("shadow_color", shadow)
		m.set_shader_parameter("light_color", light)
		_mat_cache[ck] = m
	return _mat_cache[ck]
