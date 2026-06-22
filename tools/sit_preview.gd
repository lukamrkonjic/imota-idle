extends Node
## sit_preview — renders the player rig STANDING vs SITTING (the cross-legged monk
## pose) from a game-like iso angle and saves one PNG, so the seated pose can be
## eyeballed without driving the live game. Touches rendering only.
##   godot --path . res://tools/sit_preview.tscn -- --out=C:/path/

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const MoverRig := preload("res://scripts/render/mover_rig.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

var _out := "user://shots/"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_log("ready start; out=%s" % _out)
	DisplayServer.window_set_size(Vector2i(900, 520))

	var world := Node3D.new()
	add_child(world)

	# Warm ground + sky so the silhouette reads against it.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.30, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(46), 0)   # sun upper-right, like the game
	sun.light_energy = 1.1
	world.add_child(sun)

	# Ground plane so we can see whether the seat actually meets the floor.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.27, 0.36, 0.26)
	ground.material_override = gmat
	world.add_child(ground)

	# Three rigs: standing, half-sit, full-sit — left to right.
	var skin := Color(0.85, 0.68, 0.55)
	# Close-up tuning: the full-sit figure from two angles (front-quarter, then side).
	var yaws := [0.0, PI / 2.0]
	for i: int in yaws.size():
		var rig := PropMeshes.player_rig(skin)
		rig.set_meta("base_scale", 1.0)
		world.add_child(rig)
		var px := float(i) * 2.0 - 1.0
		var ry := float(yaws[i])
		# Idle pose first (matches the renderer's order), then layer the sit.
		MoverRig._pose_humanoid(rig, Vector3(px, 0, 0), ry, 0.0, 0.0, 0.0, 1.0, 0.0)
		rig.position.x = px   # _pose_humanoid overwrites position; restore spacing
		rig.position.z = 0.0
		MoverRig.pose_sit(rig, 1.0, 1.0)

	# Iso ortho camera (the game's default yaw PI/4, gentle pitch).
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.6
	var pitch := 0.42
	var yaw := PI / 4.0
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	cam.position = Vector3(0, 0.35, 0) + dir * 20.0
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.35, 0), Vector3.UP)
	cam.current = true
	cam.make_current()

	_log("scene built; waiting to render")
	# Give the renderer a few real frames (signal awaits proved flaky here), then grab.
	for _i: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_log("captured frame")
	var img := get_viewport().get_texture().get_image()
	var path: String = _out.path_join("sit_preview.png")
	var err := img.save_png(path)
	_log("save_png err=%d -> %s" % [err, ProjectSettings.globalize_path(path)])
	get_tree().quit(0)


func _log(msg: String) -> void:
	var f := FileAccess.open(_out.path_join("sit_preview.log"), FileAccess.READ_WRITE if FileAccess.file_exists(_out.path_join("sit_preview.log")) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(msg)
		f.close()
	print("[sit_preview] ", msg)
