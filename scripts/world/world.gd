extends Node2D
## Procedural chunked overworld — scene composition and controller delegation.
## Input, pathing, entities, activities, layers, and visuals live in *Controller
## scripts under scripts/world/.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkManager := preload("res://scripts/worldgen/chunk_manager.gd")
const UnexploredBackdrop := preload("res://scripts/worldgen/unexplored_backdrop.gd")
const PlayerAvatar := preload("res://scripts/world/player_avatar.gd")
const WorldEntitySpawner := preload("res://scripts/world/world_entity_spawner.gd")
const WorldPathController := preload("res://scripts/world/world_path_controller.gd")
const WorldInputController := preload("res://scripts/world/world_input_controller.gd")
const WorldActivityController := preload("res://scripts/world/world_activity_controller.gd")
const WorldAutoTaskController := preload("res://scripts/world/world_auto_task_controller.gd")
const WorldLayerController := preload("res://scripts/world/world_layer_controller.gd")
const WorldVisualController := preload("res://scripts/world/world_visual_controller.gd")
const SimDirector := preload("res://scripts/world/sim/sim_director.gd")
const WorldCollisionController := preload("res://scripts/world/world_collision_controller.gd")
const WorldAmbience := preload("res://scripts/world/world_ambience.gd")
const BiomeDebugOverlay := preload("res://scripts/world/biome_debug_overlay.gd")
const ClickMarkerNode := preload("res://scripts/ui/click_marker_node.gd")
const HitSplat := preload("res://scripts/world/hit_splat.gd")
const ArrowProj := preload("res://scripts/world/arrow_proj.gd")
const PerfLogger := preload("res://scripts/world/perf_logger.gd")
const BakeQueue := preload("res://scripts/world/bake_queue.gd")
const PerfStressFixture := preload("res://scripts/render/perf_stress_fixture.gd")
# WorldRender3D is a global class_name (scripts/render/world_render_3d.gd) — no preload needed.

# --- public state (tests, HUD) ---
# The single switch that decouples the live game from the world editor. When false, this World
# instance still STREAMS and RENDERS the world (so the editor sees the real 3D result of its edits)
# but runs NONE of the gameplay simulation — no player pathing, no enemy AI, no sim-players, no
# creature collision. The editor embeds this scene with gameplay_active = false; "Test Level" flips
# it true. One gate here means zero `if editor` checks scattered through the gameplay systems.
var gameplay_active := true
# Sim-players are a populated-MMO flourish for the real game; the world editor's Test Level turns
# them OFF (it's for testing the LEVEL — pathing/terrain — not the crowd). Independent of
# gameplay_active so the rest of the game still runs in a test.
var sims_enabled := true
var entities: Array = []
var player: Node2D
var hud: CanvasLayer
var chunk_manager: Node2D
var unexplored_backdrop: Node2D
var current_layer := 0
var hovered_entity: Node2D = null
var pending_action: Dictionary = {}
var combat_target_entity: Node2D = null
var auto_task: Dictionary = {}
var gather_ref: Dictionary = {}

# --- internal scene graph ---
var _entities_layer: Node2D
var _chunk_containers: Dictionary = {}
var _site_entities: Dictionary = {}
var _decor_nodes: Array = []
var _water_decor_nodes: Array = []
var _roofed_entities: Array = []  # houses/buildings only — for per-frame roof fade
var _click_fx_layer: Node2D
var _camera: Camera2D
var render_3d: WorldRender3D        # 3D pixel-art renderer (null/headless = 2D path); typed so its API is compile-checked
var editor_stream_cap := 0          # world editor: max terrain chunk radius (0 = uncapped)
var _ambient: CanvasModulate
var _ambience: Node2D
var _biome_debug: Node2D
var _perf_logger: Node
var _last_bake_gate_pos := Vector2.INF
var last_hover_us := 0              # diagnostic: cost of update_hover() last frame (perf tools read this)

# --- controllers ---
var _entity_spawner: RefCounted
var _path_ctrl: RefCounted
var _input_ctrl: RefCounted
var _activity_ctrl: RefCounted
var _auto_task_ctrl: RefCounted
var _layer_ctrl: RefCounted
var _visual_ctrl: RefCounted
var _sim_director: RefCounted
var _collision_ctrl: RefCounted


func _ready() -> void:
	hud = $HUD
	_init_controllers()
	_build_scene()
	_connect_events()
	call_deferred("_finalize_player_spawn")
	chunk_manager.update_center(player.position)
	_entity_spawner.sort_entities_for_targeting()
	_path_ctrl.rebuild()


func _finalize_player_spawn() -> void:
	var pos := WorldGen.spawn_position()
	# Restore the saved world position if we have one and it's still valid terrain;
	# otherwise fall back to the spawn floor (new game, or a no-longer-walkable spot).
	if GameState.player_pos.is_finite() and WorldGen.is_spawn_floor(GameState.player_pos):
		pos = GameState.player_pos
		player.position = pos
	elif not WorldGen.is_spawn_floor(player.position):
		player.position = pos
	chunk_manager.update_center(player.position)
	_entity_spawner.sort_entities_for_targeting()
	_path_ctrl.mark_path_dirty()
	_path_ctrl.rebuild()


func _init_controllers() -> void:
	_entity_spawner = WorldEntitySpawner.new()
	_path_ctrl = WorldPathController.new()
	_input_ctrl = WorldInputController.new()
	_activity_ctrl = WorldActivityController.new()
	_auto_task_ctrl = WorldAutoTaskController.new()
	_layer_ctrl = WorldLayerController.new()
	_visual_ctrl = WorldVisualController.new()
	_sim_director = SimDirector.new()
	_collision_ctrl = WorldCollisionController.new()
	for ctrl: RefCounted in [_entity_spawner, _path_ctrl, _input_ctrl, _activity_ctrl, _auto_task_ctrl, _layer_ctrl, _visual_ctrl, _sim_director, _collision_ctrl]:
		ctrl.setup(self)


func _build_scene() -> void:
	_ambient = CanvasModulate.new()
	_ambient.color = Color(1.04, 1.02, 0.98)
	add_child(_ambient)

	unexplored_backdrop = UnexploredBackdrop.new()
	unexplored_backdrop.name = "UnexploredBackdrop"
	add_child(unexplored_backdrop)

	chunk_manager = ChunkManager.new()
	chunk_manager.name = "Chunks"
	add_child(chunk_manager)
	chunk_manager.chunk_loaded.connect(_entity_spawner.on_chunk_loaded)
	chunk_manager.chunk_unloaded.connect(_entity_spawner.on_chunk_unloaded)

	var bake_queue := BakeQueue.new()
	bake_queue.name = "BakeQueue"
	add_child(bake_queue)

	_perf_logger = PerfLogger.new()
	_perf_logger.name = "PerfLogger"
	_perf_logger.setup(self)
	add_child(_perf_logger)

	_entities_layer = Node2D.new()
	_entities_layer.name = "Entities"
	_entities_layer.y_sort_enabled = true
	add_child(_entities_layer)

	_click_fx_layer = Node2D.new()
	_click_fx_layer.name = "ClickFX"
	_click_fx_layer.z_index = 600
	add_child(_click_fx_layer)

	player = PlayerAvatar.new()
	player.name = "Player"
	player.position = WorldGen.spawn_position()
	player.arrived.connect(_path_ctrl.on_waypoint_reached)
	_entities_layer.add_child(player)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.65, 1.65)
	# Near-fixed follow: the player stays centred, but a quick smoothing pass eases
	# the per-frame motion so it isn't a rigid pixel-lock — just a touch softer than
	# a fixed cam, without the sluggish drift of a dead zone.
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 12.0
	player.add_child(_camera)
	unexplored_backdrop.set("camera", _camera)

	_visual_ctrl.build_darkness()

	_ambience = WorldAmbience.new()
	_ambience.name = "Ambience"
	add_child(_ambience)
	_ambience.setup(self)

	# Dawn-mist overlay: a full-screen shader haze above the 3D present (layer 3), under the weather
	# particles (layer 4). Strength is driven by the global `dawn_mist` from the DayNight cycle.
	var mist_layer := CanvasLayer.new()
	mist_layer.name = "DawnMist"
	mist_layer.layer = 3
	add_child(mist_layer)
	var mist := ColorRect.new()
	mist.set_anchors_preset(Control.PRESET_FULL_RECT)
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = load("res://shaders/dawn_mist.gdshader")
	mist.material = mist_mat
	mist_layer.add_child(mist)

	_biome_debug = BiomeDebugOverlay.new()
	_biome_debug.name = "BiomeDebug"
	_biome_debug.z_index = 500
	_biome_debug.visible = false
	add_child(_biome_debug)

	hud.call("bind_world", self)

	# 3D pixel-art renderer (committed port). No-ops in headless; hides the 2D
	# world visuals and presents the 3D world under the HUD.
	render_3d = WorldRender3D.new()
	render_3d.name = "WorldRender3D"
	add_child(render_3d)
	render_3d.setup(self)

	# Weather FX (rain/snow/wind) rendered INSIDE the low-res pixel viewport so it shares the world's
	# pixel grid — chunky + on-grid, not thin full-res lines floating on top. Falls back to a full-res
	# CanvasLayer when the 3D pixel pipeline isn't active (2D substrate / headless).
	var weather_fx := WorldWeatherFx.new()
	weather_fx.name = "WeatherFx"
	if render_3d == null or not render_3d.attach_pixel_overlay(weather_fx):
		var weather_layer := CanvasLayer.new()
		weather_layer.name = "WeatherFx"
		weather_layer.layer = 4
		add_child(weather_layer)
		weather_layer.add_child(weather_fx)

	PerfStressFixture.populate(self)


func _connect_events() -> void:
	EventBus.action_progress.connect(func(f: float) -> void: player.set_progress(f))
	EventBus.activity_stopped.connect(_activity_ctrl.on_activity_stopped)
	EventBus.enemy_hp_changed.connect(_activity_ctrl.on_enemy_hp_changed)
	EventBus.enemy_killed.connect(func(n: String) -> void:
		_activity_ctrl.on_enemy_killed()
		GameState.slayer_kill(n))
	EventBus.xp_gained.connect(_activity_ctrl.on_xp_gained)
	EventBus.player_died.connect(func(k: String) -> void:
		_activity_ctrl.on_activity_stopped("player_died")
		_layer_ctrl.on_player_died())
	EventBus.level_up.connect(func(_s: String, _l: int) -> void: _path_ctrl.on_level_up())
	EventBus.site_respawned.connect(_auto_task_ctrl.on_site_respawned)
	# Felling/regrowing a tree changes whether its tile blocks movement — refresh the nav graph so
	# the cleared stump becomes walkable (and a regrown trunk blocks again).
	EventBus.wc_tree_felled.connect(func(_e: Node, _s: String) -> void: _path_ctrl.mark_path_dirty())
	EventBus.wc_tree_grew.connect(func(_e: Node, _s: String) -> void: _path_ctrl.mark_path_dirty())
	EventBus.combat_hit_splat.connect(_spawn_hit_splat)
	EventBus.combat_ranged_shot.connect(_spawn_arrow)
	# UI → world intents (replaces UI calling world.call("...") directly).
	EventBus.bank_requested.connect(auto_bank)
	EventBus.gather_requested.connect(auto_gather)
	EventBus.station_requested.connect(auto_station)
	EventBus.teleport_requested.connect(teleport_to)
	EventBus.navigate_requested.connect(func(p: Vector2) -> void: navigate_to(p))
	EventBus.rest_requested.connect(halt_player)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if gameplay_active:
		GameState.player_pos = player.position   # kept current so saves capture where you are
	chunk_manager.update_center(player.position)
	var t1 := Time.get_ticks_usec()
	_update_stream_radius()
	var t2 := Time.get_ticks_usec()
	# Gameplay simulation — gated so the editor's view-only instance never runs the game (see
	# gameplay_active). Streaming + the visual pass below always run so the world still looks right.
	if gameplay_active:
		_path_ctrl.process_tick(delta)
	var t3 := Time.get_ticks_usec()
	_visual_ctrl.process_tick(delta)
	var t4 := Time.get_ticks_usec()
	var t5 := t4
	var t6 := t4
	if gameplay_active:
		_input_ctrl.update_hover()
		t5 = Time.get_ticks_usec()
		_activity_ctrl.process_tick(delta)
		t6 = Time.get_ticks_usec()
		if sims_enabled:
			_sim_director.process_tick(delta)
		_collision_ctrl.process_tick(delta)
	var t7 := Time.get_ticks_usec()
	last_hover_us = t5 - t4
	if _perf_logger != null:
		_perf_logger.record(delta, {
			"chunk": t1 - t0, "stream": t2 - t1, "path": t3 - t2,
			"visual": t4 - t3, "hover": t5 - t4, "activity": t6 - t5,
			"sims": t7 - t6,
		})


## Scale the streaming radii to the camera so terrain + entities always fill the
## view (plus a margin for off-screen pop-in) at any zoom, then shrink back in
## when zoomed close so we don't keep a huge ring loaded needlessly.
func _update_stream_radius() -> void:
	var zoom: float = _camera.zoom.x
	if zoom <= 0.0:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Half-extent of the view in world units, converted to chunk distance in the
	# isometric basis (a chunk spans CHUNK_TILES*ISO_HW in x, *ISO_HH in y).
	var wx: float = vp.x / zoom * 0.5
	var wy: float = vp.y / zoom * 0.5
	var span_x: float = float(WG.CHUNK_TILES) * WG.ISO_HW
	var span_y: float = float(WG.CHUNK_TILES) * WG.ISO_HH
	var r: int = ceili((wx / span_x + wy / span_y) * 0.5)
	# World editor (aerial view): the View slider FORCES the terrain radius so it can
	# both load more (see further) and stay bounded when zoomed way out (no OOM). It
	# overrides the zoom-derived radius entirely — the slider is the authority.
	if editor_stream_cap > 0:
		r = mini(r, editor_stream_cap)   # auto-follow the zoom-derived radius, bounded by the editor ceiling
		chunk_manager.editor_view_cap = editor_stream_cap   # raise the DATA hard cap so the ceiling is reachable
	# Terrain must fill the whole zoomed-out view, but interactive/entity chunks
	# only need a modest buffer around the player. Expanding both was flooding the
	# moving camera with hundreds of extra CanvasItems.
	var active_r: int = WG.NAV_RADIUS if zoom < 0.7 else mini(r + 1, WG.ACTIVE_RADIUS + 1)
	# Stream DATA at least one ring beyond the 3D terrain build ring, so every chunk it
	# meshes has its 8 neighbours' data (seamless borders). The render's terrain_ring scales
	# with the view-distance slider; the zoom-derived r still widens streaming when zoomed out.
	var terrain_need: int = 0
	if render_3d != null and render_3d.is_active():
		terrain_need = int(render_3d.terrain_ring) + 2
	chunk_manager.set_radii(maxi(r + 2, terrain_need), active_r)
	var bake_queue := get_node_or_null("BakeQueue")
	if bake_queue != null:
		var moving := _last_bake_gate_pos != Vector2.INF and player.position.distance_squared_to(_last_bake_gate_pos) > 1.0
		bake_queue.set("paused", moving and zoom < 0.7)
		_last_bake_gate_pos = player.position


func _unhandled_input(event: InputEvent) -> void:
	_input_ctrl.handle_input(event)


# --- public API (tests + HUD) ---

func show_click_fx(world_pos: Vector2, interactable: bool) -> void:
	var marker: Node2D = ClickMarkerNode.new()
	if render_3d != null and render_3d.is_active():
		# The 2D click layer is hidden under the 3D renderer, so the marker lives on
		# the screen-space overlay, projected onto the clicked ground point.
		render_3d.fx_layer.add_child(marker)
		marker.position = render_3d.iso_to_screen(world_pos, 0.0)
	else:
		_click_fx_layer.add_child(marker)
		marker.global_position = world_pos
	marker.call("begin", interactable)


## Pop a damage splat over the struck target — the enemy we're hitting, or the
## player when the enemy lands a blow. Skips silently if there is no live target.
func _spawn_hit_splat(amount: int, miss: bool, on_player: bool) -> void:
	var anchor: Node2D = player if on_player else combat_target_entity
	if not is_instance_valid(anchor):
		return
	var splat: Node2D = HitSplat.new()
	splat.set("amount", amount)
	splat.set("miss", miss)
	splat.set("anchor", anchor)
	if render_3d != null and render_3d.is_active():
		# 3D: the 2D world is hidden, so the splat lives on a screen-space overlay and
		# projects the target's body through the 3D camera each frame. The lift scales
		# with the target's size so the splat sits ON the body (low on small mobs, high
		# on big ones), and it's drawn much larger to read at a glance.
		splat.set("projector", render_3d)
		splat.set("lift", render_3d.mover_lift(anchor))
		splat.set("scale_mul", 3.0)
		splat.set("follow_offset", Vector2(randf_range(-10.0, 10.0), randf_range(-8.0, 4.0)))
		render_3d.fx_layer.add_child(splat)
	else:
		# 2D: sit the splat low over the body, pinned via a fixed local offset.
		var rise := 14.0
		if not on_player and anchor.has_method("icon_height"):
			rise = float(anchor.call("icon_height")) * 0.32
		var off := Vector2(randf_range(-3.0, 3.0), -rise + randf_range(-2.0, 2.0))
		splat.set("follow_offset", off)
		splat.position = anchor.position + off
		_click_fx_layer.add_child(splat)


## Fly an arrow from the player's bow to the current combat target; the arrow pops
## the damage splat on arrival (see arrow_proj.gd). Falls back to an instant splat
## if the target vanished mid-flight.
func _spawn_arrow(amount: int, miss: bool) -> void:
	if not is_instance_valid(combat_target_entity):
		EventBus.combat_hit_splat.emit(amount, miss, false)
		return
	var arrow: Node2D = ArrowProj.new()
	arrow.set("start", player.position + Vector2(0.0, -16.0))
	arrow.set("end", combat_target_entity.position - Vector2(0.0, 16.0))
	arrow.set("amount", amount)
	arrow.set("miss", miss)
	_click_fx_layer.add_child(arrow)


func begin_action(entity: Node2D) -> void:
	_activity_ctrl.begin_action(entity)


func walk_to_pos(target: Vector2) -> bool:
	return _path_ctrl.walk_to_pos(target)


## Fully halt the player: stop walking, stop every activity sim, and clear any queued/auto
## action. Driven by the HUD rest orb via EventBus.rest_requested (no direct UI→world reach).
func halt_player() -> void:
	_path_ctrl.stop_walking()
	_activity_ctrl.stop_all_sims()
	pending_action = {}
	auto_task = {}


## Navigate to a map/minimap-picked world position: clear any pending action / auto-task
## (this is a plain move command) and path there. Returns false if unreachable.
func navigate_to(target: Vector2) -> bool:
	pending_action = {}
	auto_task = {}
	# Minimap clicks are coarse — if the picked spot isn't walkable (water, cliff, off-map), route to
	# the NEAREST walkable tile instead of refusing, so a click always takes the player somewhere
	# sensible (e.g. the shore nearest a click in the sea). Only reroute when walkable ground is
	# genuinely nearby (within the search radius); a click far out at open sea finds nothing and just
	# declines, rather than yanking the player to the home-spawn fallback.
	if not WorldGen.is_walkable_world(target, current_layer):
		const SNAP_RINGS := 64
		var snap: Vector2 = WorldGen.nearest_walkable_world(target, current_layer, SNAP_RINGS)
		if snap.distance_to(target) <= float(SNAP_RINGS) * WG.TILE + 1.0 \
				and WorldGen.is_walkable_world(snap, current_layer):
			target = snap
		else:
			EventBus.combat_log.emit("[color=#444]Nowhere to walk near there.[/color]")
			player.play_no()
			return false
	return walk_to_pos(target)


## Active route for overlays (minimap). Returns {} when no route is being walked.
func active_route() -> Dictionary:
	if _path_ctrl == null or not _path_ctrl.has_active_route():
		return {}
	return {"points": _path_ctrl.route_waypoints(), "dest": _path_ctrl.route_destination()}


## Mouse position in 2D iso world space. With the 3D renderer active, the on-screen
## image comes from the 3D camera, so we project the cursor through THAT camera onto
## the terrain instead of trusting the (hidden) Camera2D's screen mapping.
func mouse_world_pos() -> Vector2:
	if render_3d != null and render_3d.is_active():
		return render_3d.screen_to_iso(get_viewport().get_mouse_position())
	return get_global_mouse_position()


func auto_gather(skill: String, node_name: String) -> void:
	_auto_task_ctrl.auto_gather(skill, node_name)


func auto_station(skill: String, recipe_name: String = "") -> void:
	_auto_task_ctrl.auto_station(skill, recipe_name)


func auto_bank() -> void:
	_auto_task_ctrl.auto_bank()


func teleport_to(pos: Vector2) -> void:
	_layer_ctrl.teleport_to(pos)


func _auto_find_next_deferred() -> void:
	_auto_task_ctrl.find_next()
