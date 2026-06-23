extends RefCounted
class_name StaticPropBatcher
## Batches all static decor + props into per-(mesh,material) MultiMeshes (extracted from the
## WorldRender3D monolith). The rebuild is TIME-SLICED across frames — collect a slice of props,
## then emit a few MultiMesh groups per frame into a HIDDEN staging node, swapping it in only when
## complete — so no single frame does the full O(all props) work and the old batch stays visible
## meanwhile (no gap). It also skips its slice on chunk-build frames to avoid stacking spikes.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const BATCH_REBUILD_MIN := 0.35      # min seconds between static-batch rebuilds
const RB_COLLECT_PER_FRAME := 150     # props collected per frame (caps height_at samples/frame)
const RB_EMIT_INSTANCES_PER_FRAME := 500  # instances buffered per frame (caps a giant group's fill)
const _IDENTITY_XF := Transform3D()  # sentinel for "not yet cached" (props never sit at identity)

var world: Node2D
var batches_root: Node3D
var _height: Callable        # height_at(iso: Vector2) -> float
var _iso_to_3d: Callable     # iso_to_3d(iso: Vector2, y: float) -> Vector3

var _static_sig := ""
var _batch_xf: Dictionary = {}       # static prop instance_id -> cached world Transform3D
var _batch_rebuild_t := 0.0          # last static-batch rebuild START time (throttle)
var _rb_active := false
var _rb_phase := 0                   # 0 = collecting, 1 = emitting
var _rb_list: Array = []             # snapshot [[kind:int 0=decor/1=water/2=ent, node], …]
var _rb_i := 0                       # phase 0: list index;  phase 1: group-key index
var _rb_groups: Dictionary = {}
var _rb_xf: Dictionary = {}
var _rb_keys: Array = []
var _rb_sig := ""
var _rb_staging: Node3D = null
var _rb_g: Dictionary = {}           # group currently being emitted (filled incrementally)
var _rb_gbuf := PackedFloat32Array() # its instance buffer, filled across frames
var _rb_gi := 0                      # instance index within the current group


func setup(w: Node2D, root: Node3D, height_provider: Callable, iso_to_3d_provider: Callable) -> void:
	world = w
	batches_root = root
	_height = height_provider
	_iso_to_3d = iso_to_3d_provider


## Force a fresh rebuild on the next update (editor edits / preview teleports / placed props).
func invalidate() -> void:
	_static_sig = ""


## Batch all static decor + props into per-(mesh,material) MultiMeshes, merged across the whole
## visible set. TIME-SLICED across frames (see RB_* state); the old batch stays visible until the
## new one is fully built, then swaps in. terrain_built = a chunk mesh built this frame.
func update(terrain_built: bool) -> void:
	if not _rb_active:
		var sig := "%s:%d:%d:%d" % [str(world.current_layer), int(world._decor_nodes.size()), int(world._water_decor_nodes.size()), int(world.entities.size())]
		if sig == _static_sig:
			return
		var now := Time.get_ticks_msec() / 1000.0
		if now - _batch_rebuild_t < BATCH_REBUILD_MIN:
			return                              # throttle: let a streaming burst settle
		_batch_rebuild_t = now
		_start_staged_rebuild(sig)
	if terrain_built:
		return                                  # stagger: don't run a slice on a chunk-build frame
	_advance_staged_rebuild()


## Rebuild the static batch NOW, synchronously. Used when ONE prop's look changes (a tree felled
## to a stump, or regrown) so the swap is instant — otherwise the staged rebuild keeps the old
## full tree up for a few frames and you see it standing next to the falling copy. Meshes are
## cached and per-prop transforms are reused, so a single rebuild is cheap; fellings are rare.
func force_rebuild() -> void:
	_rb_active = false
	_start_staged_rebuild("force:%d" % int(world.entities.size()))
	var guard := 0
	while _rb_active and guard < 200000:
		_advance_staged_rebuild()
		guard += 1


## Snapshot the current static-prop set for a fresh staged rebuild.
func _start_staged_rebuild(sig: String) -> void:
	_rb_active = true
	_rb_phase = 0
	_rb_i = 0
	_rb_groups = {}
	_rb_xf = {}
	_rb_sig = sig
	_rb_list = []
	for d: Node in world._decor_nodes:
		_rb_list.append([0, d])
	for d: Node in world._water_decor_nodes:
		_rb_list.append([1, d])
	for e: Node in world.entities:
		if is_instance_valid(e) and not PropMeshes.is_moving(e):
			_rb_list.append([2, e])


func _advance_staged_rebuild() -> void:
	if _rb_phase == 0:
		# Collect a slice of props into groups. Cached transforms (the costly per-prop terrain
		# height sample) are reused for props that persisted from the last build.
		var processed := 0
		while _rb_i < _rb_list.size() and processed < RB_COLLECT_PER_FRAME:
			var item: Array = _rb_list[_rb_i]
			_rb_i += 1
			processed += 1
			var kind: int = item[0]
			var d = item[1]   # UNTYPED: nodes can be freed between snapshot and processing
			if not is_instance_valid(d):
				continue
			var id: int = d.get_instance_id()
			var pl: Transform3D = _batch_xf.get(id, _IDENTITY_XF)
			if kind == 0:
				if pl == _IDENTITY_XF:
					pl = Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.131), _iso_to_3d.call(d.position, _height.call(d.position)))
				_rb_xf[id] = pl
				_collect(PropMeshes.decor_parts(str(d.kind)), pl, _rb_groups)
			elif kind == 1:
				if pl == _IDENTITY_XF:
					pl = Transform3D(Basis(Vector3.UP, float(int(d.variant)) * 0.17), _iso_to_3d.call(d.position, _height.call(d.position) + 0.04))
				_rb_xf[id] = pl
				_collect(PropMeshes.water_decor_parts(str(d.kind)), pl, _rb_groups)
			else:
				var parts: Array = PropMeshes.entity_parts(d)
				if parts.is_empty():
					continue
				if pl == _IDENTITY_XF:
					# Most structures sit axis-aligned (yaw 0); bridge deck segments carry a yaw
					# so they lay along the path they were drawn over.
					var base_h: float = _height.call(d.position)
					var basis := Basis(Vector3.UP, float(d.yaw))
					if float(d.bridge_t) >= 0.0:
						# Bridge: height LERPS between the two solid-ground endpoints so the span
						# stays level and floats over the water/gap instead of sagging per-tile.
						var h_a: float = _height.call(d.bridge_a)
						var h_b: float = _height.call(d.bridge_b)
						base_h = lerpf(h_a, h_b, float(d.bridge_t))
						if str(d.kind) == "bridge_pole":
							# Piling: stretch the unit mesh (Y 0..-1) DOWN from the deck to the actual
							# terrain/water below this pole, so every pile reaches the ground.
							var ground: float = _height.call(d.position)
							var drop: float = maxf(0.2, base_h + float(d.height_offset) - ground)
							basis = Basis(Vector3.UP, float(d.yaw)).scaled(Vector3(1.0, drop, 1.0))
						else:
							# Orient the DECK along the straight 3D line A->B (yaw + pitch) so the
							# whole span is ONE clean ramp — no bends, no steps.
							var a3: Vector3 = _iso_to_3d.call(d.bridge_a, h_a)
							var b3: Vector3 = _iso_to_3d.call(d.bridge_b, h_b)
							var fwd: Vector3 = b3 - a3
							if fwd.length() > 0.001:
								fwd = fwd.normalized()
								var rx: Vector3 = Vector3.UP.cross(fwd)
								rx = rx.normalized() if rx.length() > 0.001 else Vector3.RIGHT
								basis = Basis(rx, fwd.cross(rx).normalized(), fwd)
					pl = Transform3D(basis, _iso_to_3d.call(d.position, base_h + float(d.height_offset)))
				_rb_xf[id] = pl
				_collect(parts, pl, _rb_groups)
		if _rb_i >= _rb_list.size():
			_rb_phase = 1
			_rb_keys = _rb_groups.keys()
			_rb_i = 0
			_rb_staging = Node3D.new()
			_rb_staging.visible = false         # hidden until fully built — old batch stays up
			batches_root.add_child(_rb_staging)
	else:
		# Emit into the hidden staging node, budgeted by INSTANCES so even one giant group
		# (e.g. all grass) fills across several frames instead of spiking a single frame.
		var budget := RB_EMIT_INSTANCES_PER_FRAME
		while budget > 0 and _rb_i < _rb_keys.size():
			if _rb_g.is_empty():
				_rb_g = _rb_groups[_rb_keys[_rb_i]]
				_rb_gbuf = PackedFloat32Array()
				_rb_gbuf.resize((_rb_g["xf"] as Array).size() * 12)
				_rb_gi = 0
			var xf: Array = _rb_g["xf"]
			while _rb_gi < xf.size() and budget > 0:
				var t: Transform3D = xf[_rb_gi]
				var b := t.basis
				var o := t.origin
				var j := _rb_gi * 12
				_rb_gbuf[j] = b.x.x;     _rb_gbuf[j + 1] = b.y.x;  _rb_gbuf[j + 2] = b.z.x;   _rb_gbuf[j + 3] = o.x
				_rb_gbuf[j + 4] = b.x.y; _rb_gbuf[j + 5] = b.y.y;  _rb_gbuf[j + 6] = b.z.y;   _rb_gbuf[j + 7] = o.y
				_rb_gbuf[j + 8] = b.x.z; _rb_gbuf[j + 9] = b.y.z;  _rb_gbuf[j + 10] = b.z.z;  _rb_gbuf[j + 11] = o.z
				_rb_gi += 1
				budget -= 1
			if _rb_gi >= xf.size():
				_finish_group_mmi(_rb_g, _rb_gbuf, _rb_staging)
				_rb_g = {}
				_rb_i += 1
		if _rb_i >= _rb_keys.size() and _rb_g.is_empty():
			# Done: reveal the new batch and drop the old one (hide first to avoid a 1-frame
			# double-draw while queue_free is deferred).
			for c: Node in batches_root.get_children():
				if c != _rb_staging:
					(c as Node3D).visible = false
					c.queue_free()
			_rb_staging.visible = true
			_batch_xf = _rb_xf
			_static_sig = _rb_sig
			_rb_active = false
			_rb_groups = {}
			_rb_list = []
			_rb_keys = []
			_rb_staging = null
			_rb_gbuf = PackedFloat32Array()


## Create a MultiMeshInstance3D for a group from a pre-filled transform buffer.
func _finish_group_mmi(g: Dictionary, buf: PackedFloat32Array, root: Node3D) -> void:
	var n := (g["xf"] as Array).size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = g["mesh"]
	mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = g["mat"]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi)


func _collect(parts: Array, placement: Transform3D, groups: Dictionary) -> void:
	for p: Dictionary in parts:
		var key := str(p["mesh"].get_instance_id()) + "|" + str(p["mat"].get_instance_id())
		if not groups.has(key):
			groups[key] = {"mesh": p["mesh"], "mat": p["mat"], "xf": []}
		var local := Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		groups[key]["xf"].append(placement * local)
