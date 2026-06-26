extends Node
## fish_shot — windowed verification capture for the animated fishing-spot school. Spawns the real
## world, hunts for a `fish` gather site by streaming around coastal chunks, frames it close, and
## saves a few frames so the swimming animation can be eyeballed. Usage:
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

	# Sites populate at chunk ACTIVATION (streaming), not raw get_chunk. Sweep coastal chunks,
	# stream each, and scan the chunk-manager's loaded chunks for a fishing site.
	var target := Vector2.ZERO
	var found := false
	var swept := 0
	for r: int in range(0, 12):
		for cy: int in range(-r, r + 1):
			for cx: int in range(-r, r + 1):
				if absi(cx) != r and absi(cy) != r:
					continue
				var pos := WG.tile_to_world(cx * WG.CHUNK_TILES + 8, cy * WG.CHUNK_TILES + 8)
				_world.player.position = pos
				_world.chunk_manager.update_center(pos)
				swept += 1
				for i: int in 14:
					await get_tree().process_frame
				for ch: RefCounted in _world.chunk_manager.loaded_chunks():
					for s: Dictionary in ch.sites:
						if str(s.get("skill", "")) == "fishing":
							target = ch.tile_world(int(s["tx"]), int(s["ty"]))
							found = true
							break
					if found: break
				if found: break
			if found: break
		if found: break

	if not found:
		print("  NO FISHING SITE FOUND (swept=%d chunks)" % swept)
		get_tree().quit(1)
		return

	# Frame the spot close-up.
	_world.player.position = target + Vector2(0, WG.TILE * 2.0)
	_world.chunk_manager.update_center(target)
	if cam != null:
		cam.zoom = Vector2(2.2, 2.2)
		cam.reset_smoothing()
	for i: int in 40:
		await get_tree().process_frame
	# Three frames spaced out so the orbiting school is visibly in different positions.
	for n: int in 3:
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path := _out_dir.path_join("fish_%d.png" % n)
		if img.save_png(path) == OK:
			_saved.append(ProjectSettings.globalize_path(path))
			print("  saved %s" % ProjectSettings.globalize_path(path))

	print("\n=== FISH RESULT ===")
	print(JSON.stringify({"tool": "fish_shot", "saved": _saved, "at": str(target)}))
	get_tree().quit(0)
