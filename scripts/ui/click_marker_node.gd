extends Node2D
## OSRS click X: centre-out growth, then centre-out dissolve.

const ClickMarkerArt := preload("res://scripts/ui/click_marker_art.gd")
const ClickMarkerAnim := preload("res://scripts/ui/click_marker_anim.gd")

var _interactable := false
var _frame := 0
var _accum := 0.0


func begin(interactable: bool) -> void:
	_interactable = interactable
	z_index = 600
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_accum += delta
	while _accum >= ClickMarkerAnim.STEP:
		_accum -= ClickMarkerAnim.STEP
		_frame += 1
		if _frame >= ClickMarkerAnim.frame_count():
			queue_free()
			return
		queue_redraw()


func _draw() -> void:
	var step: Dictionary = ClickMarkerAnim.step(_frame)
	ClickMarkerArt.draw(
		self, Vector2.ZERO, _interactable,
		int(step["arm"]), int(step["gap"]))
