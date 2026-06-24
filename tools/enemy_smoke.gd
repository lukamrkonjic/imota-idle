extends Node
## Headless smoke test for enemy MODELS + ANIMATIONS. Builds the rig for every enemy in
## DataRegistry, runs its matching gait for a few frames (idle + moving + a bite), and reports the
## archetype distribution. Catches rig-build crashes, missing pivots and pose errors without a GPU.
##   godot --headless --path . res://tools/enemy_smoke.tscn

const MoverMeshes := preload("res://scripts/render/mover_meshes.gd")


class Stub extends Node:    # enemy_rig() takes a Node and reads .label / .action / .is_boss off it
	var label: String = ""
	var action: Dictionary = {}
	var is_boss: bool = false


func _ready() -> void:
	var by_type: Dictionary = {}
	var sample: Dictionary = {}      # body3d -> a few example names
	var fails: Array = []
	for name: String in DataRegistry.enemies.keys():
		var e := Stub.new()
		e.label = String(name)
		e.action = {"name": String(name), "level": 1}
		var rig: Node3D = MoverMeshes.enemy_rig(e)
		if rig == null:
			fails.append("%s: null rig" % name)
			continue
		var body3d := String(rig.get_meta("body3d", "?"))
		by_type[body3d] = int(by_type.get(body3d, 0)) + 1
		var ex: Array = sample.get(body3d, [])
		if ex.size() < 4:
			ex.append(String(name))
			sample[body3d] = ex
		add_child(rig)
		for k: int in 8:                                  # idle + moving alternating, with a bite atk
			_pose(rig, body3d, float(k) * 0.13, 0.85 if k % 2 == 0 else 0.0)
		rig.free()
		e.free()
	print("=== enemy model smoke test (%d enemies) ===" % DataRegistry.enemies.size())
	var keys: Array = by_type.keys()
	keys.sort()
	for bt: String in keys:
		print("  %-10s x%-3d  e.g. %s" % [bt, by_type[bt], ", ".join(sample[bt])])
	if fails.is_empty():
		print("OK: every enemy rig built + posed, no crashes")
	else:
		print("FAILURES (%d):" % fails.size())
		for f: String in fails:
			print("  ", f)
	get_tree().quit(1 if not fails.is_empty() else 0)


func _pose(rig: Node3D, bt: String, t: float, walk: float) -> void:
	var p := Vector3.ZERO
	match bt:
		"bird":
			MoverRig._pose_bird(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"humanoid":
			match String(rig.get_meta("gait", "")):
				"goblin":
					MoverRig._pose_goblin(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
				"gnoll":
					MoverRig._pose_gnoll(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
				_:
					MoverRig._pose_humanoid(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3, 0.0)
		"dragon":
			MoverRig._pose_dragon(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"serpent", "crawler":
			MoverRig._pose_serpent(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"slime":
			MoverRig._pose_slime(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"wraith", "eye":
			MoverRig._pose_float(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"spider", "scarab":
			MoverRig._pose_scuttle(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"crab":
			MoverRig._pose_crab(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		"bat":
			MoverRig._pose_bat(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
		_:
			MoverRig._pose_quadruped(rig, p, 0.0, walk, t, 0.0, 1.0, 0.3)
