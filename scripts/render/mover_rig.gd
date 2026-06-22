extends RefCounted
class_name MoverRig
## Procedural character rig: the per-frame poses (humanoid/goblin/gnoll/quadruped/bird),
## secondary motion (hair sway, cloth/cape flow), and the cached pivot resolver. Pure/static
## — every input is a param, no render state — so the orchestrator (`_animate_mover` in
## world_render_3d) just calls MoverRig._pose_*(...) etc. Extracted from the render monolith.

## Cheap "hair physics": any hair/beard/mane/tuft pivot on a rig gets a soft sway —
## bouncing and leaning back as the character moves, drifting on a light idle wind.
## Pure procedural (a rotation per pivot), no real physics. Rigs opt in by parenting
## their soft bits under a pivot named hair/beard/mane/tuft.
static func _sway_hair(node: Node3D, walk: float, t: float, phase: float) -> void:
	for hp: String in ["hair", "beard", "mane"]:
		var p: Node3D = node.get_node_or_null(NodePath(hp))
		if p == null:
			p = _pivot(node, hp)
		if p == null:
			continue
		var amp := 0.5 + walk * 1.4
		p.rotation = Vector3(
			-walk * 0.16 + sin(t * 5.2 + phase) * 0.05 * amp,   # lift/lean back when moving
			sin(t * 3.4 + phase) * 0.03 * amp,
			sin(t * 2.7 + phase * 1.4) * 0.04 * amp)


## Cheap cloth "sim" for worn robes/capes: pure procedural secondary motion — no
## physics, no per-vertex work. The skirt (socket_legs) and cape (socket_back)
## pivot at the waist/shoulders, trailing back as you move and rippling on a soft
## wind oscillation, so robes flow instead of standing rigid.
static func _flow_cloth(node: Node3D, walk: float, t: float, phase: float) -> void:
	for sock_name: String in ["socket_legs", "socket_back"]:
		var sock: Node = node.get_node_or_null(NodePath(sock_name))
		if sock == null:
			sock = _pivot(node, sock_name)
		if sock == null:
			continue
		var eq: Node3D = sock.get_node_or_null(^"equip")
		if eq == null or not bool(eq.get_meta("cloth", false)):
			continue
		if int(eq.get_meta("cape_segments", 0)) > 0:
			_flow_cape(eq, walk, t, phase)
			continue
		var amp := 0.45 + walk * 1.7
		eq.rotation = Vector3(
			-walk * 0.24 + sin(t * 4.2 + phase) * 0.07 * amp,
			sin(t * 3.1 + phase) * 0.04 * amp,
			sin(t * 2.6 + phase * 1.7) * 0.06 * amp)


## A fixed per-link drape curve (radians of backward tilt added at each link). It
## stays near-vertical down the back, then folds toward horizontal at the hem, so
## the chain falls under "gravity" to the floor and the last links POOL/drag behind
## the heels — a long, heavy, majestic cape rather than a stiff board.
const CAPE_DRAPE := [0.03, 0.05, 0.08, 0.13, 0.42, 0.82]

## Cheap cape "cloth sim": hold the drape curve (so the cape hangs down and drags on
## the ground), then add only a slow, low-amplitude undulation rolled down the chain
## — a heavy fabric sway, never an upward billow. ~12 sin() calls, no physics.
static func _flow_cape(eq: Node3D, walk: float, t: float, phase: float) -> void:
	var amp := 0.02 + walk * 0.06         # small: heavy cloth barely lifts when moving
	var seg: Node3D = eq.get_node_or_null(^"cape_seg0")
	var d := 0
	while seg != null:
		var base_x: float = CAPE_DRAPE[d] if d < CAPE_DRAPE.size() else 0.12
		var lag := float(d) * 0.55
		# Gentle ripple (kept below the drape so it undulates without lifting), plus a
		# slow side-to-side sway that grows a touch toward the trailing hem.
		var ripple := sin(t * 1.7 + phase - lag) * amp
		var sway := sin(t * 1.25 + phase * 1.2 - lag) * amp * (1.0 + 0.3 * float(d))
		seg.rotation = Vector3(base_x + maxf(ripple, -base_x * 0.5), 0.0, sway)
		seg = seg.get_node_or_null(NodePath("cape_seg%d" % (d + 1)))
		d += 1



## Jointed biped: knees and elbows flex for a natural bent-leg walk, and a `crouch`
## meta gives a bent-kneed standing stance (goblins stoop, the gnoll sneaks low).
## `lean` hunches the body, `arm_rest` keeps arms a touch forward (never ramrod).
static func _pose_humanoid(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var lean: float = float(node.get_meta("lean", 0.04))
	# `hunch` curves the upper back forward at the spine pivot (an old-lady stoop) —
	# legs/hips stay vertical, so it reads as a natural bent back, NOT a whole-body
	# forward lean (the Michael-Jackson tilt we want to avoid).
	var hunch: float = float(node.get_meta("hunch", 0.0))
	var arm_rest: float = float(node.get_meta("arm_rest", 0.08))
	var crouch: float = float(node.get_meta("crouch", 0.1))
	var holds_staff: bool = str(node.get_meta("pose", "")) == "staff"
	var breathe := rest * sin(t * 1.9 + phase) * 0.03
	var sway := rest * sin(t * 1.15 + phase) * 0.05
	var stride := t * 6.0 + phase
	# The life of the walk is in the BODY, not just the limbs: it rocks side-to-side
	# toward the planted foot (the `roll`, once per stride), bobs up and settles on
	# each footfall (twice per stride — the little "shake" on every step), and leans
	# a touch into the stride. This carries the walk; the limbs stay understated.
	var roll := sin(stride) * 0.09 * walk
	var bob := absf(sin(stride)) * 0.055 * walk
	var settle := absf(sin(stride)) * 0.045 * walk
	# Idle sway is upward-only so it never sinks the feet below the ground; GROUND_LIFT
	# compensates for the boot mesh sitting a touch below the rig origin + the crouch.
	var idle_bob := rest * (0.5 + 0.5 * sin(t * 2.0 + phase)) * 0.02
	node.rotation = Vector3(lean + walk * 0.06 + breathe * 0.4, yaw, sway + roll)
	# Curl the upper back forward (head leads, shoulders round) — the spine pivot
	# carries everything above the hips; a touch more curl while walking.
	_set_pivot(node, "spine", hunch + walk * 0.05)
	node.position = pos3 + Vector3(0, bob + idle_bob + 0.09 - crouch * 0.14, 0)
	node.scale = Vector3(base * (1.0 - settle * 0.4), base * (1.0 + breathe + settle), base * (1.0 - settle * 0.4))
	# Legs: a natural stride — moderate hip swing, the knee lifting in its swing phase
	# to clear the ground (not a deep squat, not a stiff post).
	var hip := sin(stride) * 0.42 * walk
	var hip_crouch := -crouch * 0.42                 # thighs forward to sit into the crouch
	var knee_base := 0.16 + crouch * 0.95            # standing knee bend
	var knee_l := knee_base + walk * (0.1 + 0.45 * maxf(0.0, sin(stride + 1.1)))
	var knee_r := knee_base + walk * (0.1 + 0.45 * maxf(0.0, sin(stride + PI + 1.1)))
	_set_pivot(node, "leg_l", hip + hip_crouch)
	_set_pivot(node, "leg_r", -hip + hip_crouch)
	_set_pivot(node, "leg_l/knee_l", knee_l)   # knees are nested under the hip pivots
	_set_pivot(node, "leg_r/knee_r", knee_r)
	# Arms: a relaxed counter-swing to the legs; ELBOWS fold FORWARD (negative — the
	# forearm comes up toward the front like a real arm, never bent backward), with a
	# soft constant crook so the arms read as relaxed, not stiff or flailing.
	var idle_arm := rest * sin(t * 1.5 + phase) * 0.1
	var arm_l := arm_rest + sin(stride + PI) * 0.4 * walk + idle_arm
	var arm_r := arm_rest + sin(stride) * 0.4 * walk - idle_arm
	var elbow_base := -(0.2 + crouch * 0.25)
	var elbow_l := elbow_base - walk * 0.22 * maxf(0.0, sin(stride + PI + 0.5))
	var elbow_r := elbow_base - walk * 0.22 * maxf(0.0, sin(stride + 0.5))
	if holds_staff:
		arm_r = 0.12 + idle_arm * 0.3   # rest the hand on a side-planted staff
		elbow_r = -0.16
	if atk > 0.0:
		var strike := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.5, strike)   # lead arm chops overarm
		elbow_r = lerpf(elbow_r, -1.0, strike)  # forearm folds in for the chop
		arm_l = lerpf(arm_l, 0.4, strike)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", elbow_l)   # elbows are nested under the shoulder pivots
	_set_pivot(node, "arm_r/elbow_r", elbow_r)


## Goblin stance — stands UPRIGHT but cocky and twitchy (a nimble medieval-game
## goblin, not a hunchback): a slightly coiled wide stance on bent knees, the torso
## near-vertical with just a hint of forward attitude, weight shifting, the head
## darting to glance around, and clawed hands held ready at the waist. The walk is a
## fast, light, bouncy scamper.
static func _pose_goblin(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var holds_staff: bool = str(node.get_meta("pose", "")) == "staff"
	var crouch := 0.24                                               # bent knees, but STANDING
	var stride := t * 8.4 + phase                                    # fast little legs
	var bob := absf(sin(stride)) * 0.08 * walk
	var skip := absf(sin(stride * 0.5 + 0.4)) * 0.045 * walk
	# Idle life: shifty side-weight, glancing around, sudden nervous twitches.
	var shift := rest * sin(t * 2.3 + phase) * 0.08
	var glance := rest * sin(t * 0.85 + phase) * 0.4
	var twitch := rest * maxf(0.0, sin(t * 1.3 + phase * 2.0) - 0.6) * 0.6
	var roll := sin(stride) * 0.12 * walk
	node.rotation = Vector3(0.03, yaw, shift + roll)
	node.position = pos3 + Vector3(0, bob + skip + 0.09 - crouch * 0.14, 0)
	# Spine: near-vertical (just a hint of forward attitude) that twists to glance +
	# a quick scheming jitter — upright, never toppling.
	var spine: Node3D = _pivot(node, "spine")
	if spine != null:
		spine.rotation = Vector3(0.12 + walk * 0.05 + twitch, glance, rest * sin(t * 3.0 + phase) * 0.05)
	# Legs: a fast, light, high-knee scamper from a wide bent-knee stance.
	var hip := sin(stride) * 0.5 * walk
	var hipc := -crouch * 0.42
	var kbase := 0.2 + crouch * 0.95
	_set_pivot(node, "leg_l", hip + hipc)
	_set_pivot(node, "leg_r", -hip + hipc)
	_set_pivot(node, "leg_l/knee_l", kbase + walk * (0.22 + 0.62 * maxf(0.0, sin(stride + 1.1))))
	_set_pivot(node, "leg_r/knee_r", kbase + walk * (0.22 + 0.62 * maxf(0.0, sin(stride + PI + 1.1))))
	# Arms: clawed hands held ready at the waist (a small idle fidget), pumping when
	# scampering; a staff-goblin grips its planted staff with the right hand instead.
	var fidget := rest * sin(t * 4.8 + phase) * 0.12
	var arm_l := 0.46 + sin(stride + PI) * 0.42 * walk
	var arm_r := 0.46 + sin(stride) * 0.42 * walk
	var elbow_r := -0.82 + fidget
	if holds_staff:
		arm_r = 0.16
		elbow_r = -0.18
	if atk > 0.0:
		var st := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.4, st)                              # a quick stabby swipe
		elbow_r = lerpf(elbow_r, -0.9, st)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", -0.82 - fidget)
	_set_pivot(node, "arm_r/elbow_r", elbow_r)


## Gnoll gait — a heavy hyena-beast prowl (predatory, not a tidy walk): the head is
## carried low and forward, shoulders rolling, a slow menacing weight-sway, broken by
## a sudden cackling snout-up jerk. The walk is a powerful, lurching, long-stride lope.
static func _pose_gnoll(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var stride := t * 5.2 + phase                                    # slow, heavy strides
	var bob := absf(sin(stride)) * 0.06 * walk
	# Idle: slow heavy sway, breathing shoulders, an occasional cackle head-jerk.
	var sway := rest * sin(t * 1.3 + phase) * 0.1
	var breathe := rest * (0.5 + 0.5 * sin(t * 1.8 + phase)) * 0.05
	var cackle := rest * maxf(0.0, sin(t * 0.9 + phase) - 0.78) * 0.9
	var roll := sin(stride) * 0.15 * walk                           # heavy shoulder roll
	node.rotation = Vector3(0.04, yaw, sway + roll)
	node.position = pos3 + Vector3(0, bob + 0.04, 0)
	# Spine: stands UPRIGHT and imposing — chest up, only a slight forward set (ready,
	# not falling). The snout already juts from the rig; the head dips a touch on each
	# footfall and snaps up to cackle. Heavy breathing rocks the shoulders.
	var spine: Node3D = _pivot(node, "spine")
	if spine != null:
		var dip := absf(sin(stride)) * 0.1 * walk
		spine.rotation = Vector3(0.15 + breathe + dip - cackle, sway * 0.5, 0)
	# Legs: a powerful digitigrade stance/lope — stands tall on bent hocks, long push.
	var hip := sin(stride) * 0.44 * walk
	var hipc := -0.14
	var kbase := 0.5
	_set_pivot(node, "leg_l", hip + hipc)
	_set_pivot(node, "leg_r", -hip + hipc)
	_set_pivot(node, "leg_l/knee_l", kbase + walk * (0.15 + 0.5 * maxf(0.0, sin(stride + 1.1))))
	_set_pivot(node, "leg_r/knee_r", kbase + walk * (0.15 + 0.5 * maxf(0.0, sin(stride + PI + 1.1))))
	# Arms: long and heavy, hanging at the sides with a slight ready set, swinging on
	# the lope; a big overhead claw-rake on attack.
	var idle_arm := rest * sin(t * 1.4 + phase) * 0.1
	var arm_l := 0.16 + sin(stride + PI) * 0.46 * walk + idle_arm
	var arm_r := 0.16 + sin(stride) * 0.46 * walk - idle_arm
	var elbow := -0.42
	if atk > 0.0:
		var st := sin(atk * PI)
		arm_r = lerpf(arm_r, -1.7, st)
		elbow = lerpf(elbow, -1.1, st)
		arm_l = lerpf(arm_l, 0.5, st)
	_set_pivot(node, "arm_l", arm_l)
	_set_pivot(node, "arm_r", arm_r)
	_set_pivot(node, "arm_l/elbow_l", elbow)
	_set_pivot(node, "arm_r/elbow_r", elbow)


## Four-legged trot: diagonal leg pairs swing together (FL+BR vs FR+BL), low body
## bob, the back dips a touch on each push, and the tail wags. A swing leans the
## whole body in for a headbutt/bite.
static func _pose_quadruped(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	# Idle life: slow breathing, a gentle side-to-side weight shift, and a periodic
	# head-down graze dip so a standing beast never just freezes.
	var breathe := rest * sin(t * 1.5 + phase) * 0.022
	var sway := rest * sin(t * 0.85 + phase) * 0.035
	var graze := rest * maxf(0.0, sin(t * 0.45 + phase) - 0.4) * 0.32
	node.rotation = Vector3(-0.28 * sin(atk * PI) + graze, yaw, sway)
	var stride := t * 7.6 + phase
	# A clear up/down body bob while moving + a gentle idle breathing sway at rest;
	# a small ground lift so the hooves sit on the floor, not through it.
	var bob := absf(sin(stride)) * 0.06 * walk + rest * (0.5 + 0.5 * sin(t * 2.0 + phase)) * 0.02
	node.position = pos3 + Vector3(0, bob + 0.07, 0)
	var sq := sin(stride * 2.0) * 0.03 * walk
	node.scale = Vector3(base * (1.0 + sq * 0.4), base * (1.0 - sq * 0.5 + breathe), base * (1.0 + sq * 0.4))
	# Diagonal trot: FL+BR swing together, FR+BL opposite. Each knee folds through
	# its swing so the legs articulate (lift + reach) instead of swinging as posts.
	var swing := sin(stride) * 0.7 * walk
	var idle_leg := rest * sin(t * 1.1 + phase) * 0.04
	var knee_a := 0.12 + walk * (0.18 + 0.5 * maxf(0.0, sin(stride + 1.1)))
	var knee_b := 0.12 + walk * (0.18 + 0.5 * maxf(0.0, sin(stride + PI + 1.1)))
	_set_pivot(node, "leg_fl", swing + idle_leg)
	_set_pivot(node, "leg_br", swing - idle_leg)
	_set_pivot(node, "leg_fr", -swing - idle_leg)
	_set_pivot(node, "leg_bl", -swing + idle_leg)
	_set_pivot(node, "leg_fl/knee_fl", knee_a)
	_set_pivot(node, "leg_br/knee_br", knee_a)
	_set_pivot(node, "leg_fr/knee_fr", knee_b)
	_set_pivot(node, "leg_bl/knee_bl", knee_b)
	var tail: Node3D = node.get_node_or_null(^"tail")
	if tail != null:
		tail.rotation = Vector3(0.18 * sin(stride * 0.5) * walk, 0.5 * sin(t * 2.0 + phase), 0)


## Bird waddle: quick alternating steps, a side-to-side roll, and a brisk bob —
## smaller and twitchier than the beasts. A swing is a sharp forward peck.
static func _pose_bird(node: Node3D, pos3: Vector3, yaw: float, walk: float, t: float, phase: float, base: float, atk: float) -> void:
	var rest := 1.0 - walk
	var stride := t * 9.0 + phase
	# Idle life: a constant little body bob plus a sharp periodic peck-and-look,
	# and a slight head-cock sway — birds are never still.
	var idle_bob := rest * absf(sin(t * 2.2 + phase)) * 0.02
	var peck := rest * maxf(0.0, sin(t * 1.4 + phase) - 0.3) * 0.5
	var look := rest * sin(t * 0.7 + phase) * 0.12
	var bob := absf(sin(stride)) * 0.05 * walk + idle_bob
	node.position = pos3 + Vector3(0, bob + 0.03, 0)
	var roll := sin(stride) * 0.18 * walk
	node.rotation = Vector3(-0.35 * sin(atk * PI) - peck, yaw + look, roll)
	node.scale = Vector3(base, base, base)
	var swing := sin(stride) * 0.7 * walk
	_set_pivot(node, "leg_l", swing)
	_set_pivot(node, "leg_r", -swing)


# --- combat animation: lunges driven by the tick-combat hit splats -------------


static func _set_pivot(node: Node3D, pivot_name: String, angle: float) -> void:
	var p := _pivot(node, pivot_name)
	if p != null:
		p.rotation.x = angle


## Like _set_pivot but also yaws the pivot (Y) — for poses that splay a limb sideways
## (e.g. the cross-legged sit opening the knees outward); single-axis pitch can't.
static func _set_pivot_xy(node: Node3D, pivot_name: String, ax: float, ay: float) -> void:
	var p := _pivot(node, pivot_name)
	if p != null:
		p.rotation.x = ax
		p.rotation.y = ay


## Cross-legged "seated on the ground" fold — a meditating-monk pose layered over the
## idle pose by the renderer. `sit` is the eased 0..1 amount, `base` the rig scale.
##
## A single-axis pitch on the hips reads as sitting on an invisible chair (thighs jut
## forward, shins hang straight down). To sit ON THE GROUND the thighs also YAW outward
## so the knees splay to the sides, the knees fold hard so the shins tuck low and cross
## in front, the torso holds near-upright, the hands settle into the lap, and the whole
## rig drops so the seat meets the ground instead of hovering at chair height.
static func pose_sit(node: Node3D, sit: float, base: float) -> void:
	if sit <= 0.001:
		return
	_set_pivot_xy(node, "leg_l", sit * -1.55, sit * 0.62)   # L thigh: fold ~flat + splay out
	_set_pivot_xy(node, "leg_r", sit * -1.55, sit * -0.62)  # R thigh: fold ~flat + splay out
	_set_pivot(node, "leg_l/knee_l", sit * 2.3)             # shins tuck back low, crossing under the lap
	_set_pivot(node, "leg_r/knee_r", sit * 2.3)
	_set_pivot(node, "spine", sit * 0.05)                   # upright meditative back (idle slump was 0.18)
	_set_pivot(node, "arm_l", sit * 0.18)                   # hands come to rest in the lap
	_set_pivot(node, "arm_r", sit * 0.18)
	_set_pivot(node, "arm_l/elbow_l", sit * -1.2)
	_set_pivot(node, "arm_r/elbow_r", sit * -1.2)
	node.position.y -= sit * 0.82 * base                    # drop the seat to the ground (idle floated at 0.46)


## Resolve a named rig pivot, CACHED per rig. Pivots like "arm_l" now sit under the
## `spine` pivot, so a plain path lookup misses and needs a recursive search — doing
## that every frame for every mover was the dominant per-frame cost. We resolve once
## (path, then recursive fallback for nested names) and cache the node (incl. nulls)
## on the rig, so subsequent frames are a dictionary hit.
static func _pivot(node: Node3D, pivot_name: String) -> Node3D:
	var cache: Dictionary
	if node.has_meta("pivot_cache"):
		cache = node.get_meta("pivot_cache")
	else:
		cache = {}
		node.set_meta("pivot_cache", cache)
	if cache.has(pivot_name):
		var c: Variant = cache[pivot_name]
		if c == null or is_instance_valid(c):
			return c
	var p: Node3D = node.get_node_or_null(NodePath(pivot_name))
	if p == null:
		var segs := pivot_name.split("/")
		var cur: Node = node.find_child(segs[0], true, false)
		for i: int in range(1, segs.size()):
			if cur == null:
				break
			cur = cur.get_node_or_null(NodePath(segs[i]))
		p = cur as Node3D
	cache[pivot_name] = p
	return p


