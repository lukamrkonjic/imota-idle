extends RefCounted
class_name FishingDecor3D
## Marks every fishing spot with a cluster of animated BUBBLES rising off the water — small pale
## spheres that swell up from the surface, drift, and pop, looping forever so the spot reads clearly
## as "fish are here, cast in". The 2D world already spawns an invisible `fish_school` water-decor
## node at each fishing site's water tile (world._water_decor_nodes); this subsystem mirrors each one
## with a 3D bubble rig and animates it every frame. Pure visual — the clickable site drives fishing.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const BUBBLES := 26
const SPOT_RADIUS := 0.6         # cluster radius on the water surface (3D world units)
const RISE_HEIGHT := 0.26        # how high a bubble climbs before it pops
const RISE_SPEED := 0.6          # base rise cycles/sec (varied per bubble)
const BUBBLE_SIZE := 0.08        # peak bubble radius (varied per bubble)
const SURFACE_LIFT := 0.03       # sit just above the water plane

var _props_root: Node3D
var _height: Callable      # height_at_iso(iso: Vector2) -> float (water surface over water)
var _iso_to_3d: Callable   # iso_to_3d(iso: Vector2, y: float) -> Vector3
var _world: Node2D
var _rigs: Dictionary = {}   # water-decor node instance_id -> Node3D rig
var _bubble_mat: StandardMaterial3D


func setup(w: Node2D, props: Node3D, height_provider: Callable, iso_to_3d_provider: Callable) -> void:
	_world = w
	_props_root = props
	_height = height_provider
	_iso_to_3d = iso_to_3d_provider
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.albedo_color = Color(0.9, 0.97, 1.0, 0.8)   # pale foam-white
	_bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Mirror + animate a bubble rig for every live `fish_school` water-decor node, freeing rigs whose
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
	for id: int in _rigs.keys():
		if not live.has(id):
			var r: Node3D = _rigs[id]
			if is_instance_valid(r):
				r.queue_free()
			_rigs.erase(id)


func _build_rig() -> Node3D:
	var rig := Node3D.new()
	for i: int in BUBBLES:
		var b := MeshInstance3D.new()
		b.mesh = PropMeshes._sphere("fish_bubble", 1.0)   # unit sphere; scaled per frame
		b.material_override = _bubble_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(b)
	return rig


func _animate(rig: Node3D, iso: Vector2, t: float, variant: float) -> void:
	var y: float = _height.call(iso) + SURFACE_LIFT
	rig.position = _iso_to_3d.call(iso, y)
	var n := rig.get_child_count()
	for i: int in n:
		var b: Node3D = rig.get_child(i)
		var fi := float(i)
		# Golden-angle spread across the spot; deterministic per-bubble radius, size and rise speed.
		var ang := fi * 2.39996 + variant * 0.017
		var rad := SPOT_RADIUS * sqrt(fposmod(fi * 0.413 + 0.13, 1.0))
		var speed := RISE_SPEED * (0.6 + 0.8 * fposmod(fi * 0.37, 1.0))
		var size := BUBBLE_SIZE * (0.45 + 0.75 * fposmod(fi * 0.53 + 0.2, 1.0))
		# EVENLY-spread phases (i/n) + a little jitter, so at every instant bubbles exist at all
		# stages of the climb — the cluster fizzes continuously with no visible loop seam.
		var ph := fposmod(fi / float(n) + fposmod(fi * 0.197, 1.0) * 0.25 + variant * 0.013, 1.0)
		var rise := fposmod(t * speed + ph, 1.0)
		var wob := sin(t * 2.3 + fi * 1.7) * 0.025   # sideways drift as it climbs
		b.position = Vector3(cos(ang) * rad + wob, rise * RISE_HEIGHT, sin(ang) * rad * 0.6)
		# Real-bubble envelope: POP in fast at the surface, hold near full size while rising, then
		# POP out near the top. (Not a slow symmetric swell — a quick appear + a quick burst.)
		var env := smoothstep(0.0, 0.1, rise) * (1.0 - smoothstep(0.82, 0.96, rise))
		b.scale = Vector3.ONE * maxf(size * env, 0.0001)
