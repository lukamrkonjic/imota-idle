extends Node
## world_shoot — windowed evaluation-screenshot capture for the AI critics.
## Runs the real world scene (NOT --headless: the dummy renderer cannot draw),
## teleports the camera to predefined positions, and saves PNGs. See
## docs/AI_WORLD_AUTHORING.md (AI evaluation loop / visual-identity critic).
##
## Usage (a window briefly opens):
##   godot --path . res://tools/world_shoot.tscn -- --out=C:/path/shots/
##
## Output PNGs default to user://shots/ (i.e. %APPDATA%/Godot/app_userdata/<game>/shots/).
## The trailer prints the absolute saved paths as JSON.

const WG := preload("res://scripts/worldgen/wg.gd")

var _world: Node2D
var _out_dir := "user://shots/"
var _saved: Array = []


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.position_smoothing_enabled = false

	# Showcase shots: a zoomed-out overview at spawn, then each named place.
	var spec: RefCounted = WorldGen.reg.spec
	var shots: Array = [
		{"name": "overview", "chunk": Vector2i(0, 0), "zoom": 0.32},
		{"name": "eastvale_spawn", "chunk": Vector2i(0, 0), "zoom": 0.95},
		{"name": "north_peaks", "chunk": Vector2i(-3, -24), "zoom": 0.85},
		{"name": "north_peaks2", "chunk": Vector2i(6, -22), "zoom": 0.85},
		{"name": "grand_north", "chunk": Vector2i(0, -32), "zoom": 0.42},
		{"name": "grand_north2", "chunk": Vector2i(-10, -30), "zoom": 0.5},
	]
	if spec != null and spec.active:
		for a: Dictionary in spec.anchors:
			shots.append({"name": str(a["id"]), "chunk": Vector2i(a["chunk"]), "zoom": 0.7})

	for shot: Dictionary in shots:
		await _capture(shot)

	print("\n=== WORLDC RESULT ===")
	print(JSON.stringify({"tool": "world_shoot", "saved": _saved}))
	get_tree().quit(0)


func _capture(shot: Dictionary) -> void:
	var c: Vector2i = shot["chunk"]
	var pos := WG.tile_to_world(c.x * WG.CHUNK_TILES + 8, c.y * WG.CHUNK_TILES + 8)
	_world.player.position = pos
	var cam: Camera2D = _world.get("_camera")
	if cam != null:
		cam.zoom = Vector2(float(shot["zoom"]), float(shot["zoom"]))
		cam.reset_smoothing()
	_world.chunk_manager.update_center(pos)
	# Let chunks stream in, entities spawn and the renderer settle.
	for i: int in 40:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join(str(shot["name"]) + ".png")
	var err := img.save_png(path)
	if err == OK:
		_saved.append(ProjectSettings.globalize_path(path))
		print("  saved %s (%s)" % [str(shot["name"]), ProjectSettings.globalize_path(path)])
	else:
		print("  FAILED to save %s (err %d)" % [str(shot["name"]), err])
