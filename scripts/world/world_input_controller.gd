extends RefCounted
class_name WorldInputController
## Mouse clicks, zoom, and hover targeting.

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
			var click_pos: Vector2 = world.mouse_world_pos()
			var target := entity_at(click_pos)
			world.show_click_fx(click_pos, target != null)
			if target != null:
				world.auto_task = {}
				world.begin_action(target)
			else:
				world.pending_action = {}
				world.auto_task = {}
				if CombatSim.active:
					# OSRS: a movement command clears YOUR attack — you stop auto-swinging
					# (no attacking-while-fleeing) — but the enemy stays COMMITTED: it keeps
					# its target and chases/retaliates as you move (persistent aggro). Click
					# it again to resume attacking; walking past its leash ends the fight.
					CombatSim.player_retaliating = false
					TickSim.stop()
					RecipeSim.stop()
				else:
					world._activity_ctrl.stop_all_sims()
					world._activity_ctrl.clear_combat_target()
				# click_pos already comes from the 3D camera's screen_to_iso projection
				# (mouse_world_pos), so walk straight there — no 2D elevation re-pick.
				world.walk_to_pos(click_pos)
			world.get_viewport().set_input_as_handled()


func update_hover() -> void:
	var mouse: Vector2 = world.mouse_world_pos()
	var found := entity_at(mouse)
	if found != world.hovered_entity:
		if world.hovered_entity != null:
			world.hovered_entity.hovered = false
		world.hovered_entity = found
		if world.hovered_entity != null:
			world.hovered_entity.hovered = true
	world.hud.call("update_world_tooltip", found)


# Old 2D iso-pixels -> 3D world-Y factor: one elevation step is 8 iso px and
# ELEV_H (0.25) world units tall, so a sprite's pixel height maps to world height
# at this ratio. Lets us reuse the per-entity icon_height()/click_radius tuning
# for the screen-space pick below.
const ISO_PX_TO_WORLD := 0.25 / 8.0
# Hover/click pre-filter radius (iso px, squared). Generous enough to cover the
# foreshortening of the tallest entities (a tree canopy's ground-hit sits well
# behind its base) while still rejecting the vast majority of off-cursor entities.
const PREFILTER_ISO_SQ := 280.0 * 280.0


func entity_at(world_pos: Vector2) -> Node2D:
	# With the 3D renderer active, the on-screen image comes from the 3D camera, so
	# the flat iso comparison below picks the wrong point (it offsets the billboard
	# up in iso space, but the 3D projection foreshortens — that mismatch is the
	# "tooltip sits too high / click lands off" feel). Pick in screen space instead.
	if world.render_3d != null and world.render_3d.is_active():
		return _entity_at_screen(world_pos)  # world_pos is already the cursor's iso ground point
	var best: Node2D = null
	var best_d := INF
	for e: Node2D in world.entities:
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


## Screen-space pick: compare the live cursor to each interactable entity's
## projected body centre (a little above its feet), within a screen radius derived
## from its iso click_radius. Correct under any camera pitch/yaw/zoom.
func _entity_at_screen(cursor_iso: Vector2) -> Node2D:
	var r3: Node = world.render_3d
	var mouse: Vector2 = world.get_viewport().get_mouse_position()
	var ppu: float = r3.world_px_per_unit()
	# Cheap iso-space pre-filter: only the handful of entities near the cursor's
	# ground point get the expensive per-entity screen projection (camera unproject
	# + terrain height sampling). Without this, projecting all ~400 entities every
	# frame costs ~10ms. iso distance is monotonic with screen distance, so a
	# generous radius can't miss a real hover target. cursor_iso is passed in (it's
	# the screen->ground projection the caller already did) to avoid a 2nd raycast.
	var best: Node2D = null
	var best_d := INF
	for e: Node2D in world.entities:
		if Dictionary(e.get("action")).is_empty():
			continue
		if e.position.distance_squared_to(cursor_iso) > PREFILTER_ISO_SQ:
			continue
		var lift: float = clampf(e.icon_height() * ISO_PX_TO_WORLD * 0.5, 0.35, 1.6)
		var center: Vector2 = r3.iso_to_screen(e.position, lift)
		var radius_px: float = maxf(18.0, e.click_radius * ISO_PX_TO_WORLD * ppu)
		var d := center.distance_to(mouse)
		if d < radius_px and d < best_d:
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
