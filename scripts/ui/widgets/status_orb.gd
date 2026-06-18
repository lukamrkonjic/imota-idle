extends Control
## A drawn status orb (HP / Prayer / Run energy) for the minimap cluster.
## Extracted from osrs_hud.gd. Set `kind` to "hp" / "prayer" / "run".

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var kind := "hp"


func _ready() -> void:
	custom_minimum_size = UiScale.v2(Vector2(42, 42))
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP  # STOP so the tooltip shows


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := size.x / 2.0
	var c := size / 2.0
	var frac := 1.0
	var col := Color(0.7, 0.12, 0.12)
	var text := ""
	match kind:
		"hp":
			frac = float(GameState.current_hp) / maxf(float(GameState.max_hp()), 1.0)
			col = Color(0.7, 0.12, 0.12)
			text = str(GameState.current_hp)
		"prayer":
			col = Color(0.3, 0.55, 0.85)
			text = str(GameState.level("prayer"))
		"run":
			col = Color(0.85, 0.78, 0.2)
			text = "100"
	draw_circle(c, r, Color(0.09, 0.09, 0.09, 0.92))
	var fill_h := size.y * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(Vector2(0, size.y - fill_h), Vector2(size.x, fill_h)).intersection(Rect2(Vector2.ZERO, size)), col)
	draw_arc(c, r - 1.0, 0.0, TAU, 36, Color(0.55, 0.5, 0.35), 2.0)
	var font := ThemeDB.fallback_font
	var fs := UiScale.i(13)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, c + Vector2(-tw / 2.0, fs * 0.4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_string(font, c + Vector2(-tw / 2.0 + 1, fs * 0.4 + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.0))
