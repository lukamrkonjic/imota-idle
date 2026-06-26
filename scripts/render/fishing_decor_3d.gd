extends RefCounted
class_name FishingDecor3D
## Marks every fishing spot with translucent BUBBLES on the water surface — small round pale-cyan
## bubbles that rise from points around the spot, grow, and pop/fade, staggered so the patch keeps
## bubbling in a continuous, seamless loop. Each bubble is a slightly-flattened sphere with a
## per-instance translucent material (so it reads as a round, see-through bubble sitting on the
## water — NOT a solid grey pebble) and renders reliably from the iso camera.
##
## The 2D world already spawns an invisible `fish_school` water-decor node at each fishing site's
## water tile (world._water_decor_nodes); this subsystem mirrors each with a bubble rig. The old
## static squashed-sphere mesh (water_decor_parts "fish_school") is skipped by StaticPropBatcher so
## the grey "pebbles" never render.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const BUBBLES := 14
const SPOT_RADIUS := 0.55         # how far across the bubbling patch is (3D world units)
const RISE_HEIGHT := 0.16         # small upward float before the bubble pops
const CYCLE_SPEED := 0.7          # bloom/rise cycles/sec (varied per bubble)
const BUBBLE_MIN := 0.07          # bubble radius at the start of a cycle
const BUBBLE_MAX := 0.16          # bubble radius at full size
const SURFACE_LIFT := 0.03        # sit just above the water plane so it isn't depth-clipped
const PEAK_ALPHA := 0.6           # translucency at full bloom (see-through, not solid)

var _props_root: Node3D
var _height: Callable      # height_at_iso(iso: Vector2) -> float (water surface over water)
var _iso_to_3d: Callable   # iso_to_3d(iso: Vector2, y: float) -> Vector3
var _world: Node2D
var _rigs: Dictionary = {}   # water-decor node instance_id -> Node3D rig
var _bubble_mesh: Mesh


func setup(w: Node2D, props: Node3D, height_provider: Callable, iso_to_3d_provider: Callable) -> void:
	_world = w
	_props_root = props
	_height = height_provider
	_iso_to_3d = iso_to_3d_provider
	_bubble_mesh = PropMeshes._sphere("fish_bubble", 1.0)


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
		b.mesh = _bubble_mesh
		# Per-bubble material so each fades its own alpha independently. Bright pale-cyan, unshaded,
		# translucent, double-sided -> a round see-through bubble on the water (never a solid pebble).
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.82, 0.96, 1.0, 0.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.material_override = m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(b)
	return rig


func _animate(rig: Node3D, iso: Vector2, t: float, variant: float) -> void:
	var y: float = _height.call(iso) + SURFACE_LIFT
	rig.position = _iso_to_3d.call(iso, y)
	var n := rig.get_child_count()
	for i: int in n:
		var b: MeshInstance3D = rig.get_child(i)
		var fi := float(i)
		# Each bubble rises at a FIXED point around the spot (deterministic angle + radius), so the
		# patch reads as several spots bubbling. Evenly-staggered phases => always some at every stage.
		var ang := fi * 2.39996 + variant * 0.017
		var rad := SPOT_RADIUS * sqrt(fposmod(fi * 0.413 + 0.13, 1.0))
		var speed := CYCLE_SPEED * (0.7 + 0.6 * fposmod(fi * 0.37, 1.0))
		var off := fi / float(n) + fposmod(fi * 0.19 + variant * 0.013, 1.0) * 0.1
		var p := fposmod(t * speed + off, 1.0)   # 0..1 bubble cycle
		b.position = Vector3(cos(ang) * rad, p * RISE_HEIGHT, sin(ang) * rad * 0.6)
		# Grow the bubble from min->max (round, sitting on the surface).
		var r := lerpf(BUBBLE_MIN, BUBBLE_MAX, smoothstep(0.0, 0.7, p))
		b.scale = Vector3(r, r, r)
		# Appear fast, hold (translucent), pop away near the top -> bubbles continuously, seamless.
		var alpha := smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.7, 1.0, p)) * PEAK_ALPHA
		var mat: StandardMaterial3D = b.material_override
		mat.albedo_color.a = alpha
