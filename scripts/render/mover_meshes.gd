extends RefCounted
## 3D rigs for MOVERS (player, enemies, quadrupeds, birds, beastmen) + worn EQUIPMENT, extracted
## from prop_meshes.gd. These build individual articulated Node3D rigs (not batched parts).
##
## Shares the low-level mesh/material primitives with the static-prop catalog: calls
## PropMeshes._box/_mat_from/_part/_cyl/_cone/_sphere/_prism + build_node. One-way dependency —
## PropMeshes never calls back here. External callers (mover_renderer_3d, sit/placeable previews)
## use MoverMeshes.player_rig / enemy_rig / apply_equipment / blob_shadow.

const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const EquipLoadout := preload("res://scripts/render/equip_loadout.gd")
const HAND_SOCKET_POS := Vector3(0.075, -0.35, 0.055)


## Articulated low-poly human with natural proportions (a normal-sized squared
## head, not a chibi ball): tousled hair, a casual shirt with rolled sleeves —
## bare-skin forearms — over dark trousers and boots. Each leg/arm hangs off a
## named pivot (leg_l/leg_r/arm_l/arm_r) for the walk + attack anim. body = shirt
## colour, head = skin. (cape kept for API compat; the player no longer uses it.)
## Faces +Z.
static func figure_rig(body: Color, head: Color, cape := Color(0, 0, 0, 0)) -> Node3D:
	var shirt := PropMeshes._mat_from(body, body.darkened(0.4), body.lightened(0.22))
	var pants := PropMeshes._mat_from(Color(0.22, 0.22, 0.27), Color(0.13, 0.13, 0.17), Color(0.32, 0.32, 0.38))
	var boot := PropMeshes._mat_from(Color(0.26, 0.17, 0.1), Color(0.15, 0.09, 0.05), Color(0.38, 0.27, 0.16))
	var skin := PropMeshes._mat_from(head, head.darkened(0.3), head.lightened(0.2))
	var hairc: Color = PixelPalette.pal("hair")
	var hairm := PropMeshes._mat_from(hairc, hairc.darkened(0.4), hairc.lightened(0.18))
	var eyed := PropMeshes._mat_from(Color(0.1, 0.1, 0.14), Color(0.05, 0.05, 0.07), Color(0.18, 0.18, 0.22))
	var root := Node3D.new()
	# Legs: dark trousers over a knee joint + boots (so the knee can flex when walking).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.13 * side, 0.9, 0), Vector3(0.19, 0.42, 0.21), Vector3(0.17, 0.4, 0.19), pants, "hleg")
		_attach(knee, PropMeshes._box("hum_boot", Vector3(0.21, 0.16, 0.28)), boot, Vector3(0, -0.46, 0.04))
	_attach(root, PropMeshes._box("hum_hips", Vector3(0.42, 0.18, 0.27)), pants, Vector3(0, 0.92, 0))
	# Everything above the hips hangs off a `spine` pivot at the waist, so the pose
	# code can curl the upper back forward into a natural stoop (legs stay vertical).
	# Child Y offsets are spine-local (world Y minus the 0.95 pivot height).
	var spine := _limb(root, "spine", Vector3(0, 0.95, 0))
	# Torso: a casual shirt with a slightly broader shoulder yoke + a small collar.
	_attach(spine, PropMeshes._box("hum_chest", Vector3(0.46, 0.52, 0.28)), shirt, Vector3(0, 0.29, 0))
	_attach(spine, PropMeshes._box("hum_yoke", Vector3(0.52, 0.14, 0.31)), shirt, Vector3(0, 0.51, 0))
	_attach(spine, PropMeshes._box("hum_collar", Vector3(0.12, 0.12, 0.08)), skin, Vector3(0, 0.51, 0.14))
	# Neck + a squared, natural-sized head.
	_attach(spine, PropMeshes._box("hum_neck", Vector3(0.14, 0.12, 0.15)), skin, Vector3(0, 0.6, 0))
	_attach(spine, PropMeshes._box("hum_head", Vector3(0.32, 0.36, 0.32)), skin, Vector3(0, 0.79, 0))
	# Tousled hair: a crown block, a swept-up front fringe, and short sides.
	_attach(spine, PropMeshes._box("hum_hair", Vector3(0.35, 0.16, 0.35)), hairm, Vector3(0, 0.95, -0.01))
	_attach(spine, PropMeshes._box("hum_fringe", Vector3(0.33, 0.1, 0.13)), hairm, Vector3(0.02, 0.91, 0.16), Vector3.ONE, Vector3(-0.35, 0, 0.1))
	_attach(spine, PropMeshes._box("hum_side", Vector3(0.36, 0.16, 0.3)), hairm, Vector3(0, 0.85, -0.06))
	# Subtle eyes set into the face (+Z).
	for ex: int in [-1, 1]:
		_attach(spine, PropMeshes._box("hum_eye", Vector3(0.05, 0.06, 0.04)), eyed, Vector3(0.08 * ex, 0.79, 0.16))
	# Optional cape/strap kept for API compatibility.
	if cape.a > 0.0:
		var capem := PropMeshes._mat_from(Color(cape.r, cape.g, cape.b), cape.darkened(0.34), cape.lightened(0.22))
		_attach(spine, PropMeshes._box("hum_cape", Vector3(0.34, 0.6, 0.07)), capem, Vector3(0, 0.15, -0.17), Vector3.ONE, Vector3(0.2, 0, 0))
	# Arms: shirt sleeve (upper) over an elbow joint, bare-skin forearm + hand. Weapon
	# sockets ride the forearm so a held weapon follows the hand and bends at the elbow.
	for side2: int in [-1, 1]:
		var el := _biped_arm(spine, side2, Vector3(0.3 * side2, 0.47, 0), Vector3(0.14, 0.26, 0.16), Vector3(0.12, 0.26, 0.14), shirt, skin, "harm")
		_attach(el, PropMeshes._box("hum_hand", Vector3(0.13, 0.13, 0.15)), skin, Vector3(0, -0.34, 0))
		_socket(el, "socket_mainhand" if side2 > 0 else "socket_offhand", Vector3(HAND_SOCKET_POS.x * side2, HAND_SOCKET_POS.y, HAND_SOCKET_POS.z))
	# Worn-gear sockets (see equip_profile): the renderer attaches armor/weapons here.
	# Upper-body sockets ride the spine; leg armor stays on the (vertical) root.
	_socket(spine, "socket_head", Vector3(0, 0.79, 0))
	_socket(spine, "socket_body", Vector3(0, 0.29, 0))
	_socket(root, "socket_legs", Vector3(0, 0.95, 0))
	_socket(spine, "socket_back", Vector3(0, 0.39, -0.16))
	root.set_meta("body_profile", {
		"torso": Vector3(0.5, 0.56, 0.32), "head": Vector3(0.36, 0.42, 0.36),
		"shoulder": 0.6, "hips": Vector3(0.42, 0.18, 0.27)})
	return root


## The player's bare adventurer body — a more sculpted low-poly figure than the
## generic enemy humanoid: a bearded head with a jaw/brow/nose and pointed ears,
## swept hair, a linen shirt with rolled sleeves, teal tartan breeches and cuffed
## boots. The OUTFIT (jerkin, belt, cape, weapons) is NOT baked in — it layers on
## via the equipment sockets (EquipLoadout.player_default), so armor and weapons
## can be swapped independently of the body. Same pivots/sockets as figure_rig.
static func player_rig(skin_col: Color) -> Node3D:
	var skin := PropMeshes._mat_from(skin_col, skin_col.darkened(0.3), skin_col.lightened(0.2))
	var skin_sh := PropMeshes._mat_from(skin_col.darkened(0.14), skin_col.darkened(0.42), skin_col.lightened(0.08))
	var linen := PropMeshes._mat_from(Color(0.82, 0.78, 0.66), Color(0.6, 0.56, 0.46), Color(0.92, 0.89, 0.8))
	var teal := PropMeshes._mat_from(Color(0.26, 0.42, 0.4), Color(0.16, 0.28, 0.27), Color(0.38, 0.56, 0.52))
	var teal2 := PropMeshes._mat_from(Color(0.36, 0.52, 0.48), Color(0.24, 0.36, 0.34), Color(0.48, 0.64, 0.6))
	var boot := PropMeshes._mat_from(Color(0.36, 0.24, 0.14), Color(0.22, 0.14, 0.08), Color(0.5, 0.36, 0.22))
	var cuff := PropMeshes._mat_from(Color(0.47, 0.33, 0.18), Color(0.3, 0.2, 0.1), Color(0.6, 0.46, 0.28))
	var hairc: Color = PixelPalette.pal("hair")
	var hairm := PropMeshes._mat_from(hairc, hairc.darkened(0.42), hairc.lightened(0.16))
	var beardm := PropMeshes._mat_from(hairc.lightened(0.06), hairc.darkened(0.4), hairc.lightened(0.22))
	var eyed := PropMeshes._mat_from(Color(0.1, 0.1, 0.14), Color(0.05, 0.05, 0.07), Color(0.18, 0.18, 0.22))
	var root := Node3D.new()
	# Legs: tartan breeches over a knee joint + cuffed boots (boots ride the shin).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.13 * side, 0.9, 0), Vector3(0.21, 0.42, 0.23), Vector3(0.18, 0.4, 0.21), teal, "pleg")
		_attach(knee, PropMeshes._box("p_stripe", Vector3(0.045, 0.4, 0.22)), teal2, Vector3(0.06, -0.2, 0.0))
		_attach(knee, PropMeshes._box("p_boot", Vector3(0.21, 0.3, 0.28)), boot, Vector3(0, -0.36, 0.02))
		_attach(knee, PropMeshes._box("p_bootcuff", Vector3(0.24, 0.09, 0.3)), cuff, Vector3(0, -0.24, 0.02))
		_attach(knee, PropMeshes._box("p_sole", Vector3(0.22, 0.06, 0.33)), cuff, Vector3(0, -0.52, 0.05))
	_attach(root, PropMeshes._box("p_hips", Vector3(0.44, 0.2, 0.28)), teal, Vector3(0, 0.9, 0))
	# Torso: a plain linen shirt — the jerkin/armor layers over it (body socket).
	_attach(root, PropMeshes._box("p_chest", Vector3(0.46, 0.54, 0.28)), linen, Vector3(0, 1.24, 0))
	_attach(root, PropMeshes._box("p_yoke", Vector3(0.52, 0.16, 0.31)), linen, Vector3(0, 1.48, 0))
	# Sculpted head: skull + jaw + brow + nose, beard, pointed ears, swept hair, eyes.
	_attach(root, PropMeshes._box("p_neck", Vector3(0.15, 0.12, 0.16)), skin, Vector3(0, 1.56, 0))
	_attach(root, PropMeshes._box("p_skull", Vector3(0.32, 0.3, 0.32)), skin, Vector3(0, 1.79, 0))
	_attach(root, PropMeshes._box("p_jaw", Vector3(0.27, 0.16, 0.29)), skin, Vector3(0, 1.65, 0.02))
	_attach(root, PropMeshes._box("p_brow", Vector3(0.3, 0.06, 0.05)), skin_sh, Vector3(0, 1.8, 0.16))
	_attach(root, PropMeshes._box("p_nose", Vector3(0.08, 0.1, 0.09)), skin, Vector3(0, 1.73, 0.18))
	# Beard hangs off a pivot at the jaw so the hair-physics sway swings it.
	var beard := _limb(root, "beard", Vector3(0, 1.62, 0.07))
	_attach(beard, PropMeshes._box("p_beard", Vector3(0.31, 0.22, 0.18)), beardm, Vector3(0, -0.02, 0.0))
	_attach(beard, PropMeshes._box("p_beard2", Vector3(0.2, 0.14, 0.11)), beardm, Vector3(0, -0.13, 0.05))
	for sx: int in [-1, 1]:
		_attach(root, PropMeshes._prism("p_ear", Vector3(0.08, 0.18, 0.09)), skin, Vector3(0.18 * sx, 1.82, 0.0), Vector3.ONE, Vector3(0, 0, -0.35 * sx))
	# Swept hair hangs off a crown pivot so it bounces/leans with movement.
	var hair := _limb(root, "hair", Vector3(0, 1.82, 0))
	_attach(hair, PropMeshes._box("p_hair_top", Vector3(0.36, 0.18, 0.36)), hairm, Vector3(0, 0.14, -0.01))
	_attach(hair, PropMeshes._box("p_hair_back", Vector3(0.35, 0.34, 0.16)), hairm, Vector3(0, -0.04, -0.15))
	_attach(hair, PropMeshes._box("p_hair_fr", Vector3(0.34, 0.12, 0.12)), hairm, Vector3(0.03, 0.1, 0.15), Vector3.ONE, Vector3(-0.5, 0, 0.12))
	for ex: int in [-1, 1]:
		_attach(root, PropMeshes._box("p_eye", Vector3(0.05, 0.06, 0.04)), eyed, Vector3(0.08 * ex, 1.77, 0.17))
	# Arms: linen sleeve (upper) over an elbow joint with a bare-skin forearm + hand;
	# weapon sockets ride the forearm (elbow) so a held weapon follows the hand.
	for s2: int in [-1, 1]:
		var el := _biped_arm(root, s2, Vector3(0.3 * s2, 1.42, 0), Vector3(0.16, 0.24, 0.18), Vector3(0.12, 0.26, 0.14), linen, skin, "parm")
		_attach(el, PropMeshes._box("p_hand", Vector3(0.13, 0.13, 0.15)), skin, Vector3(0, -0.34, 0))
		_socket(el, "socket_mainhand" if s2 > 0 else "socket_offhand", Vector3(HAND_SOCKET_POS.x * s2, HAND_SOCKET_POS.y, HAND_SOCKET_POS.z))
	_socket(root, "socket_head", Vector3(0, 1.79, 0))
	_socket(root, "socket_body", Vector3(0, 1.24, 0))
	_socket(root, "socket_legs", Vector3(0, 0.9, 0))
	_socket(root, "socket_back", Vector3(0, 1.36, -0.16))
	# Body profile: the bounding boxes worn armor is sized FROM so a piece always
	# wraps this body (never crops). Read by apply_equipment -> equip_parts.
	root.set_meta("body_profile", {
		"torso": Vector3(0.5, 0.6, 0.32), "head": Vector3(0.36, 0.42, 0.36),
		"shoulder": 0.66, "hips": Vector3(0.46, 0.22, 0.3)})
	# Posture: the player stands near-upright but relaxed (a touch of lean + arms
	# resting slightly forward), not ramrod-straight. Read by _pose_humanoid.
	root.set_meta("lean", 0.04)
	root.set_meta("arm_rest", 0.1)
	root.set_meta("crouch", 0.17)   # slightly bent knees — an athletic stance, not locked
	return root


## A sim-player rig: the same adventurer body the real player uses (so a sim reads as "another
## player", not a monster), wearing its own deterministic look. body3d/base_scale default to the
## humanoid/1.0 the pose code expects (no metas needed — MoverRenderer3D animates it like the player).
static func sim_rig(skin: Color, loadout: Dictionary) -> Node3D:
	var node := player_rig(skin)
	if not loadout.is_empty():
		apply_equipment(node, loadout)
	return node


## A static attachment point (worn gear / held weapons) — a named empty the
## renderer parents equipment meshes under. See apply_equipment / equip_profile.
static func _socket(parent: Node3D, sname: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var s := Node3D.new()
	s.name = sname
	s.position = pos
	s.rotation = rot
	parent.add_child(s)
	return s


# -------------------------------------------------------------- equipment ----
# Visible worn armor + held weapons. A rig exposes named sockets (socket_mainhand,
# socket_offhand, socket_head, socket_body, socket_legs, socket_back); apply_equipment
# attaches gear meshes to the ones a loadout fills. A rig that lacks a socket simply
# can't show that slot — that's the capability gate (a chicken has no sockets, so it
# wears nothing). See docs/render_spike/MODELS_AND_EQUIPMENT.md.

const EQUIP_SLOTS := ["socket_mainhand", "socket_offhand", "socket_head", "socket_body", "socket_legs", "socket_back"]


## Which worn slots a rig actually supports (the sockets it was built with).
static func equip_profile(rig: Node3D) -> Array:
	var out: Array = []
	for s: String in EQUIP_SLOTS:
		if rig.get_node_or_null(NodePath(s)) != null:
			out.append(s.trim_prefix("socket_"))
	return out


## Attach a loadout to a rig. loadout = {slot: {kind, material, tint?}} with slot in
## mainhand/offhand/head/body/legs/back. Clears any previously-applied gear first so
## re-applying (e.g. the player changing equipment) is clean. Slots the rig can't
## support are skipped.
static func apply_equipment(rig: Node3D, loadout: Dictionary) -> void:
	for s: String in EQUIP_SLOTS:
		# Weapon sockets are NESTED on the forearm (rig -> arm_r -> elbow_r -> socket_mainhand),
		# so look them up recursively — a direct child lookup misses them and weapons never attach.
		var sock: Node = rig.find_child(s, true, false)
		if sock == null:
			continue
		var old: Node = sock.get_node_or_null(^"equip")
		if old != null:
			old.free()
	rig.set_meta("weapon_pose", "")
	rig.set_meta("weapon_kind", "")
	rig.set_meta("weapon_attack", "")
	# A long robe replaces the visible legs — hide them so they don't poke through
	# the skirt (the wearer glides). Reset first so unequipping shows them again.
	var hide_legs := loadout.has("legs") and str(Dictionary(loadout.get("legs", {})).get("kind", "")) == "robe_bottom"
	for legn: String in ["leg_l", "leg_r"]:
		var lp: Node = rig.get_node_or_null(NodePath(legn))
		if lp != null:
			(lp as Node3D).visible = not hide_legs
	# A full helm encloses the head — hide the hair/beard so they don't poke out the
	# back of it (the black square). A soft hood keeps them. Reset when bare-headed.
	var hide_hair := loadout.has("head") and str(Dictionary(loadout.get("head", {})).get("kind", "")) == "helm"
	for hn: String in ["hair", "beard"]:
		var hp: Node = rig.get_node_or_null(NodePath(hn))
		if hp == null:
			hp = rig.find_child(hn, true, false)
		if hp != null:
			(hp as Node3D).visible = not hide_hair
	var profile: Dictionary = rig.get_meta("body_profile", {})
	for slot: String in loadout:
		var sock2: Node3D = rig.find_child("socket_" + slot, true, false)   # nested forearm sockets too
		if sock2 == null:
			continue
		var spec: Dictionary = loadout[slot]
		var kind := str(spec.get("kind", ""))
		var holder: Node3D
		if kind == "cape":
			# A cape is a segmented chain so the renderer can ripple a cheap wave down
			# it (real flow, not a rigid plank swing) — see _flow_cloth.
			holder = build_cape(equip_material(str(spec.get("material", "cloth")), spec.get("tint", Color(0, 0, 0, 0))), profile)
		else:
			var parts := equip_parts(slot, kind, str(spec.get("material", "iron")), spec.get("tint", Color(0, 0, 0, 0)), profile)
			if parts.is_empty():
				continue
			holder = PropMeshes.build_node(parts)
		holder.name = "equip"
		# Per-type GRIP so a held weapon reads correctly instead of poking up into the body:
		# the socket sits at the fist and the weapon mesh origin is its grip point, so
		# rotations happen around the hand instead of the weapon's middle.
		if slot == "mainhand":
			var grip := weapon_profile(kind)
			holder.position = grip["pos"]
			holder.rotation = grip["rot"]
			holder.set_meta("weapon_pose", grip["pose"])
			holder.set_meta("weapon_attack", grip["attack"])
			rig.set_meta("weapon_pose", grip["pose"])
			rig.set_meta("weapon_kind", kind)
			rig.set_meta("weapon_attack", grip["attack"])
		# Flag flowing cloth pieces so the renderer can sway them (cheap procedural
		# secondary motion — no physics). Skirts and capes are the big flowy ones.
		holder.set_meta("cloth", kind in ["robe_bottom", "robe_top", "cape", "hood"])
		for mi: Node in holder.get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sock2.add_child(holder)


## Socket-local grip profile for a held weapon. The rig's socket is the hand; the
## weapon meshes are modelled with their grip at local origin and their length on
## +Y, so this transform describes the held pose without ever moving the hilt out
## of the fist.
static func weapon_profile(kind: String) -> Dictionary:
	match kind:
		"staff", "raven_staff":
			return {
				"pose": "staff", "attack": "staff_cast",
				"pos": Vector3.ZERO,
				"rot": Vector3(1.5, 0.0, 0.02),
			}
		"wand":
			return {
				"pose": "staff", "attack": "staff_cast",
				"pos": Vector3.ZERO,
				"rot": Vector3(0.08, 0.0, -0.08),
			}
		"bow":
			return {
				"pose": "bow", "attack": "bow",
				"pos": Vector3.ZERO,
				"rot": Vector3(0.18, 0.0, -0.28),
			}
		"spear", "halberd":
			return {
				"pose": "polearm", "attack": "thrust",
				"pos": Vector3.ZERO,
				"rot": Vector3(0.04, 0.0, -0.08),
			}
		"greatsword", "twohand", "2h":
			return {
				"pose": "heavy", "attack": "heavy_slash",
				"pos": Vector3.ZERO,
				"rot": Vector3(0.9, 0.0, 0.72),
			}
		"battleaxe", "warhammer", "hammer":
			return {
				"pose": "heavy", "attack": "heavy_chop",
				"pos": Vector3.ZERO,
				"rot": Vector3(0.82, 0.0, 0.64),
			}
		"axe":
			return {
				"pose": "onehand", "attack": "slash",
				"pos": Vector3.ZERO,
				"rot": Vector3(1.78, 0.0, -0.46),
			}
		"dagger":
			return {
				"pose": "onehand", "attack": "stab",
				"pos": Vector3.ZERO,
				"rot": Vector3(1.7, 0.0, -0.28),
			}
		"mace":
			return {
				"pose": "onehand", "attack": "bonk",
				"pos": Vector3.ZERO,
				"rot": Vector3(1.72, 0.0, -0.38),
			}
		"fishing_rod":
			# Held forward + angled up so the long shaft reaches out over the water. The cast/idle
			# motion lives in the humanoid fishing pose; this just sets the resting grip angle.
			return {
				"pose": "onehand", "attack": "none",
				"pos": Vector3.ZERO,
				"rot": Vector3(2.35, 0.0, 0.0),
			}
		_:
			return {
				"pose": "onehand", "attack": "slash",
				"pos": Vector3.ZERO,
				"rot": Vector3(1.82, 0.0, -0.34),
			}


## Palette for an equipment material tier; `tint` overrides cloth/gem colour.
static func equip_material(mat_key: String, tint := Color(0, 0, 0, 0)) -> ShaderMaterial:
	var base: Color
	match mat_key:
		"cloth": base = tint if tint.a > 0.0 else Color(0.52, 0.52, 0.58)
		"leather": base = Color(0.44, 0.3, 0.18)
		"bronze": base = Color(0.72, 0.5, 0.28)
		"iron": base = Color(0.54, 0.55, 0.6)
		"steel": base = Color(0.72, 0.74, 0.8)
		"mithril": base = Color(0.34, 0.46, 0.74)
		"adamant": base = Color(0.3, 0.55, 0.46)
		"rune": base = Color(0.34, 0.64, 0.72)
		"gold": base = Color(0.86, 0.7, 0.26)
		"wood": base = Color(0.46, 0.32, 0.18)
		"bone": base = Color(0.9, 0.86, 0.73)        # horns / ivory trim
		"gem": base = tint if tint.a > 0.0 else Color(0.45, 0.74, 0.95)
		_: base = Color(0.52, 0.52, 0.58)
	return PropMeshes._mat_from(base, base.darkened(0.4), base.lightened(0.3))


## Build the meshes for one equipped piece. Weapons are built extending +Y from the
## grip so they swing naturally from the hand socket; armor wraps its socket centre.
static func equip_parts(slot: String, kind: String, mat_key: String, tint: Color, profile := {}) -> Array:
	var m := equip_material(mat_key, tint)
	var gold := equip_material("gold")
	var dark := equip_material("leather")
	# Body dimensions this armor must wrap (so it never crops the model it's worn on).
	# Falls back to a generic humanoid when a rig declares no profile.
	var torso: Vector3 = profile.get("torso", Vector3(0.5, 0.56, 0.32))
	var headb: Vector3 = profile.get("head", Vector3(0.36, 0.4, 0.36))
	var shoulder: float = float(profile.get("shoulder", 0.64))
	match kind:
		"staff":
			var wood := equip_material("wood")
			return [
				PropMeshes._part(PropMeshes._cyl("eq_staff", 0.035, 0.05, 1.75), wood, Vector3(0, -0.08, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_staff_bind", Vector3(0.09, 0.07, 0.09)), gold, Vector3(0, 0.72, 0.0)),
				PropMeshes._part(PropMeshes._sphere("eq_staff_gem", 0.11), equip_material("gem", tint), Vector3(0, 0.86, 0.0))]
		"raven_staff":
			# Tall gnarled staff with a raven perched on top, planted forward (+Z) of
			# the body so it stays visible whichever way the wearer turns to face.
			var wd := equip_material("wood")
			var rav := PropMeshes._mat_from(Color(0.12, 0.12, 0.15), Color(0.06, 0.06, 0.08), Color(0.24, 0.24, 0.3))
			# The staff's origin is the grip point in the fist; its lower end reaches
			# down past the hand so the idle pose can plant it on the ground.
			var sx := 0.0
			var fz := 0.0
			return [
				PropMeshes._part(PropMeshes._cyl("eq_rstaff_g", 0.05, 0.06, 2.1), wd, Vector3(sx, -0.12, fz)),
				PropMeshes._part(PropMeshes._box("eq_rstaff_knot", Vector3(0.11, 0.12, 0.11)), wd, Vector3(sx, 0.42, fz)),
				PropMeshes._part(PropMeshes._box("eq_rstaff_perch", Vector3(0.22, 0.05, 0.06)), wd, Vector3(sx, 0.88, fz)),
				PropMeshes._part(PropMeshes._sphere("eq_raven_body", 0.11), rav, Vector3(sx, 0.99, fz), Vector3(1.0, 1.05, 1.5)),
				PropMeshes._part(PropMeshes._sphere("eq_raven_head", 0.07), rav, Vector3(sx, 1.1, fz + 0.1)),
				PropMeshes._part(PropMeshes._cone("eq_raven_beak", 0.028, 0.002, 0.11), gold, Vector3(sx, 1.1, fz + 0.2), Vector3.ONE, Vector3(1.5708, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_raven_tail", Vector3(0.07, 0.04, 0.22)), rav, Vector3(sx, 0.97, fz - 0.16), Vector3.ONE, Vector3(0.4, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_raven_wing", Vector3(0.04, 0.14, 0.18)), rav, Vector3(sx + 0.08, 0.99, fz))]
		"wand":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_wand", 0.03, 0.04, 0.6), equip_material("wood"), Vector3(0, 0.2, 0.0)),
				PropMeshes._part(PropMeshes._sphere("eq_wand_tip", 0.07), equip_material("gem", tint), Vector3(0, 0.54, 0.0))]
		"greatsword", "twohand", "2h":
			return [
				PropMeshes._part(PropMeshes._box("eq_gs_blade_" + mat_key, Vector3(0.12, 1.05, 0.035)), m, Vector3(0, 0.62, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_gs_fuller", Vector3(0.035, 0.72, 0.042)), PropMeshes._mat_from(Color(0.92, 0.92, 0.96), Color(0.5, 0.52, 0.58), Color(1, 1, 1)), Vector3(0, 0.68, 0.02)),
				PropMeshes._part(PropMeshes._box("eq_gs_guard", Vector3(0.34, 0.06, 0.08)), gold, Vector3(0, 0.08, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_gs_grip", Vector3(0.06, 0.28, 0.06)), dark, Vector3(0, -0.08, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_gs_pommel", Vector3(0.09, 0.08, 0.08)), gold, Vector3(0, -0.26, 0.0))]
		"sword":
			return [
				PropMeshes._part(PropMeshes._box("eq_blade_" + mat_key, Vector3(0.07, 0.7, 0.025)), m, Vector3(0, 0.48, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_guard", Vector3(0.24, 0.05, 0.07)), gold, Vector3(0, 0.1, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_grip", Vector3(0.05, 0.18, 0.05)), dark, Vector3(0, -0.02, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_pommel", Vector3(0.07, 0.06, 0.06)), gold, Vector3(0, -0.14, 0.0))]
		"dagger":
			return [
				PropMeshes._part(PropMeshes._box("eq_dblade_" + mat_key, Vector3(0.06, 0.34, 0.02)), m, Vector3(0, 0.26, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_dguard", Vector3(0.16, 0.04, 0.06)), gold, Vector3(0, 0.06, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_dgrip", Vector3(0.05, 0.14, 0.05)), dark, Vector3(0, -0.04, 0.0))]
		"axe":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_haft", 0.03, 0.04, 0.82), equip_material("wood"), Vector3(0, 0.24, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_axehead_" + mat_key, Vector3(0.07, 0.28, 0.24)), m, Vector3(0.1, 0.58, 0.0))]
		"battleaxe":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_bax_haft", 0.035, 0.045, 1.2), equip_material("wood"), Vector3(0, 0.34, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_bax_head_" + mat_key, Vector3(0.08, 0.36, 0.34)), m, Vector3(0.15, 0.92, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_bax_head2_" + mat_key, Vector3(0.08, 0.3, 0.28)), m, Vector3(-0.12, 0.88, 0.0))]
		"warhammer", "hammer":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_wh_haft", 0.035, 0.045, 1.08), equip_material("wood"), Vector3(0, 0.3, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_wh_head_" + mat_key, Vector3(0.44, 0.18, 0.22)), m, Vector3(0, 0.88, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_wh_cap", Vector3(0.12, 0.12, 0.16)), gold, Vector3(0, 0.72, 0.0))]
		"mace":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_macehaft", 0.035, 0.045, 0.7), dark, Vector3(0, 0.2, 0.0)),
				PropMeshes._part(PropMeshes._sphere("eq_macehead_" + mat_key, 0.13), m, Vector3(0, 0.58, 0.0))]
		"fishing_rod":
			# Slim tapering wooden rod (grip at origin → tip up +Y), a small reel by the grip, and a
			# pale tip ferrule the cast line anchors near. No blade/material tier — always wood.
			var rwood := equip_material("wood")
			var rcork := equip_material("leather")
			return [
				PropMeshes._part(PropMeshes._cyl("eq_rod_shaft", 0.008, 0.026, 1.35), rwood, Vector3(0, 0.6, 0.0)),
				PropMeshes._part(PropMeshes._cyl("eq_rod_grip", 0.03, 0.034, 0.18), rcork, Vector3(0, 0.02, 0.0)),
				PropMeshes._part(PropMeshes._cyl("eq_rod_reel", 0.055, 0.055, 0.03), dark, Vector3(0.05, 0.12, 0.0), Vector3.ONE, Vector3(0, 0, 1.5708)),
				PropMeshes._part(PropMeshes._sphere("eq_rod_tip", 0.012), equip_material("cloth", Color(0.9, 0.92, 0.85)), Vector3(0, 1.27, 0.0))]
		"spear":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_spearhaft", 0.03, 0.035, 1.75), equip_material("wood"), Vector3(0, 0.34, 0.0)),
				PropMeshes._part(PropMeshes._cone("eq_spearpt_" + mat_key, 0.07, 0.005, 0.28), m, Vector3(0, 1.26, 0.0))]
		"halberd":
			return [
				PropMeshes._part(PropMeshes._cyl("eq_halb_haft", 0.03, 0.035, 1.8), equip_material("wood"), Vector3(0, 0.34, 0.0)),
				PropMeshes._part(PropMeshes._cone("eq_halb_pt_" + mat_key, 0.075, 0.005, 0.3), m, Vector3(0, 1.3, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_halb_blade_" + mat_key, Vector3(0.08, 0.28, 0.24)), m, Vector3(0.11, 1.08, 0.0))]
		"bow":
			var wood2 := equip_material("wood")
			return [
				PropMeshes._part(PropMeshes._box("eq_bow_u", Vector3(0.04, 0.5, 0.06)), wood2, Vector3(0, 0.28, 0.0), Vector3.ONE, Vector3(-0.32, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_bow_l", Vector3(0.04, 0.5, 0.06)), wood2, Vector3(0, -0.28, 0.0), Vector3.ONE, Vector3(0.32, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_bowstr", Vector3(0.012, 1.0, 0.012)), equip_material("cloth", Color(0.9, 0.9, 0.85)), Vector3(0, 0, -0.02))]
		"shield":
			return [
				PropMeshes._part(PropMeshes._box("eq_shield_" + mat_key, Vector3(0.36, 0.46, 0.06)), m, Vector3(0, 0, 0.04)),
				PropMeshes._part(PropMeshes._box("eq_shield_boss", Vector3(0.12, 0.12, 0.04)), gold, Vector3(0, 0, 0.09))]
		"helm":
			# Epic horned great-helm, sized to wrap the head (never crops). A full dome,
			# a brow ridge over a dark visor slit, a crest fin, and two big curved horns.
			var bone := equip_material("bone")
			var hw := headb.x
			var hh := headb.y
			var hd := headb.z
			var ph: Array = [
				PropMeshes._part(PropMeshes._box("eq_gh_dome", Vector3(hw + 0.1, hh + 0.08, hd + 0.1)), m, Vector3(0, 0.06, 0)),
				# Tapered face mask (narrower at the chin) so it reads as a forged helm.
				PropMeshes._part(PropMeshes._box("eq_gh_face", Vector3(hw - 0.04, hh * 0.5, hd + 0.06)), m, Vector3(0, -hh * 0.22, 0.03)),
				PropMeshes._part(PropMeshes._box("eq_gh_brow", Vector3(hw + 0.12, 0.08, hd + 0.07)), gold, Vector3(0, hh * 0.18, 0.02)),
				PropMeshes._part(PropMeshes._box("eq_gh_visor", Vector3(hw * 0.72, 0.06, 0.05)), dark, Vector3(0, hh * 0.04, hd * 0.5 + 0.07)),
				PropMeshes._part(PropMeshes._box("eq_gh_nasal", Vector3(0.07, hh * 0.34, 0.05)), gold, Vector3(0, -hh * 0.16, hd * 0.5 + 0.06)),
				PropMeshes._part(PropMeshes._box("eq_gh_crest", Vector3(0.07, 0.2, hd * 0.95)), gold, Vector3(0, hh * 0.58 + 0.04, 0))]
			# Cheek guards angling in toward the chin.
			for cs: int in [-1, 1]:
				ph.append(PropMeshes._part(PropMeshes._box("eq_gh_cheek", Vector3(0.06, hh * 0.4, hd * 0.5)), m, Vector3((hw * 0.5 - 0.01) * cs, -hh * 0.14, hd * 0.3), Vector3.ONE, Vector3(0, 0, 0.18 * cs)))
			# Two heavy horns: a thick base sweeping outward, then curling up to a point.
			for hsd: int in [-1, 1]:
				var bx := (hw * 0.5) * hsd
				ph.append(PropMeshes._part(PropMeshes._cone("eq_horn_b", 0.09, 0.062, 0.24), bone, Vector3(bx, hh * 0.18, 0.0), Vector3.ONE, Vector3(0, 0, -0.5 * hsd)))
				ph.append(PropMeshes._part(PropMeshes._cone("eq_horn_m", 0.062, 0.04, 0.28), bone, Vector3(bx + 0.15 * hsd, hh * 0.44, 0.0), Vector3.ONE, Vector3(0, 0, -0.9 * hsd)))
				ph.append(PropMeshes._part(PropMeshes._cone("eq_horn_t", 0.04, 0.004, 0.3), bone, Vector3(bx + 0.3 * hsd, hh * 0.82, -0.01), Vector3.ONE, Vector3(0, 0, -0.4 * hsd)))
			return ph
		"hood":
			# Sized from the head box so the cowl always covers it.
			var hw := headb.x
			var hh := headb.y
			var hd := headb.z
			return [
				PropMeshes._part(PropMeshes._box("eq_hood", Vector3(hw + 0.1, hh + 0.0, hd + 0.1)), m, Vector3(0, 0.04, -0.02)),
				PropMeshes._part(PropMeshes._box("eq_hood_pt", Vector3(0.16, 0.22, 0.16)), m, Vector3(0, hh * 0.55, -0.1), Vector3.ONE, Vector3(-0.5, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_hood_drape", Vector3(hw, hh * 0.9, 0.08)), m, Vector3(0, -hh * 0.5, -hd * 0.55))]
		"wizard_hat":
			# Tall pointed witch hat: a wide drooping brim that shadows the face, a
			# cone that bends forward at the tip, and a buckled hat band.
			var band := equip_material("leather")
			return [
				PropMeshes._part(PropMeshes._cone("eq_what_brim", 0.45, 0.34, 0.1), m, Vector3(0, 0.04, 0.02)),
				PropMeshes._part(PropMeshes._cone("eq_what_cone", 0.3, 0.13, 0.42), m, Vector3(0, 0.3, 0)),
				PropMeshes._part(PropMeshes._cone("eq_what_tip", 0.13, 0.01, 0.34), m, Vector3(0, 0.52, 0.16), Vector3.ONE, Vector3(0.7, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_what_band", Vector3(0.35, 0.08, 0.35)), band, Vector3(0, 0.12, 0)),
				PropMeshes._part(PropMeshes._box("eq_what_buckle", Vector3(0.11, 0.1, 0.04)), gold, Vector3(0, 0.12, 0.19))]
		"chest":
			# Epic full plate, sized to wrap the torso (never crops): a full back/side
			# shell, a sculpted domed breastplate + abs, layered faulds over the hips, a
			# gorget closing the neck, gold trim, and big spiked pauldrons on the shoulders.
			var trimm := equip_material("gold")
			var w := torso.x
			var hh := torso.y
			var d := torso.z
			var pc: Array = [
				PropMeshes._part(PropMeshes._box("eq_pl_shell_" + mat_key, Vector3(w + 0.12, hh + 0.02, d + 0.14)), m, Vector3(0, 0, -0.01)),
				PropMeshes._part(PropMeshes._box("eq_pl_chest_" + mat_key, Vector3(w + 0.09, hh * 0.5, d + 0.18)), m, Vector3(0, hh * 0.16, 0.03)),
				PropMeshes._part(PropMeshes._box("eq_pl_ab_" + mat_key, Vector3(w - 0.02, hh * 0.32, d + 0.14)), m, Vector3(0, -hh * 0.12, 0.03)),
				PropMeshes._part(PropMeshes._box("eq_pl_fauld1_" + mat_key, Vector3(w + 0.06, hh * 0.18, d + 0.16)), m, Vector3(0, -hh * 0.4, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_pl_fauld2_" + mat_key, Vector3(w - 0.04, hh * 0.18, d + 0.12)), m, Vector3(0, -hh * 0.54, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_pl_gorget_" + mat_key, Vector3(w * 0.64, 0.16, d * 0.94)), m, Vector3(0, hh * 0.46, 0.0)),
				PropMeshes._part(PropMeshes._box("eq_pl_collar", Vector3(w * 0.82, 0.08, d + 0.1)), trimm, Vector3(0, hh * 0.33, 0.03)),
				PropMeshes._part(PropMeshes._box("eq_pl_ridge", Vector3(0.06, hh * 0.48, 0.05)), trimm, Vector3(0, hh * 0.02, d * 0.5 + 0.07)),
				PropMeshes._part(PropMeshes._box("eq_pl_emblem", Vector3(0.2, 0.22, 0.05)), trimm, Vector3(0, -hh * 0.02, d * 0.5 + 0.08)),
				PropMeshes._part(PropMeshes._box("eq_pl_belt", Vector3(w + 0.02, 0.09, d + 0.1)), trimm, Vector3(0, -hh * 0.3, 0.0))]
			# Big layered pauldrons: a broad dome + a lower lame skirt, gold rim, big spike.
			for ssd: int in [-1, 1]:
				var px := (shoulder * 0.5) * ssd
				pc.append(PropMeshes._part(PropMeshes._sphere("eq_pauld_dome", 0.27), m, Vector3(px, hh * 0.44, 0.0), Vector3(1.3, 1.0, 1.35)))
				pc.append(PropMeshes._part(PropMeshes._sphere("eq_pauld_lame", 0.23), m, Vector3(px + 0.02 * ssd, hh * 0.28, 0.0), Vector3(1.35, 0.62, 1.4)))
				pc.append(PropMeshes._part(PropMeshes._box("eq_pauld_lip", Vector3(0.42, 0.07, 0.46)), trimm, Vector3(px, hh * 0.2, 0.0)))
				pc.append(PropMeshes._part(PropMeshes._cone("eq_pauld_spike", 0.09, 0.003, 0.42), trimm, Vector3(px + 0.07 * ssd, hh * 0.72, 0.0), Vector3.ONE, Vector3(0, 0, -0.3 * ssd)))
			return pc
		"jerkin":
			# Adventurer's leather vest, sized to wrap the torso (no crop): a jerkin +
			# shoulder yoke, a diagonal bandolier strap, a buckled waist belt and a pouch.
			var hide := equip_material("leather")
			var strap := PropMeshes._mat_from(Color(0.3, 0.2, 0.12), Color(0.18, 0.11, 0.06), Color(0.44, 0.31, 0.18))
			var buckle := equip_material("gold")
			var w := torso.x
			var hh := torso.y
			var d := torso.z
			return [
				PropMeshes._part(PropMeshes._box("eq_jerkin", Vector3(w + 0.06, hh + 0.0, d + 0.06)), hide, Vector3(0, 0.0, 0)),
				PropMeshes._part(PropMeshes._box("eq_jerkin_yoke", Vector3(w + 0.16, 0.16, d + 0.1)), hide, Vector3(0, hh * 0.44, 0)),
				PropMeshes._part(PropMeshes._box("eq_baldric", Vector3(0.09, hh + 0.12, d + 0.06)), strap, Vector3(0, 0.0, 0.0), Vector3.ONE, Vector3(0, 0, 0.5)),
				PropMeshes._part(PropMeshes._box("eq_belt", Vector3(w + 0.1, 0.1, d + 0.08)), strap, Vector3(0, -hh * 0.42, 0)),
				PropMeshes._part(PropMeshes._box("eq_belt_buckle", Vector3(0.1, 0.1, 0.04)), buckle, Vector3(0, -hh * 0.42, d * 0.5 + 0.05)),
				PropMeshes._part(PropMeshes._box("eq_pouch", Vector3(0.13, 0.14, 0.08)), hide, Vector3(0.18, -hh * 0.5, d * 0.5 + 0.03))]
		"robe_top":
			# A full robe that encloses the torso, a shoulder mantle + high collar that
			# hide the neck gap, a red scarf, and a couple of belt straps for layering.
			var trim := equip_material(mat_key, tint.darkened(0.22) if tint.a > 0.0 else Color(0, 0, 0, 0))
			var scarf := PropMeshes._mat_from(Color(0.74, 0.16, 0.14), Color(0.5, 0.08, 0.08), Color(0.86, 0.32, 0.26))
			# Sized to wrap the torso generously (cloth drapes a touch looser than plate).
			var w := torso.x + 0.1
			var hh := torso.y + 0.08
			var d := torso.z + 0.1
			return [
				PropMeshes._part(PropMeshes._box("eq_robetop", Vector3(w, hh, d)), m, Vector3(0, 0.02, 0)),
				PropMeshes._part(PropMeshes._box("eq_robe_mantle", Vector3(w + 0.1, 0.2, d + 0.06)), trim, Vector3(0, hh * 0.44, 0)),
				PropMeshes._part(PropMeshes._box("eq_robe_collar", Vector3(0.26, 0.2, 0.26)), trim, Vector3(0, hh * 0.62, 0)),
				PropMeshes._part(PropMeshes._box("eq_robe_scarf", Vector3(0.14, 0.24, 0.1)), scarf, Vector3(0, hh * 0.15, d * 0.5 + 0.01)),
				PropMeshes._part(PropMeshes._box("eq_robe_strap1", Vector3(w + 0.02, 0.05, d + 0.02)), trim, Vector3(0, -hh * 0.18, 0)),
				PropMeshes._part(PropMeshes._box("eq_robe_strap2", Vector3(w + 0.02, 0.05, d + 0.02)), trim, Vector3(0, -hh * 0.36, 0))]
		"robe_bottom":
			# Long, wide skirt that fully covers the legs to the ground, with a darker
			# layered hem, a waist band, and little curled boot tips peeking out front.
			var hem := equip_material(mat_key, tint.darkened(0.24) if tint.a > 0.0 else Color(0, 0, 0, 0))
			var boot := equip_material("leather")
			return [
				PropMeshes._part(PropMeshes._cone("eq_robebot", 0.52, 0.26, 1.0), m, Vector3(0, -0.5, 0)),
				PropMeshes._part(PropMeshes._cone("eq_robe_hem", 0.56, 0.5, 0.13), hem, Vector3(0, -0.97, 0)),
				PropMeshes._part(PropMeshes._cone("eq_robe_waist", 0.4, 0.34, 0.1), hem, Vector3(0, -0.04, 0)),
				PropMeshes._part(PropMeshes._box("eq_robe_boot", Vector3(0.13, 0.1, 0.2)), boot, Vector3(-0.12, -0.97, 0.15)),
				PropMeshes._part(PropMeshes._box("eq_robe_boot", Vector3(0.13, 0.1, 0.2)), boot, Vector3(0.12, -0.97, 0.15))]
		"cape":
			# Hangs from the shoulders (socket_back) and drapes down past the hips, as
			# wide as the shoulders — scales to the wearer so it never sits oddly.
			var cw := shoulder * 0.92
			var cl := torso.y + 0.55
			return [
				PropMeshes._part(PropMeshes._box("eq_cape", Vector3(cw, cl, 0.05)), m, Vector3(0, -cl * 0.36, -0.03), Vector3.ONE, Vector3(0.16, 0, 0)),
				PropMeshes._part(PropMeshes._box("eq_cape_clasp", Vector3(cw * 0.5, 0.08, 0.06)), equip_material("gold"), Vector3(0, 0.16, -0.02))]
		_:
			return []


## A cape built as a short vertical CHAIN of segment pivots (cape_seg0 -> cape_seg1
## -> ...), each holding one plate, hung from the shoulders. The renderer ripples a
## cheap traveling sine wave down the chain (a few sin() calls, no physics, no
## per-vertex work) so the cape billows and trails — cheap enough for potato builds.
## Sized to the wearer (shoulder width, torso length) so it drapes right on any rig.
static func build_cape(m: Material, profile: Dictionary) -> Node3D:
	var shoulder: float = float(profile.get("shoulder", 0.64))
	var cw := shoulder * 1.02
	# A long, full cape: enough links to reach the ground and pool/drag behind the
	# heels. The renderer's _flow_cape curves it down (gravity) and ripples it gently.
	var segs := 6
	var seg_len := 0.3
	var root := Node3D.new()
	# Static gold clasp at the collar.
	var clasp := MeshInstance3D.new()
	clasp.mesh = PropMeshes._box("eq_cape_clasp", Vector3(cw * 0.5, 0.08, 0.06))
	clasp.material_override = equip_material("gold")
	clasp.position = Vector3(0, 0.12, -0.02)
	clasp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(clasp)
	# The chain: each segment hangs off the bottom of the previous one. A gentle flare
	# toward the hem so it reads as a full, heavy, majestic cape.
	var parent := root
	for i: int in segs:
		var pivot := Node3D.new()
		pivot.name = "cape_seg%d" % i
		pivot.position = Vector3(0, 0.06, -0.05) if i == 0 else Vector3(0, -seg_len, 0)
		parent.add_child(pivot)
		var width := cw * (0.94 + 0.04 * float(i))
		var mi := MeshInstance3D.new()
		mi.mesh = PropMeshes._box("eq_cape_seg%d" % i, Vector3(width, seg_len + 0.03, 0.05))
		mi.material_override = m
		mi.position = Vector3(0, -seg_len * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		parent = pivot
	root.set_meta("cape_segments", segs)
	return root


## Beast-folk biped (gnolls): a hunched, muscular hyena-man with a snouted head,
## perked ears, a fur body + loincloth, and long arms. Uses the humanoid leg_l/r
## + arm_l/r pivots so it walks and swings like a biped. Faces +Z.
static func beastman_rig(spec: Dictionary) -> Node3D:
	var fur: Color = spec.get("fur", Color(0.55, 0.45, 0.32))
	var furm := PropMeshes._mat_from(fur, fur.darkened(0.38), fur.lightened(0.2))
	var furd := PropMeshes._mat_from(fur.darkened(0.3), fur.darkened(0.52), fur.darkened(0.1))
	var light := PropMeshes._mat_from(fur.lightened(0.24), fur.darkened(0.1), fur.lightened(0.4))
	var cloth := PropMeshes._mat_from(Color(0.34, 0.27, 0.19), Color(0.2, 0.15, 0.1), Color(0.46, 0.37, 0.26))
	var claw := PropMeshes._mat_from(Color(0.16, 0.14, 0.13), Color(0.08, 0.07, 0.06), Color(0.26, 0.23, 0.2))
	var eyec := PropMeshes._mat_from(Color(0.95, 0.55, 0.12), Color(0.7, 0.32, 0.05), Color(1.0, 0.78, 0.3))
	var root := Node3D.new()
	# Powerful digitigrade legs with a knee joint (so they bend into a sneaky crouch).
	for side: int in [-1, 1]:
		var knee := _biped_leg(root, side, Vector3(0.16 * side, 0.86, 0), Vector3(0.22, 0.4, 0.24), Vector3(0.16, 0.36, 0.18), furm, "gnleg")
		_attach(knee, PropMeshes._box("gn_paw", Vector3(0.2, 0.12, 0.3)), claw, Vector3(0, -0.4, 0.08))
	_attach(root, PropMeshes._box("gn_loin", Vector3(0.48, 0.28, 0.32)), cloth, Vector3(0, 0.84, 0))
	# The whole brute torso+head hangs off a `spine` pivot at the hips so it can curl
	# into a heavy hunched back (legs stay planted). Child Y is spine-local (world-0.88).
	var spine := _limb(root, "spine", Vector3(0, 0.88, 0))
	# Broad bare torso; lighter belly fur.
	_attach(spine, PropMeshes._box("gn_chest", Vector3(0.52, 0.46, 0.34)), furm, Vector3(0, 0.32, 0.06))
	_attach(spine, PropMeshes._box("gn_belly", Vector3(0.4, 0.3, 0.28)), light, Vector3(0, 0.12, 0.1))
	_attach(spine, PropMeshes._box("gn_shoulders", Vector3(0.64, 0.2, 0.36)), furm, Vector3(0, 0.54, 0.02))
	# Mane on a pivot so the hair-sway swings it down the back of the neck.
	var mane := _limb(spine, "mane", Vector3(0, 0.68, -0.06))
	_attach(mane, PropMeshes._box("gn_mane", Vector3(0.16, 0.34, 0.2)), furd, Vector3(0, -0.06, -0.06), Vector3.ONE, Vector3(0.3, 0, 0))
	# Forward-thrust neck + a hyena head with a long snout and a dark nose.
	_attach(spine, PropMeshes._box("gn_neck", Vector3(0.22, 0.22, 0.26)), furm, Vector3(0, 0.62, 0.12))
	_attach(spine, PropMeshes._box("gn_skull", Vector3(0.3, 0.3, 0.32)), furm, Vector3(0, 0.74, 0.18))
	_attach(spine, PropMeshes._box("gn_snout", Vector3(0.18, 0.16, 0.24)), light, Vector3(0, 0.68, 0.4))
	_attach(spine, PropMeshes._box("gn_nose", Vector3(0.1, 0.09, 0.07)), claw, Vector3(0, 0.7, 0.53))
	_attach(spine, PropMeshes._box("gn_jaw", Vector3(0.16, 0.06, 0.2)), furd, Vector3(0, 0.61, 0.42))
	# Perked, pointed ears + fierce orange eyes.
	for sx: int in [-1, 1]:
		_attach(spine, PropMeshes._cone("gn_ear", 0.08, 0.01, 0.2), furm, Vector3(0.12 * sx, 0.94, 0.12), Vector3.ONE, Vector3(-0.2, 0, 0.3 * sx))
		_attach(spine, PropMeshes._box("gn_eye", Vector3(0.05, 0.05, 0.05)), eyec, Vector3(0.08 * sx, 0.76, 0.34))
	# Long, heavy arms with an elbow joint: fur upper, darker forearm, clawed hand.
	for side2: int in [-1, 1]:
		var el := _biped_arm(spine, side2, Vector3(0.34 * side2, 0.54, 0.02), Vector3(0.17, 0.32, 0.19), Vector3(0.15, 0.3, 0.16), furm, furd, "gnarm")
		_attach(el, PropMeshes._box("gn_hand", Vector3(0.17, 0.15, 0.2)), claw, Vector3(0, -0.34, 0.02))
		_socket(el, "socket_mainhand" if side2 > 0 else "socket_offhand", Vector3(HAND_SOCKET_POS.x * side2, HAND_SOCKET_POS.y, HAND_SOCKET_POS.z))
	_socket(spine, "socket_head", Vector3(0, 0.74, 0.18))
	_socket(spine, "socket_body", Vector3(0, 0.32, 0.06))
	_socket(root, "socket_legs", Vector3(0, 0.86, 0))
	_socket(spine, "socket_back", Vector3(0, 0.46, -0.14))
	root.set_meta("body_profile", {
		"torso": Vector3(0.58, 0.62, 0.42), "head": Vector3(0.36, 0.36, 0.4),
		"shoulder": 0.72, "hips": Vector3(0.48, 0.28, 0.32)})
	return root


# ---------------------------------------------------------------- shadows ----

## A soft round blob shadow (A Short Hike style): a flat ground quad with a radial
## dark-to-clear gradient, dropped under each mover so it reads as grounded. The
## renderer scales/orients it per creature and keeps it pinned to the ground.
static func enemy_body_type(name: String) -> String:
	var n := name.to_lower()
	# Order matters: more specific creature families are tested before the farm animals and the
	# humanoid fallback, and "batter"(slime) is tested before "bat", "vaerthrax"(dragon) before any
	# slime token, so substrings can't cross-match.
	for kw: String in ["dragon", "drake", "wyvern", "wyrm", "vaerthrax", "vermithrax", "glazarth", "twinfang"]:
		if n.contains(kw):
			return "dragon"
	for kw: String in ["viper", "serpent", "snake", "cobra", "adder", "naga"]:
		if n.contains(kw):
			return "serpent"
	for kw: String in ["ooze", "slime", "jelly", "pudding", "blob", "core", "elemental", "batter", "gel", "malachite"]:
		if n.contains(kw):
			return "slime"
	for kw: String in ["ghost", "wraith", "spectre", "specter", "phantom", "grim", "revenant", "wight", "spirit", "banshee", "poltergeist"]:
		if n.contains(kw):
			return "wraith"
	for kw: String in ["eye", "beholder", "gaze", "devourer"]:
		if n.contains(kw):
			return "eye"
	for kw: String in ["spider", "widow", "arachnid", "weaver", "tarantula"]:
		if n.contains(kw):
			return "spider"
	for kw: String in ["scarab", "beetle", "weevil"]:
		if n.contains(kw):
			return "scarab"
	for kw: String in ["crab", "shellcrush", "pincer", "lobster"]:
		if n.contains(kw):
			return "crab"
	for kw: String in ["crawler", "centipede", "worm", "feeder", "hands", "maggot", "grub"]:
		if n.contains(kw):
			return "crawler"
	if n.contains("bat"):
		return "bat"
	if n.contains("bear") or n.contains("ursine"):
		return "bear"
	for kw: String in ["wolf", "wolves", "hound", "dog", "fox", "amaruq", "jackal", "warg", "lupine"]:
		if n.contains(kw):
			return "wolf"
	for kw: String in ["boar", "hog", "pig", "swine"]:
		if n.contains(kw):
			return "boar"
	# NOTE: no bare "ox" — it matches "t-ox-ic" etc. Cows are caught by their own words.
	if n.contains("cow") or n.contains("oxen") or n.contains("bull") or n.contains("cattle") or n.contains("calf"):
		return "cow"
	if n.contains("sheep") or n.contains("ram") or n.contains("lamb"):
		return "sheep"
	if n.contains("goat") or n.contains("kid"):
		return "goat"
	if n.contains("mole"):
		return "mole"
	if n.contains("chicken") or n.contains("hen") or n.contains("rooster") or n.contains("fowl") or n.contains("chick"):
		return "bird"
	return "humanoid"


## Build the right rig for an enemy node and tag it for animation.
static func enemy_rig(e: Node) -> Node3D:
	var name := str(e.get("label"))
	if name.is_empty():
		name = str(Dictionary(e.get("action")).get("name", ""))
	var type := enemy_body_type(name)
	var n := name.to_lower()
	var boss := bool(e.get("is_boss"))
	var rider := n.contains("rider")
	# Per-species base size (a human ≈ 1.0): cows tower, chickens and moles are small.
	var size := 1.0
	var node: Node3D
	match type:
		"wolf":
			var dark := n.contains("black") or n.contains("toxic") or n.contains("cave")
			var hide := Color(0.30, 0.31, 0.34) if dark else Color(0.55, 0.55, 0.60)
			node = quadruped_rig({"hide": hide, "belly": hide.lightened(0.32), "ears": "perk", "tail": "bushy", "snout": 0.28})
			size = 1.2 if n.contains("amaruq") else 1.0
		"boar":
			var pinkish := n.contains("pig")
			var hide := Color(0.90, 0.66, 0.70) if pinkish else Color(0.40, 0.31, 0.27)
			node = quadruped_rig({
				"hide": hide, "belly": hide.darkened(0.12), "ears": "perk", "tail": "short",
				"snout": 0.22, "tusks": not pinkish, "humped": not pinkish, "snout_pink": pinkish})
			size = 0.9 if pinkish else 1.05
		"cow":
			node = quadruped_rig({"hide": Color(0.66, 0.46, 0.32), "belly": Color(0.84, 0.81, 0.76), "ears": "floppy", "horns": "cow", "tail": "tuft", "snout": 0.2})
			size = 1.4
		"sheep":
			node = quadruped_rig({"hide": Color(0.92, 0.91, 0.88), "belly": Color(0.88, 0.87, 0.84), "ears": "floppy", "tail": "short", "snout": 0.14, "wool": true, "head_dark": true})
			size = 0.98
		"goat":
			node = quadruped_rig({"hide": Color(0.80, 0.78, 0.80), "belly": Color(0.88, 0.87, 0.86), "ears": "perk", "horns": "goat", "tail": "short", "snout": 0.16, "beard": true})
			size = 0.9
		"mole":
			node = quadruped_rig({"hide": Color(0.34, 0.27, 0.31), "belly": Color(0.46, 0.39, 0.42), "ears": "none", "tail": "short", "snout": 0.22})
			size = 0.6
		"bird":
			var brown := n.contains("mumma") or n.contains("momma")
			node = bird_rig({"body": Color(0.84, 0.72, 0.58) if brown else Color(0.93, 0.89, 0.80)})
			size = 0.62
		"dragon":
			var dt := _enemy_tint(n, Color(0.34, 0.5, 0.38))
			node = dragon_rig({"scale": dt, "wyvern": n.contains("wyvern")})
			size = 1.2 if n.contains("wyvern") else 1.5
		"serpent":
			node = serpent_rig({"scale": _enemy_tint(n, Color(0.32, 0.54, 0.3))})
			size = 1.0
		"slime":
			node = slime_rig({"col": _enemy_tint(n, Color(0.4, 0.7, 0.45))})
			size = 0.95
		"wraith":
			var wt := _enemy_tint(n, Color(0.42, 0.47, 0.58))
			node = wraith_rig({"robe": wt, "glow": Color(0.7, 0.95, 1.0) if wt.b > wt.r else Color(1.0, 0.7, 0.4)})
			size = 1.0
		"eye":
			node = eye_rig({"iris": _enemy_tint(n, Color(0.85, 0.7, 0.2)), "flesh": _enemy_tint(n, Color(0.7, 0.4, 0.46))})
			size = 0.9
		"spider":
			node = spider_rig({"chitin": _enemy_tint(n, Color(0.16, 0.16, 0.2))})
			size = 0.9
		"scarab":
			node = scarab_rig({"shell": _enemy_tint(n, Color(0.22, 0.26, 0.34))})
			size = 0.82
		"crawler":
			node = crawler_rig({"skin": _enemy_tint(n, Color(0.55, 0.42, 0.46))})
			size = 0.85
		"crab":
			node = crab_rig({"shell": _enemy_tint(n, Color(0.78, 0.34, 0.26))})
			size = 0.95
		"bat":
			node = bat_rig({"fur": _enemy_tint(n, Color(0.28, 0.24, 0.3))})
			size = 0.5
		"bear":
			var bt := _enemy_tint(n, Color(0.36, 0.27, 0.22))
			node = quadruped_rig({"hide": bt, "belly": bt.lightened(0.24), "ears": "perk", "tail": "short", "snout": 0.24})
			size = 1.35
		_:
			type = "humanoid"
			if n.contains("gnoll"):
				var dark_gn := n.contains("toxic") or n.contains("dark")
				node = beastman_rig({"fur": Color(0.42, 0.45, 0.36) if dark_gn else Color(0.58, 0.47, 0.33)})
				size = 1.02
			elif n.contains("goblin") or n.contains("hob"):
				node = figure_rig(Color(0.40, 0.31, 0.23), Color(0.44, 0.66, 0.34))
				size = 0.86
			elif n.contains("skelet") or n.contains("bone"):
				node = figure_rig(Color(0.62, 0.60, 0.56), Color(0.86, 0.85, 0.80))
			else:
				node = figure_rig(PixelPalette.pal("outfit_b"), PixelPalette.pal("skin_a"))
	size *= _variant_size(n)
	if rider and type == "wolf":
		_add_rider(node)
	node.set_meta("body3d", type)
	node.set_meta("base_scale", size * (1.22 if boss else 1.0))
	# Characteristic posture: goblins stoop forward with arms hanging low; gnolls
	# (beastman) are hunched brutes; skeletons lurch a little; others stand looser.
	# Posture is a curved BACK (hunch at the spine), not a whole-body forward tilt:
	# `lean` stays near-zero so they don't look like they're falling forward; `hunch`
	# rounds the upper spine for a natural stoop.
	if type == "humanoid":
		if n.contains("goblin") or n.contains("hob"):
			# Goblins get their own twitchy-skulk gait (see _pose_goblin); the lean/
			# hunch/crouch metas are only used by the fallback humanoid pose.
			node.set_meta("gait", "goblin")
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.42)
			node.set_meta("arm_rest", 0.34)
			node.set_meta("crouch", 0.3)
		elif n.contains("skelet") or n.contains("bone"):
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.16)
			node.set_meta("arm_rest", 0.12)
			node.set_meta("crouch", 0.18)
		else:
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.12)
			node.set_meta("arm_rest", 0.12)
			node.set_meta("crouch", 0.14)
		if n.contains("gnoll"):   # beastman gets its own predatory-prowl gait (_pose_gnoll)
			node.set_meta("gait", "gnoll")
			node.set_meta("lean", 0.02)
			node.set_meta("hunch", 0.5)
			node.set_meta("arm_rest", 0.28)
			node.set_meta("crouch", 0.5)
	# Visible gear from the enemy's combat archetype (skipped on rigs without the
	# matching sockets — beasts/birds just show nothing).
	var loadout := EquipLoadout.for_enemy(name, int(Dictionary(e.get("action")).get("level", 1)))
	apply_equipment(node, loadout)
	# A staff-wielder grips its planted staff (mainhand reaches forward-down).
	var mainhand: Dictionary = loadout.get("mainhand", {})
	if str(mainhand.get("kind", "")) in ["staff", "raven_staff", "wand"]:
		node.set_meta("pose", "staff")
	return node


## Name-based size multiplier layered on the per-species base: 'Giant'/'Mega'/
## 'Dire' tower, 'Mumma'/'Momma'/'Alpha' are bigger parents, young ones shrink.
static func _variant_size(n: String) -> float:
	for kw: String in ["giant", "mega", "great", "elder", "ancient", "king", "dire"]:
		if n.contains(kw):
			return 1.35
	for kw2: String in ["mumma", "momma", "mother", "queen", "alpha"]:
		if n.contains(kw2):
			return 1.24
	for kw3: String in ["brawler", "brute", "big"]:
		if n.contains(kw3):
			return 1.12
	for kw4: String in ["baby", "young", "pup", "runt", "mini", "tiny"]:
		if n.contains(kw4):
			return 0.72
	return 1.0


## Thematic tint from the enemy name so colour-variants of one archetype read differently (a Frost
## Wyvern is icy blue, a Blood Dragon crimson…). Falls back to the archetype's base colour.
static func _enemy_tint(n: String, base: Color) -> Color:
	for kw: String in ["frost", "ice", "frozen", "glaci", "snow", "brumal", "aqua", "water", "pale", "azure", "winter"]:
		if n.contains(kw):
			return Color(0.55, 0.72, 0.86)
	for kw2: String in ["fire", "ember", "flame", "crimson", "blood", "lava", "magma", "sun", "scorch"]:
		if n.contains(kw2):
			return Color(0.8, 0.3, 0.22)
	for kw3: String in ["toxic", "poison", "viridian", "emerald", "venom", "blight", "bloom", "verdant", "ooz", "plague", "virulent"]:
		if n.contains(kw3):
			return Color(0.42, 0.66, 0.32)
	for kw4: String in ["ebon", "onyx", "dark", "shadow", "night", "void", "obsidian", "black"]:
		if n.contains(kw4):
			return Color(0.2, 0.2, 0.26)
	for kw5: String in ["gold", "royal", "sand", "dune", "desert", "amber", "brass", "tomb", "bone"]:
		if n.contains(kw5):
			return Color(0.82, 0.66, 0.3)
	for kw6: String in ["purple", "warped", "entropic", "arcane", "onyx", "amethyst"]:
		if n.contains(kw6):
			return Color(0.5, 0.34, 0.66)
	return base


## Reusable four-legged beast. Legs hang off hip pivots (leg_fl/leg_fr/leg_bl/
## leg_br) and the tail off `tail`, so the gait can swing them. spec keys: hide,
## belly (Color), snout (len), ears (perk|floppy|none), horns (cow|goat|none),
## tail (short|bushy|tuft|none), and flags wool/humped/tusks/beard/head_dark.
static func quadruped_rig(spec: Dictionary) -> Node3D:
	var hide: Color = spec.get("hide", Color(0.6, 0.5, 0.4))
	var belly: Color = spec.get("belly", hide.lightened(0.2))
	var snout_len: float = float(spec.get("snout", 0.2))
	var hidem := PropMeshes._mat_from(hide, hide.darkened(0.34), hide.lightened(0.2))
	var bellym := PropMeshes._mat_from(belly, belly.darkened(0.3), belly.lightened(0.18))
	var darkm := PropMeshes._mat_from(hide.darkened(0.42), hide.darkened(0.6), hide.darkened(0.16))
	var eyem := PropMeshes._mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.12, 0.12, 0.14))
	var head_dark: bool = bool(spec.get("head_dark", false))
	var headm := darkm if head_dark else hidem
	var root := Node3D.new()
	# Torso — a fluffy sphere for woolly beasts, a chunky box otherwise.
	if bool(spec.get("wool", false)):
		_attach(root, PropMeshes._sphere("q_wool", 0.44), hidem, Vector3(0, 0.66, -0.02), Vector3(1.2, 1.0, 1.4))
	else:
		_attach(root, PropMeshes._box("q_body", Vector3(0.46, 0.44, 0.96)), hidem, Vector3(0, 0.62, 0))
		_attach(root, PropMeshes._box("q_belly", Vector3(0.4, 0.2, 0.84)), bellym, Vector3(0, 0.47, 0))
	if bool(spec.get("humped", false)):
		# A subtle shoulder rise (boar), blended into the back rather than a saddle.
		_attach(root, PropMeshes._sphere("q_hump", 0.26), hidem, Vector3(0, 0.74, 0.2), Vector3(1.04, 0.62, 0.9))
	# Neck + head at the front (+Z), with a snout, eyes, optional features.
	_attach(root, PropMeshes._box("q_neck", Vector3(0.26, 0.3, 0.3)), hidem, Vector3(0, 0.66, 0.5))
	_attach(root, PropMeshes._box("q_head", Vector3(0.34, 0.34, 0.36)), headm, Vector3(0, 0.78, 0.66))
	if snout_len > 0.0:
		var snm := PropMeshes._mat_from(Color(0.9, 0.62, 0.66), Color(0.7, 0.42, 0.46), Color(0.95, 0.74, 0.78)) if bool(spec.get("snout_pink", false)) else headm
		_attach(root, PropMeshes._box("q_snout_%d" % int(snout_len * 100), Vector3(0.22, 0.16, snout_len)), snm, Vector3(0, 0.71, 0.82 + snout_len * 0.4))
	_attach(root, PropMeshes._box("q_eye", Vector3(0.05, 0.05, 0.05)), eyem, Vector3(0.1, 0.84, 0.82))
	_attach(root, PropMeshes._box("q_eye", Vector3(0.05, 0.05, 0.05)), eyem, Vector3(-0.1, 0.84, 0.82))
	match str(spec.get("ears", "none")):
		"perk":
			for sx: int in [-1, 1]:
				_attach(root, PropMeshes._cone("q_ear_perk", 0.09, 0.01, 0.18), headm, Vector3(0.13 * sx, 0.98, 0.58), Vector3.ONE, Vector3(-0.2, 0, 0.3 * sx))
		"floppy":
			for sx2: int in [-1, 1]:
				_attach(root, PropMeshes._box("q_ear_flop", Vector3(0.08, 0.2, 0.1)), headm, Vector3(0.2 * sx2, 0.78, 0.62), Vector3.ONE, Vector3(0, 0, 0.5 * sx2))
	match str(spec.get("horns", "none")):
		"cow":
			var hornm := PropMeshes._mat_from(Color(0.86, 0.82, 0.72), Color(0.62, 0.58, 0.5), Color(0.95, 0.92, 0.84))
			for sx3: int in [-1, 1]:
				_attach(root, PropMeshes._cone("q_horn_cow", 0.06, 0.01, 0.2), hornm, Vector3(0.16 * sx3, 0.96, 0.6), Vector3.ONE, Vector3(0, 0, 0.7 * sx3))
		"goat":
			var hornm2 := PropMeshes._mat_from(Color(0.55, 0.5, 0.46), Color(0.36, 0.32, 0.3), Color(0.68, 0.63, 0.58))
			for sx4: int in [-1, 1]:
				_attach(root, PropMeshes._cone("q_horn_goat", 0.05, 0.01, 0.28), hornm2, Vector3(0.1 * sx4, 0.96, 0.52), Vector3.ONE, Vector3(1.1, 0, 0.15 * sx4))
	if bool(spec.get("tusks", false)):
		var tuskm := PropMeshes._mat_from(Color(0.9, 0.88, 0.8), Color(0.7, 0.68, 0.6), Color(0.96, 0.95, 0.9))
		for sx5: int in [-1, 1]:
			_attach(root, PropMeshes._cone("q_tusk", 0.03, 0.005, 0.12), tuskm, Vector3(0.09 * sx5, 0.66, 0.9), Vector3.ONE, Vector3(-0.6, 0, 0))
	if bool(spec.get("beard", false)):
		_attach(root, PropMeshes._box("q_beard", Vector3(0.1, 0.18, 0.06)), bellym, Vector3(0, 0.6, 0.78))
	_add_tail(root, str(spec.get("tail", "none")), hidem, darkm)
	# Four legs at the corners, each with a knee joint so the trot flexes the legs
	# instead of swinging stiff posts. hip pivots leg_fl/fr/bl/br, knees knee_fl/...
	for ld: Array in [["leg_fl", "knee_fl", -0.2, 0.32], ["leg_fr", "knee_fr", 0.2, 0.32], ["leg_bl", "knee_bl", -0.2, -0.32], ["leg_br", "knee_br", 0.2, -0.32]]:
		var knee := _joint_limb(root, str(ld[0]), str(ld[1]), Vector3(float(ld[2]), 0.46, float(ld[3])), Vector3(0.14, 0.24, 0.16), Vector3(0.13, 0.22, 0.14), hidem, "qleg")
		_attach(knee, PropMeshes._box("q_hoof", Vector3(0.15, 0.1, 0.17)), darkm, Vector3(0, -0.24, 0.02))
	# Beasts only support a body slot (barding/saddle) — no hands/head gear.
	_socket(root, "socket_body", Vector3(0, 0.66, 0))
	return root


static func _add_tail(root: Node3D, style: String, hidem: Material, darkm: Material) -> void:
	if style == "none":
		return
	var tail := _limb(root, "tail", Vector3(0, 0.66, -0.5))
	match style:
		"short":
			_attach(tail, PropMeshes._box("q_tail_s", Vector3(0.1, 0.1, 0.24)), hidem, Vector3(0, -0.02, -0.1), Vector3.ONE, Vector3(0.5, 0, 0))
		"bushy":
			_attach(tail, PropMeshes._cone("q_tail_b", 0.13, 0.03, 0.4), hidem, Vector3(0, 0.0, -0.2), Vector3.ONE, Vector3(2.3, 0, 0))
		"tuft":
			_attach(tail, PropMeshes._box("q_tail_t", Vector3(0.06, 0.34, 0.06)), hidem, Vector3(0, -0.16, 0))
			_attach(tail, PropMeshes._sphere("q_tail_tuft", 0.08), darkm, Vector3(0, -0.32, 0))


static func _add_rider(node: Node3D) -> void:
	var rskin := PropMeshes._mat_from(Color(0.44, 0.66, 0.34), Color(0.3, 0.5, 0.24), Color(0.56, 0.78, 0.42))
	var rcloth := PropMeshes._mat_from(Color(0.4, 0.3, 0.22), Color(0.28, 0.2, 0.14), Color(0.52, 0.42, 0.3))
	_attach(node, PropMeshes._box("r_torso", Vector3(0.26, 0.32, 0.22)), rcloth, Vector3(0, 1.06, -0.04))
	_attach(node, PropMeshes._box("r_head", Vector3(0.22, 0.22, 0.22)), rskin, Vector3(0, 1.32, -0.04))
	for sx: int in [-1, 1]:
		_attach(node, PropMeshes._cone("r_ear", 0.05, 0.005, 0.13), rskin, Vector3(0.15 * sx, 1.34, -0.04), Vector3.ONE, Vector3(0, 0, 0.6 * sx))


## Reusable two-legged bird (chicken). Legs hang off leg_l/leg_r hip pivots.
static func bird_rig(spec: Dictionary) -> Node3D:
	var body: Color = spec.get("body", Color(0.93, 0.89, 0.8))
	var comb: Color = spec.get("comb", Color(0.8, 0.2, 0.16))
	var beak: Color = spec.get("beak", Color(0.92, 0.62, 0.18))
	var bodym := PropMeshes._mat_from(body, body.darkened(0.3), body.lightened(0.16))
	var combm := PropMeshes._mat_from(comb, comb.darkened(0.3), comb.lightened(0.2))
	var beakm := PropMeshes._mat_from(beak, beak.darkened(0.3), beak.lightened(0.2))
	var legm := PropMeshes._mat_from(Color(0.9, 0.55, 0.18), Color(0.6, 0.35, 0.1), Color(0.95, 0.7, 0.3))
	var eyem := PropMeshes._mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.12, 0.12, 0.14))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("b_body", 0.26), bodym, Vector3(0, 0.36, -0.02), Vector3(1.0, 1.05, 1.25))
	_attach(root, PropMeshes._sphere("b_head", 0.17), bodym, Vector3(0, 0.56, 0.14))
	_attach(root, PropMeshes._cone("b_beak", 0.07, 0.005, 0.16), beakm, Vector3(0, 0.55, 0.32), Vector3.ONE, Vector3(1.5708, 0, 0))
	_attach(root, PropMeshes._box("b_comb", Vector3(0.06, 0.11, 0.16)), combm, Vector3(0, 0.72, 0.12))
	_attach(root, PropMeshes._box("b_wattle", Vector3(0.05, 0.08, 0.04)), combm, Vector3(0, 0.47, 0.27))
	_attach(root, PropMeshes._box("b_eye", Vector3(0.04, 0.04, 0.04)), eyem, Vector3(0.09, 0.58, 0.24))
	_attach(root, PropMeshes._box("b_eye", Vector3(0.04, 0.04, 0.04)), eyem, Vector3(-0.09, 0.58, 0.24))
	_attach(root, PropMeshes._box("b_tail", Vector3(0.2, 0.16, 0.1)), bodym, Vector3(0, 0.46, -0.26), Vector3.ONE, Vector3(-0.5, 0, 0))
	_attach(root, PropMeshes._box("b_wing", Vector3(0.07, 0.18, 0.26)), bodym, Vector3(0.24, 0.4, -0.02))
	_attach(root, PropMeshes._box("b_wing", Vector3(0.07, 0.18, 0.26)), bodym, Vector3(-0.24, 0.4, -0.02))
	for sx: int in [-1, 1]:
		var leg := _limb(root, "leg_l" if sx < 0 else "leg_r", Vector3(0.1 * sx, 0.24, 0))
		_attach(leg, PropMeshes._box("b_leg", Vector3(0.05, 0.24, 0.05)), legm, Vector3(0, -0.12, 0))
		_attach(leg, PropMeshes._box("b_foot", Vector3(0.14, 0.04, 0.16)), legm, Vector3(0, -0.24, 0.03))
	return root


static func _attach(parent: Node3D, mesh: Mesh, mat: Material, off: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = off
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)


static func _limb(parent: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pivot_name
	n.position = pos
	parent.add_child(n)
	return n


## A two-segment limb: an upper bone on a named pivot + a lower bone on a named
## joint pivot nested under it, so the renderer can flex the joint (knee/elbow/hock).
## Returns the joint node so the caller attaches the foot/hand below it.
static func _joint_limb(root: Node3D, pivot: String, joint: String, base: Vector3, upper: Vector3, lower: Vector3, mat: Material, key: String) -> Node3D:
	var p := _limb(root, pivot, base)
	_attach(p, PropMeshes._box(key + "_up", upper), mat, Vector3(0, -upper.y * 0.5, 0))
	var j := _limb(p, joint, Vector3(0, -upper.y, 0))
	_attach(j, PropMeshes._box(key + "_lo", lower), mat, Vector3(0, -lower.y * 0.5, 0.01))
	return j


## A two-segment leg (thigh on a leg_l/leg_r hip pivot + shin on a knee_l/knee_r
## pivot) for the bent-leg walk and crouch. Returns the knee node for the foot/boot.
static func _biped_leg(root: Node3D, side: int, hip: Vector3, thigh: Vector3, shin: Vector3, mat: Material, key: String) -> Node3D:
	return _joint_limb(root, "leg_l" if side < 0 else "leg_r", "knee_l" if side < 0 else "knee_r", hip, thigh, shin, mat, key)


## A two-segment arm: an upper arm on a shoulder pivot (arm_l/arm_r) + a forearm on
## an elbow pivot (elbow_l/elbow_r) so the renderer can bend the elbow. Returns the
## elbow node so the caller attaches the hand and (for the main hand) a weapon socket.
static func _biped_arm(root: Node3D, side: int, shoulder: Vector3, upper: Vector3, fore: Vector3, upper_mat: Material, fore_mat: Material, key: String) -> Node3D:
	var sh := _limb(root, "arm_l" if side < 0 else "arm_r", shoulder)
	_attach(sh, PropMeshes._box(key + "_up", upper), upper_mat, Vector3(0, -upper.y * 0.5, 0))
	var el := _limb(sh, "elbow_l" if side < 0 else "elbow_r", Vector3(0, -upper.y, 0))
	_attach(el, PropMeshes._box(key + "_fo", fore), fore_mat, Vector3(0, -fore.y * 0.5, 0))
	return el


# ─────────────────────────── new creature archetypes ───────────────────────────
# Each builds a low-poly rig with NAMED PIVOTS that the matching pose in mover_rig.gd swings
# (wings, tail segments, legs, claws, tentacles…). The body3d meta set in enemy_rig routes the
# right pose; base_scale + per-name colour come from enemy_rig so variants share one builder.

static func _tri_mat(c: Color) -> ShaderMaterial:
	return PropMeshes._mat_from(c, c.darkened(0.34), c.lightened(0.2))


## Winged dragon / drake / wyvern. Pivots: neck, wing_l, wing_r, tail (+tail2), leg_*.
## spec: scale/belly/wing (Color), wyvern (bool → rear legs only).
static func dragon_rig(spec: Dictionary) -> Node3D:
	var scl: Color = spec.get("scale", Color(0.34, 0.5, 0.38))
	var belly: Color = spec.get("belly", scl.lightened(0.34))
	var wing: Color = spec.get("wing", scl.darkened(0.16))
	var bipedal := bool(spec.get("wyvern", false))
	var bodym := _tri_mat(scl)
	var bellym := _tri_mat(belly)
	var wingm := _tri_mat(wing)
	var hornm := _tri_mat(Color(0.9, 0.86, 0.74))
	var eyem := PropMeshes._mat_from(Color(0.97, 0.8, 0.2), Color(0.6, 0.4, 0.08), Color(1.0, 0.92, 0.45))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("dr_body", 0.4), bodym, Vector3(0, 0.74, 0), Vector3(1.0, 0.92, 1.55))
	_attach(root, PropMeshes._box("dr_belly", Vector3(0.42, 0.2, 1.04)), bellym, Vector3(0, 0.58, 0.02))
	var neck := _limb(root, "neck", Vector3(0, 0.9, 0.52))
	_attach(neck, PropMeshes._box("dr_neck", Vector3(0.22, 0.52, 0.28)), bodym, Vector3(0, 0.18, 0.05), Vector3.ONE, Vector3(-0.55, 0, 0))
	_attach(neck, PropMeshes._box("dr_head", Vector3(0.3, 0.26, 0.4)), bodym, Vector3(0, 0.46, 0.26))
	_attach(neck, PropMeshes._cone("dr_snout", 0.12, 0.04, 0.22), bodym, Vector3(0, 0.43, 0.5), Vector3.ONE, Vector3(1.5708, 0, 0))
	for sx: int in [-1, 1]:
		_attach(neck, PropMeshes._cone("dr_horn", 0.05, 0.004, 0.24), hornm, Vector3(0.1 * sx, 0.62, 0.16), Vector3.ONE, Vector3(-0.5, 0, 0.35 * sx))
		_attach(neck, PropMeshes._sphere("dr_eye", 0.05), eyem, Vector3(0.12 * sx, 0.5, 0.4))
	for sw: int in [-1, 1]:
		var w := _limb(root, "wing_l" if sw < 0 else "wing_r", Vector3(0.16 * sw, 0.96, -0.02))
		_attach(w, PropMeshes._box("dr_wbone", Vector3(0.06, 0.06, 0.56)), wingm, Vector3(0.3 * sw, 0.02, -0.12), Vector3.ONE, Vector3(0, 0.5 * sw, 0))
		_attach(w, PropMeshes._box("dr_wmem", Vector3(0.74, 0.03, 0.66)), wingm, Vector3(0.56 * sw, 0.0, -0.18))
	var tail := _limb(root, "tail", Vector3(0, 0.72, -0.64))
	_attach(tail, PropMeshes._cone("dr_tail1", 0.17, 0.1, 0.46), bodym, Vector3(0, 0, -0.23), Vector3.ONE, Vector3(1.5708, 0, 0))
	var tail2 := _limb(tail, "tail2", Vector3(0, 0, -0.46))
	_attach(tail2, PropMeshes._cone("dr_tail2", 0.1, 0.015, 0.56), bodym, Vector3(0, 0, -0.28), Vector3.ONE, Vector3(1.5708, 0, 0))
	var legs := [["leg_bl", -0.24, -0.32], ["leg_br", 0.24, -0.32]]
	if not bipedal:
		legs.append_array([["leg_fl", -0.26, 0.34], ["leg_fr", 0.26, 0.34]])
	for ld: Array in legs:
		var leg := _limb(root, str(ld[0]), Vector3(float(ld[1]), 0.48, float(ld[2])))
		_attach(leg, PropMeshes._box("dr_thigh", Vector3(0.16, 0.42, 0.18)), bodym, Vector3(0, -0.21, 0))
		_attach(leg, PropMeshes._box("dr_claw", Vector3(0.22, 0.1, 0.26)), bodym, Vector3(0, -0.44, 0.05))
	return root


## Legless serpent / viper. A forward chain of segment pivots (seg0..seg4) the slither wave runs
## down, tapering to the tail, wedge head + eyes at the front. spec: scale (Color).
static func serpent_rig(spec: Dictionary) -> Node3D:
	var scl: Color = spec.get("scale", Color(0.32, 0.54, 0.3))
	var bodym := _tri_mat(scl)
	var bellym := _tri_mat(scl.lightened(0.3))
	var eyem := PropMeshes._mat_from(Color(0.95, 0.78, 0.16), Color(0.6, 0.4, 0.06), Color(1.0, 0.9, 0.4))
	var root := Node3D.new()
	var radii := [0.2, 0.18, 0.15, 0.12, 0.09]
	var parent := root
	for i: int in radii.size():
		var seg := _limb(parent, "seg%d" % i, Vector3(0, 0.2 if i == 0 else 0.0, 0.0 if i == 0 else 0.34))
		_attach(seg, PropMeshes._sphere("snk_seg%d" % i, float(radii[i])), bodym, Vector3(0, 0, 0.17), Vector3(1.1, 0.85, 1.35))
		parent = seg
	_attach(parent, PropMeshes._box("snk_head", Vector3(0.24, 0.16, 0.3)), bodym, Vector3(0, 0.03, 0.36))
	_attach(parent, PropMeshes._box("snk_jaw", Vector3(0.2, 0.06, 0.18)), bellym, Vector3(0, -0.04, 0.42))
	for sx: int in [-1, 1]:
		_attach(parent, PropMeshes._sphere("snk_eye", 0.04), eyem, Vector3(0.08 * sx, 0.09, 0.4))
	return root


## Gelatinous blob (ooze / slime / elemental / core). No limbs — the pose squashes & jiggles the
## "blob" pivot. A dome + inner core + bubbles + dot eyes. spec: col (Color).
static func slime_rig(spec: Dictionary) -> Node3D:
	var col: Color = spec.get("col", Color(0.4, 0.7, 0.45))
	var bodym := _tri_mat(col)
	var litem := _tri_mat(col.lightened(0.28))
	var eyem := PropMeshes._mat_from(Color(0.08, 0.09, 0.1), Color(0.03, 0.03, 0.04), Color(0.16, 0.16, 0.18))
	var root := Node3D.new()
	var blob := _limb(root, "blob", Vector3(0, 0.0, 0))
	_attach(blob, PropMeshes._sphere("sl_body", 0.46), bodym, Vector3(0, 0.4, 0), Vector3(1.15, 0.92, 1.15))
	_attach(blob, PropMeshes._sphere("sl_core", 0.2), litem, Vector3(0, 0.34, 0.04))
	_attach(blob, PropMeshes._sphere("sl_bub", 0.09), litem, Vector3(0.18, 0.56, 0.14))
	_attach(blob, PropMeshes._sphere("sl_bub", 0.06), litem, Vector3(-0.14, 0.46, 0.2))
	for sx: int in [-1, 1]:
		_attach(blob, PropMeshes._sphere("sl_eye", 0.06), eyem, Vector3(0.13 * sx, 0.46, 0.34))
	return root


## Floating wraith / ghost / spirit. A lampshade robe tapering to a wisp (no legs), hood, glowing
## eyes, and sleeved arms on arm_l/arm_r pivots the pose wavers. spec: robe/glow (Color).
static func wraith_rig(spec: Dictionary) -> Node3D:
	var robe: Color = spec.get("robe", Color(0.42, 0.47, 0.58))
	var robem := _tri_mat(robe)
	var darkm := _tri_mat(robe.darkened(0.34))
	var glow: Color = spec.get("glow", Color(0.6, 0.9, 1.0))
	var glowm := PropMeshes._mat_from(glow, glow.darkened(0.3), glow.lightened(0.3))
	var root := Node3D.new()
	_attach(root, PropMeshes._cone("wr_body", 0.02, 0.3, 0.96), robem, Vector3(0, 0.52, 0))
	_attach(root, PropMeshes._sphere("wr_hood", 0.21), robem, Vector3(0, 1.06, 0))
	_attach(root, PropMeshes._box("wr_face", Vector3(0.2, 0.2, 0.05)), darkm, Vector3(0, 1.02, 0.16))
	for sx: int in [-1, 1]:
		_attach(root, PropMeshes._sphere("wr_eye", 0.04), glowm, Vector3(0.06 * sx, 1.04, 0.2))
	for sa: int in [-1, 1]:
		var arm := _limb(root, "arm_l" if sa < 0 else "arm_r", Vector3(0.24 * sa, 0.92, 0.02))
		_attach(arm, PropMeshes._cone("wr_arm", 0.09, 0.04, 0.44), robem, Vector3(0, -0.2, 0.04), Vector3.ONE, Vector3(PI, 0, 0))
		_attach(arm, PropMeshes._sphere("wr_hand", 0.06), darkm, Vector3(0, -0.42, 0.06))
	return root


## Floating eyeball aberration (the eye / ghastly eyes / devourer). Sclera + iris + pupil, a flesh
## brow, and four dangling tentacle pivots (tent0..tent3) the pose wavers. spec: iris/flesh (Color).
static func eye_rig(spec: Dictionary) -> Node3D:
	var iris: Color = spec.get("iris", Color(0.85, 0.7, 0.2))
	var flesh: Color = spec.get("flesh", Color(0.7, 0.4, 0.46))
	var scleram := _tri_mat(Color(0.92, 0.9, 0.86))
	var irism := PropMeshes._mat_from(iris, iris.darkened(0.4), iris.lightened(0.3))
	var pupm := PropMeshes._mat_from(Color(0.05, 0.05, 0.06), Color(0.02, 0.02, 0.03), Color(0.1, 0.1, 0.12))
	var fleshm := _tri_mat(flesh)
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("ey_ball", 0.4), scleram, Vector3(0, 0.95, 0))
	_attach(root, PropMeshes._sphere("ey_iris", 0.2), irism, Vector3(0, 0.95, 0.3), Vector3(1, 1, 0.5))
	_attach(root, PropMeshes._sphere("ey_pupil", 0.1), pupm, Vector3(0, 0.95, 0.38), Vector3(1, 1, 0.5))
	_attach(root, PropMeshes._box("ey_brow", Vector3(0.52, 0.13, 0.42)), fleshm, Vector3(0, 1.26, 0.02), Vector3.ONE, Vector3(-0.3, 0, 0))
	for i: int in 4:
		var a := float(i) / 4.0 * TAU
		var tent := _limb(root, "tent%d" % i, Vector3(cos(a) * 0.22, 0.68, sin(a) * 0.22))
		_attach(tent, PropMeshes._cone("ey_tent", 0.05, 0.01, 0.42), fleshm, Vector3(0, -0.21, 0), Vector3.ONE, Vector3(PI, 0, 0))
	return root


## Eight-legged arachnid (spider / widow). Abdomen + head, 8 leg pivots (leg0..leg7) the scuttle
## ripples, fangs + glowing eyes. spec: chitin (Color), mark (Color).
static func spider_rig(spec: Dictionary) -> Node3D:
	var chit: Color = spec.get("chitin", Color(0.16, 0.16, 0.2))
	var bodym := _tri_mat(chit)
	var legm := _tri_mat(chit.darkened(0.18))
	var markm := _tri_mat(spec.get("mark", Color(0.8, 0.18, 0.16)))
	var eyem := PropMeshes._mat_from(Color(0.85, 0.2, 0.2), Color(0.5, 0.08, 0.08), Color(1.0, 0.4, 0.3))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("sp_abdo", 0.34), bodym, Vector3(0, 0.42, -0.3), Vector3(1.1, 0.95, 1.2))
	_attach(root, PropMeshes._sphere("sp_mark", 0.1), markm, Vector3(0, 0.46, -0.5))
	_attach(root, PropMeshes._sphere("sp_head", 0.22), bodym, Vector3(0, 0.38, 0.16))
	for sx: int in [-1, 1]:
		_attach(root, PropMeshes._sphere("sp_eye", 0.04), eyem, Vector3(0.08 * sx, 0.44, 0.34))
		_attach(root, PropMeshes._cone("sp_fang", 0.04, 0.005, 0.12), legm, Vector3(0.06 * sx, 0.3, 0.34), Vector3.ONE, Vector3(2.4, 0, 0))
	var li := 0
	for sx2: int in [-1, 1]:
		for f: int in 4:
			var fz := 0.3 - float(f) * 0.2
			var leg := _limb(root, "leg%d" % li, Vector3(0.2 * sx2, 0.44, fz))
			_attach(leg, PropMeshes._box("sp_legu", Vector3(0.42, 0.04, 0.04)), legm, Vector3(0.22 * sx2, -0.06, 0), Vector3.ONE, Vector3(0, 0, -0.55 * sx2))
			_attach(leg, PropMeshes._box("sp_legl", Vector3(0.04, 0.26, 0.04)), legm, Vector3(0.4 * sx2, -0.22, 0))
			li += 1
	return root


## Six-legged beetle / scarab. Domed carapace + split elytra, a head with mandibles, 6 leg pivots
## (leg0..leg5). spec: shell (Color), trim (Color, the gilt edges).
static func scarab_rig(spec: Dictionary) -> Node3D:
	var shell: Color = spec.get("shell", Color(0.22, 0.26, 0.34))
	var trim: Color = spec.get("trim", Color(0.82, 0.66, 0.24))
	var bodym := _tri_mat(shell)
	var legm := _tri_mat(shell.darkened(0.2))
	var trimm := _tri_mat(trim)
	var eyem := PropMeshes._mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.14, 0.14, 0.16))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("sc_shell", 0.42), bodym, Vector3(0, 0.42, -0.06), Vector3(1.25, 0.78, 1.4))
	_attach(root, PropMeshes._box("sc_split", Vector3(0.04, 0.16, 0.7)), trimm, Vector3(0, 0.62, -0.06))
	_attach(root, PropMeshes._sphere("sc_head", 0.2), legm, Vector3(0, 0.34, 0.5), Vector3(1.2, 0.8, 0.9))
	_attach(root, PropMeshes._cone("sc_horn", 0.07, 0.01, 0.26), trimm, Vector3(0, 0.42, 0.66), Vector3.ONE, Vector3(1.2, 0, 0))
	for sx: int in [-1, 1]:
		_attach(root, PropMeshes._sphere("sc_eye", 0.05), eyem, Vector3(0.14 * sx, 0.4, 0.56))
		_attach(root, PropMeshes._cone("sc_mand", 0.03, 0.005, 0.14), trimm, Vector3(0.08 * sx, 0.28, 0.64), Vector3.ONE, Vector3(1.4, 0, 0.4 * sx))
	var li := 0
	for sx2: int in [-1, 1]:
		for f: int in 3:
			var fz := 0.32 - float(f) * 0.3
			var leg := _limb(root, "leg%d" % li, Vector3(0.26 * sx2, 0.32, fz))
			_attach(leg, PropMeshes._box("sc_leg", Vector3(0.3, 0.04, 0.04)), legm, Vector3(0.16 * sx2, -0.04, 0), Vector3.ONE, Vector3(0, 0, -0.6 * sx2))
			_attach(leg, PropMeshes._box("sc_foot", Vector3(0.04, 0.2, 0.04)), legm, Vector3(0.3 * sx2, -0.18, 0))
			li += 1
	return root


## Segmented crawler / centipede / brain-aberration. A forward chain of body pivots (seg0..seg5)
## the undulation runs down (shared serpent pose), each segment with a pair of little legs. The
## head has mandibles + eyes. spec: skin (Color).
static func crawler_rig(spec: Dictionary) -> Node3D:
	var skin: Color = spec.get("skin", Color(0.55, 0.42, 0.46))
	var bodym := _tri_mat(skin)
	var legm := _tri_mat(skin.darkened(0.28))
	var eyem := PropMeshes._mat_from(Color(0.9, 0.85, 0.2), Color(0.5, 0.4, 0.05), Color(1.0, 0.95, 0.4))
	var root := Node3D.new()
	var parent := root
	for i: int in 6:
		var seg := _limb(parent, "seg%d" % i, Vector3(0, 0.26 if i == 0 else 0.0, 0.0 if i == 0 else 0.3))
		var r := 0.2 - float(i) * 0.014
		_attach(seg, PropMeshes._sphere("cw_seg%d" % i, r), bodym, Vector3(0, 0, 0.15), Vector3(1.2, 0.85, 1.15))
		for sx: int in [-1, 1]:
			_attach(seg, PropMeshes._box("cw_leg", Vector3(0.22, 0.03, 0.03)), legm, Vector3(0.12 * sx, -0.06, 0.15), Vector3.ONE, Vector3(0, 0, -0.5 * sx))
		parent = seg
	_attach(parent, PropMeshes._box("cw_head", Vector3(0.24, 0.18, 0.24)), bodym, Vector3(0, 0.04, 0.32))
	for sx2: int in [-1, 1]:
		_attach(parent, PropMeshes._sphere("cw_eye", 0.04), eyem, Vector3(0.08 * sx2, 0.1, 0.4))
		_attach(parent, PropMeshes._cone("cw_mand", 0.03, 0.005, 0.14), legm, Vector3(0.07 * sx2, 0.0, 0.44), Vector3.ONE, Vector3(1.4, 0, 0.5 * sx2))
	return root


## Crab / shell-crusher. Wide carapace, two big claw arms (claw_l/claw_r), six walking legs
## (leg0..leg5), eye-stalks. spec: shell (Color), claw (Color).
static func crab_rig(spec: Dictionary) -> Node3D:
	var shell: Color = spec.get("shell", Color(0.78, 0.34, 0.26))
	var claw: Color = spec.get("claw", shell.lightened(0.12))
	var bodym := _tri_mat(shell)
	var clawm := _tri_mat(claw)
	var legm := _tri_mat(shell.darkened(0.2))
	var eyem := PropMeshes._mat_from(Color(0.06, 0.06, 0.08), Color(0.03, 0.03, 0.04), Color(0.14, 0.14, 0.16))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("cr_shell", 0.44), bodym, Vector3(0, 0.4, 0), Vector3(1.5, 0.66, 1.1))
	for sx: int in [-1, 1]:
		var stalk := _limb(root, "stalk_l" if sx < 0 else "stalk_r", Vector3(0.12 * sx, 0.52, 0.22))
		_attach(stalk, PropMeshes._cyl("cr_stalk", 0.025, 0.025, 0.16), legm, Vector3(0, 0.08, 0))
		_attach(stalk, PropMeshes._sphere("cr_eye", 0.05), eyem, Vector3(0, 0.18, 0))
	for sc: int in [-1, 1]:
		var claw_p := _limb(root, "claw_l" if sc < 0 else "claw_r", Vector3(0.4 * sc, 0.4, 0.28))
		_attach(claw_p, PropMeshes._box("cr_arm", Vector3(0.12, 0.12, 0.26)), legm, Vector3(0.06 * sc, 0, 0.12))
		_attach(claw_p, PropMeshes._box("cr_claw", Vector3(0.2, 0.22, 0.26)), clawm, Vector3(0.12 * sc, 0.02, 0.3))
		_attach(claw_p, PropMeshes._box("cr_pincer", Vector3(0.16, 0.07, 0.2)), clawm, Vector3(0.12 * sc, 0.16, 0.36))
	var li := 0
	for sx2: int in [-1, 1]:
		for f: int in 3:
			var fz := 0.18 - float(f) * 0.22
			var leg := _limb(root, "leg%d" % li, Vector3(0.34 * sx2, 0.34, fz))
			_attach(leg, PropMeshes._box("cr_leg", Vector3(0.34, 0.04, 0.05)), legm, Vector3(0.18 * sx2, -0.06, 0), Vector3.ONE, Vector3(0, 0, -0.7 * sx2))
			_attach(leg, PropMeshes._box("cr_tip", Vector3(0.04, 0.2, 0.05)), legm, Vector3(0.33 * sx2, -0.2, 0))
			li += 1
	return root


## Flying bat. Small fuzzy body, big membrane wings on wing_l/wing_r pivots (fast flap), ears + fangs.
## spec: fur (Color), wing (Color).
static func bat_rig(spec: Dictionary) -> Node3D:
	var fur: Color = spec.get("fur", Color(0.28, 0.24, 0.3))
	var wing: Color = spec.get("wing", fur.darkened(0.12))
	var bodym := _tri_mat(fur)
	var wingm := _tri_mat(wing)
	var eyem := PropMeshes._mat_from(Color(0.9, 0.4, 0.2), Color(0.5, 0.15, 0.06), Color(1.0, 0.6, 0.3))
	var root := Node3D.new()
	_attach(root, PropMeshes._sphere("ba_body", 0.2), bodym, Vector3(0, 0.84, 0), Vector3(1.0, 1.1, 1.0))
	_attach(root, PropMeshes._sphere("ba_head", 0.15), bodym, Vector3(0, 1.02, 0.04))
	for sx: int in [-1, 1]:
		_attach(root, PropMeshes._cone("ba_ear", 0.06, 0.005, 0.16), bodym, Vector3(0.08 * sx, 1.16, 0.0))
		_attach(root, PropMeshes._sphere("ba_eye", 0.03), eyem, Vector3(0.06 * sx, 1.04, 0.12))
		var w := _limb(root, "wing_l" if sx < 0 else "wing_r", Vector3(0.14 * sx, 0.86, 0))
		_attach(w, PropMeshes._box("ba_wmem", Vector3(0.6, 0.03, 0.34)), wingm, Vector3(0.32 * sx, 0, -0.02))
		_attach(w, PropMeshes._box("ba_wtip", Vector3(0.3, 0.03, 0.22)), wingm, Vector3(0.6 * sx, 0.02, -0.1), Vector3.ONE, Vector3(0, 0.4 * sx, 0))
	return root
