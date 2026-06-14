extends Node
## Persists the full game state to user://save.json. Autosaves every 30s and

const SaveMigration := preload("res://autoload/save_migration.gd")
## on quit. Also restores the active activity so the grind continues on load.

const SAVE_PATH := "user://save.json"
const AUTOSAVE_INTERVAL := 30.0

var _autosave_timer := 0.0
var suppress := false  # headless tests set this so they never touch the save


func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Defer so every autoload (and the UI) is ready before load fires signals.
	load_game.call_deferred()


func _process(delta: float) -> void:
	if suppress:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not suppress:
			save_game()
		get_tree().quit()


func save_game() -> void:
	var data := GameState.to_save_dict()
	data["schemaVersion"] = SaveMigration.CURRENT_SCHEMA
	data["gameVersion"] = SaveMigration.CURRENT_GAME_VERSION
	data["savedAt"] = Time.get_unix_time_from_system()
	data["activity"] = _activity_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save file")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	WorldGen.save_world()


func _activity_dict() -> Dictionary:
	if TickSim.active:
		return {
			"kind": "gather",
			"skill": TickSim.skill,
			"node_id": str(TickSim.node.get("id", DataRegistry.resolve_node_id(TickSim.skill, TickSim.node["name"]))),
		}
	if CombatSim.active:
		return {
			"kind": "combat",
			"enemy_id": str(CombatSim.enemy.get("id", DataRegistry.resolve_enemy_id(CombatSim.enemy["name"]))),
			"train": CombatSim.train_skill,
		}
	if RecipeSim.active:
		return {
			"kind": "craft",
			"skill": RecipeSim.recipe["skill"],
			"recipe_id": str(RecipeSim.recipe.get("id", DataRegistry.resolve_recipe_id(RecipeSim.recipe["skill"], RecipeSim.recipe["name"]))),
		}
	return {}


func load_game() -> void:
	if suppress or not FileAccess.file_exists(SAVE_PATH):
		EventBus.game_loaded.emit()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_error("Corrupt save file ignored")
		EventBus.game_loaded.emit()
		return
	GameState.from_save_dict(parsed)
	parsed = SaveMigration.migrate_game_save(parsed)
	var activity: Dictionary = parsed.get("activity", {})
	match activity.get("kind", ""):
		"gather":
			var node_ref: String = str(activity.get("node_id", activity.get("node", "")))
			var node := DataRegistry.get_gather_node(str(activity["skill"]), node_ref)
			if not node.is_empty():
				TickSim.start_gather(str(activity["skill"]), str(node["name"]))
		"combat":
			var enemy_ref: String = str(activity.get("enemy_id", activity.get("enemy", "")))
			var enemy := DataRegistry.get_enemy(enemy_ref)
			if not enemy.is_empty():
				CombatSim.start_combat(str(enemy["name"]), activity.get("train", "attack"))
		"craft":
			var recipe_ref: String = str(activity.get("recipe_id", activity.get("recipe", "")))
			var recipe := DataRegistry.get_recipe(str(activity["skill"]), recipe_ref)
			if not recipe.is_empty():
				RecipeSim.start_craft(str(activity["skill"]), str(recipe["name"]))
	# No offline progress: the sims never fast-forward time the player was away.
	# `savedAt` is still written for the AFK / Rested-XP system (spec §8).
	EventBus.game_loaded.emit()
