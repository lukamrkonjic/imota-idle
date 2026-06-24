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
			# A freshly chopped-down tree shows a STUMP until it regrows (the fall is a one-off FX).
			if e.has_meta("felled"):
				return decor_parts("stump")
			# A choppable canopy tree keeps its ambient species mesh (fir/oak/birch/…) via prop_kind.
			var pk := str(e.get("prop_kind"))
			if pk.begins_with("canopy_"):
				return decor_parts(pk)
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
			return _hike_campfire_parts()   # full ring-of-stones + logs + flames, matching the firemaking fire
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
		"bridge_pole":
			return _bridge_pole_parts()
		"fence":
			return _fence_parts(true)
		"fence_post":
			return _fence_parts(false)
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
	if kind.begins_with("flower"):
		# kind = "flower_<colour>[_<shape>]"; the shape suffix gives a meadow varied
		# silhouettes (tall spikes, daisies, bells) instead of one repeated blob.
		return _flower_variant_parts(kind)
	match kind:
		"alpine_pine":
			# Foothill pines from the elevated decor pass (they only spawn on the lower,
			# green shelves — elev < 28 — so they stay GREEN, not snow-white).
			return _hike_conifer_parts(2, false)
		"alpine_boulder", "alpine_boulder0":
			return _boulder_parts(0)
		"alpine_boulder1":
			return _boulder_parts(1)
		"alpine_boulder2":
			return _boulder_parts(2)
		"wild_grass", "tall_grass":
			# Taller, looser meadow grass with golden-tipped blades — the base layer that
			# fills the ground between flower clumps so the meadow never reads as bare.
			var wg := _mat("moss_hi", "leaf_green", "sunlit_grass")
			var wt := _mat("leaf_gold", "leaf_green", "sunlit_grass")
			return [
				_part(_cone("d_wg0", 0.05, 0.006, 0.70), wg, Vector3(0.0, 0.34, 0.0), Vector3.ONE, Vector3(0.06, 0.0, 0.05)),
				_part(_cone("d_wg1", 0.05, 0.006, 0.62), wt, Vector3(0.11, 0.30, 0.05), Vector3.ONE, Vector3(0.0, 0.0, -0.5)),
				_part(_cone("d_wg2", 0.045, 0.006, 0.60), wg, Vector3(-0.12, 0.29, -0.04), Vector3.ONE, Vector3(0.0, 0.0, 0.55)),
				_part(_cone("d_wg3", 0.045, 0.006, 0.55), wt, Vector3(0.04, 0.27, -0.12), Vector3.ONE, Vector3(0.5, 0.0, 0.07)),
				_part(_cone("d_wg4", 0.04, 0.006, 0.50), wg, Vector3(-0.05, 0.26, 0.11), Vector3.ONE, Vector3(-0.45, 0.0, -0.08)),
				_part(_cone("d_wg5", 0.04, 0.006, 0.48), wt, Vector3(0.13, 0.25, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.7))]
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
			# Gold-green birch foliage — a pale lime highlight, NOT pure white, so the canopy
			# reads as autumn-gold leaves rather than a snowed-over blob.
			return _tree_parts(_mat_from(Color(0.80, 0.80, 0.36), Color(0.42, 0.50, 0.22), Color(0.93, 0.91, 0.56)))
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
		"stump", "log_stump", "tree_stump":
			return _hike_stump_parts()
		"dead_tree", "deadtree", "snag":
			return _deadtree_parts()
		# ── added clutter: rocks & minerals ─────────────────────────────────
		"boulder", "big_rock":
			return [_part(_sphere("d_bldr", 0.3), _mat("stone_a", "stone_b", "cliff_light"), Vector3(0, 0.17, 0), Vector3(1.2, 0.85, 1.1))]
		"rock_pile", "stones", "rubble_rocks":
			var rs := _mat("stone_a", "stone_b", "cliff_light")
			return [
				_part(_sphere("d_rp0", 0.16), rs, Vector3(0.0, 0.09, 0.0), Vector3(1.3, 0.75, 1.1)),
				_part(_sphere("d_rp1", 0.12), rs, Vector3(0.16, 0.07, 0.08), Vector3(1.1, 0.7, 1.0), Vector3(0, 0.6, 0)),
				_part(_sphere("d_rp2", 0.1), rs, Vector3(-0.12, 0.06, -0.1), Vector3(1.0, 0.7, 1.0))]
		"cairn":
			var cs := _mat("stone_a", "stone_b", "cliff_light")
			return [
				_part(_cyl("d_cairn0", 0.15, 0.17, 0.08), cs, Vector3(0.0, 0.04, 0.0)),
				_part(_cyl("d_cairn1", 0.12, 0.14, 0.07), cs, Vector3(0.02, 0.12, 0.0)),
				_part(_cyl("d_cairn2", 0.09, 0.11, 0.06), cs, Vector3(-0.01, 0.19, 0.01)),
				_part(_cyl("d_cairn3", 0.06, 0.08, 0.05), cs, Vector3(0.01, 0.25, 0.0))]
		"standing_stone", "menhir":
			return [_part(_box("d_menhir", Vector3(0.18, 0.72, 0.13)), _mat("stone_a", "stone_b", "cliff_light"), Vector3(0, 0.36, 0), Vector3.ONE, Vector3(0.06, 0.2, 0.04))]
		"crystal", "crystal_cluster":
			var cry := _mat_from(Color(0.45, 0.6, 0.9), Color(0.28, 0.38, 0.66), Color(0.78, 0.9, 1.0))
			return [
				_part(_cone("d_cry0", 0.06, 0.0, 0.42), cry, Vector3(0.0, 0.21, 0.0), Vector3.ONE, Vector3(0.08, 0, 0.05)),
				_part(_cone("d_cry1", 0.045, 0.0, 0.3), cry, Vector3(0.1, 0.15, 0.04), Vector3.ONE, Vector3(0, 0, -0.45)),
				_part(_cone("d_cry2", 0.04, 0.0, 0.24), cry, Vector3(-0.09, 0.12, -0.05), Vector3.ONE, Vector3(0.4, 0, 0.25))]
		"geode":
			return [
				_part(_sphere("d_geo", 0.18), _mat("stone_a", "stone_b", "cliff_light"), Vector3(0, 0.13, 0), Vector3(1.1, 0.9, 1.1)),
				_part(_sphere("d_geo_in", 0.1), _mat_from(Color(0.6, 0.5, 0.85), Color(0.4, 0.32, 0.6), Color(0.85, 0.78, 1.0)), Vector3(0.04, 0.16, 0.06), Vector3(0.9, 0.9, 0.9))]
		# ── added clutter: wood & timber ────────────────────────────────────
		"log", "fallen_log":
			var bark := _mat("trunk_a", "trunk_b", "wood_light")
			var ring := _mat("dirt_a", "trunk_b", "cabin_trim")
			return [
				_part(_cyl("d_log", 0.12, 0.13, 0.82), bark, Vector3(0, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				_part(_cyl("d_log_r", 0.125, 0.125, 0.02), ring, Vector3(0.41, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))]
		"log_pile", "woodpile", "firewood":
			var lw := _mat("trunk_a", "trunk_b", "wood_light")
			var lr := _mat("dirt_a", "trunk_b", "cabin_trim")
			return [
				_part(_cyl("d_wp0", 0.09, 0.09, 0.6), lw, Vector3(0, 0.1, -0.1), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				_part(_cyl("d_wp1", 0.09, 0.09, 0.6), lw, Vector3(0, 0.1, 0.1), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				_part(_cyl("d_wp2", 0.09, 0.09, 0.6), lw, Vector3(0, 0.28, 0.0), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				_part(_cyl("d_wpr", 0.095, 0.095, 0.02), lr, Vector3(0.3, 0.28, 0.0), Vector3.ONE, Vector3(0, 0, PI * 0.5))]
		"branch", "twigs", "sticks":
			var bw := _mat("trunk_a", "trunk_b", "wood_light")
			return [
				_part(_box("d_br0", Vector3(0.5, 0.05, 0.06)), bw, Vector3(0, 0.04, 0), Vector3.ONE, Vector3(0, 0.3, 0)),
				_part(_box("d_br1", Vector3(0.42, 0.05, 0.06)), bw, Vector3(0.02, 0.07, 0.04), Vector3.ONE, Vector3(0, -0.5, 0.1))]
		"tree_roots", "roots":
			var rw := _mat("trunk_a", "trunk_b", "wood_light")
			return [
				_part(_cyl("d_rt_c", 0.14, 0.18, 0.18), rw, Vector3(0, 0.08, 0)),
				_part(_cone("d_rt0", 0.06, 0.02, 0.3), rw, Vector3(0.16, 0.06, 0.0), Vector3.ONE, Vector3(0, 0, 1.2)),
				_part(_cone("d_rt1", 0.06, 0.02, 0.28), rw, Vector3(-0.15, 0.06, 0.05), Vector3.ONE, Vector3(0, 0, -1.2)),
				_part(_cone("d_rt2", 0.05, 0.02, 0.26), rw, Vector3(0.04, 0.06, 0.16), Vector3.ONE, Vector3(-1.2, 0, 0))]
		"mossy_log":
			var mbark := _mat("trunk_a", "trunk_b", "wood_light")
			var mmoss := _mat("foliage_b", "grass_dark", "foliage_c")
			return [
				_part(_cyl("d_mlog", 0.13, 0.14, 0.82), mbark, Vector3(0, 0.13, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				_part(_sphere("d_mlog_m0", 0.1), mmoss, Vector3(0.1, 0.24, 0.02), Vector3(1.4, 0.5, 1.0)),
				_part(_sphere("d_mlog_m1", 0.09), mmoss, Vector3(-0.16, 0.23, -0.03), Vector3(1.3, 0.5, 1.0))]
		# ── added clutter: plants & flora ───────────────────────────────────
		"cattail", "cattails", "bulrush":
			var ct_s := _mat("foliage_c", "grass_dark", "moss_hi")
			var ct_h := _mat("trunk_a", "trunk_b", "dirt_a")
			return [
				_part(_cyl("d_ct0", 0.012, 0.012, 0.72), ct_s, Vector3(0, 0.36, 0)),
				_part(_cyl("d_cth0", 0.03, 0.03, 0.16), ct_h, Vector3(0, 0.68, 0)),
				_part(_cyl("d_ct1", 0.012, 0.012, 0.62), ct_s, Vector3(0.09, 0.31, 0.05), Vector3.ONE, Vector3(0, 0, -0.1)),
				_part(_cyl("d_cth1", 0.028, 0.028, 0.14), ct_h, Vector3(0.1, 0.59, 0.06))]
		"thistle":
			var ti_s := _mat("foliage_b", "grass_dark", "foliage_c")
			var ti_b := _mat_from(Color(0.6, 0.35, 0.72), Color(0.4, 0.22, 0.5), Color(0.8, 0.56, 0.92))
			return [
				_part(_cyl("d_ti_s", 0.02, 0.03, 0.42), ti_s, Vector3(0, 0.21, 0)),
				_part(_sphere("d_ti_b", 0.09), ti_b, Vector3(0, 0.46, 0), Vector3(1.0, 1.25, 1.0))]
		"berry_bush":
			var be_l := _mat("foliage_b", "grass_dark", "foliage_a")
			var be_b := _mat_from(Color(0.66, 0.16, 0.2), Color(0.42, 0.1, 0.14), Color(0.85, 0.3, 0.32))
			return [
				_part(_sphere("d_bb", 0.28), be_l, Vector3(0, 0.22, 0), Vector3(1.1, 0.9, 1.1)),
				_part(_sphere("d_bb0", 0.04), be_b, Vector3(0.14, 0.28, 0.1)),
				_part(_sphere("d_bb1", 0.04), be_b, Vector3(-0.1, 0.31, 0.12)),
				_part(_sphere("d_bb2", 0.04), be_b, Vector3(0.05, 0.34, -0.14))]
		"clover", "clover_patch":
			var cl := _mat("moss_hi", "leaf_green", "sunlit_grass")
			return [
				_part(_sphere("d_cl0", 0.08), cl, Vector3(0, 0.05, 0), Vector3(1.2, 0.5, 1.2)),
				_part(_sphere("d_cl1", 0.07), cl, Vector3(0.12, 0.04, 0.06), Vector3(1.1, 0.5, 1.1)),
				_part(_sphere("d_cl2", 0.06), cl, Vector3(-0.1, 0.04, -0.08), Vector3(1.1, 0.5, 1.1))]
		"lily_pad", "lilypad":
			var lp_p := _mat("foliage_c", "foliage_b", "moss_hi")
			var lp_f := _mat_from(Color(0.96, 0.82, 0.86), Color(0.8, 0.6, 0.68), Color(1.0, 0.96, 0.98))
			return [
				_part(_cyl("d_lp", 0.22, 0.22, 0.02), lp_p, Vector3(0, 0.01, 0)),
				_part(_sphere("d_lpf", 0.05), lp_f, Vector3(0.06, 0.04, 0.0))]
		"dandelion":
			return [
				_part(_cyl("d_dl_s", 0.012, 0.012, 0.28), _mat("foliage_c", "grass_dark", "moss_hi"), Vector3(0, 0.14, 0)),
				_part(_sphere("d_dl_p", 0.07), _mat_from(Color(0.93, 0.95, 0.93), Color(0.78, 0.8, 0.78), Color(1, 1, 1)), Vector3(0, 0.32, 0))]
		# ── added clutter: desert / arid ────────────────────────────────────
		"agave", "aloe":
			var ag := _mat_from(Color(0.42, 0.55, 0.4), Color(0.28, 0.38, 0.28), Color(0.62, 0.74, 0.5))
			return [
				_part(_cone("d_ag0", 0.05, 0.0, 0.5), ag, Vector3(0, 0.24, 0), Vector3.ONE, Vector3(0.15, 0, 0.0)),
				_part(_cone("d_ag1", 0.05, 0.0, 0.46), ag, Vector3(0.13, 0.2, 0), Vector3.ONE, Vector3(0, 0, -0.7)),
				_part(_cone("d_ag2", 0.05, 0.0, 0.46), ag, Vector3(-0.13, 0.2, 0), Vector3.ONE, Vector3(0, 0, 0.7)),
				_part(_cone("d_ag3", 0.05, 0.0, 0.44), ag, Vector3(0, 0.2, 0.13), Vector3.ONE, Vector3(-0.7, 0, 0)),
				_part(_cone("d_ag4", 0.05, 0.0, 0.44), ag, Vector3(0, 0.2, -0.13), Vector3.ONE, Vector3(0.7, 0, 0))]
		"tumbleweed":
			return [_part(_sphere("d_tw", 0.24), _mat_from(Color(0.62, 0.5, 0.32), Color(0.45, 0.36, 0.22), Color(0.78, 0.66, 0.44)), Vector3(0, 0.23, 0), Vector3(1.1, 1.0, 1.1))]
		"sagebrush", "dry_bush":
			return [_part(_sphere("d_sage", 0.26), _mat_from(Color(0.55, 0.6, 0.46), Color(0.4, 0.45, 0.34), Color(0.72, 0.76, 0.58)), Vector3(0, 0.2, 0), Vector3(1.1, 0.75, 1.1))]
		"animal_skull", "skull", "bone_pile":
			var bo := _mat_from(Color(0.86, 0.84, 0.76), Color(0.66, 0.64, 0.56), Color(0.97, 0.95, 0.88))
			return [
				_part(_sphere("d_skull", 0.12), bo, Vector3(0, 0.1, 0), Vector3(1.0, 1.0, 1.15)),
				_part(_box("d_bone0", Vector3(0.42, 0.045, 0.05)), bo, Vector3(0.05, 0.03, 0.1), Vector3.ONE, Vector3(0, 0.4, 0)),
				_part(_box("d_bone1", Vector3(0.34, 0.045, 0.05)), bo, Vector3(-0.03, 0.03, -0.09), Vector3.ONE, Vector3(0, -0.5, 0))]
		# ── added clutter: fungi ────────────────────────────────────────────
		"toadstool":
			return [
				_part(_cyl("d_ts_s", 0.05, 0.07, 0.2), _mat("snow_a", "stone_b", "snow_a"), Vector3(0, 0.1, 0)),
				_part(_sphere("d_ts_c", 0.15), _mat_from(Color(0.78, 0.2, 0.18), Color(0.55, 0.12, 0.12), Color(0.92, 0.4, 0.34)), Vector3(0, 0.24, 0), Vector3(1.0, 0.6, 1.0))]
		"mushroom_cluster", "mushrooms":
			var mc_s := _mat("snow_a", "stone_b", "snow_a")
			var mc_c := _mat("dirt_a", "trunk_b", "gold")
			return [
				_part(_cyl("d_mc_s0", 0.04, 0.06, 0.18), mc_s, Vector3(0, 0.09, 0)),
				_part(_sphere("d_mc_c0", 0.11), mc_c, Vector3(0, 0.21, 0), Vector3(1.0, 0.6, 1.0)),
				_part(_cyl("d_mc_s1", 0.03, 0.05, 0.13), mc_s, Vector3(0.13, 0.065, 0.05)),
				_part(_sphere("d_mc_c1", 0.08), mc_c, Vector3(0.13, 0.16, 0.05), Vector3(1.0, 0.6, 1.0)),
				_part(_cyl("d_mc_s2", 0.03, 0.05, 0.1), mc_s, Vector3(-0.1, 0.05, -0.06)),
				_part(_sphere("d_mc_c2", 0.07), mc_c, Vector3(-0.1, 0.13, -0.06), Vector3(1.0, 0.6, 1.0))]
		"bracket_fungus", "shelf_fungus":
			var bf_w := _mat("trunk_a", "trunk_b", "wood_light")
			var bf_c := _mat("dirt_a", "trunk_b", "cabin_trim")
			return [
				_part(_cyl("d_bf_s", 0.05, 0.06, 0.22), bf_w, Vector3(0, 0.11, 0)),
				_part(_cyl("d_bf0", 0.12, 0.12, 0.025), bf_c, Vector3(0.08, 0.14, 0), Vector3(1, 1, 1.4)),
				_part(_cyl("d_bf1", 0.1, 0.1, 0.02), bf_c, Vector3(-0.06, 0.2, 0.02), Vector3(1, 1, 1.3))]
		# ── added clutter: snow / ice ───────────────────────────────────────
		"snow_patch", "snow_mound":
			return [_part(_sphere("d_snowp", 0.28), _mat("snow_a", "stone_b", "snow_a"), Vector3(0, 0.04, 0), Vector3(1.3, 0.3, 1.2))]
		"ice_shard", "ice_crystal":
			var ic := _mat_from(Color(0.7, 0.85, 0.95), Color(0.5, 0.66, 0.8), Color(0.88, 0.96, 1.0))
			return [
				_part(_cone("d_ice0", 0.05, 0.0, 0.4), ic, Vector3(0, 0.2, 0)),
				_part(_cone("d_ice1", 0.04, 0.0, 0.28), ic, Vector3(0.08, 0.14, 0.04), Vector3.ONE, Vector3(0, 0, -0.3)),
				_part(_cone("d_ice2", 0.035, 0.0, 0.22), ic, Vector3(-0.07, 0.11, -0.04), Vector3.ONE, Vector3(0.3, 0, 0.2))]
		"frozen_shrub":
			return [
				_part(_sphere("d_fsh", 0.28), _mat("foliage_b", "grass_dark", "foliage_a"), Vector3(0, 0.22, 0), Vector3(1.1, 0.8, 1.1)),
				_part(_sphere("d_fsh_s", 0.2), _mat("snow_a", "stone_b", "snow_a"), Vector3(0, 0.33, 0), Vector3(1.0, 0.5, 1.0))]
		# ── added clutter: coastal ──────────────────────────────────────────
		"seashell", "shells":
			var sh := _mat_from(Color(0.92, 0.86, 0.78), Color(0.74, 0.66, 0.58), Color(1.0, 0.96, 0.9))
			return [
				_part(_cone("d_sh0", 0.1, 0.02, 0.12), sh, Vector3(0, 0.06, 0), Vector3(1, 0.85, 1), Vector3(1.2, 0, 0)),
				_part(_sphere("d_sh1", 0.06), sh, Vector3(0.13, 0.04, 0.06), Vector3(1, 0.6, 1))]
		"starfish":
			var sf := _mat_from(Color(0.85, 0.45, 0.3), Color(0.66, 0.32, 0.22), Color(0.95, 0.6, 0.42))
			var arms: Array = []
			for k: int in 5:
				var a := (float(k) / 5.0) * TAU
				arms.append(_part(_cone("d_sf" + str(k), 0.05, 0.0, 0.2), sf,
					Vector3(cos(a) * 0.1, 0.03, sin(a) * 0.1), Vector3.ONE, Vector3(PI * 0.5, -a, 0)))
			return arms
		"coral":
			var co := _mat_from(Color(0.9, 0.5, 0.5), Color(0.7, 0.36, 0.4), Color(1.0, 0.66, 0.62))
			return [
				_part(_cone("d_co0", 0.05, 0.025, 0.32), co, Vector3(0, 0.16, 0)),
				_part(_cone("d_co1", 0.04, 0.02, 0.24), co, Vector3(0.1, 0.12, 0.04), Vector3.ONE, Vector3(0, 0, -0.5)),
				_part(_cone("d_co2", 0.04, 0.02, 0.22), co, Vector3(-0.09, 0.11, -0.05), Vector3.ONE, Vector3(0.4, 0, 0.2))]
		# ── added clutter: settlement / camp props ──────────────────────────
		"barrel":
			var ba_w := _mat("wood_light", "trunk_b", "cabin_trim")
			var ba_b := _mat("trunk_b", "shadow", "trunk_a")
			return [
				_part(_cyl("d_barrel", 0.17, 0.19, 0.42), ba_w, Vector3(0, 0.21, 0)),
				_part(_cyl("d_barrel_t", 0.18, 0.18, 0.04), ba_b, Vector3(0, 0.33, 0)),
				_part(_cyl("d_barrel_b", 0.2, 0.2, 0.04), ba_b, Vector3(0, 0.09, 0))]
		"crate", "box":
			return [
				_part(_box("d_crate", Vector3(0.34, 0.34, 0.34)), _mat("wood_light", "trunk_b", "cabin_trim"), Vector3(0, 0.17, 0)),
				_part(_box("d_crate_x", Vector3(0.36, 0.05, 0.05)), _mat("trunk_a", "trunk_b", "wood_light"), Vector3(0, 0.17, 0.18))]
		"sack":
			return [
				_part(_sphere("d_sack", 0.18), _mat("ore", "dirt_b", "cabin_trim"), Vector3(0, 0.17, 0), Vector3(0.9, 1.2, 0.9)),
				_part(_sphere("d_sack_t", 0.08), _mat("dirt_b", "trunk_b", "ore"), Vector3(0, 0.32, 0))]
		"hay_bale", "haystack":
			return [_part(_cyl("d_hay", 0.22, 0.22, 0.5), _mat("leaf_gold", "dirt_b", "cabin_trim"), Vector3(0, 0.22, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))]
		"bucket":
			return [
				_part(_cyl("d_bk", 0.12, 0.1, 0.2), _mat("trunk_b", "shadow", "trunk_a"), Vector3(0, 0.1, 0)),
				_part(_box("d_bk_h", Vector3(0.24, 0.02, 0.02)), _mat("stone_b", "shadow", "stone_a"), Vector3(0, 0.22, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0))]
		"signpost", "sign":
			var sp_p := _mat("trunk_a", "trunk_b", "wood_light")
			return [
				_part(_box("d_sp_p", Vector3(0.06, 0.6, 0.06)), sp_p, Vector3(0, 0.3, 0)),
				_part(_box("d_sp_b", Vector3(0.34, 0.16, 0.04)), _mat("wood_light", "trunk_b", "cabin_trim"), Vector3(0.1, 0.5, 0))]
		"fence_post", "post":
			var fp := _mat("trunk_a", "trunk_b", "wood_light")
			return [
				_part(_box("d_fp", Vector3(0.08, 0.5, 0.08)), fp, Vector3(0, 0.25, 0)),
				_part(_box("d_fp_r", Vector3(0.5, 0.05, 0.04)), fp, Vector3(0.2, 0.32, 0))]
		"anthill", "dirt_mound":
			return [_part(_cone("d_ah", 0.2, 0.06, 0.24), _mat("dirt_a", "dirt_b", "path_light"), Vector3(0, 0.12, 0))]
		_:  # grass, fern, reed, vine, moss, lichen, ... -> green tuft
			return [_part(_sphere("d_tuft", 0.22), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.16, 0), Vector3(1.0, 0.7, 1.0))]


## Bloom material for a wildflower colour token (purple/yellow/white/pink).
static func _flower_head_mat(color: String) -> Material:
	match color:
		"white":
			return _mat_from(Color(0.97, 0.97, 0.94), Color(0.74, 0.76, 0.80), Color(1, 1, 1))
		"purple":
			return _mat_from(Color(0.58, 0.28, 0.88), Color(0.38, 0.16, 0.62), Color(0.82, 0.60, 1.0))
		"pink":
			return _mat_from(Color(0.97, 0.42, 0.68), Color(0.78, 0.26, 0.48), Color(1.0, 0.74, 0.88))
		_:  # yellow / generic
			return _mat_from(Color(1.0, 0.82, 0.16), Color(0.86, 0.58, 0.07), Color(1.0, 0.94, 0.45))


## Parse a "flower_<colour>[_<shape>]" decor kind into the matching mesh. The colour drives
## the bloom material; the shape suffix (spike/daisy/bell/cluster) varies the silhouette so a
## meadow is a mix of tall lupine-style spikes, flat daisies and low clusters, not one blob.
static func _flower_variant_parts(kind: String) -> Array:
	var rest := kind.substr(7)            # drop "flower_" ("" for the bare "flower" kind)
	var color := "yellow"
	var shape := "cluster"
	for c: String in ["purple", "yellow", "white", "pink"]:
		if rest.begins_with(c):
			color = c
			if rest.length() > c.length() + 1:
				shape = rest.substr(c.length() + 1)
			break
	var head := _flower_head_mat(color)
	match shape:
		"spike":
			return _flower_spike_parts(head)
		"daisy":
			return _flower_daisy_parts(head)
		"bell":
			return _flower_bell_parts(head)
		_:
			return _flower_cluster_parts(head)


const _FOLIAGE_STEM := ["foliage_c", "grass_dark", "foliage_b"]

## Tall lupine/foxglove spike: a slim stalk with blooms stacked up it, smaller toward the tip.
static func _flower_spike_parts(head: Material) -> Array:
	var stem := _mat(_FOLIAGE_STEM[0], _FOLIAGE_STEM[1], _FOLIAGE_STEM[2])
	var parts := [
		_part(_sphere("d_ftuft", 0.13), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.07, 0), Vector3(1.0, 0.55, 1.0)),
		_part(_cone("d_fstem", 0.026, 0.012, 0.62), stem, Vector3(0, 0.33, 0))]
	var hs := [0.28, 0.37, 0.45, 0.52, 0.58, 0.63]
	var sz := [0.10, 0.092, 0.082, 0.07, 0.056, 0.04]
	for i: int in hs.size():
		var off: float = 0.04 if i % 2 == 0 else -0.04
		parts.append(_part(_sphere("d_fsp%d" % i, sz[i]), head, Vector3(off, hs[i], -off * 0.55)))
	return parts


## Flat daisy: short stem, a wide low bloom disc, and a contrasting gold centre.
static func _flower_daisy_parts(head: Material) -> Array:
	var stem := _mat(_FOLIAGE_STEM[0], _FOLIAGE_STEM[1], _FOLIAGE_STEM[2])
	return [
		_part(_sphere("d_ftuft", 0.12), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.06, 0), Vector3(1.0, 0.5, 1.0)),
		_part(_cone("d_dstem", 0.018, 0.01, 0.28), stem, Vector3(0, 0.18, 0)),
		_part(_sphere("d_dpetal", 0.135), head, Vector3(0, 0.32, 0), Vector3(1.0, 0.3, 1.0)),
		_part(_sphere("d_dcore", 0.05), _mat("gold", "leaf_gold", "snow_a"), Vector3(0, 0.345, 0))]


## Drooping bell flower (bluebell-style): a stem with a few heads nodding near the top.
static func _flower_bell_parts(head: Material) -> Array:
	var stem := _mat(_FOLIAGE_STEM[0], _FOLIAGE_STEM[1], _FOLIAGE_STEM[2])
	return [
		_part(_sphere("d_ftuft", 0.12), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.06, 0), Vector3(1.0, 0.5, 1.0)),
		_part(_cone("d_bstem", 0.02, 0.012, 0.42), stem, Vector3(0, 0.23, 0)),
		_part(_sphere("d_bb0", 0.078), head, Vector3(0.02, 0.44, 0.0), Vector3(1.0, 1.2, 1.0)),
		_part(_sphere("d_bb1", 0.066), head, Vector3(-0.10, 0.36, 0.05), Vector3(1.0, 1.2, 1.0)),
		_part(_sphere("d_bb2", 0.06), head, Vector3(0.09, 0.32, -0.05), Vector3(1.0, 1.2, 1.0))]


## Low rounded cluster: a leaf tuft topped by a small bunch of bloom heads.
static func _flower_cluster_parts(head: Material) -> Array:
	return [
		_part(_sphere("d_ftuft", 0.15), _mat("foliage_c", "grass_dark", "foliage_c"), Vector3(0, 0.11, 0), Vector3(1.0, 0.7, 1.0)),
		_part(_sphere("d_fhead0", 0.11), head, Vector3(0.0, 0.32, 0.0)),
		_part(_sphere("d_fhead1", 0.08), head, Vector3(-0.12, 0.27, 0.06)),
		_part(_sphere("d_fhead2", 0.08), head, Vector3(0.11, 0.28, -0.06))]


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
			parts = _boulder_parts(variant)
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
	# A snow-DUSTED evergreen: a green conifer whose lit/top surfaces frost white (snow_a
	# highlight), so it reads as winter-laden rather than the old solid-white blob.
	return _conifer_parts_with_material(_mat("mid_foliage", "forest_teal", "snow_a"))


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
	# Mining-rock boulder: grey stone, a touch larger than the decor boulders, faceted and
	# grounded (no more floating octahedron pyramids).
	return _rock_cluster("ore", 0, _mat("stone_a", "stone_b", "ore"), _mat("stone_b", "shadow", "stone_a"), 1.12)


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
	# An ORIENTED plank-deck segment (one per bridge tile, yaw-aligned + raised by the entity's
	# height_offset so it rides above the water). Local +Z runs ALONG the path, +X across. A solid
	# light deck with dark flush gap-lines reads as laid boards; a railing runs down each side.
	# Warm light planks (A Short Hike's bridge), with darker plank-gap lines for definition.
	var deck := _mat("wood_light", "path_orange", "cabin_trim")
	var gap := _mat("path_orange", "trunk_b", "wood_light")
	var parts: Array = [_part(_box("bridge_deck", Vector3(1.5, 0.14, 1.35)), deck, Vector3(0, 0.07, 0))]
	for z: float in [-0.45, 0.0, 0.45]:                            # dark plank gaps, flush on the deck
		parts.append(_part(_box("bridge_gap", Vector3(1.5, 0.04, 0.06)), gap, Vector3(0, 0.145, z)))
	parts.append(_part(_box("bridge_rail", Vector3(0.1, 0.26, 1.35)), gap, Vector3(-0.72, 0.24, 0)))   # side rails
	parts.append(_part(_box("bridge_rail", Vector3(0.1, 0.26, 1.35)), gap, Vector3(0.72, 0.24, 0)))
	return parts


## A fence segment: a chunky post, plus (unless it's the run's last post) two rails running ALONG
## +Z — the path direction set by the entity's yaw — that reach to the NEXT post (FENCE_RAIL ≈ the
## post spacing, with a hair of overlap so the joint is clean). Even spacing + matched rail length
## gives a tidy post-and-rail look instead of a pile of overlapping boards.
const FENCE_RAIL := 2.08    # rail length (≈ RoadBrush.FENCE_SPACING of 2.0, slight overlap)

static func _fence_parts(with_rail := true) -> Array:
	var p := _mat("trunk_a", "trunk_b", "wood_light")
	var parts: Array = [_part(_box("fence_post", Vector3(0.13, 0.54, 0.13)), p, Vector3(0, 0.27, 0))]
	if with_rail:
		var w := _mat("wood_light", "trunk_b", "cabin_trim")
		parts.append(_part(_box("fence_rail_top", Vector3(0.05, 0.08, FENCE_RAIL)), w, Vector3(0, 0.4, FENCE_RAIL * 0.5)))
		parts.append(_part(_box("fence_rail_bot", Vector3(0.05, 0.08, FENCE_RAIL)), w, Vector3(0, 0.2, FENCE_RAIL * 0.5)))
	return parts


static func _bridge_pole_parts() -> Array:
	# A UNIT piling spanning local Y 0 (top, at the deck) down to -1. The batcher scales its Y to
	# the exact drop from the deck to the terrain/water below, so every pile reaches the ground.
	return [
		_part(_box("bridge_pole_unit", Vector3(0.16, 1.0, 0.16)), _mat("path_orange", "trunk_b", "wood_light"), Vector3(0, -0.5, 0))]


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
		# Snow-DUSTED, not solid white: green needles with frosted (white-lit) tips, so a
		# winter conifer reads as frosted rather than a bugged white blob.
		leaf = _mat("foliage_c", "pine_dark", "snow_a")
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


## A low-poly FACETED stone lobe (few segments → angular crags, not a smooth pebble).
static func _facet_sphere(key: String, r: float, seg := 6) -> Mesh:
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 1.85
		m.radial_segments = seg
		m.rings = maxi(2, seg / 2)
		_mesh_cache[key] = m
	return _mesh_cache[key]


# Irregular boulder layouts — a main lobe plus asymmetric satellites. Each entry is
# [radius, offset_x, offset_z, y_scale, xz_scale]; every lobe is grounded independently
# (see _boulder_parts) so the whole rock sits flat on the terrain, never floating.
const _BOULDER_VARIANTS := [
	[[0.62, 0.0, 0.0, 0.74, 1.06], [0.40, 0.52, 0.12, 0.6, 1.18], [0.30, -0.40, -0.30, 0.58, 1.0], [0.22, 0.18, -0.46, 0.52, 1.12]],
	[[0.56, 0.10, 0.0, 0.86, 0.96], [0.46, -0.34, 0.22, 0.66, 1.12], [0.27, 0.44, -0.20, 0.56, 1.02]],
	[[0.68, 0.0, 0.05, 0.62, 1.22], [0.34, 0.40, 0.34, 0.52, 1.06], [0.30, -0.46, -0.10, 0.58, 1.0], [0.20, -0.10, 0.50, 0.48, 1.0]],
]

## A craggy, irregular rock — a cluster of faceted, flattened stone lobes. Each lobe's base is
## pinned to y=0 (its centre sits at exactly its own half-height) so the rock rests flat on the
## ground and never floats or sinks. `tag` namespaces the cached meshes per material/scale and
## the variant picks one of the asymmetric layouts so neighbouring rocks don't repeat.
static func _rock_cluster(tag: String, variant: int, base_mat: Material, accent_mat: Material, scale := 1.0) -> Array:
	var v: int = variant % _BOULDER_VARIANTS.size()
	var lobes: Array = _BOULDER_VARIANTS[v]
	var parts: Array = [_shadow_part(0.92 * scale)]
	for i: int in lobes.size():
		var L: Array = lobes[i]
		var r: float = float(L[0]) * scale
		var sy: float = float(L[3])
		var sxz: float = float(L[4])
		var half: float = r * 0.925 * sy   # SphereMesh half-height (1.85r) × y-scale → base at y=0
		parts.append(_part(
			_facet_sphere("rock_%s_%d_%d" % [tag, v, i], r, 6 if i == 0 else 5),
			base_mat if i % 2 == 0 else accent_mat,
			Vector3(float(L[1]) * scale, half, float(L[2]) * scale), Vector3(sxz, sy, sxz)))
	return parts


## Alpine/meadow decor boulder — warm cliff stone, three shapes (selected by the decor variant).
static func _boulder_parts(variant: int) -> Array:
	return _rock_cluster("bld", variant,
		_mat("cliff_warm", "cliff_shadow", "cliff_light"), _mat("cliff_shadow", "shadow", "cliff_warm"))


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
	var p := _part(_shadow_quad(), _shadow_mat(), Vector3(off.x, 0.03, off.y), Vector3(radius * 2.0, 1.0, radius * 2.0 * lon))
	p["shadow"] = true   # so the hover OUTLINE builder can skip it (no white ground disc)
	return p


## A flat round DISC on the ground (radius 0.5, so _shadow_part's diameter scaling still
## applies). Round by geometry — not by the texture's alpha — because the shadow material's
## MULTIPLY blend ignores alpha, which made the old square PlaneMesh darken as a hard square.
static func _shadow_quad() -> Mesh:
	if not _mesh_cache.has("blob_shadow_disc"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		var n := 24
		for i: int in n:
			var a0 := float(i) / n * TAU
			var a1 := float(i + 1) / n * TAU
			# centre, then rim CCW (viewed from +Y) so the upward face shows
			st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
			st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)); st.add_vertex(Vector3(cos(a1) * 0.5, 0.0, sin(a1) * 0.5))
			st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)); st.add_vertex(Vector3(cos(a0) * 0.5, 0.0, sin(a0) * 0.5))
		st.generate_normals()
		_mesh_cache["blob_shadow_disc"] = st.commit()
	return _mesh_cache["blob_shadow_disc"]


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
		m.albedo_color = Color(1, 1, 1, 1)   # darkening lives in the texture RGB (centre→rim falloff)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shadow_material = m
	return _shadow_material


## Radial alpha falloff (opaque centre -> clear rim) so the blob has soft edges.
static func _shadow_texture() -> ImageTexture:
	if _shadow_tex_cache == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := float(n) * 0.5
		for y: int in n:
			for x: int in n:
				var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c   # 0 centre .. ~1 rim
				# The shadow material MULTIPLIES, and that blend ignores alpha — so the soft
				# falloff lives in the RGB: darkest at the centre, fading to white (= no
				# darkening) at the rim, for a soft round blob instead of a hard disc.
				var v := lerpf(0.42, 1.0, smoothstep(0.12, 1.0, clampf(d, 0.0, 1.0)))
				img.set_pixel(x, y, Color(v, v, v, 1.0))
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
