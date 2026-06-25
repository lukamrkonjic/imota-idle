extends RefCounted
class_name WorldInputController
## Mouse clicks, zoom, and hover targeting.

# Wider, more extreme zoom range: lower min = pull much farther out, higher max =
# push much closer in. The 3D ortho size is CAM_SIZE_BASE / zoom, so higher zoom = nearer.
const ZOOM_MIN := 0.55
const ZOOM_MAX := 4.5
const ZOOM_STEP := 0.15

var world: Node2D

## True while the middle mouse button is held — drag then orbits the 3D camera.
var _orbiting := false

## Right-click context menu for sim-players (Follow / Examine). Built lazily on the HUD layer.
var _ctx_menu: PopupMenu
var _ctx_target: Node2D


func setup(w: Node2D) -> void:
	world = w


## True when the cursor is over an actual HUD panel, so world hover/click must be suppressed.
## The HUD root is a FULL-SCREEN passthrough (MOUSE_FILTER_PASS) covering the whole window, so
## gui_get_hovered_control() returns it even over empty world — we must NOT treat that as UI.
## Walk up from the hovered control: only an ancestor that actually STOPS the mouse (a real
## panel) counts. The passthrough root is PASS, so over open world this returns false.
func _over_ui() -> bool:
	var c: Control = world.get_viewport().gui_get_hovered_control()
	while c != null:
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		c = c.get_parent() as Control
	return false


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
	# Middle-mouse drag orbits the camera, same axes as the arrow keys. Press starts the
	# drag (ignored over a HUD panel so it can't hijack a scrollable list), release ends it,
	# and motion in between feeds the renderer's orbit.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_orbiting = event.pressed and not _over_ui()
		if event.pressed:
			world.get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		if world.render_3d != null and world.render_3d.is_active():
			world.render_3d.orbit_drag(event.relative)
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
			if _over_ui():
				return   # click is on the HUD, not the world
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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _over_ui():
				return   # right-click is on the HUD, not the world
			var rsim := _sim_at(world.mouse_world_pos())
			if rsim != null:
				_show_sim_menu(rsim)
				world.get_viewport().set_input_as_handled()


func update_hover() -> void:
	if _over_ui():
		# Cursor is on the HUD — clear any world hover so a world entity behind a panel
		# doesn't keep its tooltip/highlight showing over the UI.
		if world.hovered_entity != null:
			world.hovered_entity.hovered = false
			world.hovered_entity = null
		world.hud.call("update_world_tooltip", null)
		return
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
		# Trees are tall: lift the pick centre up onto the CANOPY (not the trunk base) and keep the
		# radius tight to it, so hovering matches the tree's visible mass instead of a wide ground ring.
		var tree := str(e.get("kind")) == "tree"
		var lift: float = clampf(e.icon_height() * ISO_PX_TO_WORLD * (0.62 if tree else 0.5), 0.35, 2.8 if tree else 1.6)
		var center: Vector2 = r3.iso_to_screen(e.position, lift)
		var radius_px: float = maxf(16.0, e.click_radius * ISO_PX_TO_WORLD * ppu)
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


# ------------------------------------------------------------ sim-player right-click menu ----

## Nearest sim-player under the cursor (sims carry an empty action so the normal entity pick skips
## them — this dedicated pick powers the right-click Follow menu). Screen-space under the 3D camera.
func _sim_at(cursor_iso: Vector2) -> Node2D:
	if world.render_3d != null and world.render_3d.is_active():
		var r3: Node = world.render_3d
		var mouse: Vector2 = world.get_viewport().get_mouse_position()
		var ppu: float = r3.world_px_per_unit()
		var best: Node2D = null
		var best_d := INF
		for e: Node2D in world.entities:
			if str(e.get("kind")) != "sim":
				continue
			if e.position.distance_squared_to(cursor_iso) > PREFILTER_ISO_SQ:
				continue
			var center: Vector2 = r3.iso_to_screen(e.position, 1.0)   # ~mid-body
			var radius_px: float = maxf(18.0, float(e.get("click_radius")) * ISO_PX_TO_WORLD * ppu)
			var d := center.distance_to(mouse)
			if d < radius_px and d < best_d:
				best_d = d
				best = e
		return best
	# 2D fallback (headless / no 3D): iso-space proximity.
	var best2: Node2D = null
	var best2_d := INF
	for e: Node2D in world.entities:
		if str(e.get("kind")) != "sim":
			continue
		var c: Vector2 = e.position - Vector2(0, e.icon_height() * 0.5)
		var d := c.distance_to(cursor_iso)
		if d < maxf(float(e.get("click_radius")), 28.0) and d < best2_d:
			best2_d = d
			best2 = e
	return best2


func _ensure_ctx_menu() -> void:
	if _ctx_menu != null:
		return
	_ctx_menu = PopupMenu.new()
	world.hud.add_child(_ctx_menu)
	_ctx_menu.id_pressed.connect(_on_ctx_id)


func _show_sim_menu(e: Node2D) -> void:
	_ensure_ctx_menu()
	_ctx_target = e
	_ctx_menu.clear()
	var nm := str(e.get("label"))
	# "Follow" = YOU trail them. "Ask to follow" = they trail you.
	if world._path_ctrl.is_following_entity(e):
		_ctx_menu.add_item("Stop following %s" % nm, 2)
	else:
		_ctx_menu.add_item("Follow %s" % nm, 1)
	if world._sim_director.is_following(e):
		_ctx_menu.add_item("Ask %s to stop" % nm, 5)
	else:
		_ctx_menu.add_item("Ask %s to follow" % nm, 4)
	_ctx_menu.add_item("Examine %s" % nm, 3)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Cancel", 0)
	_ctx_menu.reset_size()
	_ctx_menu.position = Vector2i(world.get_viewport().get_mouse_position()) + Vector2i(4, 2)
	_ctx_menu.popup()


func _on_ctx_id(id: int) -> void:
	if not is_instance_valid(_ctx_target):
		return
	match id:
		1:
			world._path_ctrl.follow_entity(_ctx_target)   # you follow them
		2:
			world._path_ctrl.stop_following()
		3:
			world._sim_director.examine(_ctx_target)
		4:
			world._sim_director.command_follow(_ctx_target)   # they follow you
		5:
			world._sim_director.stop_follow(_ctx_target)
