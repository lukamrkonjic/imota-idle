extends Node
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

const GATHER_TICKS := 4  # one success roll every 4 ticks (2.4s), like OSRS WC

var active := false
var skill := ""
var node: Dictionary = {}
var timer := 0.0

var rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if active:
		advance(delta)


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
	var n := DataRegistry.get_gather_node(p_skill, node_name)
	if n.is_empty():
		return false
	if GameState.level(p_skill) < int(n["level"]):
		EventBus.combat_log.emit("%s level %d required for %s" % [p_skill.capitalize(), n["level"], node_name])
		return false
	if GameState.tool_progress(p_skill) <= 0:
		EventBus.combat_log.emit("No suitable tool equipped for %s" % p_skill.capitalize())
		return false
	stop("switching")
	CombatSim.stop("switching")
	RecipeSim.stop("switching")
	skill = p_skill
	node = n
	timer = 0.0
	active = true
	EventBus.activity_started.emit("gather", "%s — %s" % [skill.capitalize(), node["name"]])
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	node = {}
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
	for item_name: String in node["items"]:
		if GameState.add_item(item_name, 1) == 0:
			EventBus.combat_log.emit("Inventory full — %s stopped." % skill.capitalize())
			stop("inventory_full")
			return
		EventBus.loot_gained.emit(item_name, 1)
	GameState.add_xp(skill, float(node["xp"]))
