extends RefCounted
class_name FishingDecor3D
## Renders the animated "school of fish" that marks every fishing spot: a ring of dark fish
## SHADOWS gliding in a slow, endless circle on the water surface (the satisfying loop). The 2D
## world already spawns an invisible `fish_school` water-decor node at each fishing site's water
## tile (world._water_decor_nodes); this subsystem mirrors each one with a small 3D rig of flat
## shadow ellipses and animates them every frame. Shadows use the same MULTIPLY blob-shadow
## material as movers, so they darken the water beneath them and read as fish gliding just under
## the surface. Pure visual — no gameplay; the clickable site entity drives the actual fishing.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const FISH_PER_SCHOOL := 6
const ORBIT_RX := 0.62           # circle radii (3D world units) — slightly oval so it reads as depth
const ORBIT_RZ := 0.40
const ORBIT_SPEED := 0.7         # radians/sec — slow, calming glide
const SURFACE_LIFT := 0.05       # sit just above the water plane so the shadow isn't z-fighting
const BODY_LEN := 0.34           # fish-shadow body size (long axis, +Z)
const BODY_WIDTH := 0.16

var _props_root: Node3D
var _height: Callable      # height_at_iso(iso: Vector2) -> float (returns water surface over water)
var _iso_to_3d: Callable   # iso_to_3d(iso: Vector2, y: float) -> Vector3
var _world: Node2D
var _rigs: Dictionary = {}   # water-decor node instance_id -> Node3D rig


func setup(w: Node2D, props: Node3D, height_provider: Callable, iso_to_3d_provider: Callable) -> void:
	_world = w
	_props_root = props
	_height = height_provider
	_iso_to_3d = iso_to_3d_provider


## Mirror + animate a 3D school for every live `fish_school` water-decor node, and free rigs whose
## node has been culled (chunk unloaded). Called once per frame from the render coordinator.
func update(_delta: float) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var live: Dictionary = {}
	for node: Node in _world._water_decor_nodes:
		if not is_instance_valid(node) or str(node.get("kind")) != "fish_school":
			continue
		var id := node.get_instance_id()
		live[id] = true
		var rig: Node3D = _rigs.get(id)
		if rig == null:
			rig = _build_rig()
			_props_root.add_child(rig)
			_rigs[id] = rig
		_animate(rig, node.position, t, float(int(node.get("variant"))))
	# Drop rigs whose source node is gone.
	for id: int in _rigs.keys():
		if not live.has(id):
			var r: Node3D = _rigs[id]
			if is_instance_valid(r):
				r.queue_free()
			_rigs.erase(id)


func _build_rig() -> Node3D:
	var rig := Node3D.new()
	for i: int in FISH_PER_SCHOOL:
		# Each fish is a flat shadow ellipse (body) with a smaller trailing disc (tail). Reusing
		# the mover blob-shadow mesh+material keeps the art consistent and costs no new assets.
		var fish := Node3D.new()
		var body: MeshInstance3D = PropMeshes.blob_shadow()
		body.name = "body"
		body.scale = Vector3(BODY_WIDTH, 1.0, BODY_LEN)
		fish.add_child(body)
		var tail: MeshInstance3D = PropMeshes.blob_shadow()
		tail.name = "tail"
		tail.scale = Vector3(BODY_WIDTH * 0.7, 1.0, BODY_LEN * 0.5)
		tail.position = Vector3(0.0, 0.0, -BODY_LEN * 0.55)
		fish.add_child(tail)
		rig.add_child(fish)
	return rig


func _animate(rig: Node3D, iso: Vector2, t: float, variant: float) -> void:
	var y: float = _height.call(iso) + SURFACE_LIFT
	rig.position = _iso_to_3d.call(iso, y)
	var phase := variant * 0.013   # per-spot offset so neighbouring schools aren't in lockstep
	for i: int in rig.get_child_count():
		var fish: Node3D = rig.get_child(i)
		# Evenly spaced around the ring, drifting forever.
		var a := t * ORBIT_SPEED + phase + TAU * float(i) / float(FISH_PER_SCHOOL)
		# Gentle breathing of the ring radius + a tiny vertical bob so it feels alive, not mechanical.
		var rx := ORBIT_RX * (1.0 + 0.06 * sin(t * 0.8 + float(i)))
		var rz := ORBIT_RZ * (1.0 + 0.06 * cos(t * 0.7 + float(i)))
		fish.position = Vector3(cos(a) * rx, 0.0, sin(a) * rz)
		# Point each fish along its travel direction (body long axis is +Z -> yaw = -a).
		fish.rotation.y = -a
		# Tail wiggle: oscillate the trailing disc side-to-side.
		var tail: Node3D = fish.get_node("tail")
		tail.position.x = sin(t * 6.0 + a * 2.0) * BODY_WIDTH * 0.4
