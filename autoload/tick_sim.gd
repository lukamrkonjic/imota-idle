extends "res://scripts/activity_sim.gd"  # ActivitySim, by path so it compiles with a cold class cache
## Gathering simulation, OSRS-faithful: gathering skills (Woodcutting, Mining,
## Fishing, Foraging) roll a binary success check every GATHER_TICKS game ticks.
## On success you get the resource + its XP; on a failed roll nothing happens and
## you wait for the next roll. No progress bar, no accumulation — same family as
## OSRS Woodcutting (roll every 4 ticks / 2.4s).
##
## Success chance scales with skill level and tool tier. It's derived from the
## previously tuned economy (old model: each ~1.495s action dealt tool "progress"
## damage; 100 damage = 1 resource), so average yields are unchanged — only the
## delivery is now a per-roll OSRS-style success instead of a filling bar.

const GatherNodeDef := preload("res://scripts/content/gather_node_def.gd")  # path preload: cold-cache safe

const GATHER_TICKS := 4  # one success roll every 4 ticks (2.4s), like OSRS WC

# `active` + register + _process come from ActivitySim.
var skill := ""
var node: GatherNodeDef = GatherNodeDef.new()
var timer := 0.0

var rng := RandomNumberGenerator.new()


## Separated from _process so headless tests can drive simulated time.
func advance(delta: float) -> void:
	if not active:
		return
	timer += delta
	var interval := gather_interval()
	while timer >= interval and active:
		timer -= interval
		_roll_action()


func start_gather(p_skill: String, node_name: String) -> bool:
	var n := DataRegistry.node_def(p_skill, node_name)
	if n.is_empty():
		return false
	if GameState.level(p_skill) < n.level:
		EventBus.combat_log.emit("%s level %d required for %s" % [p_skill.capitalize(), n.level, n.display_name])
		return false
	if GameState.tool_progress(p_skill) <= 0:
		EventBus.combat_log.emit("No suitable tool equipped for %s" % p_skill.capitalize())
		return false
	stop("switching")
	_stop_others()
	skill = p_skill
	node = n
	timer = 0.0
	active = true
	EventBus.activity_started.emit("gather", "%s — %s" % [skill.capitalize(), node.display_name])
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	node = GatherNodeDef.new()
	EventBus.activity_stopped.emit(reason)


## Fixed roll cadence (OSRS gathering rolls on a fixed tick speed; level raises
## success, not swing speed).
func gather_interval() -> float:
	return float(GATHER_TICKS) * GameState.TICK


## WoodcuttingSkill.CalculateChopSpeed (legacy): 1.495 - 0.005*(level-1), floor
## 1.0s. Retained only to derive the per-roll success chance below so the tuned
## economy is preserved.
static func action_speed(level: int) -> float:
	return maxf(1.495 - 0.005 * float(level - 1), 1.0)


## Probability that one roll yields the resource. The old model's expected
## resources/sec was (tool_progress/100) / action_speed(level); one roll every
## gather_interval seconds reproduces that expectation, so average yields match
## the previous balance while the mechanic is now an OSRS-style success roll.
func success_chance(level: int) -> float:
	var per_sec := (float(GameState.tool_progress(skill)) / 100.0) / action_speed(level)
	return clampf(per_sec * gather_interval(), 0.0, 1.0)


func _roll_action() -> void:
	if rng.randf() < success_chance(GameState.level(skill)):
		_award_resource()


func _award_resource() -> void:
	for item_name: String in node.items:
		if GameState.add_item(item_name, 1) == 0:
			EventBus.combat_log.emit("Inventory full — %s stopped." % skill.capitalize())
			stop("inventory_full")
			return
		EventBus.loot_gained.emit(item_name, 1)
	GameState.add_xp(skill, node.xp)


func save_activity() -> Dictionary:
	return {"kind": "gather", "skill": skill, "node_id": node.id} if active else {}


func restore_activity(data: Dictionary) -> void:
	if str(data.get("kind", "")) != "gather":
		return
	var node_ref: String = str(data.get("node_id", data.get("node", "")))
	var nd := DataRegistry.get_gather_node(str(data.get("skill", "")), node_ref)
	if not nd.is_empty():
		start_gather(str(data.get("skill", "")), str(nd["name"]))
