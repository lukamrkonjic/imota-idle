extends RefCounted
class_name WorldPathController
## A* pathing, walk targets, and long-distance re-pathing.

const WG := preload("res://scripts/worldgen/wg.gd")
const PathFinder := preload("res://scripts/worldgen/path_finder.gd")

var world: Node2D
var path_finder: RefCounted = PathFinder.new()

var _path := PackedVector2Array()
var _path_i := 0
var _long_target := Vector2.ZERO
var _has_long_target := false
var _repath_budget := 0
var _needs_rebuild := true


func setup(w: Node2D) -> void:
	world = w


func mark_path_dirty() -> void:
	_needs_rebuild = true


func on_level_up() -> void:
	_needs_rebuild = true


func process_tick() -> void:
	if _needs_rebuild:
		rebuild()


func rebuild() -> void:
	_needs_rebuild = false
	path_finder.rebuild(world.chunk_manager.call("loaded_chunks"), WorldGen.reg, WorldGen.player_entry_level())


func on_waypoint_reached() -> void:
	_advance_waypoint()


func stop_walking() -> void:
	world.player.stop_walking()
	_path = PackedVector2Array()
	_path_i = 0
	_has_long_target = false


func walk_to_pos(target: Vector2) -> bool:
	var tile := WG.world_to_tile(target)
	var direct_ground_click: bool = world.pending_action.is_empty()
	if path_finder.in_region(tile):
		var lock := int(path_finder.lock_req_at(tile))
		if lock > 0:
			var zone: Dictionary = WorldGen.zone_at(target)
			EventBus.combat_log.emit("[color=#a01010]You need level %d to enter %s.[/color]" % [
				int(zone["req"]), str(zone["name"])])
			world.player.play_no()
			world.pending_action = {}
			world.auto_task = {}
			return false
		if direct_ground_click and not path_finder.has_reachable_tile(tile):
			EventBus.combat_log.emit("[color=#444]You can't reach that.[/color]")
			world.player.play_no()
			world.pending_action = {}
			return false
		_has_long_target = false
	else:
		var zone: Dictionary = WorldGen.zone_at(target)
		if int(zone["req"]) > WorldGen.player_entry_level():
			EventBus.combat_log.emit("[color=#a01010]You need level %d to enter %s.[/color]" % [
				int(zone["req"]), str(zone["name"])])
			world.player.play_no()
			world.pending_action = {}
			world.auto_task = {}
			return false
		_long_target = target
		_has_long_target = true
		_repath_budget = 200
		target = _clamp_to_region(target)
	var snap_target: bool = _has_long_target or not direct_ground_click
	var path := PackedVector2Array(path_finder.find_path(world.player.position, target, snap_target))
	if path.is_empty():
		EventBus.combat_log.emit("[color=#444]You can't reach that.[/color]")
		world.player.play_no()
		world.pending_action = {}
		return false
	if not world.pending_action.is_empty() and not _has_long_target and path.size() >= 2:
		path.remove_at(path.size() - 1)
	_path = path
	_path_i = 0
	_advance_waypoint()
	return true


func _clamp_to_region(target: Vector2) -> Vector2:
	var rect := WG.tile_region_world_rect(path_finder.region, 2)
	return target.clamp(rect.position, rect.end)


func _advance_waypoint() -> void:
	if _path_i < _path.size():
		world.player.walk_to(_path[_path_i])
		_path_i += 1
	else:
		_on_path_finished()


func _on_path_finished() -> void:
	if _has_long_target:
		if world.player.position.distance_to(_long_target) > WG.TILE * 1.5 and _repath_budget > 0:
			_repath_budget -= 1
			world.chunk_manager.update_center(world.player.position)
			rebuild()
			if walk_to_pos(_long_target):
				return
		_has_long_target = false
	if not world.pending_action.is_empty():
		var action: Dictionary = world.pending_action
		world.pending_action = {}
		world._activity_ctrl.execute_action(action)
	elif world.auto_task.get("mode", "") == "gather" and not TickSim.active:
		world._auto_task_ctrl.find_next()
