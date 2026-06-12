extends RefCounted
class_name WorldLayerController
## Cave/surface layer switching, obelisks, and teleport.

const WG := preload("res://scripts/worldgen/wg.gd")

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func try_descend(target_layer: int) -> void:
	var cfg: Dictionary = WorldGen.reg.cave_layers.get(target_layer, {})
	if cfg.is_empty():
		return
	if bool(cfg.get("locked", false)):
		EventBus.combat_log.emit("[color=#a01010]%s[/color]" % str(cfg.get("lockMessage", "The way is sealed.")))
		return
	switch_layer(target_layer)
	EventBus.combat_log.emit("[color=#444]You descend into the %s.[/color]" % str(cfg.get("name", "caves")))


func switch_layer(target_layer: int) -> void:
	world._activity_ctrl.stop_all_sims()
	world._activity_ctrl.clear_combat_target()
	world._path_ctrl.stop_walking()
	world.gather_ref = {}
	world.current_layer = target_layer
	world.chunk_manager.set_layer(target_layer)
	world.chunk_manager.update_center(world.player.position)
	world._path_ctrl.rebuild()
	if target_layer < 0:
		var cfg: Dictionary = WorldGen.reg.cave_layers.get(target_layer, {})
		world._ambient.color = Color.from_string("#" + str(cfg.get("tint", "808090")), Color.WHITE)
		EventBus.biome_changed.emit("cave", str(cfg.get("music", "caves")))
	else:
		world._ambient.color = Color.WHITE
		world._visual_ctrl.reset_biome_tracking()
	EventBus.world_layer_changed.emit(target_layer)


func use_obelisk(action: Dictionary, entity: Node2D) -> void:
	var chunk: RefCounted = WorldGen.chunks.get(str(action["chunk_key"]))
	if chunk == null:
		return
	for poi: Dictionary in chunk.pois:
		if str(poi["type"]) == "obelisk":
			if WorldGen.unlock_obelisk(chunk, poi):
				EventBus.combat_log.emit("[color=#5a3a8a]You attune to the obelisk. You can now teleport here.[/color]")
				if entity != null:
					entity.attuned = true
			else:
				world.hud.call("open_obelisks")
			return


func teleport_to(pos: Vector2) -> void:
	world._activity_ctrl.stop_all_sims()
	world._activity_ctrl.clear_combat_target()
	world._path_ctrl.stop_walking()
	world.pending_action = {}
	world.auto_task = {}
	if world.current_layer != 0:
		switch_layer(0)
	world.player.position = WorldGen.nearest_walkable_world(pos + Vector2(0, WG.TILE))
	world.chunk_manager.update_center(world.player.position)
	world._path_ctrl.rebuild()
	EventBus.combat_log.emit("[color=#5a3a8a]You teleport.[/color]")


func on_player_died() -> void:
	world._activity_ctrl.on_player_died_grace()
	world._activity_ctrl.clear_combat_target()
	world._path_ctrl.stop_walking()
	world.pending_action = {}
	world.auto_task = {}
	if world.current_layer != 0:
		switch_layer(0)
	var camp: Dictionary = WorldGen.find_nearest_poi(0, world.player.position, ["campsite"])
	world.player.position = WorldGen.spawn_position()
	world.chunk_manager.update_center(world.player.position)
	world._path_ctrl.rebuild()
	EventBus.combat_log.emit("[color=#a01010]You wake up at the campsite.[/color]")
