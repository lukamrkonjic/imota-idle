extends RefCounted
class_name UiTheme
## Single source of truth for the OSRS-style HUD palette + the shared StyleBox / list-row factories.
##
## Colours and the two near-identical style helpers used to be re-declared in osrs_hud.gd and
## admin_menu.gd (and the gold accent re-typed at call sites). They now live here; the panels keep
## thin local aliases so existing call sites are untouched.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

# --- Palette -----------------------------------------------------------------
const STONE := Color(0.24, 0.22, 0.20)          # panel background
const STONE_DARK := Color(0.16, 0.15, 0.14)     # panel border / inset
const PARCHMENT := Color(0.84, 0.79, 0.65)      # light fill
const PARCHMENT_DARK := Color(0.55, 0.45, 0.3)
const TEXT_DARK := Color(0.15, 0.1, 0.05)
const HOVER_YELLOW := Color(1.0, 1.0, 0.4)
const GOLD := Color(0.85, 0.72, 0.3)            # accent (coins / highlights)
const DISABLED_GRAY := Color(0.5, 0.5, 0.5)


# --- StyleBox factories ------------------------------------------------------

## Stone panel: STONE fill, STONE_DARK border, rounded corners. (was admin_menu._panel_style)
static func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = STONE
	s.border_color = STONE_DARK
	s.set_border_width_all(UiScale.i(2))
	s.set_corner_radius_all(UiScale.i(4))
	return s


## Padded button/cell box: `c` fill, rounded, 8x6 content margins, optional border. (was osrs_hud._style)
static func padded_style(c: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(UiScale.i(4))
	sb.content_margin_left = UiScale.f(8.0)
	sb.content_margin_right = UiScale.f(8.0)
	sb.content_margin_top = UiScale.f(6.0)
	sb.content_margin_bottom = UiScale.f(6.0)
	if border != Color.TRANSPARENT:
		sb.set_border_width_all(2)
		sb.border_color = border
	return sb


## A list row: an expanding label + (optional) trailing action button, added to `parent`.
## Returns the row so callers can append extra widgets. `on_click` is wired to the button.
static func list_row(parent: Node, text: String, button_text: String, on_click: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	if not button_text.is_empty():
		var btn := Button.new()
		btn.text = button_text
		btn.pressed.connect(on_click)
		row.add_child(btn)
	parent.add_child(row)
	return row
