extends RefCounted
class_name SlayerState
## Slayer-task domain, extracted from GameState.
##
## Holds the active task + earned points. State lives here; GameState forwards the public API and
## serializes slayer_task + slayer_points. The RNG is intentionally unseeded (deterministic),
## matching the prior in-GameState behaviour.

var task: Dictionary = {}        # {monster, required, done} or {} when none
var points: int = 0              # currency earned from completing slayer tasks
var _rng := RandomNumberGenerator.new()


## Assign a new task: a random eligible monster (within Slayer level, non-boss) and a kill count
## scaled by level. No-op (returns the current task) if one is already active.
func assign() -> Dictionary:
	if not task.is_empty():
		return task
	var slvl := GameState.level("slayer")
	var pool: Array = []
	for e: Dictionary in DataRegistry.enemies.values():
		if bool(e.get("isBoss", false)):
			continue
		if int(e.get("beastMasteryReq", 0)) > slvl:
			continue
		# Store the DISPLAY name — that's what EventBus.enemy_killed emits, so kills match.
		pool.append(str(e.get("displayName", e.get("name", ""))))
	if pool.is_empty():
		return {}
	var monster: String = pool[_rng.randi() % pool.size()]
	var required := 15 + slvl / 2 + _rng.randi() % 10
	task = {"monster": monster, "required": required, "done": 0}
	EventBus.slayer_changed.emit()
	return task


## A kill toward the active task. On completion: a Slayer XP bonus + Slayer points, task cleared.
func kill(enemy_name: String) -> void:
	if task.is_empty() or str(task.get("monster", "")) != enemy_name:
		return
	task["done"] = int(task["done"]) + 1
	if int(task["done"]) >= int(task["required"]):
		var pts := 8 + GameState.level("slayer") / 4
		points += pts
		GameState.add_xp("slayer", float(int(task["required"]) * 12))   # completion bonus
		EventBus.combat_log.emit("[color=#9ad29a]Slayer task complete! +%d Slayer points.[/color]" % pts)
		task = {}
	EventBus.slayer_changed.emit()


func cancel() -> void:
	task = {}
	EventBus.slayer_changed.emit()
