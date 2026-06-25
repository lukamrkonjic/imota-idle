extends Node3D

const MoverMeshes := preload("res://scripts/render/mover_meshes.gd")
const MoverRig := preload("res://scripts/render/mover_rig.gd")


func _ready() -> void:
	get_viewport().size = Vector2i(1280, 720)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-45, -35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-20, 145, 0)
	add_child(fill)
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 2.0, 5.5)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	add_child(cam)
	_spawn(-1.8, "sword")
	_spawn(0.0, "greatsword")
	_spawn(1.8, "staff")
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://weapon_pose_preview.png")
	get_tree().quit(0)


func _spawn(x: float, weapon_kind: String) -> void:
	var rig := MoverMeshes.player_rig(Color(0.86, 0.68, 0.56))
	MoverMeshes.apply_equipment(rig, {"mainhand": {"kind": weapon_kind, "material": "iron"}})
	add_child(rig)
	MoverRig._pose_humanoid(rig, Vector3(x, 0, 0), 0.0, 0.0, 0.0, x * 0.7, 1.0, 0.0)
