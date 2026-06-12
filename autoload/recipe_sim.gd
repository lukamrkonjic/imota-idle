extends Node
## Production-skill crafting loop (Recipe.cs subclasses): consume inputs,
## wait the recipe timer, grant output + XP, auto-repeat while inputs last.

var active := false
var recipe: Dictionary = {}
var timer := 0.0
var crafted := 0


func _process(delta: float) -> void:
	if active:
		advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	timer += delta
	while active and timer >= float(recipe["time"]):
		timer -= float(recipe["time"])
		_complete_craft()
	if active:
		EventBus.action_progress.emit(timer / float(recipe["time"]))


func start_craft(skill: String, recipe_name: String) -> bool:
	var r := DataRegistry.get_recipe(skill, recipe_name)
	if r.is_empty():
		return false
	if GameState.level(skill) < int(r["levelReq"]):
		EventBus.combat_log.emit("%s level %d required for %s" % [skill.capitalize(), r["levelReq"], recipe_name])
		return false
	if not _has_inputs(r):
		EventBus.combat_log.emit("Missing ingredients for %s" % recipe_name)
		return false
	stop("switching")
	TickSim.stop("switching")
	CombatSim.stop("switching")
	recipe = r
	timer = 0.0
	crafted = 0
	active = true
	EventBus.activity_started.emit("craft", "%s — %s" % [skill.capitalize(), recipe_name])
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	recipe = {}
	EventBus.activity_stopped.emit(reason)


func _has_inputs(r: Dictionary) -> bool:
	for input: Dictionary in r["inputs"]:
		if GameState.count_item(input["item"]) < int(input["qty"]):
			return false
	return true


func _complete_craft() -> void:
	for input: Dictionary in recipe["inputs"]:
		GameState.remove_item(input["item"], int(input["qty"]))
	var out: Dictionary = recipe["output"]
	if GameState.add_item(out["item"], int(out["qty"])) == 0:
		EventBus.combat_log.emit("Inventory full — crafting stopped.")
		stop("inventory_full")
		return
	crafted += 1
	EventBus.loot_gained.emit(out["item"], int(out["qty"]))
	GameState.add_xp(recipe["skill"], float(recipe["xp"]))
	# Stop as soon as the last possible craft finishes rather than waiting
	# for the next timer to expire on missing ingredients.
	if active and not _has_inputs(recipe):
		EventBus.combat_log.emit("Out of ingredients — crafting stopped.")
		stop("out_of_inputs")
