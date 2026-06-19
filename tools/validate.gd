extends Node
## Headless validation. Run:
const ValidateContent := preload("res://tools/validate_content.gd")
const ContentId := preload("res://scripts/content/content_id.gd")
const SaveMigration := preload("res://autoload/save_migration.gd")
const SkillRemap := preload("res://scripts/content/skill_remap.gd")
const ContentRename := preload("res://scripts/content/content_rename.gd")
const CombatStyles := preload("res://scripts/combat/combat_styles.gd")
const DropRoller := preload("res://scripts/combat/drop_roller.gd")
const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const PathFinder := preload("res://scripts/worldgen/path_finder.gd")
##   godot --headless --path C:/Dev/bloobs-godot res://tools/validate.tscn
## Drives the sims with synthetic delta time, so it completes in milliseconds.

var failures := 0


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	FarmingSim.suppress = true
	WorldGen.store.suppress = true
	WorldGen.reset(WorldGen.DEFAULT_SEED)
	CombatSim.rng.seed = 0xB100B5
	TickSim.rng.seed = 0x6A7E12  # deterministic gathering rolls for tests
	phase0_data()
	phase0_content_schema()
	phase0_stable_ids()
	phase3_content_rename()
	phase2_skill_roster()
	phase1_gathering()
	phase1_inventory_bank_equipment()
	phase2_combat()
	phase3_save_roundtrip()
	phase3_save_migration()
	phase3_rename_alias()
	phase3_recipes()
	phase4_food_shop_offline()
	phase4_auto_eat()
	phase5_combat_depth()
	phase6_skill_loops()
	phase3_gather_smoke()
	phase_item_loss_guards()
	phase_activity_exclusion()
	phase6_worldgen()
	phase6_chunk_snapshots()
	await phase5_world()
	if failures == 0:
		print("ALL TESTS PASSED")
		get_tree().quit(0)
	else:
		print("%d TEST(S) FAILED" % failures)
		get_tree().quit(1)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		failures += 1
		printerr("FAIL  %s" % label)


func phase0_data() -> void:
	print("== Phase 0: data registry ==")
	# Floors, not exact counts: the content build actively adds/prunes records (M0 hard-
	# deleted ~867 replace/deprecate items), so guard against catastrophic loss, not drift.
	check(DataRegistry.items.size() > 800, "items loaded (%d)" % DataRegistry.items.size())
	check(DataRegistry.enemies.size() == 120, "enemies loaded (%d)" % DataRegistry.enemies.size())
	check(DataRegistry.recipes.size() > 700, "recipes loaded (%d)" % DataRegistry.recipes.size())
	var logs := DataRegistry.get_item("Logs")
	check(not logs.is_empty(), "item lookup by name: Logs")
	# OSRS xp(2)=83, slowed by S=1.25 -> 104. Cap is 99 (was Bloobs 1000).
	check(DataRegistry.xp_for_level(2) == 104, "XP for level 2 == 104 (OSRS x1.25) (got %d)" % DataRegistry.xp_for_level(2))
	check(DataRegistry.max_level == 99, "level cap is 99 (got %d)" % DataRegistry.max_level)
	print("  info XP for level 50 = %d" % DataRegistry.xp_for_level(50))
	check(DataRegistry.xp_for_level(50) > DataRegistry.xp_for_level(49), "XP table monotonic at 50")
	check(DataRegistry.level_for_xp(float(DataRegistry.xp_for_level(50))) == 50, "level_for_xp inverts xp_for_level")
	# BasicEnemy.RecalculateStats: HP = level*4 — verify the export agrees.
	var bad_hp := 0
	for name: String in DataRegistry.enemies:
		var e: Dictionary = DataRegistry.enemies[name]
		if int(e["maxHealth"]) != int(e["level"]) * 4:
			bad_hp += 1
	check(bad_hp == 0, "enemy HP == level*4 across bestiary (%d mismatches)" % bad_hp)
	var chicken := DataRegistry.get_enemy("Chickens")
	check(not chicken.is_empty(), "enemy lookup: Chickens")
	if not chicken.is_empty():
		check(chicken["drops"].size() > 0, "Chickens drop table parsed (%d entries)" % chicken["drops"].size())
	check(not DataRegistry.get_item("Bronze Sword").is_empty(), "recipe-defined gear in item index (Bronze Sword)")
	check(DataRegistry.gather_nodes["woodcutting"].size() >= 19, "tree list parsed (%d trees)" % DataRegistry.gather_nodes["woodcutting"].size())
	# Ids are opaque numeric (item.1042), not name-derived; the legacy slug id
	# (what live saves hold) aliases to the same numeric id.
	var logs_id := DataRegistry.resolve_item_id("Logs")
	check(logs_id.begins_with("item.") and logs_id.trim_prefix("item.").is_valid_int(), "item id is opaque numeric (%s)" % logs_id)
	check(DataRegistry.resolve_item_id(ContentId.item_id("Logs")) == logs_id, "legacy item slug aliases to numeric id")
	check(DataRegistry.resolve_node_id("woodcutting", ContentId.node_id("woodcutting", "Regular Tree")) == DataRegistry.resolve_node_id("woodcutting", "Regular Tree"), "legacy node slug aliases to numeric id")
	check(DataRegistry.resolve_enemy_id(ContentId.enemy_id("Chickens")) == DataRegistry.resolve_enemy_id("Chickens"), "legacy enemy slug aliases to numeric id")


func phase0_content_schema() -> void:
	print("== Phase 0b: content schema ==")
	var result: Dictionary = ValidateContent.run()
	var errors: Array = result["errors"]
	var warnings: Array = result["warnings"]
	if errors.size() > 0:
		for e: String in errors.slice(0, 5):
			printerr("  content error: %s" % e)
	if warnings.size() > 0:
		print("  info %d dangling content refs (export gaps)" % warnings.size())
	check(errors.is_empty(), "content schema valid (%d errors, %d warnings)" % [errors.size(), warnings.size()])


func phase0_stable_ids() -> void:
	print("== Phase 0c: stable id indexes ==")
	check(DataRegistry.items_by_id.size() == DataRegistry.items.size(), "items_by_id indexed")
	check(DataRegistry.items_by_id.has(DataRegistry.resolve_item_id("Oak Logs")), "items_by_id has Oak Logs")
	check(DataRegistry.nodes_by_id.has(DataRegistry.resolve_node_id("woodcutting", "Oak Tree")), "nodes_by_id has Oak Tree")
	# Every item carries an explicit, opaque, frozen numeric id (no name-slug ids).
	var bad_ids := 0
	for name: String in DataRegistry.items:
		var id: String = str(DataRegistry.items[name].get("id", ""))
		if not (id.begins_with("item.") and id.trim_prefix("item.").is_valid_int()):
			bad_ids += 1
	check(bad_ids == 0, "all items carry opaque numeric ids (%d bad)" % bad_ids)


func phase3_content_rename() -> void:
	print("== Phase 3d: IP rename integrity ==")
	# Renamed item: legacy name + id are frozen; displayName changed; both names
	# resolve to the same frozen id (cross-references and saves survive).
	var ore := DataRegistry.get_item("Cerulium Ore")
	check(not ore.is_empty(), "legacy name 'Cerulium Ore' still resolves")
	if not ore.is_empty():
		check(str(ore["name"]) == "Cerulium Ore", "legacy name field unchanged")
		check(str(ore["displayName"]) == "Azurite Ore", "Cerulium Ore -> Azurite Ore (got %s)" % str(ore.get("displayName", "")))
		check(DataRegistry.resolve_item_id("Cerulium Ore") == str(ore["id"]), "legacy name resolves to frozen id")
		check(DataRegistry.resolve_item_id("Azurite Ore") == str(ore["id"]), "new display name resolves to same id")
	check(DataRegistry.enemy_display_name("Aurelion the Sunbound Pharaoh") == "Solheim the Sunbound Pharaoh", "boss exact-renamed")
	check(DataRegistry.item_display_name("Suncoil Logs") == "Elderlog Logs", "token cascade: Suncoil Logs -> Elderlog Logs")

	# Audit: no surviving Bloobs token leaks into ANY display name (items/enemies/
	# nodes). Whole-word match against the rename map's token + exact keys.
	var map := ContentRename.load_map()
	var banned: Dictionary = {}
	for t: String in map.get("tokens", {}):
		banned[t] = true
	banned["Bloob"] = true  # core IP stem must never appear
	var leaks: Array = []
	var scan := func(disp: String) -> void:
		if disp.contains("Bloob"):
			leaks.append(disp)
			return
		for w: String in disp.split(" "):
			if banned.has(w.trim_suffix(",")):
				leaks.append(disp)
				return
	for name: String in DataRegistry.items:
		scan.call(str(DataRegistry.items[name].get("displayName", name)))
	for name: String in DataRegistry.enemies:
		scan.call(str(DataRegistry.enemies[name].get("displayName", name)))
	for skill: String in DataRegistry.gather_nodes:
		for n: Dictionary in DataRegistry.gather_nodes[skill]:
			scan.call(str(n.get("displayName", n["name"])))
	if leaks.size() > 0:
		printerr("  leak examples: %s" % str(leaks.slice(0, 5)))
	check(leaks.is_empty(), "no Bloobs token leaks in display names (%d)" % leaks.size())


func phase4_auto_eat() -> void:
	print("== Phase 4: auto-eat / idle survival ==")
	GameState.reset_state()
	var shrimp_id := DataRegistry.resolve_item_id("Shrimp")  # heals 3
	GameState.add_item("Shrimp", 5)
	# Full HP -> never auto-eats.
	GameState.set_hp(GameState.max_hp())
	check(not GameState.auto_eat(0.5), "no auto-eat at full HP")
	check(GameState.count_item("Shrimp") == 5, "no food wasted at full HP")
	# Best food = the least-wasteful one that covers the deficit (only Shrimp here).
	GameState.set_hp(GameState.max_hp() - 2)
	check(GameState.best_food_id() == shrimp_id, "best_food_id returns available food")
	# Below threshold -> eats exactly one and heals.
	var maxhp := GameState.max_hp()
	GameState.set_hp(maxi(1, int(float(maxhp) * 0.3)))
	var hp_before := GameState.current_hp
	check(GameState.auto_eat(0.5), "auto-eat fires below threshold")
	check(GameState.current_hp > hp_before, "auto-eat raised HP")
	check(GameState.count_item("Shrimp") == 4, "auto-eat consumed one food")
	# Wired into the combat loop and gated by the setting.
	check(CombatSim.has_method("_auto_eat"), "combat loop has auto-eat")
	check(GameSettings.auto_eat_enabled, "auto-eat enabled by default")

	# Integration: taking a hit below threshold mid-combat triggers a heal.
	GameState.reset_state()
	GameState.add_item("Shrimp", 10)
	if CombatSim.start_combat("Chickens", "attack"):
		GameState.set_hp(2)  # below 50% of 10
		var fed_before := GameState.count_item("Shrimp")
		var safety := 2000
		while GameState.count_item("Shrimp") == fed_before and safety > 0 and CombatSim.active:
			CombatSim.advance(0.1)
			safety -= 1
		check(GameState.count_item("Shrimp") < fed_before, "idle combat auto-ate to survive")
		check(GameState.current_hp > 0, "player did not die while food remained")
		CombatSim.stop()


func phase5_combat_depth() -> void:
	print("== Phase 5: combat depth ==")
	GameState.reset_state()
	# Combat level: OSRS formula. Fresh char = Defence 1, HP 10, rest 1.
	# base = 0.25*(1+10+0)=2.75; melee=0.325*(1+1)=0.65 -> floor(3.4)=3.
	check(GameState.combat_level() == 3, "combat level at start == 3 (got %d)" % GameState.combat_level())
	GameState.add_xp("attack", float(DataRegistry.xp_for_level(40)))
	GameState.add_xp("strength", float(DataRegistry.xp_for_level(40)))
	check(GameState.combat_level() > 3, "combat level rises with melee stats (%d)" % GameState.combat_level())

	# Per-weapon attack speed (OSRS ticks): default 4 ticks = 2.4s, or the weapon's
	# data field (in ticks) when present.
	GameState.reset_state()
	check(GameState.attack_ticks() == 4, "default attack speed 4 ticks")
	check(absf(GameState.attack_interval() - 2.4) < 0.001, "default attack interval 2.4s")
	GameState.add_xp("attack", float(DataRegistry.xp_for_level(3)))
	GameState.equip("Bronze Sword")
	var sword := DataRegistry.get_item("Bronze Sword")
	sword["attackSpeed"] = 3   # ticks
	check(absf(GameState.attack_interval() - 1.8) < 0.001, "weapon tick speed overrides default")
	sword.erase("attackSpeed")  # don't leak into other tests

	# Death: one random equipped slot is destroyed (Protect Item negates).
	GameState.reset_state()  # starter equips Bronze Axe in the Axe slot only
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var safety := 200
	var lost := ""
	while lost.is_empty() and safety > 0 and GameState.equipment.has("Axe"):
		lost = GameState.lose_random_equipped_slot(rng)
		safety -= 1
	check(not GameState.equipment.has("Axe"), "death destroyed the equipped item")
	GameState.reset_state()
	GameState.active_prayers = ["Protect Item"]
	check(GameState.is_prayer_active("Protect Item"), "Protect Item prayer registers")

	# DropRoller: guaranteed entries always drop, zero-chance never.
	var rolled: Array = DropRoller.roll([
		{"item": "Bones", "chance": 1.0, "min": 1, "max": 1},
		{"item": "Nothing", "chance": 0.0, "min": 1, "max": 1}], rng)
	check(rolled.size() == 1 and str(rolled[0]["item"]) == "Bones", "DropRoller rolls guaranteed, skips impossible")


func phase6_skill_loops() -> void:
	print("== Phase 6: skill loops ==")

	# Prayer: burying bones grants Prayer XP and consumes them.
	GameState.reset_state()
	GameState.add_item("Bones", 5)
	var pray_before := GameState.xp("prayer")
	var buried := GameState.bury_bones()
	check(buried == 5, "buried all 5 bones (got %d)" % buried)
	check(GameState.count_item("Bones") == 0, "bones consumed on bury")
	check(GameState.xp("prayer") > pray_before, "burying bones grants Prayer XP")

	# High Alchemy: gated at Magic 55, turns an item into coins + Magic XP.
	GameState.reset_state()
	GameState.add_item("Logs", 1)
	check(not GameState.high_alch("Logs"), "High Alch blocked below Magic 55")
	GameState.add_xp("magic", float(DataRegistry.xp_for_level(55)))
	var coins_before := GameState.coins
	var mxp_before := GameState.xp("magic")
	check(GameState.high_alch("Logs"), "High Alch succeeds at Magic 55")
	check(GameState.coins > coins_before, "High Alch yields coins")
	check(GameState.xp("magic") > mxp_before, "High Alch grants Magic XP")
	check(GameState.count_item("Logs") == 0, "High Alch consumed the item")

	# Run energy (Agility meta): drains and regenerates.
	GameState.reset_state()
	GameState.use_run_energy(40.0)
	check(absf(GameState.run_energy - 60.0) < 0.01, "run energy drains")
	GameState.regen_run_energy(10.0)
	check(GameState.run_energy > 60.0, "run energy regenerates over time")

	# Farming: plant -> background growth on the tick -> auto-harvest + XP.
	GameState.reset_state()
	FarmingSim.reset()
	GameState.add_item("Cotton Seed", 1)
	check(FarmingSim.plant("Cotton Seed"), "planted a seed in a plot")
	check(GameState.count_item("Cotton Seed") == 0, "seed consumed on plant")
	var farm_xp_before := GameState.xp("farming")
	# Background-while-busy: a gather runs at the same time as farming growth.
	TickSim.rng.seed = 0x6A7E12
	TickSim.start_gather("woodcutting", "Regular Tree")
	var safety := 400  # 40s > the 20-tick (20s) Cotton grow time
	while GameState.count_item("Cotton") == 0 and safety > 0:
		TickSim.advance(0.1)
		FarmingSim.advance(0.1)
		safety -= 1
	TickSim.stop()
	check(GameState.count_item("Cotton") >= 3, "crop auto-harvested (got %d)" % GameState.count_item("Cotton"))
	check(GameState.xp("farming") > farm_xp_before, "auto-harvest granted Farming XP")
	check(GameState.count_item("Logs") > 0, "gathering ran while farming grew in the background")

	# Farming save round-trip: a growing plot survives save/load.
	FarmingSim.reset()
	GameState.add_item("Cotton Seed", 1)
	FarmingSim.plant("Cotton Seed")
	var snap := FarmingSim.to_save()
	var trip: Dictionary = JSON.parse_string(JSON.stringify(snap))
	FarmingSim.reset()
	FarmingSim.from_save(trip)
	check(FarmingSim.ready_count() == 1, "in-progress plot survives save/load")


func phase2_skill_roster() -> void:
	print("== Phase 2: skill roster + migration ==")
	check(GameState.SKILLS.size() == 22, "22 skills in roster (got %d)" % GameState.SKILLS.size())
	for s: String in ["prayer", "slayer", "hunter", "farming", "alchemy", "agility"]:
		check(GameState.SKILLS.has(s), "roster includes %s" % s)
	for s: String in ["devotion", "beastmastery", "tracking", "dexterity", "homesteading", "herbology", "imbuing", "soulbinding"]:
		check(not GameState.SKILLS.has(s), "roster drops Bloobs skill %s" % s)
	# Recipes were re-homed: no recipe keeps a Bloobs skill key.
	var bad_recipe_skills := 0
	for key: String in DataRegistry.recipes:
		if SkillRemap.MAP.has(str(DataRegistry.recipes[key]["skill"])):
			bad_recipe_skills += 1
	check(bad_recipe_skills == 0, "no recipe keeps a Bloobs skill key (%d)" % bad_recipe_skills)

	# Migration: an old save's skill XP maps to the new keys; folds sum (no loss).
	var legacy := {
		"schemaVersion": 4,
		"skills": {
			"devotion": {"xp": 500.0, "level": 5},
			"beastmastery": {"xp": 1000.0, "level": 8},
			"herbology": {"xp": 300.0, "level": 4},
			"crafting": {"xp": 100.0, "level": 2},
			"imbuing": {"xp": 50.0, "level": 1},
			"soulbinding": {"xp": 25.0, "level": 1},
			"woodcutting": {"xp": 5000.0, "level": 20},
		},
		"inventory": [], "bank": {}, "equipment": {}, "coins": 0, "current_hp": 10,
	}
	var m := SaveMigration.migrate_game_save(legacy)
	var sk: Dictionary = m["skills"]
	check(absf(float(sk["prayer"]["xp"]) - 500.0) < 0.01, "devotion XP -> prayer")
	check(absf(float(sk["slayer"]["xp"]) - 1000.0) < 0.01, "beastmastery XP -> slayer")
	check(absf(float(sk["alchemy"]["xp"]) - 300.0) < 0.01, "herbology XP -> alchemy")
	check(absf(float(sk["crafting"]["xp"]) - 175.0) < 0.01, "crafting + imbuing + soulbinding folded (got %.0f)" % float(sk["crafting"]["xp"]))
	check(absf(float(sk["woodcutting"]["xp"]) - 5000.0) < 0.01, "surviving skill XP preserved")
	check(not sk.has("devotion") and not sk.has("imbuing"), "no Bloobs skill keys remain in migrated save")


func phase1_gathering() -> void:
	print("== Phase 1: gathering tick loop ==")
	GameState.reset_state()
	TickSim.rng.seed = 0x6A7E12  # reproducible rolls regardless of prior phases
	var started := TickSim.start_gather("woodcutting", "Regular Tree")
	check(started, "started woodcutting Regular Tree")
	# OSRS model: one success roll every 4 ticks (2.4s). Success chance is derived
	# to preserve the old tuned economy (~10 Logs/min at L1 with a Bronze Axe).
	check(absf(TickSim.success_chance(1) - 0.4013) < 0.005,
		"L1 Bronze-Axe gather success ~0.40 (got %.4f)" % TickSim.success_chance(1))
	check(TickSim.success_chance(99) > TickSim.success_chance(1),
		"higher level raises gather success (OSRS: level helps, not swing speed)")
	var xp_before := GameState.xp("woodcutting")
	# Simulate 600 seconds in 0.1s frames -> ~250 rolls, expected ~100 Logs.
	for i: int in 6000:
		TickSim.advance(0.1)
	var logs := GameState.count_item("Logs")
	var xp_gained := GameState.xp("woodcutting") - xp_before
	check(logs >= 75 and logs <= 125, "600s WC at L1 yields ~100 Logs (got %d)" % logs)
	check(absf(xp_gained - float(logs) * 25.0) < 0.01, "each Log awards its 25 XP (got %.1f)" % xp_gained)
	check(TickSim.gather_interval() == 2.4, "gather roll cadence is 4 ticks (2.4s)")
	check(TickSim.action_speed(1) == 1.495, "chop speed at level 1 == 1.495")
	check(TickSim.action_speed(100) == 1.0, "chop speed floors at 1.0s")
	TickSim.stop()


func phase1_inventory_bank_equipment() -> void:
	print("== Phase 1: inventory / bank / equipment ==")
	GameState.reset_state()
	GameState.add_item("Logs", 5)
	check(GameState.count_item("Logs") == 5, "add_item stacks")
	GameState.deposit("Logs", 3)
	var logs_id := DataRegistry.resolve_item_id("Logs")
	check(GameState.count_item("Logs") == 2 and int(GameState.bank.get(logs_id, 0)) == 3, "deposit moves to bank")
	GameState.withdraw("Logs", 3)
	check(GameState.count_item("Logs") == 5 and not GameState.bank.has("Logs"), "withdraw returns")
	check(GameState.slot_for_item("Bronze Sword") == "Weapon", "slot inference: sword -> Weapon")
	check(GameState.slot_for_item("Bronze Pickaxe") == "Pickaxe", "slot inference: pickaxe before axe")
	check(GameState.equipment.get("Axe", "") == DataRegistry.resolve_item_id("Bronze Axe"), "starter axe equipped")
	check(GameState.tool_progress("woodcutting") == 25, "tool progress read from Axe slot")
	# Bronze Sword requires Attack 3 — equip must be gated, then succeed.
	check(not GameState.equip("Bronze Sword"), "equip blocked below Attack req")
	GameState.add_xp("attack", float(DataRegistry.xp_for_level(3)))
	check(GameState.equip("Bronze Sword"), "equip succeeds at Attack 3")
	check(GameState.equipment_damage() == 1.0, "Bronze Sword adds 1 equipment damage")


func phase2_combat() -> void:
	print("== Phase 2: combat vs Chickens ==")
	GameState.reset_state()
	var started := CombatSim.start_combat("Chickens", "attack")
	check(started, "combat started")
	var hp_xp_before := GameState.xp("hitpoints")
	var atk_xp_before := GameState.xp("attack")
	# Simulate up to 10 minutes; stop after the first kill + respawn.
	var safety := 6000
	while CombatSim.kills < 3 and safety > 0 and CombatSim.active:
		CombatSim.advance(0.1)
		safety -= 1
	check(CombatSim.kills >= 3, "killed Chickens 3 times within sim budget (kills=%d)" % CombatSim.kills)
	var e := DataRegistry.get_enemy("Chickens")
	var atk_gain := GameState.xp("attack") - atk_xp_before
	var hp_gain := GameState.xp("hitpoints") - hp_xp_before
	# Phase 5: XP is awarded per hit now, so the trained skill and HP both accrue
	# in proportion to damage dealt (ratio == the style coefficients).
	check(atk_gain > 0.0, "per-hit attack XP accrues (%.1f)" % atk_gain)
	check(hp_gain > 0.0, "per-hit hitpoints XP accrues (%.1f)" % hp_gain)
	var ratio := atk_gain / maxf(hp_gain, 0.001)
	check(absf(ratio - CombatStyles.XP_PER_DAMAGE / CombatStyles.HP_XP_PER_DAMAGE) < 0.05,
		"per-hit XP ratio matches style coefficients (got %.2f)" % ratio)
	var got_drop := false
	for d: Dictionary in e["drops"]:
		if float(d["chance"]) >= 0.99 and GameState.count_item(d["item"]) >= CombatSim.kills:
			got_drop = true
	check(got_drop, "100%% drop received on every kill")
	CombatSim.stop()


func phase3_save_roundtrip() -> void:
	print("== Phase 3: save/load round trip ==")
	GameState.reset_state()
	GameState.add_xp("woodcutting", 5000.0)
	GameState.add_item("Logs", 42)
	GameState.deposit("Logs", 20)
	GameState.add_coins(1234)
	GameState.player_pos = Vector2(321.5, -654.0)
	var snapshot := GameState.to_save_dict()
	var json_trip: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	GameState.reset_state()
	check(not GameState.player_pos.is_finite(), "reset clears player_pos to spawn sentinel")
	GameState.from_save_dict(json_trip)
	check(GameState.player_pos.is_equal_approx(Vector2(321.5, -654.0)), "player world position survives save")
	check(GameState.level("woodcutting") == DataRegistry.level_for_xp(5000.0), "skill level survives save")
	check(GameState.count_item("Logs") == 22, "inventory survives save (got %d)" % GameState.count_item("Logs"))
	check(int(GameState.bank.get(DataRegistry.resolve_item_id("Logs"), 0)) == 20, "bank survives save")
	check(GameState.coins == 1234, "coins survive save")
	check(snapshot.has("coins") and not snapshot.has("gold"), "save dict uses coins field, not gold")
	check(GameState.equipment.get("Axe", "") == DataRegistry.resolve_item_id("Bronze Axe"), "equipment survives save")
	check(int(snapshot.get("schemaVersion", 0)) >= 4, "save dict includes schemaVersion")
	check(GameState.BASE_INVENTORY_SLOTS == 28, "inventory is 28 slots")


func phase3_save_migration() -> void:
	print("== Phase 3b: save migration v1 -> v2 ==")
	GameState.reset_state()
	GameState.add_item("Logs", 5)
	var legacy := {
		"skills": GameState.skills.duplicate(true),
		"inventory": [{"name": "Logs", "qty": 5}],
		"bank": {"Logs": 10},
		"equipment": {"Axe": "Bronze Axe"},
		"gold": 0,
		"current_hp": 10,
	}
	var migrated := SaveMigration.migrate_game_save(legacy)
	check(migrated["inventory"][0]["id"] == DataRegistry.resolve_item_id("Logs"), "migrates inventory names to ids")
	check(migrated["bank"].has(DataRegistry.resolve_item_id("Logs")), "migrates bank keys to ids")
	GameState.reset_state()
	GameState.from_save_dict(legacy)
	check(GameState.count_item("Logs") == 5, "legacy name save loads")
	check(int(GameState.bank.get(DataRegistry.resolve_item_id("Logs"), 0)) == 10, "legacy bank loads")

	# v2 -> v3: a previous-release save holds the old *slug* ids; every one must
	# migrate to its opaque numeric id with zero "unknown item" loss.
	var logs_slug := ContentId.item_id("Logs")
	var oak_slug := ContentId.item_id("Oak Logs")
	var axe_slug := ContentId.item_id("Bronze Axe")
	var v2 := {
		"schemaVersion": 2,
		"skills": GameState.skills.duplicate(true),
		"inventory": [{"id": logs_slug, "qty": 7}, {"id": oak_slug, "qty": 3}],
		"bank": {logs_slug: 10},
		"equipment": {"Axe": axe_slug},
		"gold": 0,
		"current_hp": 10,
		"activity": {"kind": "gather", "skill": "woodcutting", "node_id": ContentId.node_id("woodcutting", "Regular Tree")},
	}
	var v3 := SaveMigration.migrate_game_save(v2)
	check(int(v3["schemaVersion"]) == SaveMigration.CURRENT_SCHEMA, "v2 save bumped to current schema")
	var logs_num := DataRegistry.resolve_item_id("Logs")
	check(v3["inventory"][0]["id"] == logs_num and int(v3["inventory"][0]["qty"]) == 7, "v3 inventory slug->numeric")
	check(v3["inventory"].size() == 2, "v3 inventory loses no stacks")
	check(v3["bank"].has(logs_num), "v3 bank slug->numeric")
	check(v3["equipment"]["Axe"] == DataRegistry.resolve_item_id("Bronze Axe"), "v3 equipment slug->numeric")
	check(v3["activity"]["node_id"] == DataRegistry.resolve_node_id("woodcutting", "Regular Tree"), "v3 activity node slug->numeric")


func phase3_rename_alias() -> void:
	print("== Phase 3c: rename alias resolution ==")
	var alias_id := DataRegistry.resolve_item_id("Logs")
	DataRegistry.aliases["items"]["Legacy Log Stack"] = alias_id
	check(DataRegistry.resolve_item_id("Legacy Log Stack") == alias_id, "alias resolves renamed display name")
	check(not DataRegistry.get_item("Legacy Log Stack").is_empty(), "alias lookup returns item")
	GameState.reset_state()
	GameState.from_save_dict({
		"inventory": [{"name": "Legacy Log Stack", "qty": 3}],
		"bank": {},
		"equipment": {},
		"skills": GameState.skills,
		"gold": 0,
		"current_hp": 10,
	})
	check(GameState.count_item(alias_id) == 3, "renamed item in save loads via alias")
	DataRegistry.aliases["items"].erase("Legacy Log Stack")


func phase3_recipes() -> void:
	print("== Phase 3: crafting loop ==")
	GameState.reset_state()
	# Cook Raw Shrimp -> Shrimp (cooking level 5 recipe in the export).
	var recipe := DataRegistry.get_recipe("cooking", "Shrimp")
	check(not recipe.is_empty(), "cooking recipe lookup: Shrimp")
	if recipe.is_empty():
		return
	GameState.add_item("Raw Shrimp", 3)
	check(not RecipeSim.start_craft("cooking", "Shrimp"), "craft blocked below level req")
	GameState.add_xp("cooking", float(DataRegistry.xp_for_level(5)))
	check(RecipeSim.start_craft("cooking", "Shrimp"), "crafting started at level 5")
	var xp_before := GameState.xp("cooking")
	for i: int in int(float(recipe["time"]) * 10.0 * 3.5):
		RecipeSim.advance(0.1)
	check(GameState.count_item("Shrimp") == 3, "3 Shrimp cooked (got %d)" % GameState.count_item("Shrimp"))
	check(GameState.count_item("Raw Shrimp") == 0, "inputs consumed")
	check(not RecipeSim.active, "crafting auto-stopped when out of inputs")
	check(absf(GameState.xp("cooking") - xp_before - 3.0 * float(recipe["xp"])) < 0.01, "cooking XP from recipe data")

	# Firemaking (M6): burn logs -> Ashes + Firemaking XP, via RecipeSim (no station).
	var fm := DataRegistry.get_recipe("firemaking", "Burn Logs")
	check(not fm.is_empty(), "firemaking recipe exists (Burn Logs)")
	if not fm.is_empty():
		GameState.add_item("Logs", 4)
		var fm_ash := GameState.count_item("Ashes")
		var fm_xp := GameState.xp("firemaking")
		check(RecipeSim.start_craft("firemaking", "Burn Logs"), "firemaking started (no station)")
		for i: int in int(float(fm["time"]) * 10.0 * 4.5):
			RecipeSim.advance(0.1)
		check(GameState.count_item("Ashes") - fm_ash >= 3, "logs burned to Ashes (got %d)" % (GameState.count_item("Ashes") - fm_ash))
		check(GameState.xp("firemaking") > fm_xp, "firemaking XP gained")

	# Prayer (M6): Devotion, toggle, group exclusivity, drain, combat multiplier.
	GameState.reset_state()
	GameState.add_xp("prayer", float(DataRegistry.xp_for_level(20)))
	GameState.recharge_devotion()
	check(GameState.devotion_points() == float(GameState.devotion_max()), "devotion full after recharge")
	check(GameState.toggle_prayer("Clarity of Thought"), "prayer toggled on")
	check(GameState.is_prayer_active("Clarity of Thought"), "prayer is active")
	check(absf(GameState.prayer_accuracy_mult("melee") - 1.05) < 0.001, "prayer accuracy multiplier applies")
	GameState.toggle_prayer("Improved Reflexes")  # same "accuracy" group
	check(not GameState.is_prayer_active("Clarity of Thought"), "same-group prayer auto-deactivated")
	var dev0 := GameState.devotion_points()
	GameState.drain_devotion(1.0)
	check(GameState.devotion_points() < dev0, "devotion drains while a prayer is active")
	GameState.toggle_prayer("Improved Reflexes")
	check(GameState.active_prayers.is_empty(), "prayer toggled off")

	# Hunter + Thieving (M6): new GATHER skills via the existing pipeline (no tool gate).
	for sk: Array in [["hunter", "Bird Snare"], ["thieving", "Fruit Stall"]]:
		var gnode := DataRegistry.get_gather_node(str(sk[0]), str(sk[1]))
		check(not gnode.is_empty(), "%s node exists (%s)" % [sk[0], sk[1]])
		if not gnode.is_empty():
			GameState.reset_state()
			check(TickSim.start_gather(str(sk[0]), str(sk[1])), "%s gather started without a tool" % sk[0])
			var gxp := GameState.xp(str(sk[0]))
			for i: int in 600:
				TickSim.advance(0.1)
				if GameState.xp(str(sk[0])) > gxp:
					break
			check(GameState.xp(str(sk[0])) > gxp, "%s XP gained from gathering" % sk[0])
			TickSim.stop("test")


func phase4_food_shop_offline() -> void:
	print("== Phase 4: food / shop / no-offline / coins migration ==")
	GameState.reset_state()
	GameState.set_hp(5)
	GameState.add_item("Shrimp", 2)
	check(GameState.eat("Shrimp"), "eating cooked food works")
	check(GameState.current_hp == 8, "Shrimp heals 3 (hp=%d)" % GameState.current_hp)
	GameState.add_coins(300)
	check(GameState.buy_item("Iron Axe", 1), "shop purchase works")
	check(GameState.coins == 300 - DataRegistry.item_value("Iron Axe"), "coins deducted (%d left)" % GameState.coins)
	check(not GameState.buy_item("Sunwrought Axe", 1), "purchase blocked without coins")

	# Offline progress is removed: loading a save never fast-forwards time away.
	check(not SaveManager.has_method("_apply_offline_progress"), "offline progress removed from SaveManager")

	# v3 (or older) save carrying the legacy 'gold' field migrates to 'coins'.
	var legacy_gold := {
		"schemaVersion": 3,
		"skills": GameState.skills.duplicate(true),
		"inventory": [], "bank": {}, "equipment": {},
		"gold": 777, "current_hp": 10,
	}
	var migrated := SaveMigration.migrate_game_save(legacy_gold)
	check(int(migrated.get("coins", -1)) == 777 and not migrated.has("gold"), "gold field migrates to coins")
	GameState.reset_state()
	GameState.from_save_dict(legacy_gold)
	check(GameState.coins == 777, "legacy gold save loads as coins")


## The gather loop drives loot + activity state. Formerly asserted through the legacy
## 2D UI's labels (scenes/main.tscn); now tests the underlying TickSim/GameState
## behaviour directly, so the legacy UI can be deleted.
## Fill every free inventory slot with distinct items (so add_item of a NEW item
## returns 0), skipping any names in `exclude`.
func _fill_bag(exclude: Array) -> void:
	var ex := {}
	for n: String in exclude:
		ex[DataRegistry.resolve_item_id(n)] = true
	for id: String in DataRegistry.items_by_id.keys():
		if GameState.inventory.size() >= GameState.max_inventory_slots():
			return
		if ex.has(id) or GameState.count_item(id) > 0:
			continue
		GameState.add_item(id, 1)


## Guards against the item-loss bugs: a full inventory must never destroy items when
## swapping equipment or when a craft's output can't fit.
func phase_item_loss_guards() -> void:
	print("== Item-loss guards ==")
	# Equip swap on a full bag must return the worn item, not overwrite/destroy it.
	GameState.reset_state()
	GameState.add_xp("defence", 200000.0)   # high enough to wear Iron Helm
	GameState.add_item("Bronze Helm", 1)
	check(GameState.equip("Bronze Helm"), "equip Bronze Helm")
	GameState.add_item("Iron Helm", 1)
	_fill_bag([])
	check(GameState.inventory.size() >= GameState.max_inventory_slots(), "inventory full for equip-swap test")
	check(GameState.equip("Iron Helm"), "equip Iron Helm over Bronze on a full bag")
	check(GameState.count_item("Bronze Helm") == 1, "swapped-out Bronze Helm returned (not destroyed)")
	check(GameState.count_item("Iron Helm") == 0, "Iron Helm now worn")

	# Recipe whose output can't fit must roll the inputs back, not consume them.
	GameState.reset_state()
	GameState.add_item("Logs", 5)
	RecipeSim.recipe = {"inputs": [{"item": "Logs", "qty": 1}], "output": {"item": "Oak Logs", "qty": 1}, "skill": "woodcutting", "xp": 1.0}
	RecipeSim.active = true
	_fill_bag(["Oak Logs"])   # full, and the output item is absent so it needs a new slot
	var logs_before := GameState.count_item("Logs")
	RecipeSim._complete_craft()
	check(GameState.count_item("Logs") == logs_before, "craft inputs rolled back when output can't fit")
	check(GameState.count_item("Oak Logs") == 0, "no phantom output produced on a full bag")
	RecipeSim.active = false


## The three active sims (gather/combat/craft) are mutually exclusive: starting one
## stops the others via ActivityManager. Guards that registration + arbitration work.
func phase_activity_exclusion() -> void:
	print("== Activity mutual exclusion ==")
	GameState.reset_state()
	TickSim.rng.seed = 1
	if not TickSim.start_gather("woodcutting", "Regular Tree"):
		check(false, "could not start gather for exclusion test")
		return
	check(TickSim.active, "gather active before combat")
	if CombatSim.start_combat("Chickens", "attack"):
		check(not TickSim.active, "starting combat stops gathering")
		check(CombatSim.active, "combat active")
	TickSim.start_gather("woodcutting", "Regular Tree")
	check(not CombatSim.active, "starting gather stops combat")
	TickSim.stop()
	CombatSim.stop()


func phase3_gather_smoke() -> void:
	print("== Phase 3: gather loop smoke test ==")
	GameState.reset_state()
	TickSim.rng.seed = 0x6A7E12
	check(TickSim.start_gather("woodcutting", "Regular Tree"), "start_gather woodcutting Regular Tree")
	check(TickSim.active and TickSim.skill == "woodcutting", "tick sim active on the requested skill")
	for i: int in 600:  # ~25 rolls; a Log is effectively certain at p~0.4
		TickSim.advance(0.1)
	check(GameState.count_item("Logs") > 0, "gathering yields Logs")
	TickSim.stop()
	check(not TickSim.active, "tick sim idle after stop")


## Drive the player along its A* path instantly (teleport to each waypoint
## and fire arrived) until the pending action executes or the walk ends.
func _drive_walk(world: Node2D) -> void:
	var player: Node2D = world.get("player")
	var safety := 600
	while safety > 0:
		safety -= 1
		if not bool(player.get("walking")):
			break
		player.position = player.get("walk_target")
		player.set("walking", false)
		player.emit_signal("arrived")


func phase5_world() -> void:
	print("== Phase 5: procedural world scene ==")
	GameState.reset_state()
	WorldGen.reset(WorldGen.DEFAULT_SEED)
	var scene: PackedScene = load("res://scenes/world.tscn")
	var world: Node2D = scene.instantiate()
	add_child(world)
	await get_tree().process_frame

	check(world.get("player") != null, "player avatar exists")
	var loaded: Array = world.get("chunk_manager").call("loaded_chunks")
	check(loaded.size() >= 49, "nav-ring chunks active around spawn (%d)" % loaded.size())
	var terrain_count: int = int(world.get("chunk_manager").call("terrain_chunk_count"))
	check(terrain_count >= 49, "wide terrain ring starts loaded (%d chunks)" % terrain_count)
	var entities: Array = world.get("entities")
	check(entities.size() > 30, "world entities spawned from chunk data (%d)" % entities.size())

	var hud: CanvasLayer = world.get("hud")
	check(hud != null, "OSRS HUD attached")
	var hover: Label = hud.get("hover_label")
	check(hover.text == "Walk here", "default hover text")
	var chat: RichTextLabel = hud.get("chat")
	check(chat.text.contains("Welcome to Imota"), "chatbox welcome line")

	var enemy_tooltip_ok := false
	for e: Node2D in entities:
		if str(e.get("action").get("type", "")) != "enemy":
			continue
		var content: Dictionary = e.call("tooltip_content")
		if not str(content.get("title", "")).is_empty() and not str(content.get("action", "")).is_empty():
			enemy_tooltip_ok = true
			break
	check(enemy_tooltip_ok, "enemy tooltip has title and action text")

	# Home camp around the spawn: bank chest entity exists.
	var bank_entity: Node2D = null
	var gather_entity: Node2D = null
	for e: Node2D in entities:
		var a: Dictionary = e.get("action")
		if str(a.get("station", "")) == "bank" and bank_entity == null:
			bank_entity = e
		if str(a.get("type", "")) == "gather" and gather_entity == null \
				and GameState.level(str(a["skill"])) >= 1 and int(e.get("sub_label").trim_prefix("Lvl ")) == 1:
			gather_entity = e
	check(bank_entity != null, "bank chest spawned at the home campsite")
	check(gather_entity != null, "a level-1 gather site exists near spawn")

	# Click-to-walk-to-gather: walk the path, then TickSim starts.
	if gather_entity != null:
		world.call("begin_action", gather_entity)
		_drive_walk(world)
		check(TickSim.active, "walk-to gather starts TickSim")
		var gather_skill := str(Dictionary(gather_entity.get("action"))["skill"])
		check(TickSim.skill == gather_skill, "TickSim gathers the clicked skill")
		TickSim.stop()

	# Auto-gather loop: find nearest node by name, walk there, gather, and
	# deplete -> the task hunts the next node.
	world.call("auto_gather", "woodcutting", "Regular Tree")
	_drive_walk(world)
	if TickSim.active:
		check(TickSim.node["name"] == "Regular Tree", "auto-gather reached the nearest Regular Tree")
		var site_ref: Dictionary = world.get("gather_ref")
		check(not site_ref.is_empty(), "gather site tracked for depletion")
		# Burn the node dry: each xp tick consumes one resource.
		var spins := 200
		while TickSim.active and spins > 0:
			TickSim.advance(6.0)
			spins -= 1
		check(not TickSim.active, "node depleted stops gathering")
		var task: Dictionary = world.get("auto_task")
		check(str(task.get("mode", "")) == "gather", "auto task persists after depletion")
		await get_tree().process_frame  # _auto_find_next is deferred
		_drive_walk(world)
		task = world.get("auto_task")
		check(TickSim.active or bool(task.get("waiting", false)), "auto task moved to the next node (or waits for respawn)")
		TickSim.stop()
	else:
		check(false, "auto_gather walked to a Regular Tree and started")

	# Bank auto-path.
	world.call("auto_bank")
	_drive_walk(world)
	check(str(hud.get("popup_title").get("text")) == "Bank", "auto_bank walks to the bank and opens it")
	world.queue_free()
	await get_tree().process_frame


func phase6_worldgen() -> void:
	print("== Phase 6: procedural world generation ==")
	# Determinism: identical seed -> identical chunk.
	var proc_chunk := Vector2i(14, 12)  # Tanglewild is fixed:false, so it stays procedural.
	WorldGen.reset(4242)
	var a: RefCounted = WorldGen.get_chunk(0, proc_chunk.x, proc_chunk.y)
	var a_tiles: PackedByteArray = a.tiles.duplicate()
	var a_sites: int = a.sites.size()
	var a_first := "" if a.sites.is_empty() else str(a.sites[0]["node"])
	WorldGen.reset(4242)
	var b: RefCounted = WorldGen.get_chunk(0, proc_chunk.x, proc_chunk.y)
	check(b.tiles == a_tiles, "same seed regenerates identical tiles")
	check(b.sites.size() == a_sites and (b.sites.is_empty() or str(b.sites[0]["node"]) == a_first),
		"same seed regenerates identical sites")
	WorldGen.reset(4243)
	var c: RefCounted = WorldGen.get_chunk(0, proc_chunk.x, proc_chunk.y)
	check(c.tiles != a_tiles, "different seed yields different terrain")

	WorldGen.reset(WorldGen.DEFAULT_SEED)
	# Home chunk guarantees: campsite with bank + respawn + safety.
	var home: RefCounted = WorldGen.get_chunk(0, 0, 0)
	var camp: Dictionary = {}
	for poi: Dictionary in home.pois:
		if str(poi["type"]) == "campsite":
			camp = poi
	check(not camp.is_empty(), "home chunk has a campsite")
	check(bool(camp.get("respawn", false)) and home.safe, "home campsite is a safe respawn point")
	var spawn := WorldGen.spawn_position()
	check(WorldGen.is_spawn_floor(spawn), "player spawn is on dry flat ground (not water or shore)")
	if WorldGen.reg.spec.active and WorldGen.reg.spec.finite:
		var finite_bounds: Rect2i = WorldGen.reg.spec.bounds
		var top_edge: RefCounted = WorldGen.get_chunk(0,
			finite_bounds.position.x + finite_bounds.size.x / 2,
			finite_bounds.position.y + 3)
		var sand_id: int = int(WorldGen.reg.tile_index["sand"])
		var sand_count := 0
		for tid: int in top_edge.tiles:
			if tid == sand_id:
				sand_count += 1
		check(sand_count < int(float(top_edge.tiles.size()) * 0.80),
			"finite coastline avoids all-sand square edge chunks (%d/%d sand)" % [sand_count, top_edge.tiles.size()])
		var elevated_water := 0
		for cc: Vector2i in [Vector2i(-3, -24), Vector2i(6, -22), Vector2i(3, -28)]:
			var alpine_chunk: RefCounted = WorldGen.get_chunk(0, cc.x, cc.y)
			for i: int in alpine_chunk.tiles.size():
				if alpine_chunk.elev[i] > 3 and bool(WorldGen.reg.tile_def(alpine_chunk.tiles[i]).get("water", false)):
					elevated_water += 1
		check(elevated_water == 0, "mountains displace stray lake/river water above their feet")
		for inland: Vector2i in [Vector2i(203, -447), Vector2i(165, -448)]:
			var inland_parent_idx: int = WorldGen.generator.classifier.parent_biome_idx(float(inland.x), float(inland.y))
			var inland_parent: String = str(WorldGen.reg.biomes[inland_parent_idx]["id"])
			check(inland_parent != "ocean", "low inland valley %s is not classified as ocean" % [inland])
	var has_bank := false
	for part: Dictionary in camp.get("parts", []):
		if str(part.get("station", "")) == "bank":
			has_bank = true
	check(has_bank, "home campsite includes a bank chest")
	check(WorldGen.find_nearest_station(0, Vector2.ZERO, "bank").size() > 0, "find_nearest_station locates a bank")

	# Terrain pathing: water is never a node; gentle slopes up to MAX_CLIMB_STEP (2)
	# are walkable, but a steeper cliff edge (3+ steps) is not.
	var pf_chunk: RefCounted = Chunk.new()
	pf_chunk.setup(0, 200, 200)
	pf_chunk.zone = {"req": 1}
	pf_chunk.tiles.fill(int(WorldGen.reg.tile_index["grass"]))
	pf_chunk.tiles[Chunk.idx(1, 0)] = int(WorldGen.reg.tile_index["shallow"])
	pf_chunk.elev[Chunk.idx(0, 1)] = 1
	pf_chunk.elev[Chunk.idx(0, 2)] = 3   # +2 from (0,1): a walkable slope
	pf_chunk.elev[Chunk.idx(0, 3)] = 6   # +3 from (0,2): too steep to climb
	pf_chunk.elev[Chunk.idx(2, 0)] = 34  # high shelf remains a valid navigation node
	pf_chunk.elev[Chunk.idx(3, 0)] = 46  # above MAX_REACHABLE_ELEV (44): summit crown excluded
	var pf := PathFinder.new()
	pf.rebuild([pf_chunk], WorldGen.reg, 1)
	var base := Vector2i(pf_chunk.cx, pf_chunk.cy) * WG.CHUNK_TILES
	check(not pf.has_reachable_tile(base + Vector2i(1, 0)), "pathfinder rejects shallow water nodes")
	var climb_one := pf.find_path(
		WG.tile_to_world(base.x, base.y),
		WG.tile_to_world(base.x, base.y + 1),
		false)
	check(not climb_one.is_empty(), "pathfinder allows one-step elevation climbs")
	var climb_two := pf.find_path(
		WG.tile_to_world(base.x, base.y + 1),
		WG.tile_to_world(base.x, base.y + 2),
		false)
	check(not climb_two.is_empty(), "pathfinder allows two-step slope climbs")
	var climb_three := pf.find_path(
		WG.tile_to_world(base.x, base.y + 2),
		WG.tile_to_world(base.x, base.y + 3),
		false)
	check(climb_three.is_empty(), "pathfinder rejects three-step cliff climbs")
	check(pf.has_reachable_tile(base + Vector2i(2, 0)), "pathfinder includes high climbable alpine shelves")
	check(not pf.has_reachable_tile(base + Vector2i(3, 0)), "pathfinder excludes only the summit crown")

	# Admin teleports are allowed to target authored/biome tiles that happen to
	# be on raised mountain terrain, but the final landing tile must be flat.
	var admin_chunk: RefCounted = Chunk.new()
	admin_chunk.setup(0, 230, 230)
	admin_chunk.zone = {"req": 1}
	admin_chunk.tiles.fill(int(WorldGen.reg.tile_index["grass"]))
	admin_chunk.elev.fill(5)
	admin_chunk.elev[Chunk.idx(4, 3)] = 0
	WorldGen.chunks[admin_chunk.key()] = admin_chunk
	var raised_admin_target: Vector2 = admin_chunk.tile_world(3, 3)
	var flat_admin_landing: Vector2 = WorldGen.nearest_admin_teleport_world(raised_admin_target, 0, 4)
	check(not WorldGen.is_admin_teleport_floor(raised_admin_target), "admin landing rejects raised walkable terraces")
	check(WorldGen.is_admin_teleport_floor(flat_admin_landing)
		and WorldGen.elevation_at(flat_admin_landing) == 0,
		"admin teleport snaps to zero-elevation walkable ground")

	# Zone scaling: home zone is level 1, far zones are far harder.
	var home_zone: Dictionary = WorldGen.generator.zone_map.zone_for_chunk(0, 0)
	check(int(home_zone["req"]) == 1, "home zone requirement is 1")
	var far_zone: Dictionary = WorldGen.generator.zone_map.zone_for_chunk(50, 50)
	check(int(far_zone["req"]) >= 60, "zone at distance 70 chunks is level 60+ (got %d)" % int(far_zone["req"]))
	check(not str(home_zone["name"]).is_empty(), "zones get procedural names (%s)" % str(home_zone["name"]))

	# Sites respect the zone band and fishing sits at water edges.
	var checked_sites := 0
	var band_ok := true
	var water_ok := true
	for cy: int in range(-2, 3):
		for cx: int in range(-2, 3):
			var chunk: RefCounted = WorldGen.get_chunk(0, cx, cy)
			var req := int(chunk.zone["req"])
			for s: Dictionary in chunk.sites:
				checked_sites += 1
				if int(s["level"]) > req + 10:
					band_ok = false
				if str(s["skill"]) == "fishing":
					var adj := false
					for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = int(s["tx"]) + off.x
						var ny: int = int(s["ty"]) + off.y
						if nx >= 0 and ny >= 0 and nx < 16 and ny < 16 \
								and bool(WorldGen.reg.tile_def(chunk.tile_id(nx, ny))["water"]):
							adj = true
					if not adj:
						water_ok = false
	check(checked_sites > 20, "gather sites populate the home area (%d)" % checked_sites)
	check(band_ok, "every site's node level fits its zone band")
	check(water_ok, "fishing spots all touch water")

	# Monsters stay within the zone level band and out of safe chunks.
	check(home.monsters.is_empty(), "no monsters in the safe home chunk")
	var monster_ok := true
	var monster_count := 0
	for cy: int in range(-2, 3):
		for cx: int in range(-2, 3):
			var chunk: RefCounted = WorldGen.get_chunk(0, cx, cy)
			var req := float(chunk.zone["req"])
			for m: Dictionary in chunk.monsters:
				monster_count += 1
				if float(m["level"]) > req * 2.6 + 0.01:
					monster_ok = false
	check(monster_count > 0, "monsters roam the home area (%d)" % monster_count)
	check(monster_ok, "monster levels fit their zone band")

	# Caves: deterministic, ladders mirror the surface entrance, tiles valid.
	var entrance: Dictionary = WorldGen.find_nearest_poi(0, Vector2.ZERO, ["cave_entrance"])
	check(not entrance.is_empty(), "a cave entrance exists near spawn")
	if not entrance.is_empty():
		var sc: RefCounted = entrance["chunk"]
		var cave: RefCounted = WorldGen.get_chunk(-1, sc.cx, sc.cy)
		var ladder := false
		for poi: Dictionary in cave.pois:
			if str(poi["type"]) == "ladder_up":
				var part: Dictionary = poi["parts"][0]
				if int(part["tx"]) == int(entrance["part"]["tx"]) and int(part["ty"]) == int(entrance["part"]["ty"]):
					ladder = true
		check(ladder, "cave ladder_up matches the surface entrance tile")
		var floor_found := false
		for i: int in cave.tiles.size():
			if bool(WorldGen.reg.tile_def(cave.tiles[i])["walkable"]):
				floor_found = true
				break
		check(floor_found, "cave layer has walkable floor")

	# Depletion persistence: a depleted site survives a chunk-cache wipe and
	# respawns once its timer has passed.
	var site_chunk: RefCounted = null
	for cy: int in range(-2, 3):
		for cx: int in range(-2, 3):
			if site_chunk == null and WorldGen.get_chunk(0, cx, cy).sites.size() > 0:
				site_chunk = WorldGen.get_chunk(0, cx, cy)
	if site_chunk != null:
		var key: String = site_chunk.key()
		WorldGen.deplete_site(site_chunk, 0)
		WorldGen.chunks.clear()
		var reloaded: RefCounted = WorldGen.get_chunk(0, site_chunk.cx, site_chunk.cy)
		check(not bool(reloaded.sites[0]["available"]), "depleted site persists across chunk reload")
		WorldGen.store.record_depletion(key, 0, Time.get_unix_time_from_system() - 5.0)
		WorldGen.chunks.clear()
		var respawned: RefCounted = WorldGen.get_chunk(0, site_chunk.cx, site_chunk.cy)
		check(bool(respawned.sites[0]["available"]), "expired depletion respawns on reload")

	# Obelisk unlock + teleport registry.
	var obelisk: Dictionary = WorldGen.find_nearest_poi(0, Vector2.ZERO, ["obelisk"])
	check(not obelisk.is_empty(), "a teleport obelisk exists in the world")
	if not obelisk.is_empty():
		check(WorldGen.unlock_obelisk(obelisk["chunk"], obelisk["poi"]), "obelisk attunes once")
		check(not WorldGen.unlock_obelisk(obelisk["chunk"], obelisk["poi"]), "obelisk does not attune twice")
		check(WorldGen.unlocked_obelisks().size() == 1, "unlocked obelisk listed for teleport")

	# Nearest-site search returns the actual closest available node.
	var near: Dictionary = WorldGen.find_nearest_site(0, Vector2.ZERO, "woodcutting", "Regular Tree", 4)
	check(not near.is_empty(), "find_nearest_site locates a Regular Tree near spawn")

	WorldGen.reset(WorldGen.DEFAULT_SEED)


func phase6_chunk_snapshots() -> void:
	print("== Phase 6b: chunk snapshot preservation ==")
	WorldGen.reset(9999)
	var chunk_a: RefCounted = WorldGen.get_chunk(0, 14, 12)
	var tiles_a: PackedByteArray = chunk_a.tiles.duplicate()
	var elev_a: PackedByteArray = chunk_a.elev.duplicate()
	var sites_a: int = chunk_a.sites.size()
	WorldGen.snapshot_chunk_if_needed(chunk_a)
	check(WorldGen.store.has_chunk_snapshot(chunk_a.key()), "snapshot saved for explored chunk")
	WorldGen.chunks.clear()
	WorldGen.generator.setup(WorldGen.reg, 8888)
	var chunk_b: RefCounted = WorldGen.get_chunk(0, 14, 12)
	check(chunk_b.tiles == tiles_a, "snapshot restores identical tiles after seed change")
	check(chunk_b.elev == elev_a, "snapshot restores identical elevation after seed change")
	check(chunk_b.sites.size() == sites_a, "snapshot restores site count")
	var unvisited: RefCounted = WorldGen.get_chunk(0, 15, 12)
	WorldGen.chunks.clear()
	WorldGen.generator.setup(WorldGen.reg, 7777)
	var unvisited_b: RefCounted = WorldGen.get_chunk(0, 15, 12)
	check(not WorldGen.store.has_chunk_snapshot(unvisited.key()), "unvisited chunk has no snapshot")
	check(unvisited_b.tiles != unvisited.tiles or unvisited_b.sites.size() != unvisited.sites.size(),
		"unvisited chunk regenerates with new generator (no snapshot)")

	# Disk round-trip: snapshots must survive JSON (Vector2i fields become
	# strings if not normalized — this broke spawn_position on second launch).
	WorldGen.snapshot_chunk_if_needed(WorldGen.get_chunk(0, 0, 0))
	var trip: Variant = JSON.parse_string(JSON.stringify(WorldGen.store.chunk_snapshots))
	WorldGen.store.chunk_snapshots = trip
	WorldGen.chunks.clear()
	var chunk_c: RefCounted = WorldGen.get_chunk(0, 14, 12)
	check(chunk_c.tiles == tiles_a, "snapshot survives JSON disk round-trip")
	var home_c: RefCounted = WorldGen.get_chunk(0, 0, 0)
	var anchors_typed: bool = home_c.pois.size() > 0
	for poi: Dictionary in home_c.pois:
		if not poi.get("anchor") is Vector2i:
			anchors_typed = false
	check(anchors_typed, "poi anchors are Vector2i after disk round-trip")
	check(not home_c.zone.has("site_chunk") or home_c.zone["site_chunk"] is Vector2i,
		"zone site_chunk is Vector2i after disk round-trip")
	var respawn: Vector2 = WorldGen.spawn_position()
	check(WorldGen.is_spawn_floor(respawn), "spawn_position works on snapshot-restored home chunk")
	WorldGen.reset(WorldGen.DEFAULT_SEED)
