extends RefCounted
## Disposable visual load fixture for renderer performance work. Enabled only by the command-line
## flag `--perf-stress` (or `--perf-stress=<count>`); it never creates gameplay entities, touches
## chunks, or writes save/world state.

const WorldDecor := preload("res://scripts/world/world_decor.gd")

const DEFAULT_COUNT := 2400
const MIN_COUNT := 100
const MAX_COUNT := 12000
const INNER_RADIUS := 180.0
const OUTER_RADIUS := 4300.0
const KINDS := [
	"canopy_broadleaf", "canopy_pine", "canopy_birch", "canopy_maple",
	"boulder", "rock_pile", "cairn", "standing_stone", "crystal_cluster",
	"fallen_log", "mushroom", "fern", "shrub", "cactus",
]


static func enabled() -> bool:
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--perf-stress" or arg.begins_with("--perf-stress="):
			return true
	return false


static func populate(world: Node2D) -> void:
	if not enabled() or world == null or world.player == null or world._entities_layer == null:
		return
	var count := _requested_count()
	var origin: Vector2 = world.player.position
	for i: int in count:
		var decor := WorldDecor.new()
		decor.kind = KINDS[i % KINDS.size()]
		decor.variant = int((i * 7919 + 17) % 10000)
		var angle := float(i * 137) * PI / 180.0
		# Square-root distribution makes the whole spawn area dense instead of piling props in a ring.
		var radial_t := sqrt(float((i * 3571) % count) / float(maxi(count - 1, 1)))
		var radius := lerpf(INNER_RADIUS, OUTER_RADIUS, radial_t)
		decor.position = origin + Vector2(cos(angle) * radius, sin(angle) * radius * 0.58)
		decor.visible = false
		world._entities_layer.add_child(decor)
		world._decor_nodes.append(decor)
	print("[perf-stress] spawned %d non-interactive batched props around spawn" % count)


static func _requested_count() -> int:
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--perf-stress="):
			return clampi(int(arg.trim_prefix("--perf-stress=")), MIN_COUNT, MAX_COUNT)
	return DEFAULT_COUNT
