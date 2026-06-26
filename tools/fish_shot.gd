extends Node
## fish_shot — windowed verification capture for the fishing visuals. Spawns the real world, finds a
## shore tile beside water, stands the player there, then FORCES the fishing state (rod, then cage)
## so the rod-cast pose + line and the lobster kneel can be eyeballed. Usage:
##   godot --path . res://tools/fish_shot.tscn -- --out=/tmp/fish/

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

	# Stream a few coastal spots, then find a shore tile (dry, walkable, water next to it).
	var shore := Vector2i(-9999, -9999)
	var water_pos := Vector2.ZERO
	for c: Vector2i in [Vector2i(0, 0), Vector2i(2, 1), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(3, 0), Vector2i(-3, -1)]:
		var pos := WG.tile_to_world(c.x * WG.CHUNK_TILES + 8, c.y * WG.CHUNK_TILES + 8)
		_world.player.position = pos
		_world.chunk_manager.update_center(pos)
		for i: int in 24:
			await get_tree().process_frame
		var found := _find_shore()
		if found[0].x > -9999:
			shore = found[0]
			water_pos = found[1]
			break

	if shore.x <= -9999:
		print("  NO SHORE FOUND")
		get_tree().quit(1)
		return

	_world.player.position = WG.tile_to_world(shore.x, shore.y)
	_world.player.stop_walking()
	_world.chunk_manager.update_center(_world.player.position)
	if cam != null:
		cam.zoom = Vector2(3.2, 3.2)
		cam.reset_smoothing()
	for i: int in 30:
		await get_tree().process_frame

	# Inject a fishing-spot water-decor node at the cast water tile so the 3D bubbles render, then
	# frame just the water for a clear look at the bubbling.
	var WorldWaterDecor := load("res://scripts/world/world_water_decor.gd")
	var decor: Node2D = WorldWaterDecor.new()
	decor.kind = "fish_school"
	decor.variant = 0
	decor.position = _cast
	decor.visible = false
	_world.add_child(decor)
	_world._water_decor_nodes.append(decor)
	var cam0: Camera2D = _world.get("_camera")
	for n: int in 2:
		for i: int in 30:
			if cam0 != null:
				cam0.zoom = Vector2(4.5, 4.5)
			_world.player.position = WG.tile_to_world(shore.x, shore.y)
			_world.chunk_manager.update_center(_world.player.position)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var bimg: Image = get_viewport().get_texture().get_image()
		var bpath := _out_dir.path_join("bubbles_%d.png" % n)
		if bimg.save_png(bpath) == OK:
			_saved.append(ProjectSettings.globalize_path(bpath))
			print("  saved %s" % ProjectSettings.globalize_path(bpath))

	# One capture per skill so every gather pose can be eyeballed.
	await _capture("fishing", "Sardine", "fish_rod")        # rod cast + line
	await _capture("fishing", "Lobster", "fish_lobster")    # kneel, hands in water
	await _capture("mining", "Copper Ore", "mine")          # pickaxe swing
	await _capture("foraging", "Brightberry Bush", "forage")
	await _capture("hunter", "Rabbit Burrow", "trap")
	await _capture("thieving", "Market Stall", "steal")

	print("\n=== FISH RESULT ===")
	print(JSON.stringify({"tool": "fish_shot", "saved": _saved, "shore": str(shore)}))
	get_tree().quit(0)


var _cast := Vector2.ZERO


## Force a gather state for a skill and grab two frames (the pose eases in + the motion cycles).
func _capture(skill: String, node_name: String, tag: String) -> void:
	var nd := GatherNodeDef.new()
	nd.name = node_name
	nd.display_name = node_name
	for n: int in 2:
		# Re-assert each frame so the activity sim's own ticks can't stop it mid-capture.
		var cam: Camera2D = _world.get("_camera")
		for i: int in 34:
			TickSim.node = nd
			TickSim.skill = skill
			TickSim.active = true
			if cam != null:
				cam.zoom = Vector2(4.5, 4.5)   # force max zoom-in each frame (the rig mirrors this)
			if skill == "fishing":
				_world.player.set_fish_cast(_cast)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path := _out_dir.path_join("%s_%d.png" % [tag, n])
		if img.save_png(path) == OK:
			_saved.append(ProjectSettings.globalize_path(path))
			print("  saved %s" % ProjectSettings.globalize_path(path))
	TickSim.active = false


## Scan loaded chunks for a dry, walkable tile with a water 4-neighbour. Returns [shore_tile, water_pos].
func _find_shore() -> Array:
	var reg: RefCounted = WorldGen.reg
	for ch: RefCounted in _world.chunk_manager.loaded_chunks():
		for ly: int in WG.CHUNK_TILES:
			for lx: int in WG.CHUNK_TILES:
				var td: Dictionary = reg.tile_def(ch.tile_id(lx, ly))
				if bool(td.get("water", false)) or not bool(td.get("walkable", true)):
					continue
				for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = lx + off.x
					var ny: int = ly + off.y
					if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
						continue
					if bool(reg.tile_def(ch.tile_id(nx, ny)).get("water", false)):
						var gx: int = ch.cx * WG.CHUNK_TILES + lx
						var gy: int = ch.cy * WG.CHUNK_TILES + ly
						_cast = ch.tile_world(nx, ny)
						return [Vector2i(gx, gy), _cast]
	return [Vector2i(-9999, -9999), Vector2.ZERO]
