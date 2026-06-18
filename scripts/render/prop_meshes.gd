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

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
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
		_:
			return []


static func is_moving(e: Node) -> bool:
	return str(e.kind) == "enemy"


static func decor_parts(kind: String) -> Array:
	match kind:
		"flower":
			return [
				_part(_sphere("d_ftuft", 0.16), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.12, 0), Vector3(1.0, 0.7, 1.0)),
				_part(_sphere("d_fhead", 0.1), _mat("gold", "dirt_a", "snow_a"), Vector3(0, 0.34, 0))]
		"grass":
			return [_part(_cone("d_grass", 0.18, 0.02, 0.38), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.19, 0), Vector3(0.75, 1.0, 0.75))]
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
	# Tall stately fir: a full cone-stack climbing well above eye line so the
	# forest reads with real vertical presence (≈1.4× the old height).
	var dark := _mat("forest_green", "forest_teal", "leaf_green")
	return [
		_part(_cyl("contrunk", 0.15, 0.22, 1.4), _mat("bark_brown", "dark_bark", "olive_wood"), Vector3(0, 0.68, 0)),
		_part(_cone("fir0", 1.2, 0.82, 1.55), dark, Vector3(0, 1.42, 0)),
		_part(_cone("fir1", 0.95, 0.58, 1.4), dark, Vector3(0.05, 2.4, 0)),
		_part(_cone("fir2", 0.66, 0.32, 1.25), dark, Vector3(-0.04, 3.32, 0.02)),
		_part(_cone("fir3", 0.4, 0.05, 1.1), dark, Vector3(0.02, 4.18, 0)),
		_part(_cone("fir_sap_a", 0.42, 0.08, 0.86), dark, Vector3(-0.78, 0.5, 0.4), Vector3(0.85, 0.85, 0.85)),
		_part(_cone("fir_sap_b", 0.36, 0.06, 0.72), dark, Vector3(0.82, 0.4, -0.28), Vector3(0.82, 0.82, 0.82))]


## Pine: tall, with a bare reddish lower trunk and a few broad, well-separated
## tiers high up (distinct from the full-to-ground fir cone-stack).
static func _pine_parts() -> Array:
	# Towering pine: a long bare reddish trunk with a high, well-separated crown —
	# the tallest silhouette in the treeline (≈1.35× the old height).
	var needle := _mat("pine_dark", "forest_teal", "pine_mid")
	var bark := _mat("trunk_a", "trunk_b", "bark_brown")
	return [
		_part(_cyl("pine_trunk", 0.13, 0.22, 3.3), bark, Vector3(0, 1.65, 0)),
		_part(_cone("pine_t0", 1.15, 0.76, 0.8), needle, Vector3(0, 3.0, 0)),
		_part(_cone("pine_t1", 0.9, 0.52, 0.72), needle, Vector3(0.05, 3.66, 0)),
		_part(_cone("pine_t2", 0.62, 0.3, 0.66), needle, Vector3(-0.04, 4.28, 0.02)),
		_part(_cone("pine_t3", 0.36, 0.04, 0.62), needle, Vector3(0.02, 4.86, 0)),
		_part(_cone("pine_low", 0.52, 0.12, 0.66), needle, Vector3(-0.66, 2.1, 0.36), Vector3(0.8, 0.8, 0.8))]


## Maple: a broad, slightly flattened dome on a stout trunk — warm autumnal
## foliage so it reads as a cozy accent among the dark firs/pines.
static func _maple_parts(leaf: ShaderMaterial) -> Array:
	var bark := _mat("bark_brown", "dark_bark", "trunk_a")
	return [
		_part(_cyl("maple_trunk", 0.18, 0.3, 1.45), bark, Vector3(0, 0.72, 0)),
		_part(_sphere("maple_dome", 1.5), leaf, Vector3(0, 1.95, 0), Vector3(1.3, 0.74, 1.3)),
		_part(_sphere("maple_l", 1.02), leaf, Vector3(-0.96, 1.66, 0.22), Vector3(1.1, 0.7, 1.1)),
		_part(_sphere("maple_r", 1.0), leaf, Vector3(0.96, 1.72, -0.2), Vector3(1.1, 0.7, 1.1)),
		_part(_sphere("maple_top", 0.92), leaf, Vector3(0.04, 2.46, -0.02), Vector3(1.1, 0.82, 1.1)),
		_part(_sphere("maple_under", 0.52), leaf, Vector3(0.62, 0.66, 0.5), Vector3(1.3, 0.4, 1.0))]


## Warm russet/gold canopy for maples (the cozy warm pop in the dark forest).
static func _maple_mat() -> ShaderMaterial:
	return _mat("leaf_orange", "leaf_red", "leaf_gold")


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


static func _house_parts(e: Node) -> Array:
	var roof: Color = e.get("roof_color")
	var roof_mat := _mat_from(roof, roof.darkened(0.36), roof.lightened(0.22))
	var wall := _mat("dirt_a", "trunk_b", "gold")
	var trim := _mat("trunk_a", "trunk_b", "dirt_a")
	var window := _mat("water_foam", "water_b", "snow_a")
	var size_scale := 1.0
	if str(e.kind) == "building":
		size_scale = clampf(float(e.get("display_size")) / 6.0, 0.85, 1.7)
	return [
		_part(_box("house_body", Vector3(2.7, 1.55, 2.1)), wall, Vector3(0, 0.82, 0), Vector3(size_scale, 1.0, size_scale)),
		_part(_box("house_foundation", Vector3(3.0, 0.18, 2.35)), _mat("stone_a", "stone_b", "ore"), Vector3(0, 0.09, 0), Vector3(size_scale, 1.0, size_scale)),
		_part(_prism("house_roof", Vector3(3.35, 1.25, 2.75)), roof_mat, Vector3(0, 2.0, 0), Vector3(size_scale, 1.0, size_scale)),
		_part(_box("house_door", Vector3(0.62, 0.92, 0.1)), trim, Vector3(-0.55 * size_scale, 0.5, 1.08 * size_scale)),
		_part(_box("house_window", Vector3(0.48, 0.38, 0.1)), window, Vector3(0.58 * size_scale, 0.92, 1.08 * size_scale))]


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


static func _hike_conifer_parts(variant: int) -> Array:
	var leaf := _mat("pine_mid", "pine_dark", "foliage_c")
	if variant % 3 == 1:
		leaf = _mat("fir_a", "pine_dark", "foliage_c")
	elif variant % 3 == 2:
		leaf = _mat("pine_dark", "shadow", "pine_mid")
	return [
		_part(_cyl("hike_pine_trunk", 0.15, 0.22, 1.35), _mat("trunk_a", "trunk_b", "dirt_a"), Vector3(0, 0.68, 0)),
		_part(_cone("hike_pine_skirt", 1.05, 0.38, 1.22), leaf, Vector3(0, 1.18, 0)),
		_part(_cone("hike_pine_mid", 0.86, 0.22, 1.22), leaf, Vector3(0.05, 1.88, 0.02)),
		_part(_cone("hike_pine_top", 0.58, 0.04, 1.28), leaf, Vector3(-0.03, 2.58, -0.02)),
		_part(_cone("hike_pine_tip", 0.28, 0.0, 0.72), leaf, Vector3(0.02, 3.18, 0.01))]


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
		root.add_child(mi)
	return root


## Articulated low-poly figure: torso/head/hair are fixed to the root; each leg
## and arm hangs off a named pivot Node3D (leg_l/leg_r/arm_l/arm_r) so the walk
## animation can swing them around X. body = outfit color, head = skin color.
static func figure_rig(body: Color, head: Color) -> Node3D:
	# Medieval villager: belted tunic (torso + flared hem skirt + sleeves) in the
	# outfit color, dark hose, leather belt + boots, and a simple cloth cap. Legs
	# and arms hang off named pivots (leg_l/leg_r/arm_l/arm_r) for the walk swing.
	var tunic := _mat_from(body, body.darkened(0.35), body.lightened(0.2))
	var hose := _mat_from(body.darkened(0.55).lerp(Color(0.17, 0.15, 0.13), 0.5), body.darkened(0.7), body.darkened(0.25))
	var leather := _mat_from(Color(0.27, 0.18, 0.11), Color(0.16, 0.1, 0.06), Color(0.4, 0.29, 0.18))
	var skin := _mat_from(head, head.darkened(0.28), head.lightened(0.18))
	var capc := _mat_from(body.darkened(0.42), body.darkened(0.62), body.lightened(0.05))
	var root := Node3D.new()
	# Upper body: belted tunic with a flared hem (the medieval silhouette).
	_attach(root, _box("rig_torso", Vector3(0.42, 0.5, 0.27)), tunic, Vector3(0, 1.0, 0))
	_attach(root, _box("rig_belt", Vector3(0.46, 0.09, 0.31)), leather, Vector3(0, 0.78, 0))
	_attach(root, _box("rig_skirt", Vector3(0.5, 0.34, 0.34)), tunic, Vector3(0, 0.62, 0))
	_attach(root, _box("rig_neck", Vector3(0.16, 0.1, 0.16)), skin, Vector3(0, 1.3, 0))
	_attach(root, _box("rig_head", Vector3(0.36, 0.36, 0.36)), skin, Vector3(0, 1.52, 0))
	# Simple cloth cap (with a small brim) instead of bare hair.
	_attach(root, _box("rig_cap", Vector3(0.42, 0.2, 0.42)), capc, Vector3(0, 1.76, 0))
	_attach(root, _box("rig_cap_brim", Vector3(0.46, 0.06, 0.18)), capc, Vector3(0, 1.68, 0.16))
	# Legs: hose + a tall leather boot, pivoting at the hip.
	for side: int in [-1, 1]:
		var leg := _limb(root, "leg_l" if side < 0 else "leg_r", Vector3(0.11 * side, 0.58, 0))
		_attach(leg, _box("rig_shin", Vector3(0.15, 0.5, 0.17)), hose, Vector3(0, -0.25, 0))
		_attach(leg, _box("rig_boot", Vector3(0.17, 0.24, 0.25)), leather, Vector3(0, -0.48, 0.03))
	# Arms: tunic sleeves + skin hands, pivoting at the shoulder.
	for side2: int in [-1, 1]:
		var arm := _limb(root, "arm_l" if side2 < 0 else "arm_r", Vector3(0.29 * side2, 1.2, 0))
		_attach(arm, _box("rig_arm", Vector3(0.12, 0.44, 0.14)), tunic, Vector3(0, -0.21, 0))
		_attach(arm, _box("rig_hand", Vector3(0.12, 0.12, 0.13)), skin, Vector3(0, -0.46, 0))
	return root


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
	var size := 1.0
	var node: Node3D
	match type:
		"wolf":
			var dark := n.contains("black") or n.contains("toxic") or n.contains("cave")
			var hide := Color(0.30, 0.31, 0.34) if dark else Color(0.55, 0.55, 0.60)
			node = quadruped_rig({"hide": hide, "belly": hide.lightened(0.32), "ears": "perk", "tail": "bushy", "snout": 0.28})
			size = 1.16 if n.contains("amaruq") else 1.0
		"boar":
			var pinkish := n.contains("pig")
			var hide := Color(0.90, 0.66, 0.70) if pinkish else Color(0.40, 0.31, 0.27)
			node = quadruped_rig({
				"hide": hide, "belly": hide.darkened(0.12), "ears": "perk", "tail": "short",
				"snout": 0.22, "tusks": not pinkish, "humped": not pinkish, "snout_pink": pinkish})
			size = 0.92
		"cow":
			node = quadruped_rig({"hide": Color(0.66, 0.46, 0.32), "belly": Color(0.84, 0.81, 0.76), "ears": "floppy", "horns": "cow", "tail": "tuft", "snout": 0.2})
			size = 1.16
		"sheep":
			node = quadruped_rig({"hide": Color(0.92, 0.91, 0.88), "belly": Color(0.88, 0.87, 0.84), "ears": "floppy", "tail": "short", "snout": 0.14, "wool": true, "head_dark": true})
			size = 1.02
		"goat":
			node = quadruped_rig({"hide": Color(0.80, 0.78, 0.80), "belly": Color(0.88, 0.87, 0.86), "ears": "perk", "horns": "goat", "tail": "short", "snout": 0.16, "beard": true})
		"mole":
			node = quadruped_rig({"hide": Color(0.34, 0.27, 0.31), "belly": Color(0.46, 0.39, 0.42), "ears": "none", "tail": "short", "snout": 0.22})
			size = 0.74
		"bird":
			var brown := n.contains("mumma") or n.contains("momma")
			node = bird_rig({"body": Color(0.84, 0.72, 0.58) if brown else Color(0.93, 0.89, 0.80)})
			size = 1.12 if brown else 0.9
		_:
			type = "humanoid"
			if n.contains("goblin") or n.contains("hob") or n.contains("gnoll"):
				node = figure_rig(Color(0.40, 0.31, 0.23), Color(0.44, 0.66, 0.34))
			elif n.contains("skelet") or n.contains("bone"):
				node = figure_rig(Color(0.62, 0.60, 0.56), Color(0.86, 0.85, 0.80))
			else:
				node = figure_rig(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a"))
	if rider and type == "wolf":
		_add_rider(node)
	node.set_meta("body3d", type)
	node.set_meta("base_scale", size * (1.22 if boss else 1.0))
	return node


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
	# Four legs at the corners; hips pivot around X for the trot.
	for ld: Array in [["leg_fl", -0.2, 0.32], ["leg_fr", 0.2, 0.32], ["leg_bl", -0.2, -0.32], ["leg_br", 0.2, -0.32]]:
		var leg := _limb(root, str(ld[0]), Vector3(float(ld[1]), 0.44, float(ld[2])))
		_attach(leg, _box("q_leg", Vector3(0.14, 0.42, 0.15)), hidem, Vector3(0, -0.21, 0))
		_attach(leg, _box("q_hoof", Vector3(0.15, 0.1, 0.17)), darkm, Vector3(0, -0.44, 0.01))
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


# ------------------------------------------------------------------ helpers ----

static func _part(mesh: Mesh, mat: Material, off: Vector3, scl := Vector3.ONE) -> Dictionary:
	return {"mesh": mesh, "mat": mat, "off": off, "scl": scl}


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
