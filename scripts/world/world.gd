extends Node2D
## Procedural chunked overworld — scene composition and controller delegation.
## Input, pathing, entities, activities, layers, and visuals live in *Controller
## scripts under scripts/world/.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkManager := preload("res://scripts/worldgen/chunk_manager.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")
const UnexploredBackdrop := preload("res://scripts/worldgen/unexplored_backdrop.gd")
const PlayerAvatar := preload("res://scripts/world/player_avatar.gd")
const WorldEntitySpawner := preload("res://scripts/world/world_entity_spawner.gd")
const WorldPathController := preload("res://scripts/world/world_path_controller.gd")
const WorldInputController := preload("res://scripts/world/world_input_controller.gd")
const WorldActivityController := preload("res://scripts/world/world_activity_controller.gd")
const WorldAutoTaskController := preload("res://scripts/world/world_auto_task_controller.gd")
const WorldLayerController := preload("res://scripts/world/world_layer_controller.gd")
const WorldVisualController := preload("res://scripts/world/world_visual_controller.gd")
const WorldAmbience := preload("res://scripts/world/world_ambience.gd")
const BiomeDebugOverlay := preload("res://scripts/world/biome_debug_overlay.gd")
const ClickMarkerNode := preload("res://scripts/ui/click_marker_node.gd")
const PerfLogger := preload("res://scripts/world/perf_logger.gd")
const BakeQueue := preload("res://scripts/world/bake_queue.gd")
const EntitySpriteCache := preload("res://scripts/world/entity_sprite_cache.gd")
const SpriteAtlas := preload("res://scripts/world/sprite_atlas.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")

# --- public state (tests, HUD) ---
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
var last_frame_timings: Dictionary = {}  # per-frame subsystem usec, for spike attribution

# --- internal scene graph ---
var _entities_layer: Node2D
var _chunk_containers: Dictionary = {}
var _site_entities: Dictionary = {}
var _decor_nodes: Array = []
var _water_decor_nodes: Array = []
var _visible_entities: Array = []  # maintained by WorldVisualController for hot queries
var _roofed_entities: Array = []  # houses/buildings only — for per-frame roof fade
var _click_fx_layer: Node2D
var _camera: Camera2D
var _ambient: CanvasModulate
var _ambience: Node2D
var _biome_debug: Node2D
var _perf_logger: Node
var _last_bake_gate_pos := Vector2.INF
var _last_stream_motion_msec := 0

const STREAM_SETTLE_MSEC := 220

# --- controllers ---
var _entity_spawner: RefCounted
var _path_ctrl: RefCounted
var _input_ctrl: RefCounted
var _activity_ctrl: RefCounted
var _auto_task_ctrl: RefCounted
var _layer_ctrl: RefCounted
var _visual_ctrl: RefCounted


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
	if not WorldGen.is_spawn_floor(player.position):
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
	for ctrl: RefCounted in [_entity_spawner, _path_ctrl, _input_ctrl, _activity_ctrl, _auto_task_ctrl, _layer_ctrl, _visual_ctrl]:
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

	var sprite_atlas := SpriteAtlas.new()
	sprite_atlas.name = "SpriteAtlas"
	add_child(sprite_atlas)

	var bake_queue := BakeQueue.new()
	bake_queue.name = "BakeQueue"
	add_child(bake_queue)

	var sprite_cache := EntitySpriteCache.new()
	sprite_cache.name = "EntitySpriteCache"
	add_child(sprite_cache)
	WorldEntity.sprite_cache = sprite_cache

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
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	player.add_child(_camera)
	unexplored_backdrop.set("camera", _camera)

	_visual_ctrl.build_darkness()

	_ambience = WorldAmbience.new()
	_ambience.name = "Ambience"
	add_child(_ambience)
	_ambience.setup(self)

	_biome_debug = BiomeDebugOverlay.new()
	_biome_debug.name = "BiomeDebug"
	_biome_debug.z_index = 500
	_biome_debug.visible = false
	add_child(_biome_debug)

	hud.call("bind_world", self)


func _connect_events() -> void:
	EventBus.action_progress.connect(func(f: float) -> void: player.set_progress(f))
	EventBus.activity_stopped.connect(_activity_ctrl.on_activity_stopped)
	EventBus.enemy_hp_changed.connect(_activity_ctrl.on_enemy_hp_changed)
	EventBus.enemy_killed.connect(func(_n: String) -> void: _activity_ctrl.on_enemy_killed())
	EventBus.xp_gained.connect(_activity_ctrl.on_xp_gained)
	EventBus.player_died.connect(func(k: String) -> void:
		_activity_ctrl.on_activity_stopped("player_died")
		_layer_ctrl.on_player_died())
	EventBus.level_up.connect(func(_s: String, _l: int) -> void: _path_ctrl.on_level_up())
	EventBus.site_respawned.connect(_auto_task_ctrl.on_site_respawned)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	chunk_manager.update_center(player.position)
	var t1 := Time.get_ticks_usec()
	_update_stream_radius()
	var t2 := Time.get_ticks_usec()
	_path_ctrl.process_tick()
	var t3 := Time.get_ticks_usec()
	_visual_ctrl.process_tick(delta)
	var t4 := Time.get_ticks_usec()
	_input_ctrl.update_hover()
	var t5 := Time.get_ticks_usec()
	_activity_ctrl.process_tick(delta)
	var t6 := Time.get_ticks_usec()
	last_frame_timings = {
		"chunk": t1 - t0, "stream": t2 - t1, "path": t3 - t2,
		"visual": t4 - t3, "hover": t5 - t4, "activity": t6 - t5,
	}
	if _perf_logger != null:
		_perf_logger.record(delta, last_frame_timings)


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
	var camera_r: int = ceili((wx / span_x + wy / span_y) * 0.5)
	# Terrain gets the widest shell, entities get a still-off-camera shell, and
	# nav stays fixed in ChunkManager.loaded_chunks(). That keeps trees/enemies
	# from popping into view without making A* rebuild the whole visible world.
	chunk_manager.set_radii(camera_r + 2, camera_r + 1)
	# Freeze entity animations when zoomed far out — the per-frame live redraw of
	# hundreds of visible enemies/fish is the dominant cost there and invisible.
	WorldEntity.animations_enabled = zoom >= 0.7
	var bake_queue := get_node_or_null("BakeQueue")
	if bake_queue != null:
		var moving := _last_bake_gate_pos != Vector2.INF and player.position.distance_squared_to(_last_bake_gate_pos) > 1.0
		if moving:
			_last_stream_motion_msec = Time.get_ticks_msec()
		var stream_stable := Time.get_ticks_msec() - _last_stream_motion_msec >= STREAM_SETTLE_MSEC
		if chunk_manager.has_method("set_stream_busy"):
			chunk_manager.call("set_stream_busy", not stream_stable)
		bake_queue.set("paused", moving)
		ChunkRenderer.visible_mesh_applies_allowed = stream_stable
		_last_bake_gate_pos = player.position


func _unhandled_input(event: InputEvent) -> void:
	_input_ctrl.handle_input(event)


# --- public API (tests + HUD) ---

func show_click_fx(world_pos: Vector2, interactable: bool) -> void:
	var marker: Node2D = ClickMarkerNode.new()
	_click_fx_layer.add_child(marker)
	marker.global_position = world_pos
	marker.call("begin", interactable)


func begin_action(entity: Node2D) -> void:
	_activity_ctrl.begin_action(entity)


func walk_to_pos(target: Vector2) -> bool:
	return _path_ctrl.walk_to_pos(target)


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
