extends RefCounted
class_name MoverRenderer3D
## Renders the moving entities — player + enemies — as individual animated rigs (extracted from
## the WorldRender3D monolith): A Short Hike-style gait/turn-spring/squash, combat attack lunges,
## take-a-hit red flash + shake, death topples, blob shadows, the player's worn equipment, and
## the silhouette OUTLINES for highlighted/hovered entities. Also exposes mover projection data
## (lift / head-top / base scale) the screen-space combat UI needs.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const EquipLoadout := preload("res://scripts/render/equip_loadout.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

# Turn spring: a body accelerates into a turn and damps out of it (slightly underdamped for a
# snappy-but-physical settle), so facing changes are never instant.
const TURN_STIFFNESS := 62.0
const TURN_DAMPING := 14.0
const HURT_DUR := 0.2               # how long the take-a-hit red flash + shake lasts
const ATTACK_DUR := 0.42            # seconds one swing lunge plays over
const CHOP_RATE := 1.3              # woodcutting swings/sec — continuous overhead axe chop
const DEATH_DUR := 0.65             # seconds a death topple settles over
const BAR_CLEARANCE := 0.30         # constant world-unit gap a floating HP bar sits above every head

var world: Node2D
var props_root: Node3D
var _outlines_root: Node3D
var _height: Callable        # height_at(iso: Vector2) -> float
var _iso_to_3d: Callable     # iso_to_3d(iso: Vector2, y: float) -> Vector3
var _sun: DirectionalLight3D

var editor_hide_player := false

var _player_node: Node3D
var _chopping := false                # player is mid-woodcutting (drives the chop swing + axe-in-hand)
var _mover_nodes: Dictionary = {}    # moving entity id -> Node3D (player/enemies)
var _mover_prev: Dictionary = {}     # key -> last 3D pos (for walk detection)
var _mover_yaw: Dictionary = {}      # key -> facing yaw (turned with spring inertia)
var _mover_yaw_vel: Dictionary = {}  # key -> angular velocity for the turn spring
var _mover_walk: Dictionary = {}     # key -> smoothed walk amount 0..1
var _mover_sit: Dictionary = {}      # key -> smoothed sit amount 0..1 (player resting)
var _attack_t: Dictionary = {}       # key -> time (s) the last attack lunge started
var _hurt_t: Dictionary = {}         # key -> time (s) a body last took a hit (red flash + shake)
var _mover_death: Dictionary = {}    # key -> {t0, pos} while a defeated mover plays its death topple
var _shadow_nodes: Dictionary = {}   # key -> blob-shadow MeshInstance3D pinned to ground
var _outline_mat: ShaderMaterial     # shared white outline material (grown hull, cull_front)
var _outline_nodes: Dictionary = {}  # static entity id -> outline Node3D
var _outlined_movers: Dictionary = {} # mover id -> true (material_overlay applied)


func setup(w: Node2D, props: Node3D, outlines_root: Node3D, height_provider: Callable, iso_to_3d_provider: Callable, sun_provider: Callable) -> void:
	world = w
	props_root = props
	_outlines_root = outlines_root
	_height = height_provider
	_iso_to_3d = iso_to_3d_provider
	_sun = sun_provider.call()
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("outline_color", Color(1.0, 1.0, 1.0, 1.0))
	_outline_mat.set_shader_parameter("width", 0.045)
	# Drive attack lunges off the combat ticks: each hit splat is one swing landing.
	EventBus.combat_hit_splat.connect(_on_combat_swing)
	EventBus.combat_ranged_shot.connect(func(_a: int, _m: bool) -> void: _mark_attack("player"))


func set_editor_hide_player(v: bool) -> void:
	editor_hide_player = v


## Movers (player + enemies) stay individual nodes — few of them, and they move.
func update(delta: float) -> void:
	var dt := delta
	var t := Time.get_ticks_msec() / 1000.0
	if editor_hide_player:
		if _player_node != null:
			_player_node.visible = false
			var psh: Node3D = _shadow_nodes.get("player")
			if psh != null:
				psh.visible = false
	else:
		if _player_node == null:
			_player_node = PropMeshes.player_rig(PixelPalette.pal("skin_a"))
			_prep_mover(_player_node, "player")
			_apply_player_equipment()
			EventBus.equipment_changed.connect(_apply_player_equipment)
		_refresh_chop_weapon()
		_animate_mover(_player_node, "player", world.player.position, t, dt)
	var live := {}
	for e: Node in world.entities:
		if not is_instance_valid(e) or not PropMeshes.is_moving(e):
			continue
		var id := e.get_instance_id()
		live[id] = true
		var n: Node3D = _mover_nodes.get(id)
		if n == null:
			n = PropMeshes.enemy_rig(e)
			_prep_mover(n, str(id))
			_mover_nodes[id] = n
		# A defeated enemy (dimmed) plays its death topple instead of the normal gait.
		_animate_mover(n, str(id), e.position, t, dt, bool(e.get("dimmed")))
	for id: int in _mover_nodes.keys():
		if not live.has(id):
			var n: Node = _mover_nodes[id]
			if is_instance_valid(n):
				n.queue_free()
			_mover_nodes.erase(id)
			_mover_prev.erase(id); _mover_yaw.erase(id); _mover_yaw_vel.erase(id); _mover_walk.erase(id)
			_mover_death.erase(str(id)); _hurt_t.erase(str(id))
			_free_shadow(str(id))


## Add a mover rig to the scene, drop a blob shadow under it, and turn off its
## real cast shadow (the blob replaces it for the clean A Short Hike look).
func _prep_mover(node: Node3D, key: String) -> void:
	props_root.add_child(node)
	_disable_cast_shadows(node)
	# Measure the rig's true head height ONCE here, in its built rest pose (before any gait
	# animation), so floating HP bars sit a consistent distance above every body.
	node.set_meta("rig_top_y", _rig_top_y(node))
	var shadow := PropMeshes.blob_shadow()
	props_root.add_child(shadow)
	_shadow_nodes[key] = shadow


## (Re)build the player's visible gear from GameState.equipment — on spawn and
## whenever equipment changes.
func _apply_player_equipment(_a := "", _b := "") -> void:
	if _player_node == null:
		return
	var loadout := EquipLoadout.for_player(GameState.equipment)
	PropMeshes.apply_equipment(_player_node, loadout)
	# Grip a planted staff when one is wielded (else stand normally).
	var mainhand: Dictionary = loadout.get("mainhand", {})
	_player_node.set_meta("pose", "staff" if str(mainhand.get("kind", "")) in ["staff", "raven_staff", "wand"] else "")
	_disable_cast_shadows(_player_node)


## The player is mid-woodcutting. (An axe is required to start a chop, so this also implies one
## is equipped.) Drives the continuous chop swing + the axe-in-hand swap.
func _is_chopping() -> bool:
	return TickSim.active and TickSim.skill == "woodcutting"


## While chopping, show the equipped AXE in hand (not the player's sword/staff); restore the
## normal loadout when they stop. Only re-applies on the start/stop transition.
func _refresh_chop_weapon() -> void:
	if _player_node == null:
		return
	var now := _is_chopping()
	if now == _chopping:
		return
	_chopping = now
	if now:
		var axe := _axe_loadout()
		if not axe.is_empty():
			PropMeshes.apply_equipment(_player_node, axe)
			_disable_cast_shadows(_player_node)
			return
	_apply_player_equipment()   # stopped chopping (or no axe slot) -> back to normal gear


## The player's loadout with the mainhand forced to the equipped axe (its own tier/material).
func _axe_loadout() -> Dictionary:
	var axe_id := str(GameState.equipment.get("Axe", ""))
	if axe_id.is_empty():
		return {}
	var ld := EquipLoadout.for_player(GameState.equipment)
	var def = DataRegistry.item_def(axe_id)
	ld["mainhand"] = {"kind": "axe", "material": EquipLoadout._material(def, DataRegistry.item_display_name(axe_id))}
	return ld


func _disable_cast_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c: Node in node.get_children():
		_disable_cast_shadows(c)


func _free_shadow(key: String) -> void:
	var s: Node = _shadow_nodes.get(key)
	if is_instance_valid(s):
		s.queue_free()
	_shadow_nodes.erase(key)


## A Short Hike-style walk feel: gentle bob + squash-stretch while moving, body turns to face
## travel. The pose itself is per body template (humanoid stride, quadruped trot, bird waddle).
func _animate_mover(node: Node3D, key: String, pos2d: Vector2, t: float, dt: float, dying := false) -> void:
	var pos3: Vector3 = _iso_to_3d.call(pos2d, _height.call(pos2d))
	var btype0 := str(node.get_meta("body3d", "humanoid"))
	# A defeated enemy topples and settles where it fell (its own death per body type),
	# then holds until it respawns; skip the normal gait + the drift-home slide.
	if dying:
		_death_anim(node, key, pos3, t, float(node.get_meta("base_scale", 1.0)), btype0)
		return
	if _mover_death.has(key):
		_mover_death.erase(key)            # respawned — clear so it stands back up
		_mover_prev[key] = pos3            # don't read the death->home jump as a walk
	var prev: Vector3 = _mover_prev.get(key, pos3)
	var vel := pos3 - prev
	_mover_prev[key] = pos3
	var speed := vel.length() / maxf(dt, 0.0001)
	var target_walk := clampf(speed / 3.0, 0.0, 1.0)
	var walk: float = lerpf(float(_mover_walk.get(key, 0.0)), target_walk, clampf(dt * 10.0, 0.0, 1.0))
	_mover_walk[key] = walk
	# Desired heading: face where you're moving; in a fight the foe's bearing wins.
	var yaw: float = float(_mover_yaw.get(key, 0.0))
	var moving := speed > 0.35
	var desired := yaw
	var want := false
	if moving:
		# The PLAYER faces its STABLE walk target (the waypoint it's heading to) rather than the
		# instantaneous velocity, so a single-frame path snap at the start of a walk can't read as
		# a backward step and spin the body 180°. Other movers face their travel direction.
		if key == "player" and world.player.walking:
			var wt: Vector3 = _iso_to_3d.call(world.player.walk_target, 0.0)
			var dv := Vector2(wt.x - pos3.x, wt.z - pos3.z)
			if dv.length() > 0.06:
				desired = atan2(dv.x, dv.y)
				want = true
		else:
			desired = atan2(vel.x, vel.z)
			want = true
	# Woodcutting: square up to the tree being chopped, so the player always faces it.
	if key == "player" and _chopping and not world.gather_ref.is_empty():
		var te: Object = world.gather_ref.get("entity")
		if is_instance_valid(te):
			var t3: Vector3 = _iso_to_3d.call((te as Node2D).position, 0.0)
			desired = atan2(t3.x - pos3.x, t3.z - pos3.z)
			want = true
	var face: Variant = _combat_face_pos(key, moving)
	if face != null:
		var f3: Vector3 = _iso_to_3d.call(face, 0.0)
		desired = atan2(f3.x - pos3.x, f3.z - pos3.z)
		want = true
	if want:
		var sdt := minf(dt, 0.04)                 # clamp so a frame spike can't blow up the spring
		var yvel: float = float(_mover_yaw_vel.get(key, 0.0))
		var diff := wrapf(desired - yaw, -PI, PI)
		yvel += (diff * TURN_STIFFNESS - yvel * TURN_DAMPING) * sdt
		yaw = wrapf(yaw + yvel * sdt, -PI, PI)
		_mover_yaw_vel[key] = yvel
		_mover_yaw[key] = yaw
	var phase := float(absi(hash(key)) % 1000) * 0.006283
	var base: float = float(node.get_meta("base_scale", 1.0))
	var atk := _attack_progress(key, t)
	# Woodcutting: a continuous overhead axe chop (the pose's atk drive already swings the lead
	# arm overarm), so the player visibly hacks at the tree while the gather ticks run.
	if key == "player" and _chopping:
		atk = fmod(t * CHOP_RATE, 1.0)
	var btype := str(node.get_meta("body3d", "humanoid"))
	match btype:
		"bird":
			MoverRig._pose_bird(node, pos3, yaw, walk, t, phase, base, atk)
		"humanoid":
			# Goblins and gnolls get their own lore-flavoured gaits; everyone else
			# (player, skeletons, generic humanoids) uses the upright human pose.
			match str(node.get_meta("gait", "")):
				"goblin":
					MoverRig._pose_goblin(node, pos3, yaw, walk, t, phase, base, atk)
				"gnoll":
					MoverRig._pose_gnoll(node, pos3, yaw, walk, t, phase, base, atk)
				_:
					MoverRig._pose_humanoid(node, pos3, yaw, walk, t, phase, base, atk)
		_:
			MoverRig._pose_quadruped(node, pos3, yaw, walk, t, phase, base, atk)
	# Resting: the player folds down to sit on the ground (right-click the run orb).
	var sit_target := 1.0 if (key == "player" and GameState.resting and not moving) else 0.0
	var sit: float = lerpf(float(_mover_sit.get(key, 0.0)), sit_target, clampf(dt * 7.0, 0.0, 1.0))
	_mover_sit[key] = sit
	MoverRig.pose_sit(node, sit, base)
	# A swing steps the body into the target — the lunge that sells the hit.
	if atk > 0.0:
		node.position += Vector3(sin(yaw), 0.0, cos(yaw)) * (sin(atk * PI) * 0.22)
	# Pin the blob shadow to the ground under the mover, oriented with the body, sized to its
	# footprint, and pushed in the direction the sunlight travels so it falls down-light.
	var shadow: Node3D = _shadow_nodes.get(key)
	if shadow != null:
		var off := _shadow_push() * base
		shadow.position = Vector3(pos3.x + off.x, pos3.y + 0.04, pos3.z + off.y)
		shadow.rotation.y = yaw
		var fp := _shadow_footprint(btype)
		shadow.scale = Vector3(fp.x * base * 1.12, 1.0, fp.y * base * 1.12)
	MoverRig._flow_cloth(node, walk, t, phase)
	MoverRig._sway_hair(node, walk, t, phase)
	_apply_hurt(node, key, t, base)


## Death topple: a defeated mover crumples where it fell and settles to the ground over
## DEATH_DUR, then holds the corpse pose until it respawns. Flavoured per enemy type.
func _death_anim(node: Node3D, key: String, pos3: Vector3, t: float, base: float, btype: String) -> void:
	var d: Dictionary = _mover_death.get(key, {})
	if d.is_empty():
		d = {"t0": t, "pos": pos3}                       # freeze where it died
		_mover_death[key] = d
	var raw := clampf((t - float(d["t0"])) / DEATH_DUR, 0.0, 1.0)
	var p := ease(raw, 0.35)                              # quick drop, then settle
	var dpos: Vector3 = d["pos"]
	var yaw := float(_mover_yaw.get(key, 0.0))
	var fall := p * 1.5
	var tilt := 0.0
	var roll := 0.0
	match btype:
		"bird":
			roll = fall                                  # flops onto its side, legs up
		"humanoid":
			match str(node.get_meta("gait", "")):
				"goblin":
					tilt = fall                          # crumples forward (faceplant)
				"gnoll":
					tilt = -fall * 1.05                  # heavy backward topple
				_:
					tilt = -fall                         # falls onto its back
		_:
			roll = fall                                  # quadruped collapses sideways
	# Limbs relax out of their gait into a loose sprawl as it goes limp.
	for pv: String in ["leg_l", "leg_r", "arm_l", "arm_r"]:
		MoverRig._set_pivot(node, pv, lerpf(0.0, 0.25, p))
	var spine: Node3D = MoverRig._pivot(node, "spine")
	if spine != null:
		spine.rotation = spine.rotation.lerp(Vector3.ZERO, clampf(p, 0.0, 1.0))
	node.rotation = Vector3(tilt, yaw, roll)
	node.position = dpos + Vector3(0, 0.04 - p * 0.06 * base, 0)
	node.scale = Vector3(base, base, base)
	# The blob shadow sinks and shrinks away under the corpse.
	var shadow: Node3D = _shadow_nodes.get(key)
	if shadow != null:
		var fp := _shadow_footprint(btype)
		var ss := base * (1.0 - 0.55 * p)
		shadow.position = Vector3(dpos.x, dpos.y + 0.04, dpos.z)
		shadow.rotation.y = yaw
		shadow.scale = Vector3(fp.x * ss, 1.0, fp.y * ss)
	_apply_hurt(node, key, t, base)   # the killing blow's red flash carries into the topple


## Take-a-hit feedback: a subtle red wash (per-instance shader flash) plus a tiny positional
## shake on the struck body, decaying over HURT_DUR. Adds to whatever the pose set.
func _apply_hurt(node: Node3D, key: String, t: float, base: float) -> void:
	if not _hurt_t.has(key):
		return
	var p := clampf(1.0 - (t - float(_hurt_t[key])) / HURT_DUR, 0.0, 1.0)
	if p <= 0.0:
		_set_hurt_flash(node, 0.0)   # one final clear, then stop touching it
		_hurt_t.erase(key)
		return
	_set_hurt_flash(node, p * 0.35)  # subtle: a brief light-red wash that fades out
	var sh := p * 0.03 * base        # small jitter, scaled to body size
	node.position += Vector3(sin(t * 94.0) * sh, 0.0, cos(t * 86.0) * sh)


## Push the per-instance `hurt` flash onto every toon mesh under the rig.
func _set_hurt_flash(node: Node, v: float) -> void:
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).set_instance_shader_parameter(&"hurt", v)
		if c.get_child_count() > 0:
			_set_hurt_flash(c, v)


## Ground-plane (x,z) offset a blob shadow is pushed, matching the direction the sunlight
## travels — so shadows fall away from the sun (down-left on screen).
func _shadow_push() -> Vector2:
	if _sun == null:
		return Vector2(0.32, 0.18)
	var travel := -_sun.global_transform.basis.z   # light shines along -Z of its basis
	var h := Vector2(travel.x, travel.z)
	if h.length() < 0.001:
		return Vector2(0.32, 0.18)
	return h.normalized() * 0.42


## Footprint (x = width, y = length-along-Z) of the blob shadow per body type.
func _shadow_footprint(btype: String) -> Vector2:
	match btype:
		"bird":
			return Vector2(0.58, 0.64)
		"humanoid":
			return Vector2(0.78, 0.86)
		_:
			return Vector2(1.05, 1.62)  # four-legged: a longer oval along the spine


## A hit splat means a swing just landed: lunge the attacker. on_player = the enemy hit us.
func _on_combat_swing(_amount: int, miss: bool, on_player: bool) -> void:
	var tgt: Node = world.combat_target_entity
	if on_player:
		# The enemy swung at the player: enemy lunges, and the PLAYER took the hit.
		if is_instance_valid(tgt):
			_mark_attack(str(tgt.get_instance_id()))
		if not miss:
			_mark_hurt("player")
	else:
		# The player swung at the enemy: player lunges, the ENEMY took the hit.
		_mark_attack("player")
		if not miss and is_instance_valid(tgt):
			_mark_hurt(str(tgt.get_instance_id()))


func _mark_attack(key: String) -> void:
	_attack_t[key] = Time.get_ticks_msec() / 1000.0


## Flag a body as just-hit so it flashes red and shakes for HURT_DUR.
func _mark_hurt(key: String) -> void:
	_hurt_t[key] = Time.get_ticks_msec() / 1000.0


func _attack_progress(key: String, t: float) -> float:
	var p := (t - float(_attack_t.get(key, -99.0))) / ATTACK_DUR
	return p if p >= 0.0 and p <= 1.0 else 0.0


## The iso position a mover should face mid-fight, or null when not in combat.
func _combat_face_pos(key: String, moving: bool) -> Variant:
	if not CombatSim.active:
		return null
	var tgt: Node = world.combat_target_entity
	if not is_instance_valid(tgt):
		return null
	if key == "player":
		# Square up to the foe only while holding position — if we're walking/running
		# (away or anywhere) face the travel direction instead of the enemy.
		return null if moving else tgt.position
	if key == str(tgt.get_instance_id()):
		return world.player.position
	return null


# --------------------------------------------------------------------- outlines ----

## White contour outlines for entities flagged highlight_outline (Alt-hold) or hovered. Enemies
## (movers) get a material_overlay on their rig; static interactables get a parts-built inverted-
## hull node. Pooled by entity id and rebuilt only when the highlighted set changes.
func update_outlines() -> void:
	var want := {}
	for e: Node2D in world.entities:
		if is_instance_valid(e) and (e.highlight_outline or e.hovered):
			want[e.get_instance_id()] = e
	for id: int in _outline_nodes.keys():
		if not want.has(id):
			_outline_nodes[id].queue_free()
			_outline_nodes.erase(id)
	for id: int in _outlined_movers.keys():
		if not want.has(id):
			var rig: Node3D = _mover_nodes.get(id)
			if rig != null:
				_set_rig_outline(rig, false)
			_outlined_movers.erase(id)
	for id: int in want:
		var e: Node2D = want[id]
		if PropMeshes.is_moving(e):
			var rig: Node3D = _mover_nodes.get(id)
			if rig != null and not _outlined_movers.has(id):
				_set_rig_outline(rig, true)
				_outlined_movers[id] = true
		else:
			var node: Node3D = _outline_nodes.get(id)
			if node == null:
				node = _build_outline_node(e)
				if node == null:
					continue
				_outlines_root.add_child(node)
				_outline_nodes[id] = node
			node.transform = Transform3D(Basis.IDENTITY, _iso_to_3d.call(e.position, _height.call(e.position)))


func _build_outline_node(e: Node2D) -> Node3D:
	var parts: Array = PropMeshes.entity_parts(e)
	if parts.is_empty():
		return null
	var node := Node3D.new()
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = _outline_mat
		mi.transform = Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	return node


func _set_rig_outline(rig: Node3D, on: bool) -> void:
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_overlay = _outline_mat if on else null
		for c: Node in n.get_children():
			stack.append(c)


# ----------------------------------------------------------------- projection API ----

func get_player_node() -> Node3D:
	return _player_node


func get_mover_node(entity: Node) -> Node3D:
	return _mover_nodes.get(entity.get_instance_id())


## World-Y to anchor a hitsplat at, scaled to the mover's size so the splat sits ON the body.
func mover_lift(entity: Node) -> float:
	if entity == world.player and _player_node != null:
		return float(_player_node.get_meta("base_scale", 1.0)) * 1.0
	var n: Node3D = _mover_nodes.get(entity.get_instance_id())
	if n != null:
		return float(n.get_meta("base_scale", 1.0)) * 0.95
	return 0.95


## World-Y just above the model's head for floating UI (HP bars). Uses the rig's MEASURED top
## scaled by its size, plus one constant clearance — identical gap for every entity.
func mover_top(entity: Node) -> float:
	var n: Node3D = _player_node if entity == world.player else _mover_nodes.get(entity.get_instance_id())
	if n == null:
		return 2.4
	var base := float(n.get_meta("base_scale", 1.0))
	var top_local := float(n.get_meta("rig_top_y", 2.0))
	return base * top_local + BAR_CLEARANCE


## Highest point of a mover rig in its OWN local space (feet ~ y 0), measured from the mesh
## AABBs so floating UI clears the ACTUAL head. Held weapons (socket subtrees) are skipped.
func _rig_top_y(root: Node3D) -> float:
	var top := _accumulate_top_y(root, Transform3D.IDENTITY, -1.0e9)
	return top if top > 0.01 else 2.0


func _accumulate_top_y(node: Node, xform: Transform3D, best: float) -> float:
	for child: Node in node.get_children():
		if not (child is Node3D):
			continue
		var nm := String(child.name)
		if nm.contains("socket_mainhand") or nm.contains("socket_offhand"):
			continue   # held weapon/tool — tracks the body, not the staff tip
		var cx: Transform3D = xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var ab: AABB = (child as MeshInstance3D).mesh.get_aabb()
			for i in 8:
				var corner: Vector3 = cx * (ab.position + Vector3(
					ab.size.x if (i & 1) != 0 else 0.0,
					ab.size.y if (i & 2) != 0 else 0.0,
					ab.size.z if (i & 4) != 0 else 0.0))
				best = maxf(best, corner.y)
		best = _accumulate_top_y(child, cx, best)
	return best
