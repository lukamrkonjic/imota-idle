extends RefCounted
class_name FishingDecor3D
## Marks every fishing spot with rising AIR BUBBLES on the water — small translucent cyan rings with
## a white highlight that spawn at one underwater point, float up with a slight wobble, grow, then
## burst into an expanding ring and fade, with new ones continuously spawning so the spot always
## shimmers. Each bubble is a camera-facing (billboard) quad with a procedurally drawn bubble texture,
## so it reads as a round translucent bubble from the iso camera — not a solid sphere/pebble.
##
## The 2D world already spawns an invisible `fish_school` water-decor node at each fishing site's
## water tile (world._water_decor_nodes); this subsystem mirrors each with a bubble rig.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const BUBBLES := 16
const RISE_HEIGHT := 0.3          # how high a bubble climbs (3D world units) before it bursts
const RISE_SPEED := 0.5           # base rise cycles/sec (varied per bubble)
const SOURCE_SPREAD := 0.24       # how far bubbles drift apart as they rise from the source point
const BUBBLE_MIN := 0.09          # quad size as it leaves the source
const BUBBLE_MAX := 0.18          # quad size just before it bursts
const SURFACE_Y := 0.04           # the source sits a touch below the water plane

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
		# Per-bubble material duplicate so each fades its own alpha independently as it bursts. A
		# LOW-alpha, bright pale-cyan unshaded sphere reads as a see-through air bubble (not a solid
		# pebble — that was an opaque pale sphere). Billboard quads refused to render in this pipeline.
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.78, 0.95, 1.0, 0.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.material_override = m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(b)
	return rig


func _animate(rig: Node3D, iso: Vector2, t: float, variant: float) -> void:
	var y: float = _height.call(iso)
	rig.position = _iso_to_3d.call(iso, y)
	var n := rig.get_child_count()
	for i: int in n:
		var b: MeshInstance3D = rig.get_child(i)
		var fi := float(i)
		var speed := RISE_SPEED * (0.7 + 0.6 * fposmod(fi * 0.37, 1.0))
		# Evenly-staggered phases so a bubble is always at every stage — continuous, seamless rise.
		var off := fi / float(n) + fposmod(fi * 0.19 + variant * 0.013, 1.0) * 0.12
		var p := fposmod(t * speed + off, 1.0)
		# Drift outward + wobble as it climbs from the single source point.
		var ang := fi * 2.39996 + variant * 0.017
		var spread := SOURCE_SPREAD * p
		var wob := sin(t * 3.0 + fi * 1.7) * 0.035 * p
		# Keep the bubble just ABOVE the water plane (the water mesh writes depth and would clip a
		# submerged sprite), rising from the source point on the surface.
		b.position = Vector3(cos(ang) * spread + wob, SURFACE_Y + p * RISE_HEIGHT, sin(ang) * spread * 0.6)
		# Grow as it rises, then EXPAND hard in the burst window (reads as a ring/ripple pop).
		var size := lerpf(BUBBLE_MIN, BUBBLE_MAX, p)
		if p > 0.8:
			size *= 1.0 + (p - 0.8) / 0.2 * 1.4
		b.scale = Vector3(size, size, size)
		# Fade in fast at the source, hold (translucent) while rising, fade out through the burst ->
		# seamless loop. Peak alpha kept low so it reads as a see-through bubble, not a solid blob.
		var alpha := smoothstep(0.0, 0.07, p) * (1.0 - smoothstep(0.8, 1.0, p)) * 0.55
		var mat: StandardMaterial3D = b.material_override
		mat.albedo_color.a = alpha
