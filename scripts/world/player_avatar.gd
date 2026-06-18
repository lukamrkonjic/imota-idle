extends Node2D
## Aldenfall paper-doll player: idle/run/gather poses, facing flip, walk-to
## movement, and an action progress bar above the head.

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

signal arrived

const SPEED := 130.0
const JUMP_DUR := 0.26   # one hop when stepping up a large elevation change
const JUMP_AMP := 9.0
const NO_DUR := 0.5      # head-shake "can't go there" wobble

var walk_target := Vector2.ZERO
var walking := false
var progress := -1.0
var facing := 1
var _target_facing := 1     # desired facing; the flip animates toward it
var _face_squash := 1.0      # horizontal scale during a turn (1 normal, dips to 0 mid-flip)
var _t := 0.0
var _fish_cast_local := Vector2.ZERO
var _fish_casting := false
# Terrain-elevation follow: the avatar rides the terraced ground height so it is
# clear when he is up on a slope versus down on flat land.
var _vis_y := 0.0          # smoothed vertical draw offset (px, negative = up)
var _prev_elev := -9999
var _jump_t := -1.0
var _no_t := -1.0


func _ready() -> void:
	EventBus.equipment_changed.connect(func() -> void: queue_redraw())
	EventBus.activity_started.connect(func(_kind: String, _label: String) -> void: queue_redraw())
	EventBus.activity_stopped.connect(func(_reason: String) -> void: queue_redraw())


func _process(delta: float) -> void:
	_t += delta
	if walking:
		var to_target := walk_target - position
		var step := SPEED * delta
		# While fighting, facing is driven toward the enemy (face_toward) instead.
		if absf(to_target.x) > 1.0 and not CombatSim.active:
			_target_facing = 1 if to_target.x >= 0.0 else -1
		if to_target.length() <= step:
			position = walk_target
			walking = false
			arrived.emit()
		else:
			position += to_target.normalized() * step
	_animate_facing(delta)
	_update_elevation(delta)
	queue_redraw()


## Aim the avatar at a world x (used by combat to keep him turned to the target).
func face_toward(world_x: float) -> void:
	if absf(world_x - position.x) > 1.0:
		_target_facing = 1 if world_x >= position.x else -1


## Smooth turn: squash horizontally to ~0, swap the facing at the midpoint, expand
## back — so the side switch reads as a quick spin instead of an instant mirror.
func _animate_facing(delta: float) -> void:
	if facing != _target_facing:
		_face_squash = move_toward(_face_squash, 0.0, delta * 14.0)
		if _face_squash <= 0.05:
			facing = _target_facing
	else:
		_face_squash = move_toward(_face_squash, 1.0, delta * 14.0)


## Ride the terraced terrain height. Snaps on the first frame / teleport, then
## smoothly eases as the player crosses tiles; a big step up triggers a hop.
func _update_elevation(delta: float) -> void:
	var elev: int = WorldGen.elevation_at(position) if WorldGen != null else 0
	if _prev_elev == -9999:
		_prev_elev = elev
		_vis_y = -float(elev) * WG.ELEV_STEP_PX
	# Hop on every elevation change while walking — up OR down — so climbing and
	# descending terraces reads as Minecraft-style step jumps.
	if walking and absi(elev - _prev_elev) >= 1 and _jump_t < 0.0:
		_jump_t = 0.0
	_prev_elev = elev
	_vis_y = lerpf(_vis_y, -float(elev) * WG.ELEV_STEP_PX, clampf(delta * 12.0, 0.0, 1.0))
	if _jump_t >= 0.0:
		_jump_t += delta
		if _jump_t >= JUMP_DUR:
			_jump_t = -1.0
	if _no_t >= 0.0:
		_no_t += delta
		if _no_t >= NO_DUR:
			_no_t = -1.0


## Play a left-right-left head-shake to signal "you can't go there".
func play_no() -> void:
	if _no_t < 0.0:
		_no_t = 0.0
	queue_redraw()


func _visual_offset() -> Vector2:
	var jy := 0.0
	if _jump_t >= 0.0:
		jy = -sin(PI * (_jump_t / JUMP_DUR)) * JUMP_AMP
	var nx := 0.0
	if _no_t >= 0.0:
		nx = sin(_no_t * TAU * 3.0) * 4.0 * (1.0 - _no_t / NO_DUR)
	return Vector2(nx, _vis_y + jy)


func walk_to(target: Vector2) -> void:
	walk_target = target
	walking = true


func stop_walking() -> void:
	walking = false


func set_progress(f: float) -> void:
	progress = f
	queue_redraw()


func set_fish_cast(world_pos: Vector2) -> void:
	_fish_cast_local = to_local(world_pos)
	_fish_casting = true
	queue_redraw()


func clear_fish_cast() -> void:
	_fish_casting = false
	queue_redraw()


func _mode() -> String:
	if walking:
		return "run"
	if TickSim.active:
		match TickSim.skill:
			"woodcutting":
				return "chop"
			"mining":
				return "mine"
			"fishing":
				return "fish"
			"foraging":
				return "forage"
		return "gather"
	if RecipeSim.active:
		return "craft"
	if CombatSim.active:
		# Stance follows the equipped weapon, not the trained stat — a bow always
		# uses the ranged (draw-and-loose) pose even while training a melee skill.
		match GameState.weapon_combat_style():
			"ranged":
				return "combat_range"
			"magic":
				return "combat_magic"
		return "combat_melee"
	return "idle"


func _draw() -> void:
	draw_set_transform(_visual_offset(), 0.0, Vector2(maxf(_face_squash, 0.02), 1.0))
	var cast_local := _fish_cast_local if _fish_casting else Vector2.ZERO
	IsoSprites.draw_player(
		self, PixelPalette.pal("skin_a"), PixelPalette.pal("outfit_a"),
		PixelPalette.pal("hair"), _mode(), _t, facing, cast_local)
	# Skilling progress bar — hidden to match OSRS (no per-action bar over the head).
	# Kept commented in case we want it back for a specific skill later.
	#if progress >= 0.0:
		#var bar_w := 36.0
		#var top := Vector2(-bar_w / 2.0, -48.0)
		#draw_rect(Rect2(top, Vector2(bar_w, 5)), Color(0.1, 0.1, 0.12, 0.85))
		#draw_rect(Rect2(top, Vector2(bar_w * clampf(progress, 0.0, 1.0), 5)), Color(0.91, 0.75, 0.25))
