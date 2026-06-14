extends Node
## Headless validation. Run:
const ValidateContent := preload("res://tools/validate_content.gd")
const ContentId := preload("res://scripts/content/content_id.gd")
const SaveMigration := preload("res://autoload/save_migration.gd")
const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const PathFinder := preload("res://scripts/worldgen/path_finder.gd")
##   godot --headless --path C:/Dev/bloobs-godot res://tools/validate.tscn
## Drives the sims with synthetic delta time, so it completes in milliseconds.

var failures := 0


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	WorldGen.reset(WorldGen.DEFAULT_SEED)
	CombatSim.rng.seed = 0xB100B5
	phase0_data()
	phase0_content_schema()
	phase0_stable_ids()
	phase1_gathering()
	phase1_inventory_bank_equipment()
	phase2_combat()
	phase3_save_roundtrip()
	phase3_save_migration()
	phase3_rename_alias()
	phase3_recipes()
	phase4_food_shop_offline()
	await phase3_ui_smoke()
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
	check(DataRegistry.items.size() > 1000, "items loaded (%d)" % DataRegistry.items.size())
	check(DataRegistry.enemies.size() == 120, "enemies loaded (%d)" % DataRegistry.enemies.size())
	# 1009 raw recipe assets minus ~94 input-less placeholder stubs and ~160
	# duplicate-name variants leaves 775 real recipes.
	check(DataRegistry.recipes.size() == 775, "recipes loaded (%d)" % DataRegistry.recipes.size())
	var logs := DataRegistry.get_item("Logs")
	check(not logs.is_empty(), "item lookup by name: Logs")
	check(DataRegistry.xp_for_level(2) == 83, "XP for level 2 == 83 (got %d)" % DataRegistry.xp_for_level(2))
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
	check(DataRegistry.resolve_item_id("Logs") == ContentId.item_id("Logs"), "item id: Logs")
	check(DataRegistry.resolve_node_id("woodcutting", "Regular Tree") == ContentId.node_id("woodcutting", "Regular Tree"), "node id: Regular Tree")
	check(DataRegistry.resolve_enemy_id("Chickens") == ContentId.enemy_id("Chickens"), "enemy id: Chickens")


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
	check(DataRegistry.items_by_id.has(ContentId.item_id("Oak Logs")), "items_by_id has Oak Logs")
	check(DataRegistry.nodes_by_id.has(ContentId.node_id("woodcutting", "Oak Tree")), "nodes_by_id has Oak Tree")


func phase1_gathering() -> void:
	print("== Phase 1: gathering tick loop ==")
	GameState.reset_state()
	var started := TickSim.start_gather("woodcutting", "Regular Tree")
	check(started, "started woodcutting Regular Tree")
	var xp_before := GameState.xp("woodcutting")
	# Simulate 60 seconds in 0.1s frames.
	for i: int in 600:
		TickSim.advance(0.1)
	# Level 1: action every 1.495s -> 40 actions in 60s; Bronze Axe progress 25
	# -> a log every 4 actions = 10 logs, 250 XP.
	var logs := GameState.count_item("Logs")
	var xp_gained := GameState.xp("woodcutting") - xp_before
	check(logs == 10, "60s WC at level 1 yields 10 Logs (got %d)" % logs)
	check(absf(xp_gained - 250.0) < 0.01, "60s WC yields 250 XP (got %.1f)" % xp_gained)
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
	check(absf(atk_gain - float(e["combatXp"]) * CombatSim.kills) < 0.01,
		"attack XP == combatXp * kills (got %.0f, want %.0f)" % [atk_gain, float(e["combatXp"]) * CombatSim.kills])
	check(absf(hp_gain - float(e["hitpointsXp"]) * CombatSim.kills) < 0.01,
		"hitpoints XP == hitpointsXp * kills")
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
	GameState.add_gold(1234)
	var snapshot := GameState.to_save_dict()
	var json_trip: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	GameState.reset_state()
	GameState.from_save_dict(json_trip)
	check(GameState.level("woodcutting") == DataRegistry.level_for_xp(5000.0), "skill level survives save")
	check(GameState.count_item("Logs") == 22, "inventory survives save (got %d)" % GameState.count_item("Logs"))
	check(int(GameState.bank.get(DataRegistry.resolve_item_id("Logs"), 0)) == 20, "bank survives save")
	check(GameState.gold == 1234, "gold survives save")
	check(GameState.equipment.get("Axe", "") == DataRegistry.resolve_item_id("Bronze Axe"), "equipment survives save")
	check(int(snapshot.get("schemaVersion", 0)) >= 2, "save dict includes schemaVersion")


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


func phase3_rename_alias() -> void:
	print("== Phase 3c: rename alias resolution ==")
	var alias_id := ContentId.item_id("Logs")
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


func phase4_food_shop_offline() -> void:
	print("== Phase 4: food / shop / offline ==")
	GameState.reset_state()
	GameState.set_hp(5)
	GameState.add_item("Shrimp", 2)
	check(GameState.eat("Shrimp"), "eating cooked food works")
	check(GameState.current_hp == 8, "Shrimp heals 3 (hp=%d)" % GameState.current_hp)
	GameState.add_gold(300)
	check(GameState.buy_item("Iron Axe", 1), "shop purchase works")
	check(GameState.gold == 300 - DataRegistry.item_value("Iron Axe"), "gold deducted (%d left)" % GameState.gold)
	check(not GameState.buy_item("Sunwrought Axe", 1), "purchase blocked without gold")
	# Offline progress: 1 simulated hour of woodcutting while away.
	GameState.reset_state()
	TickSim.start_gather("woodcutting", "Regular Tree")
	SaveManager._apply_offline_progress(Time.get_unix_time_from_system() - 3600.0)
	# 1h at level 1 ramps chop speed slightly as levels rise; expect roughly
	# 3600 / 1.495 / 4 ≈ 600 logs, allow a wide band.
	var logs := GameState.count_item("Logs")
	check(logs > 500 and logs < 700, "offline hour yields ~600 logs (got %d)" % logs)
	check(GameState.level("woodcutting") > 10, "offline XP levelled woodcutting (lvl %d)" % GameState.level("woodcutting"))
	TickSim.stop()


func phase3_ui_smoke() -> void:
	print("== Phase 3: UI smoke test ==")
	GameState.reset_state()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var ui: Control = scene.instantiate()
	add_child(ui)
	await get_tree().process_frame
	TickSim.start_gather("woodcutting", "Regular Tree")
	for i: int in 100:
		TickSim.advance(0.1)
	await get_tree().process_frame
	var activity: Label = ui.get("activity_label")
	check(activity.text.contains("Regular Tree"), "activity label shows current node")
	var feed: RichTextLabel = ui.get("feed")
	check(feed.text.contains("+1 Logs"), "loot feed shows gathered logs")
	TickSim.stop()
	await get_tree().process_frame
	check(activity.text.contains("Idle"), "activity label resets on stop")
	ui.queue_free()


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
	var has_bank := false
	for part: Dictionary in camp.get("parts", []):
		if str(part.get("station", "")) == "bank":
			has_bank = true
	check(has_bank, "home campsite includes a bank chest")
	check(WorldGen.find_nearest_station(0, Vector2.ZERO, "bank").size() > 0, "find_nearest_station locates a bank")

	# Terrain pathing: water is never a node, one elevation step is climbable,
	# and a two-step cliff edge is not.
	var pf_chunk: RefCounted = Chunk.new()
	pf_chunk.setup(0, 200, 200)
	pf_chunk.zone = {"req": 1}
	pf_chunk.tiles.fill(int(WorldGen.reg.tile_index["grass"]))
	pf_chunk.tiles[Chunk.idx(1, 0)] = int(WorldGen.reg.tile_index["shallow"])
	pf_chunk.elev[Chunk.idx(0, 1)] = 1
	pf_chunk.elev[Chunk.idx(0, 2)] = 3
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
	check(climb_two.is_empty(), "pathfinder rejects two-step cliff climbs")

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
