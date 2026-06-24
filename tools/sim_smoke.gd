extends Node
## Headless smoke test for SIM-PLAYERS (docs/SIM_PLAYERS_PLAN.md phases 0-3). Three passes, no GPU:
##   1. Identity is deterministic (same world+slot -> same name/look/levels).
##   2. Every sim rig builds + poses (idle / walk / gather-chop / sit) across the whole level ladder.
##   3. The live world scene actually spawns sims near the player and they move without crashing.
##   godot --headless --path . res://tools/sim_smoke.tscn

const MoverMeshes := preload("res://scripts/render/mover_meshes.gd")
const SimIdentity := preload("res://scripts/world/sim/sim_identity.gd")
const SimPlayer := preload("res://scripts/world/sim/sim_player.gd")

var _fails: Array = []


func _ready() -> void:
	_test_determinism()
	_test_rigs()
	_test_dialogue()
	await _test_live_spawn()
	if _fails.is_empty():
		print("OK: sim-player smoke passed (identity deterministic, rigs build+pose, world spawns sims)")
		get_tree().quit(0)
	else:
		print("FAILURES (%d):" % _fails.size())
		for f: String in _fails:
			print("  ", f)
		get_tree().quit(1)


func _test_determinism() -> void:
	var a := SimIdentity.build(7, 3, 5, 1, Vector2(100, 100))
	var b := SimIdentity.build(7, 3, 5, 1, Vector2(100, 100))
	if a.pname != b.pname or a.combat_level != b.combat_level or a.skin != b.skin or a.loadout != b.loadout:
		_fails.append("identity not deterministic for same seed+slot (%s vs %s)" % [a.pname, b.pname])
	# A different world seed should generally yield a different cast (sanity, not a hard guarantee).
	var diff := 0
	for slot: int in 8:
		if SimIdentity.build(7, 0, 0, slot, Vector2.ZERO).pname != SimIdentity.build(99, 0, 0, slot, Vector2.ZERO).pname:
			diff += 1
	if diff == 0:
		_fails.append("different world seeds produced an identical cast (suspicious)")
	print("  identity: '%s' lvl %d | sample look slots: %s" % [a.pname, a.combat_level, str(a.loadout.keys())])


func _test_rigs() -> void:
	var built := 0
	var slots_seen: Dictionary = {}
	for i: int in 48:
		var sim := SimIdentity.build(12345, i, i * 3 + 1, i % 3, Vector2.ZERO)
		var rig: Node3D = MoverMeshes.sim_rig(sim.skin, sim.loadout)
		if rig == null:
			_fails.append("null sim rig at i=%d (lvl %d)" % [i, sim.combat_level])
			continue
		add_child(rig)
		for k: String in sim.loadout.keys():
			slots_seen[k] = true
		# Idle, walking, and the gather "chop" swing — the three poses a sim shows in-world.
		for k: int in 6:
			var walk := 0.7 if k % 2 == 0 else 0.0
			var chop := 0.5 if k % 3 == 0 else 0.0
			MoverRig._pose_humanoid(rig, Vector3.ZERO, 0.3, walk, float(k) * 0.13, 0.0, 1.0, 0.0, chop)
		MoverRig.pose_sit(rig, 0.0, 1.0)
		rig.free()
		built += 1
	print("  rigs: built+posed %d sim rigs; equipment slots exercised: %s" % [built, str(slots_seen.keys())])


func _test_dialogue() -> void:
	var dia := SimIdentity.dialogue()
	if dia.is_empty():
		_fails.append("dialogue.json failed to load")
		return
	for key: String in ["greetings", "player_greetings", "smalltalk", "group"]:
		if (dia.get(key, []) as Array).is_empty():
			_fails.append("dialogue.%s is empty" % key)
	# @name templating must resolve cleanly.
	var line := str((dia.get("greetings", ["Hey @name!"]) as Array)[0]).replace("@name", "Bryn")
	if line.contains("@name"):
		_fails.append("@name templating left a placeholder")
	print("  dialogue: %d greeting lines, sample -> '%s'" % [(dia.get("greetings", []) as Array).size(), line])


## Boot the real world scene and let it run; confirm the director spawns sims that actually move.
func _test_live_spawn() -> void:
	var ws: PackedScene = load("res://scenes/world.tscn")
	if ws == null:
		_fails.append("could not load world scene")
		return
	var world: Node = ws.instantiate()
	add_child(world)
	# Give chunks time to stream and the director (1s rescan) time to spawn + walk a few legs.
	var positions: Dictionary = {}
	var moved := false
	for _f: int in 420:
		await get_tree().process_frame
		var dir: RefCounted = world.get("_sim_director")
		if dir == null:
			continue
		for sim in dir.sims():
			var e: Node2D = sim.entity
			if not is_instance_valid(e):
				continue
			var id := e.get_instance_id()
			if positions.has(id) and (positions[id] as Vector2).distance_to(e.position) > 1.0:
				moved = true
			positions[id] = e.position
	var dir2: RefCounted = world.get("_sim_director")
	var n: int = dir2.sims().size() if dir2 != null else 0
	if n <= 0:
		_fails.append("no sims spawned in the live world after 420 frames")
	elif not moved:
		_fails.append("sims spawned (%d) but none moved" % n)
	print("  live world: %d sims spawned, movement observed=%s" % [n, str(moved)])
	world.queue_free()
