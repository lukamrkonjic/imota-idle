extends Node
## Gathering simulation. Faithful to the Unity skills' deltaTime pattern:
## a timer accumulates each frame; when it passes the action duration one
## gather action fires (WoodcuttingSkill.Update / chopTimer).
##
## Node model (Trees.ReduceHealth): each action deals tool "progress" damage;
## every 100 accumulated damage awards 1 resource + the node's XP.

var active := false
var skill := ""
var node: Dictionary = {}
var timer := 0.0
var action_duration := 1.5
var damage_dealt := 0


func _process(delta: float) -> void:
	if active:
		advance(delta)


## Separated from _process so headless tests can drive simulated time.
func advance(delta: float) -> void:
	if not active:
		return
	timer += delta
	while timer >= action_duration and active:
		timer -= action_duration
		_perform_action()
	if active:
		EventBus.action_progress.emit(timer / action_duration)


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
	damage_dealt = 0
	action_duration = action_speed(GameState.level(skill))
	active = true
	EventBus.activity_started.emit("gather", "%s — %s" % [skill.capitalize(), node["name"]])
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	node = {}
	EventBus.activity_stopped.emit(reason)


## WoodcuttingSkill.CalculateChopSpeed: 1.495 - 0.005*(level-1), floor 1.0s.
static func action_speed(level: int) -> float:
	return maxf(1.495 - 0.005 * float(level - 1), 1.0)


func _perform_action() -> void:
	damage_dealt += GameState.tool_progress(skill)
	while damage_dealt >= 100:
		damage_dealt -= 100
		_award_milestone()
		if not active:
			return
	# Level may have risen mid-session; keep speed current.
	action_duration = action_speed(GameState.level(skill))


func _award_milestone() -> void:
	for item_name: String in node["items"]:
		if GameState.add_item(item_name, 1) == 0:
			EventBus.combat_log.emit("Inventory full — %s stopped." % skill.capitalize())
			stop("inventory_full")
			return
		EventBus.loot_gained.emit(item_name, 1)
	GameState.add_xp(skill, float(node["xp"]))
