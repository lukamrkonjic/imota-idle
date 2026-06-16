extends RefCounted
class_name WorldActivityController
## Gather/combat/station actions and sim lifecycle.

const WG := preload("res://scripts/worldgen/wg.gd")
const FishingHelper := preload("res://scripts/world/fishing_helper.gd")

const STATION_OPEN := {
	"bank": "bank", "shop": "shop",
	"campfire": "cooking", "range": "cooking", "anvil": "smithing",
	"crafting": "crafting", "fletching": "fletching",
	"herbology": "alchemy", "imbuing": "crafting",
	"devotion": "prayer", "altar": "prayer", "soul_altar": "crafting",
}

const AGGRO_INTERVAL := 0.5
const AGGRO_GRACE := 4.0
const LEASH_RADIUS_TILES := 8.0  # player gets this far from the mob's spawn -> it gives up
const CHASE_SPEED := 150.0        # px/s the mob chases — clearly slower than the player (230) so you can outrun it
const RETURN_SPEED := 170.0       # px/s it walks back to spawn after de-aggro
const ATTACK_GAP_TILES := 0.7     # how close beside you the chaser stops

var world: Node2D

var _aggro_timer := 0.0
var _aggro_grace := 0.0
var _last_chased: Node2D = null     # mob currently engaged, so we can send it home on combat end
var _returning: Dictionary = {}     # entity -> home Vector2, walking back to its spawn


func setup(w: Node2D) -> void:
	world = w


func process_tick(delta: float) -> void:
	_aggro_grace = maxf(_aggro_grace - delta, 0.0)
	_update_chase(delta)
	_update_returning(delta)
	_aggro_timer += delta
	if _aggro_timer >= AGGRO_INTERVAL:
		_aggro_timer = 0.0
		_check_aggro()


## OSRS chase + leash. While you're fighting (or have fled mid-fight), the mob
## runs you down. It remembers its spawn tile; if you get further than the leash
## radius FROM THAT SPAWN, it gives up, and walks back home. Killing it sends the
## corpse home too so it respawns where it started.
func _update_chase(delta: float) -> void:
	var tgt: Node2D = world.combat_target_entity
	if CombatSim.active and is_instance_valid(tgt):
		_last_chased = tgt
		_returning.erase(tgt)  # re-engaged before it got home
		if not tgt.has_meta("home_pos"):
			tgt.set_meta("home_pos", tgt.position)
		var home: Vector2 = tgt.get_meta("home_pos")
		if tgt.dimmed:
			_step_toward(tgt, home, RETURN_SPEED * delta)  # dead: drift home before respawn
			return
		if world.player.position.distance_to(home) > _leash_radius():
			var nm := str(CombatSim.enemy.get("displayName", CombatSim.enemy.get("name", "enemy")))
			CombatSim.stop("fled")  # clears target; the else-branch walks it home next tick
			_aggro_grace = AGGRO_GRACE  # don't instantly re-aggro the mob you just escaped
			EventBus.combat_log.emit("[color=#7a7a30]The %s loses interest and returns home.[/color]" % nm)
			return
		_step_toward(tgt, world.player.position, CHASE_SPEED * delta, WG.TILE * ATTACK_GAP_TILES)
	elif is_instance_valid(_last_chased):
		_begin_return(_last_chased)  # combat just ended (kill / flee / switch) — send it home
		_last_chased = null
	else:
		_last_chased = null


func _begin_return(entity: Node2D) -> void:
	if not entity.has_meta("home_pos"):
		return
	var home: Vector2 = entity.get_meta("home_pos")
	if entity.position.distance_to(home) > 2.0:
		_returning[entity] = home


func _update_returning(delta: float) -> void:
	if _returning.is_empty():
		return
	var done: Array = []
	for entity: Node2D in _returning:
		if not is_instance_valid(entity):
			done.append(entity)
			continue
		var home: Vector2 = _returning[entity]
		_step_toward(entity, home, RETURN_SPEED * delta)
		if entity.position.distance_to(home) <= 2.0:
			entity.position = home
			entity.queue_redraw()
			done.append(entity)
	for e: Node2D in done:
		_returning.erase(e)


## Move an entity toward target, stopping `gap` short of it. Returns having moved
## at most `max_step` this frame.
func _step_toward(entity: Node2D, target: Vector2, max_step: float, gap: float = 0.0) -> void:
	var to := target - entity.position
	var dist := to.length()
	var goal := dist - gap
	if goal <= 1.0:
		return
	entity.position += to / dist * minf(max_step, goal)
	entity.queue_redraw()


func _leash_radius() -> float:
	return float(WorldGen.reg.monster_cfg.get("leashRadiusTiles", LEASH_RADIUS_TILES)) * WG.TILE


func begin_action(entity: Node2D) -> void:
	stop_all_sims()
	clear_combat_target()
	world.player.clear_fish_cast()
	world.pending_action = entity.action.duplicate()
	world.pending_action["entity_path"] = entity.get_path()
	var target := entity.position
	var action: Dictionary = entity.action
	if str(action.get("type", "")) == "gather" and str(action.get("skill", "")) == "fishing":
		var chunk: RefCounted = WorldGen.chunks.get(str(action["chunk_key"]))
		if chunk != null:
			var i := int(action["site_index"])
			if i < chunk.sites.size():
				target = FishingHelper.best_stand(world.player.position, chunk, chunk.sites[i])
	world.walk_to_pos(target)


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
	if str(action["skill"]) == "fishing":
		if not FishingHelper.can_cast_from(world.player.position, chunk, site):
			EventBus.combat_log.emit("[color=#444]Stand on the shore to cast into the water.[/color]")
			if world.auto_task.get("mode", "") == "gather":
				world._auto_task_ctrl.find_next()
			return
		world.player.set_fish_cast(FishingHelper.water_world_pos(chunk, site))
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
	world.player.clear_fish_cast()
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
