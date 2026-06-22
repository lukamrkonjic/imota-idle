extends Node
## Render the recoloured smithy model from a few angles to eyeball the synthesised colours.
##   godot --path . res://tools/smithy_preview.tscn -- --out=C:/path/

const SmithyProp := preload("res://scripts/render/smithy_prop.gd")

var _out := "user://shots/"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1000, 520))

	var world := Node3D.new()
	add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.30, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.64)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(46), 0)
	sun.light_energy = 1.15
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.30, 0.40, 0.28)
	ground.material_override = gmat
	world.add_child(ground)

	var scale := SmithyProp.scale_for(4.0)
	for i: int in 2:
		var inst := SmithyProp.build()
		inst.scale = Vector3(scale, scale, scale)
		inst.position = Vector3(float(i) * 6.0 - 3.0, SmithyProp.bottom_offset(scale), 0.0)
		inst.rotation.y = PI * (0.15 + float(i) * 0.6)
		world.add_child(inst)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.0
	var pitch := 0.5
	var yaw := PI / 4.0
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	cam.position = Vector3(0, 2.2, 0) + dir * 24.0
	world.add_child(cam)
	cam.look_at(Vector3(0, 2.0, 0), Vector3.UP)
	cam.current = true

	for _i: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = _out.path_join("smithy_preview.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SMITHY PREVIEW saved ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
