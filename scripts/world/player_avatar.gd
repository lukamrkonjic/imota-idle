extends Node2D
## Player logic node: walk-to movement + position. The visible body is a 3D mesh
## rig built by the 3D renderer (PropMeshes.player_rig) — this node is never drawn.
## The old 2D paper-doll (facing flip, idle/gather/combat poses, elevation hop) is
## gone; orientation and gait are derived in 3D from velocity + the combat target.
## The set_*/face_*/play_no methods are kept as harmless stubs so the activity and
## path controllers can keep calling them.

signal arrived

const WALK_SPEED := 34.0   # ~1.8 tiles/sec — OSRS walk pace
const RUN_SPEED := 68.0    # 2x walk, gated on run toggle + energy
const ACCEL := 460.0   # px/s² — eases up to full speed in ~0.2s (a little inertia)
var _speed := 0.0      # current eased speed

## Target pace this frame: run when toggled on and there's energy, else walk.
func _target_speed() -> float:
	if GameState.run_enabled and GameState.run_energy > 0.0:
		return RUN_SPEED
	return WALK_SPEED


## The player's current walk/run pace — read by sim-player followers so they sprint when you sprint
## (RuneScape-style Follow).
func move_speed() -> float:
	return _target_speed()


func is_running() -> bool:
	return GameState.run_enabled and GameState.run_energy > 0.0

var walk_target := Vector2.ZERO
var walking := false
var progress := -1.0


func _process(delta: float) -> void:
	if walking:
		GameState.is_moving = true
		if GameState.resting:
			GameState.set_resting(false)   # moving cancels rest
		# A little inertia: ease the speed up from rest so a start isn't an instant
		# snap to full pace (but ACCEL is high enough that it never feels sluggish).
		_speed = move_toward(_speed, _target_speed(), ACCEL * delta)
		# Running spends energy (Agility-scaled inside GameState).
		if GameState.run_enabled and GameState.run_energy > 0.0:
			GameState.drain_running(delta)
		var to_target := walk_target - position
		var step := _speed * delta
		if to_target.length() <= step:
			position = walk_target
			walking = false
			# Reaching a WAYPOINT is not a stop — keep the eased speed so momentum carries
			# straight into the next leg. `arrived` synchronously sets the next waypoint
			# (walking=true again) or calls stop_walking() at the real destination.
			arrived.emit()
		else:
			position += to_target.normalized() * step
	else:
		GameState.is_moving = false
		_speed = 0.0


func walk_to(target: Vector2) -> void:
	walk_target = target
	walking = true


func stop_walking() -> void:
	walking = false


func set_progress(f: float) -> void:
	progress = f


# ── kept as stubs (the 3D rig handles facing/poses; these no longer drive visuals) ──

## Combat used to turn the 2D paper-doll toward the foe; the 3D rig now squares up to
## the live combat target on its own, so this is a no-op.
func face_toward(_world_x: float) -> void:
	pass


## "Can't go there" head-shake — was a 2D-only wobble; no 3D equivalent yet.
func play_no() -> void:
	pass


## Fishing: where the line lands on the water (2D iso world pos). The 3D renderer reads `fishing`
## + `fish_cast_pos` to face the spot, play the rod-cast (or lobster-kneel) pose, and draw the line.
var fishing := false
var fish_cast_pos := Vector2.ZERO


func set_fish_cast(world_pos: Vector2) -> void:
	fish_cast_pos = world_pos
	fishing = true


func clear_fish_cast() -> void:
	fishing = false
