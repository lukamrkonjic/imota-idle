extends RefCounted
class_name WorldInputController
## Mouse clicks, zoom, and hover targeting.

const WG := preload("res://scripts/worldgen/wg.gd")

const ZOOM_MIN := 1.1
const ZOOM_MAX := 2.4
const ZOOM_STEP := 0.1

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		if world.get("_biome_debug") != null:
			world._biome_debug.call("toggle")
			world.get_viewport().set_input_as_handled()
		return
	# Trackpad pinch-to-zoom (macOS): the gesture's factor is the relative
	# magnification per tick (>1 pinch-out/zoom-in, <1 pinch-in/zoom-out), so
	# multiplying the current zoom by it gives smooth continuous scaling.
	if event is InputEventMagnifyGesture:
		_set_zoom(world._camera.zoom.x * event.factor)
		world.get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(world._camera.zoom.x + ZOOM_STEP)
			world.get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(world._camera.zoom.x - ZOOM_STEP)
			world.get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var click_pos := world.get_global_mouse_position()
			var target := entity_at(click_pos)
			world.show_click_fx(click_pos, target != null)
			if target != null:
				world.auto_task = {}
				world.begin_action(target)
			else:
				world.pending_action = {}
				world.auto_task = {}
				if CombatSim.active:
					# Walking off mid-fight doesn't end combat — the mob gives chase
					# and the leash decides if you actually escape (handled in the
					# activity controller). Only drop skilling sims here.
					TickSim.stop()
					RecipeSim.stop()
				else:
					world._activity_ctrl.stop_all_sims()
					world._activity_ctrl.clear_combat_target()
				# Resolve the raised tile drawn under the cursor so clicking a mountain
				# walks onto it, not to the flat tile rendered in front of it.
				var tile := WorldGen.tile_at_screen(click_pos, int(world.get("current_layer")))
				if GameSettings.noclip:
					# Fly: straight line to the click, ignoring pathfinding/terrain.
					world.player.walk_to(WG.tile_to_world(tile.x, tile.y))
				else:
					world.walk_to_pos(WG.tile_to_world(tile.x, tile.y))
			world.get_viewport().set_input_as_handled()


func update_hover() -> void:
	var mouse := world.get_global_mouse_position()
	var found := entity_at(mouse)
	if found != world.hovered_entity:
		if world.hovered_entity != null:
			world.hovered_entity.hovered = false
		world.hovered_entity = found
		if world.hovered_entity != null:
			world.hovered_entity.hovered = true
	world.hud.call("update_world_tooltip", found)


func entity_at(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	var candidates: Array = world._visible_entities if not world._visible_entities.is_empty() else world.entities
	for raw: Variant in candidates:
		if not is_instance_valid(raw):
			continue
		var e: Node2D = raw
		if not e.visible:
			continue
		# Only interactable entities are hover/click targets. Decorative props —
		# walls, houses, ruined masonry, bridges, street clutter — carry an empty
		# action, so they get no tooltip and clicks pass through to walk-here.
		if Dictionary(e.get("action")).is_empty():
			continue
		var center: Vector2 = e.position - Vector2(0, e.icon_height() * 0.5)
		var d := center.distance_to(world_pos)
		if d < e.click_radius and d < best_d:
			best_d = d
			best = e
	return best


static func hover_text(e: Node2D) -> String:
	if e == null:
		return "Walk here"
	if e.has_method("action_text"):
		var text: String = e.call("action_text")
		if not text.is_empty():
			return text
	return "Walk here"


func _set_zoom(z: float) -> void:
	var c := clampf(z, ZOOM_MIN, ZOOM_MAX)
	world._camera.zoom = Vector2(c, c)
