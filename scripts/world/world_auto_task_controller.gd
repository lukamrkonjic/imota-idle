extends RefCounted
class_name WorldAutoTaskController
## Auto-gather, auto-bank, and auto-station routing.

const GATHER_VERB := {"woodcutting": "Chop", "mining": "Mine", "fishing": "Fish", "foraging": "Pick",
	"hunter": "Trap", "thieving": "Steal"}

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func auto_gather(skill: String, node_name: String) -> void:
	var node: Dictionary = DataRegistry.get_gather_node(skill, node_name)
	if node.is_empty():
		return
	if GameState.level(skill) < int(node["level"]):
		EventBus.combat_log.emit("[color=#a01010]%s level %d required for %s.[/color]" % [
			skill.capitalize(), int(node["level"]), str(node.get("displayName", node_name))])
		return
	world._activity_ctrl.stop_all_sims()
	world._activity_ctrl.clear_combat_target()
	world.auto_task = {"mode": "gather", "skill": skill, "node": node_name}
	EventBus.combat_log.emit("[color=#444]Auto-%s: %s — looking for the nearest node.[/color]" % [
		GATHER_VERB.get(skill, "gather").to_lower(), node_name])
	find_next()


func auto_station(skill: String, recipe_name: String = "") -> void:
	# Firemaking needs no station — you light logs where you stand (OSRS-style). Start the
	# burn immediately (or open the log list) instead of walking to a station.
	if skill == "firemaking":
		world._activity_ctrl.stop_all_sims()
		world._activity_ctrl.clear_combat_target()
		if not recipe_name.is_empty():
			RecipeSim.start_craft("firemaking", recipe_name)
		else:
			world.hud.call("open_recipes", "firemaking")
		return
	var wanted: Array = WorldGen.reg.stations.get(skill, [])
	var best: Dictionary = {}
	var best_d := INF
	for st: String in wanted:
		var found: Dictionary = WorldGen.find_nearest_station(world.current_layer, world.player.position, st)
		if not found.is_empty() and world.player.position.distance_to(found["pos"]) < best_d:
			best_d = world.player.position.distance_to(found["pos"])
			best = found
			best["station"] = st
	if best.is_empty():
		EventBus.combat_log.emit("[color=#444]No %s station found nearby.[/color]" % skill.capitalize())
		return
	world._activity_ctrl.stop_all_sims()
	world._activity_ctrl.clear_combat_target()
	world.pending_action = {"type": "station", "station": str(best["station"]), "skill": skill}
	if not recipe_name.is_empty():
		world.pending_action["recipe"] = recipe_name
	world.walk_to_pos(best["pos"])


func auto_bank() -> void:
	var found: Dictionary = WorldGen.find_nearest_station(world.current_layer, world.player.position, "bank")
	if found.is_empty() and world.current_layer != 0:
		found = WorldGen.find_nearest_station(0, world.player.position, "bank")
		if not found.is_empty():
			EventBus.combat_log.emit("[color=#444]The nearest bank is on the surface.[/color]")
			return
	if found.is_empty():
		EventBus.combat_log.emit("[color=#444]No bank found nearby.[/color]")
		return
	world._activity_ctrl.stop_all_sims()
	world._activity_ctrl.clear_combat_target()
	world.pending_action = {"type": "station", "station": "bank"}
	world.walk_to_pos(found["pos"])


func find_next() -> void:
	if world.auto_task.get("mode", "") != "gather":
		return
	var skill := str(world.auto_task["skill"])
	var node_name := str(world.auto_task["node"])
	var found: Dictionary = WorldGen.find_nearest_site(world.current_layer, world.player.position, skill, node_name)
	if found.is_empty():
		world.auto_task["waiting"] = true
		EventBus.combat_log.emit("[color=#444]All %s nodes are depleted — waiting for a respawn.[/color]" % node_name)
		return
	world.auto_task.erase("waiting")
	var chunk: RefCounted = found["chunk"]
	world.pending_action = {
		"type": "gather", "skill": skill, "node": node_name,
		"chunk_key": chunk.key(), "site_index": int(found["site_index"]),
	}
	world.walk_to_pos(found["pos"])


func call_deferred_find_next() -> void:
	world.call_deferred("_auto_find_next_deferred")


func on_site_respawned(chunk_key: String, site_index: int) -> void:
	var e: Node2D = world._site_entities.get("%s#%d" % [chunk_key, site_index])
	if e != null:
		e.dimmed = false
	if world.auto_task.get("mode", "") == "gather" and bool(world.auto_task.get("waiting", false)) and not TickSim.active:
		find_next()
