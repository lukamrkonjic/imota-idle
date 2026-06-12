extends Node2D
## Aldenfall paper-doll player: idle/run/gather poses, facing flip, walk-to
## movement, and an action progress bar above the head.

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

signal arrived

const SPEED := 230.0

var walk_target := Vector2.ZERO
var walking := false
var progress := -1.0
var facing := 1
var _t := 0.0


func _ready() -> void:
	EventBus.equipment_changed.connect(func() -> void: queue_redraw())
	EventBus.activity_started.connect(func(_kind: String, _label: String) -> void: queue_redraw())
	EventBus.activity_stopped.connect(func(_reason: String) -> void: queue_redraw())


func _process(delta: float) -> void:
	_t += delta
	if walking:
		var to_target := walk_target - position
		var step := SPEED * delta
		if absf(to_target.x) > 1.0:
			facing = 1 if to_target.x >= 0.0 else -1
		if to_target.length() <= step:
			position = walk_target
			walking = false
			arrived.emit()
		else:
			position += to_target.normalized() * step
	queue_redraw()


func walk_to(target: Vector2) -> void:
	walk_target = target
	walking = true


func stop_walking() -> void:
	walking = false


func set_progress(f: float) -> void:
	progress = f
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
		match CombatSim.train_skill:
			"ranged":
				return "combat_range"
			"magic":
				return "combat_magic"
		return "combat_melee"
	return "idle"


func _draw() -> void:
	IsoSprites.draw_player(
		self, PixelPalette.pal("skin_a"), PixelPalette.pal("outfit_a"),
		PixelPalette.pal("hair"), _mode(), _t, facing)
	if progress >= 0.0:
		var bar_w := 36.0
		var top := Vector2(-bar_w / 2.0, -48.0)
		draw_rect(Rect2(top, Vector2(bar_w, 5)), Color(0.1, 0.1, 0.12, 0.85))
		draw_rect(Rect2(top, Vector2(bar_w * clampf(progress, 0.0, 1.0), 5)), Color(0.91, 0.75, 0.25))
