extends Node
## Production-skill crafting loop (Recipe.cs subclasses): consume inputs,
## wait the recipe timer, grant output + XP, auto-repeat while inputs last.

const ActivityManager := preload("res://scripts/activity_manager.gd")

var active := false
var recipe: RecipeDef = RecipeDef.new()
var timer := 0.0
var crafted := 0


func _ready() -> void:
	ActivityManager.register(self)


func _process(delta: float) -> void:
	if active:
		advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	timer += delta
	while active and timer >= recipe.time:
		timer -= recipe.time
		_complete_craft()
	if active:
		EventBus.action_progress.emit(timer / recipe.time)


func start_craft(skill: String, recipe_name: String) -> bool:
	var r := DataRegistry.recipe_def(skill, recipe_name)
	if r.is_empty():
		return false
	if GameState.level(skill) < r.level_req:
		EventBus.combat_log.emit("%s level %d required for %s" % [skill.capitalize(), r.level_req, recipe_name])
		return false
	if not _has_inputs(r.inputs):
		EventBus.combat_log.emit("Missing ingredients for %s" % recipe_name)
		return false
	stop("switching")
	ActivityManager.stop_others(self)
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
	recipe = RecipeDef.new()
	EventBus.activity_stopped.emit(reason)


func _has_inputs(inputs: Array) -> bool:
	for input: Dictionary in inputs:
		if GameState.count_item(input["item"]) < int(input["qty"]):
			return false
	return true


func _complete_craft() -> void:
	for input: Dictionary in recipe.inputs:
		GameState.remove_item(input["item"], int(input["qty"]))
	var out: Dictionary = recipe.output
	if GameState.add_item(out["item"], int(out["qty"])) == 0:
		# No room for the output: roll the inputs back so nothing is destroyed
		# (previously the inputs were consumed with no output on a full inventory).
		for input: Dictionary in recipe.inputs:
			GameState.add_item(input["item"], int(input["qty"]))
		EventBus.combat_log.emit("Inventory full — crafting stopped.")
		stop("inventory_full")
		return
	crafted += 1
	EventBus.loot_gained.emit(out["item"], int(out["qty"]))
	if recipe.skill == "firemaking":
		EventBus.firemaking_log_burned.emit()   # world FX: feed a log into the fire
	GameState.add_xp(recipe.skill, recipe.xp)
	# Stop as soon as the last possible craft finishes rather than waiting
	# for the next timer to expire on missing ingredients.
	if active and not _has_inputs(recipe.inputs):
		EventBus.combat_log.emit("Out of ingredients — crafting stopped.")
		stop("out_of_inputs")
