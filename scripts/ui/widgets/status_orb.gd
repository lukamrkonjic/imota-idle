extends Control
## A status tile (HP / Prayer / Run energy) for the minimap cluster — styled to match
## the IconButton action tiles (stone rect + border) for visual consistency.
## The run tile is interactive: left-click toggles running, right-click toggles rest.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var kind := "hp"


func _ready() -> void:
	custom_minimum_size = UiScale.v2(Vector2(44, 40))
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP  # STOP so the tooltip shows + clicks land
	if kind == "run":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Run tile: left-click toggles run on/off, right-click sits down to recharge faster.
func _gui_input(event: InputEvent) -> void:
	if kind != "run":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			GameState.toggle_run()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			GameState.set_resting(not GameState.resting)
			accept_event()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var frac := 1.0
	var col := Color(0.7, 0.12, 0.12)
	var text := ""
	var lbl := ""
	var border := Color(0.55, 0.5, 0.35)
	match kind:
		"hp":
			frac = float(GameState.current_hp) / maxf(float(GameState.max_hp()), 1.0)
			col = Color(0.7, 0.16, 0.16); lbl = "HP"; text = str(GameState.current_hp)
		"prayer":
			frac = 1.0
			col = Color(0.3, 0.55, 0.85); lbl = "Pray"; text = str(GameState.level("prayer"))
		"run":
			frac = GameState.run_energy / 100.0
			lbl = "Run"; text = str(int(GameState.run_energy))   # OSRS floors the % (int truncates)
			if GameState.resting:
				col = Color(0.4, 0.62, 0.9); border = Color(0.55, 0.8, 1.0)      # resting
			elif GameState.run_enabled:
				col = Color(0.9, 0.78, 0.22); border = Color(1.0, 0.92, 0.45)    # running (bright frame)
			else:
				col = Color(0.5, 0.45, 0.16)                                     # walking
	# Frame (matches IconButton): dark stone fill + level tint + border.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.16, 0.14))
	var fh := (size.y - 4.0) * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(Vector2(2.0, size.y - 2.0 - fh), Vector2(size.x - 4.0, fh)), Color(col.r, col.g, col.b, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), border, false, UiScale.f(2.0))
	# Label (top) + value (centre).
	var font := ThemeDB.fallback_font
	var lfs := UiScale.i(9)
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
	draw_string(font, Vector2(size.x * 0.5 - lw / 2.0, UiScale.f(11.0)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(0.82, 0.78, 0.6))
	var fs := UiScale.i(14)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(size.x * 0.5 - tw / 2.0 + 1, size.y * 0.5 + fs * 0.55 + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(size.x * 0.5 - tw / 2.0, size.y * 0.5 + fs * 0.55), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
