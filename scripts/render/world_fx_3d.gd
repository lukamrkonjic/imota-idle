extends RefCounted
class_name WorldFx3D
## World FX: the firemaking campfire (build/flicker/feed/decay) and prayer-activation bursts.
## A stateful collaborator of WorldRender3D (passed as `_ctx` for iso_to_3d/height_at/
## props_root/cam/world/_player_node). Listens to EventBus itself; the render node just calls
## update(delta) each frame after the movers sync. Extracted from the render monolith.

var _ctx                              # WorldRender3D (extends Node; untyped for its custom API)
var _fire: Node3D
var _fire_flames: Node3D
var _fire_phase := ""
var _fire_t := 0.0
var _fire_decay := 0.0
var _fire_flare := 0.0
var _kneel_t := 0.0
var _fx_bursts: Array = []


func setup(ctx) -> void:
	_ctx = ctx
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.activity_stopped.connect(_on_activity_stopped)
	EventBus.prayer_activated.connect(_on_prayer_activated)
	EventBus.firemaking_log_burned.connect(_on_firemaking_burned)


func _on_activity_started(kind: String, detail: String) -> void:
	if kind == "craft" and detail.begins_with("Firemaking"):
		_light_fire()


func _on_activity_stopped(_reason: String) -> void:
	# Player stopped feeding logs — let the fire burn down to embers and vanish.
	if _fire != null and _fire_phase == "burn":
		_fire_phase = "decay"
		_fire_decay = 0.0


func _light_fire() -> void:
	if _fire == null or not is_instance_valid(_fire):
		_fire = _build_campfire()
		_fire.position = _fire_spot()
		_ctx.props_root.add_child(_fire)
		_fire_flames = _fire.get_node_or_null("flames")
	_fire_phase = "burn"   # resumes if it was decaying


## Ground spot a short step IN FRONT of the player (toward the camera, so it reads as set
## down before them rather than under their feet).
func _fire_spot() -> Vector3:
	var ppos: Vector3 = _ctx.iso_to_3d(_ctx.world.player.position, _ctx.height_at(_ctx.world.player.position))
	var fwd: Vector3 = _ctx.cam.global_position - ppos
	fwd.y = 0.0
	if fwd.length() > 0.01:
		ppos += fwd.normalized() * 1.1
	return ppos


## A small campfire: a ring of stones, charred logs, and emissive flames (self-lit — no
## dynamic light, which washed out the toon-shaded world). The "flames" child is animated.
func _build_campfire() -> Node3D:
	var node := Node3D.new()
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.46, 0.46, 0.50)
	for i: int in 7:
		var a := TAU * float(i) / 7.0
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.22
		s.mesh = sm
		s.material_override = stone_mat
		s.position = Vector3(cos(a) * 0.36, 0.06, sin(a) * 0.36)
		s.scale = Vector3(1.0, 0.7, 1.0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(s)
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.22, 0.14, 0.09)
	for j: int in 2:
		var lg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.05
		lm.bottom_radius = 0.05
		lm.height = 0.5
		lg.mesh = lm
		lg.material_override = log_mat
		lg.position = Vector3(0.0, 0.06, 0.0)
		lg.rotation = Vector3(PI / 2.0, float(j) * 1.4, 0.0)
		lg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lg)
	var flames := Node3D.new()
	flames.name = "flames"
	for f: Array in [[0.0, 0.55, Color(1.0, 0.5, 0.14)], [0.07, 0.4, Color(1.0, 0.82, 0.3)]]:
		var fm := CylinderMesh.new()
		fm.top_radius = 0.005
		fm.bottom_radius = 0.16 - float(f[0])
		fm.height = float(f[1])
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = f[2]
		fmat.emission_enabled = true
		fmat.emission = f[2]
		fmat.emission_energy_multiplier = 2.6
		var fi := MeshInstance3D.new()
		fi.mesh = fm
		fi.material_override = fmat
		fi.position = Vector3(float(f[0]), 0.12 + float(f[1]) * 0.5, 0.0)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.add_child(fi)
	node.add_child(flames)
	return node


## Player feeds a log: kneel-crouch + a log tossed into the fire + a flame flare.
func _on_firemaking_burned() -> void:
	if _fire == null or not is_instance_valid(_fire):
		return
	_fire_flare = 0.5
	_kneel_t = 0.5
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.34, 0.22, 0.12)
	var lm := CylinderMesh.new()
	lm.top_radius = 0.05
	lm.bottom_radius = 0.05
	lm.height = 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = lm
	mi.material_override = log_mat
	mi.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node := Node3D.new()
	node.add_child(mi)
	var from: Vector3 = _ctx.iso_to_3d(_ctx.world.player.position, _ctx.height_at(_ctx.world.player.position) + 0.7)
	_ctx.props_root.add_child(node)
	node.position = from
	_fx_bursts.append({"node": node, "t": 0.0, "dur": 0.4, "kind": "log",
		"from": from, "to": _fire.position + Vector3(0.0, 0.2, 0.0)})


func _on_prayer_activated(prayer_name: String) -> void:
	if _ctx.world.player == null:
		return
	var col := _prayer_color(prayer_name)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node := Node3D.new()
	node.add_child(mi)
	node.position = _ctx.iso_to_3d(_ctx.world.player.position, _ctx.height_at(_ctx.world.player.position) + 1.2)
	_ctx.props_root.add_child(node)
	_fx_bursts.append({"node": node, "mat": mat, "t": 0.0, "dur": 0.8, "kind": "burst"})


func update(delta: float) -> void:
	_fire_flare = maxf(_fire_flare - delta, 0.0)
	if _fire != null and is_instance_valid(_fire):
		_fire_t += delta
		var flare := 1.0 + _fire_flare * 1.2
		if _fire_phase == "burn" and _fire_flames != null:
			var f := PixelAnim.flicker(_fire_t, 11.0, 0.12, 23.0, 0.06) * flare
			_fire_flames.scale = Vector3(1.0, f, 1.0)
		elif _fire_phase == "decay":
			_fire_decay += delta
			var k := clampf(1.0 - _fire_decay / 5.0, 0.0, 1.0)   # embers over ~5s
			if _fire_flames != null:
				_fire_flames.scale = Vector3(k, k, k)
			if _fire_decay >= 5.0:
				_fire.queue_free()
				_fire = null
				_fire_flames = null
				_fire_phase = ""
	# Kneel-to-feed: briefly lower the player rig (re-applied each frame after _sync_movers).
	if _kneel_t > 0.0 and _ctx._player_node != null:
		_kneel_t = maxf(_kneel_t - delta, 0.0)
		_ctx._player_node.position.y -= 0.22
	for i: int in range(_fx_bursts.size() - 1, -1, -1):
		var b: Dictionary = _fx_bursts[i]
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			_fx_bursts.remove_at(i)
			continue
		b["t"] += delta
		var p: float = clampf(b["t"] / float(b["dur"]), 0.0, 1.0)
		if str(b.get("kind", "burst")) == "log":
			# Arc the log from the player into the fire.
			var from: Vector3 = b["from"]
			var to: Vector3 = b["to"]
			node.position = from.lerp(to, p) + Vector3(0.0, sin(p * PI) * 0.6, 0.0)
			node.rotate_x(delta * 8.0)
		else:
			node.scale = Vector3.ONE * (0.4 + p * 1.4)
			node.position.y += delta * 1.1
			(b["mat"] as StandardMaterial3D).albedo_color.a = (1.0 - p) * 0.85
		if p >= 1.0:
			node.queue_free()
			_fx_bursts.remove_at(i)



func _prayer_color(prayer_name: String) -> Color:
	var group := str(DataRegistry.prayers.get(prayer_name, {}).get("group", ""))
	var base: Color
	match group:
		"defence": base = Color(0.40, 0.62, 1.0)
		"damage": base = Color(1.0, 0.42, 0.20)
		"accuracy": base = Color(1.0, 0.88, 0.30)
		"protect": base = Color(0.72, 0.42, 1.0)
		_: base = Color(0.75, 1.0, 0.78)
	var h := float(absi(hash(prayer_name)) % 1000) / 1000.0
	return base.lerp(Color.from_hsv(h, 0.5, 1.0), 0.18)
