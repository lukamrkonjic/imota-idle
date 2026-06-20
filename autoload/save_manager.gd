extends Node
## Persists the full game state to user://save.json. Autosaves every 30s and

const SaveMigration := preload("res://autoload/save_migration.gd")
const ActivityManager := preload("res://scripts/activity_manager.gd")
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
	data["farming"] = FarmingSim.to_save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save file")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	WorldGen.save_world()


func _activity_dict() -> Dictionary:
	# Each activity sim owns its own (de)serialization now; the manager returns the active one.
	return ActivityManager.save_active()


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
	FarmingSim.from_save(parsed.get("farming", {}))
	# Each sim re-starts its own activity if the saved "kind" matches (owned by the sim now).
	ActivityManager.restore_active(parsed.get("activity", {}))
	# No offline progress: the sims never fast-forward time the player was away.
	# `savedAt` is still written for the AFK / Rested-XP system (spec §8).
	EventBus.game_loaded.emit()
