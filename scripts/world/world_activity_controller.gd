extends RefCounted
class_name WorldActivityController
## Gather/combat/station actions and sim lifecycle.

const WG := preload("res://scripts/worldgen/wg.gd")

const STATION_OPEN := {
	"bank": "bank", "shop": "shop",
	"campfire": "cooking", "range": "cooking", "anvil": "smithing",
	"crafting": "crafting", "fletching": "fletching",
	"herbology": "herbology", "imbuing": "imbuing",
	"devotion": "devotion", "altar": "devotion", "soul_altar": "soulbinding",
}

const AGGRO_INTERVAL := 0.5
const AGGRO_GRACE := 4.0

var world: Node2D

var _aggro_timer := 0.0
var _aggro_grace := 0.0


func setup(w: Node2D) -> void:
	world = w


func process_tick(delta: float) -> void:
	_aggro_grace = maxf(_aggro_grace - delta, 0.0)
	_aggro_timer += delta
	if _aggro_timer >= AGGRO_INTERVAL:
		_aggro_timer = 0.0
		_check_aggro()


func begin_action(entity: Node2D) -> void:
	stop_all_sims()
	clear_combat_target()
	world.pending_action = entity.action.duplicate()
	world.pending_action["entity_path"] = entity.get_path()
	world.walk_to_pos(entity.position)


func execute_action(action: Dictionary) -> void:
	var entity: Node2D = world.get_node_or_null(action.get("entity_path", NodePath()))
	match str(action.get("type", "")):
		"gather":
			_start_gather(action)
		"enemy":
			if CombatSim.start_combat(str(action["name"]), str(world.hud.call("train_style"))):
				world.combat_target_entity = entity
		"station":
			var st := str(action["station"])
			var open := str(STATION_OPEN.get(st, ""))
			if open == "bank":
				world.hud.call("open_bank")
			elif open == "shop":
				world.hud.call("open_shop")
			elif not open.is_empty():
				if action.has("recipe"):
					RecipeSim.start_craft(str(action.get("skill", open)), str(action["recipe"]))
				else:
					world.hud.call("open_recipes", str(action.get("skill", open)))
		"hook":
			EventBus.combat_log.emit("[color=#444]%s[/color]" % str(action["message"]))
		"descend":
			world._layer_ctrl.try_descend(int(action["target_layer"]))
		"ascend":
			world._layer_ctrl.switch_layer(int(action["target_layer"]))
		"obelisk":
			world._layer_ctrl.use_obelisk(action, entity)
		"landmark":
			EventBus.combat_log.emit("[color=#5a3a8a]You marvel at the %s. Travellers tell stories about this place.[/color]" % str(action["label"]))


func _start_gather(action: Dictionary) -> void:
	var chunk: RefCounted = WorldGen.chunks.get(str(action["chunk_key"]))
	if chunk == null:
		return
	var i := int(action["site_index"])
	if i >= chunk.sites.size():
		return
	var site: Dictionary = chunk.sites[i]
	if not bool(site["available"]):
		EventBus.combat_log.emit("[color=#444]The %s is depleted.[/color]" % str(site["node"]))
		if world.auto_task.get("mode", "") == "gather":
			world._auto_task_ctrl.find_next()
		return
	if TickSim.start_gather(str(action["skill"]), str(action["node"])):
		world.gather_ref = {
			"chunk": chunk, "site_index": i,
			"entity": world._site_entities.get("%s#%d" % [chunk.key(), i]),
		}
	elif world.auto_task.get("mode", "") == "gather":
		world.auto_task = {}


func on_xp_gained(skill: String, amount: float) -> void:
	if TickSim.active and not world.gather_ref.is_empty() and skill == TickSim.skill:
		var chunk: RefCounted = world.gather_ref["chunk"]
		var i := int(world.gather_ref["site_index"])
		var site: Dictionary = chunk.sites[i]
		site["remaining"] = int(site["remaining"]) - 1
		if int(site["remaining"]) <= 0:
			var entity: Node2D = world.gather_ref.get("entity")
			WorldGen.deplete_site(chunk, i)
			TickSim.stop("depleted")
			if entity != null:
				entity.dimmed = true
			EventBus.combat_log.emit("[color=#444]The %s is depleted.[/color]" % str(site["node"]))
			world.gather_ref = {}
			if world.auto_task.get("mode", "") == "gather":
				world._auto_task_ctrl.call_deferred_find_next()
	world._visual_ctrl.show_xp_float(skill, amount)


func stop_all_sims() -> void:
	TickSim.stop()
	CombatSim.stop()
	RecipeSim.stop()


func clear_combat_target() -> void:
	if world.combat_target_entity != null:
		world.combat_target_entity.set_hp_fraction(-1.0)
		world.combat_target_entity.dimmed = false
		world.combat_target_entity = null


func on_player_died_grace() -> void:
	_aggro_grace = AGGRO_GRACE * 2.0


func on_activity_stopped(reason: String) -> void:
	world.player.set_progress(-1.0)
	if reason != "switching":
		clear_combat_target()
	if reason != "depleted" and reason != "switching":
		world.gather_ref = {}
	if reason == "stopped" or reason == "player_died":
		_aggro_grace = AGGRO_GRACE


func on_enemy_hp_changed(current: float, max_hp: float) -> void:
	if world.combat_target_entity != null:
		world.combat_target_entity.set_hp_fraction(current / maxf(max_hp, 1.0))
		if current >= max_hp:
			world.combat_target_entity.dimmed = false


func on_enemy_killed() -> void:
	if world.combat_target_entity != null:
		world.combat_target_entity.dimmed = true


func _check_aggro() -> void:
	if CombatSim.active or _aggro_grace > 0.0 or world.auto_task.get("mode", "") == "gather" and TickSim.active:
		return
	var entry := WorldGen.player_entry_level()
	for e: Node2D in world.entities:
		var a: Dictionary = e.action
		if str(a.get("type", "")) != "enemy" or not bool(a.get("aggressive", false)) or e.dimmed:
			continue
		var lvl := int(a.get("level", 1))
		if entry >= int(float(lvl) * float(WorldGen.reg.monster_cfg.get("aggroLevelFactor", 2.0))):
			continue
		var radius := float(WorldGen.reg.monster_cfg.get("aggroRadiusTiles", 3.2)) * WG.TILE
		if e.position.distance_to(world.player.position) > radius:
			continue
		world._path_ctrl.stop_walking()
		stop_all_sims()
		world.pending_action = {}
		world.auto_task = {}
		if CombatSim.start_combat(str(a["name"]), str(world.hud.call("train_style"))):
			world.combat_target_entity = e
			EventBus.combat_log.emit("[color=#a01010]A %s attacks you!" % str(a["name"]) + "[/color]")
		return
