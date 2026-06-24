extends RefCounted
class_name WorldCollisionController
## Soft creature separation: living movers (player, sim-players, enemies) can't stand inside one
## another — overlapping pairs are gently pushed apart each frame, so followers queue up BEHIND you
## instead of stacking on your tile, and a crowd reads as bodies, not one blob. The PLAYER is the
## fixed anchor (never shoved by NPCs); everyone else yields around it. Pushes are clamped to walkable
## ground so separation can never squeeze a body into water or through a tree.
##
## Cheap by construction: only movers within SEP_RADIUS of the player take part (off-screen packs are
## nobody's problem), so the O(n²) pass is over a small near set even when hundreds of mobs exist.

const WG := preload("res://scripts/worldgen/wg.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")

const SEP_RADIUS_TILES := 12.0     # only resolve movers this close to the player
const PLAYER_RADIUS := WG.TILE * 0.34
const HUMANOID_RADIUS := WG.TILE * 0.34
const MAX_PUSH := WG.TILE * 0.6    # clamp a single frame's correction so a deep overlap eases out

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func process_tick(_delta: float) -> void:
	if world.player == null:
		return
	var pp: Vector2 = world.player.position
	var sep_sq := (SEP_RADIUS_TILES * WG.TILE) * (SEP_RADIUS_TILES * WG.TILE)
	# Build the near set: the player (anchor) plus nearby living movers.
	var nodes: Array[Node2D] = [world.player]
	var radii: Array[float] = [PLAYER_RADIUS]
	var movable: Array[bool] = [false]
	for e: Node2D in world.entities:
		if not is_instance_valid(e) or not PropMeshes.is_moving(e) or e.dimmed:
			continue
		if e.position.distance_squared_to(pp) > sep_sq:
			continue
		nodes.append(e)
		radii.append(_radius(e))
		movable.append(true)
	var tgt: Node2D = world.combat_target_entity
	for i: int in range(nodes.size()):
		for j: int in range(i + 1, nodes.size()):
			# Don't fight the combat positioner: the player and its target keep their OSRS attack gap.
			if (nodes[i] == world.player and nodes[j] == tgt) or (nodes[j] == world.player and nodes[i] == tgt):
				continue
			_separate(nodes[i], radii[i], movable[i], nodes[j], radii[j], movable[j])


func _separate(a: Node2D, ra: float, ma: bool, b: Node2D, rb: float, mb: bool) -> void:
	var d := b.position - a.position
	var dist := d.length()
	var minsep := ra + rb
	if dist >= minsep:
		return
	var n: Vector2 = d / dist if dist > 0.001 else Vector2(1, 0)
	var overlap := minf(minsep - dist, MAX_PUSH)
	if not ma and not mb:
		return
	elif not ma:
		_try_push(b, n * overlap)
	elif not mb:
		_try_push(a, -n * overlap)
	else:
		_try_push(a, -n * overlap * 0.5)
		_try_push(b, n * overlap * 0.5)


## Apply a positional nudge only if it lands on walkable ground (never push a body into water/cliffs
## or onto a blocked prop tile).
func _try_push(node: Node2D, delta: Vector2) -> void:
	var np: Vector2 = node.position + delta
	if WorldGen.is_walkable_world(np, world.current_layer):
		node.position = np


func _radius(e: Node2D) -> float:
	if str(e.kind) == "sim":
		return HUMANOID_RADIUS
	# Enemies: scale the personal space to the body footprint so big mobs keep more room.
	var ds := float(e.get("display_size")) if e.get("display_size") != null else 34.0
	var r := WG.TILE * (0.28 + ds / 240.0)
	if bool(e.get("is_boss")):
		r *= 1.4
	return r
