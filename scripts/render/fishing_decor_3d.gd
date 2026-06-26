extends RefCounted
class_name FishingDecor3D
## Marks every fishing spot with a cluster of animated BUBBLES rising off the water — small pale
## spheres that swell up from the surface, drift, and pop, looping forever so the spot reads clearly
## as "fish are here, cast in". The 2D world already spawns an invisible `fish_school` water-decor
## node at each fishing site's water tile (world._water_decor_nodes); this subsystem mirrors each one
## with a 3D bubble rig and animates it every frame. Pure visual — the clickable site drives fishing.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const BUBBLES := 14
const SPOT_RADIUS := 0.62        # cluster radius on the water surface (3D world units)
const RISE_HEIGHT := 0.3         # how high a bubble climbs before it pops
const RISE_SPEED := 0.55         # base rise cycles/sec (varied per bubble)
const BUBBLE_SIZE := 0.09        # peak bubble radius
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
	for i: int in rig.get_child_count():
		var b: Node3D = rig.get_child(i)
		# Deterministic per-bubble layout (golden-angle spread) + rise phase/speed, offset by the
		# spot's variant so neighbouring spots bubble out of sync.
		var fi := float(i)
		var ang := fi * 2.39996 + variant * 0.017
		var rad := SPOT_RADIUS * sqrt(fposmod(fi * 0.413 + 0.13, 1.0))
		var speed := RISE_SPEED * (0.7 + 0.6 * fposmod(fi * 0.37, 1.0))
		var ph := fposmod(fi * 0.61 + variant * 0.013, 1.0)
		var rise := fposmod(t * speed + ph, 1.0)
		# A little sideways wobble as it climbs.
		var wob := sin(t * 2.0 + fi) * 0.03
		b.position = Vector3(cos(ang) * rad + wob, rise * RISE_HEIGHT, sin(ang) * rad * 0.6)
		# Swell in from nothing, peak mid-climb, pop to nothing at the top.
		var sc := BUBBLE_SIZE * sin(rise * PI)
		b.scale = Vector3.ONE * maxf(sc, 0.0001)
