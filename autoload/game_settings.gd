extends Node
## Player preferences persisted to user://settings.json.

signal changed(property: StringName)

const SETTINGS_PATH := "user://settings.json"

const UI_SCALE_MIN := 0.85
const UI_SCALE_MAX := 2.0
const DEFAULT_UI_SCALE := 1.0
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_FPS_LIMIT := 60
const DEFAULT_PIXELATION := 0.5   # picked via the "Pixel size" dropdown; 0 = native, 1 = chunkiest
const DEFAULT_VIEW_DISTANCE := 0.55   # longer than the old fixed range by default
const DEFAULT_CAM_ROTATE_SPEED := 1.0   # arrow-key camera orbit/tilt speed multiplier (1 = default)
const CAM_ROTATE_SPEED_MIN := 0.25
const CAM_ROTATE_SPEED_MAX := 2.5

const FPS_LIMIT_OPTIONS := [
	{"value": 30, "label": "30"},
	{"value": 60, "label": "60"},
	{"value": 120, "label": "120"},
	{"value": 144, "label": "144"},
	{"value": 0, "label": "Unlimited"},
]

# "Pixel size" dropdown: discrete render-chunkiness levels (small -> large pixel blocks).
# `value` is the level INDEX; it maps onto RenderViewportPresenter.PIXEL_LEVELS (keep both
# the same length). The index is stored as the 0..1 `pixelation` float (value / max index)
# so existing saves keep working — see pixel_level() / set_pixel_level(). Level 0 = "Off"
# renders at native window resolution; the renderer makes higher levels DPI-aware so a block
# is a consistent, crisp on-screen size on Retina and standard displays alike.
const PIXEL_SIZE_OPTIONS := [
	{"value": 0, "label": "Off — crisp render"},
	{"value": 1, "label": "Fine"},
	{"value": 2, "label": "Medium"},
	{"value": 3, "label": "Chunky (recommended)"},
	{"value": 4, "label": "Chunkier"},
	{"value": 5, "label": "Very chunky"},
	{"value": 6, "label": "Max"},
]

# "Resolution" dropdown: the windowed render size (independent of Pixel size — this scales the
# whole game window, Pixel size sets how chunky the pixels are within it). `value` is the option
# index; `w`/`h` are the target window size in pixels (0,0 = "Auto" = maximized / fit the screen).
# Sizes larger than the display are clamped. "Fullscreen" (maximized) takes priority — a concrete
# resolution only applies in windowed mode. See resolution_index() / set_resolution_index().
const RESOLUTION_OPTIONS := [
	{"value": 0, "label": "Auto (fit window)", "w": 0, "h": 0},
	{"value": 1, "label": "1280 × 720", "w": 1280, "h": 720},
	{"value": 2, "label": "1600 × 900", "w": 1600, "h": 900},
	{"value": 3, "label": "1920 × 1080", "w": 1920, "h": 1080},
	{"value": 4, "label": "2560 × 1440", "w": 2560, "h": 1440},
	{"value": 5, "label": "3200 × 1800", "w": 3200, "h": 1800},
]

# Rebindable key bindings. Add an entry here and the settings menu grows a rebind
# row for it automatically; handlers read the bound key via keybind(id).
const KEYBIND_ACTIONS := [
	{"id": "hide_hud", "label": "Hide HUD", "default": KEY_H},
]

var suppress := false  # headless tests set this so they never touch settings

var ui_scale: float = DEFAULT_UI_SCALE
var master_volume: float = DEFAULT_MASTER_VOLUME
var fullscreen: bool = true   # windowed-fullscreen (maximized + title bar) by default
var res_w: int = 0   # explicit windowed resolution; 0,0 = Auto (maximized / fit screen)
var res_h: int = 0
var vsync: bool = true
var show_zone_banner: bool = true
var show_chat: bool = true
var show_hover_tooltip: bool = true
var show_fps: bool = false
# Minimap: when true the minimap is always north-up (compass fixed). When false it
# rotates with the camera so "up" on the minimap matches the on-screen view direction.
var minimap_lock_north: bool = true
var fps_limit: int = DEFAULT_FPS_LIMIT
var pixelation: float = DEFAULT_PIXELATION   # 3D render crunch; read by the renderer
var view_distance: float = DEFAULT_VIEW_DISTANCE  # 0 = near, 1 = far; read by the renderer
var cam_rotate_speed: float = DEFAULT_CAM_ROTATE_SPEED  # arrow-key orbit/tilt speed; read by the renderer

# Idle automation (spec §12, §21). Auto-eat the best food when HP drops to/below
# the threshold fraction of max during combat.
var auto_eat_enabled: bool = true
var auto_eat_threshold: float = 0.5

# Auto-retaliate (OSRS): when on, the player automatically fights back against (and
# is auto-engaged by) an aggressive enemy. When off, you only fight enemies you click.
var auto_retaliate: bool = true

var keybinds: Dictionary = {}  # action id -> Key keycode


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	keybinds = _default_keybinds()
	var data := JsonIO.read_dict(SETTINGS_PATH)
	if data.is_empty():
		return
	ui_scale = clampf(float(data.get("ui_scale", DEFAULT_UI_SCALE)), UI_SCALE_MIN, UI_SCALE_MAX)
	master_volume = clampf(float(data.get("master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)
	fullscreen = bool(data.get("fullscreen", true))
	res_w = maxi(0, int(data.get("res_w", 0)))
	res_h = maxi(0, int(data.get("res_h", 0)))
	vsync = bool(data.get("vsync", true))
	show_zone_banner = bool(data.get("show_zone_banner", true))
	show_chat = bool(data.get("show_chat", true))
	show_hover_tooltip = bool(data.get("show_hover_tooltip", true))
	show_fps = bool(data.get("show_fps", false))
	minimap_lock_north = bool(data.get("minimap_lock_north", true))
	fps_limit = int(data.get("fps_limit", DEFAULT_FPS_LIMIT))
	if not _is_valid_fps_limit(fps_limit):
		fps_limit = DEFAULT_FPS_LIMIT
	auto_eat_enabled = bool(data.get("auto_eat_enabled", true))
	auto_eat_threshold = clampf(float(data.get("auto_eat_threshold", 0.5)), 0.0, 1.0)
	auto_retaliate = bool(data.get("auto_retaliate", true))
	pixelation = clampf(float(data.get("pixelation", DEFAULT_PIXELATION)), 0.0, 1.0)
	view_distance = clampf(float(data.get("view_distance", DEFAULT_VIEW_DISTANCE)), 0.0, 1.0)
	cam_rotate_speed = clampf(float(data.get("cam_rotate_speed", DEFAULT_CAM_ROTATE_SPEED)), CAM_ROTATE_SPEED_MIN, CAM_ROTATE_SPEED_MAX)
	var saved_kb: Dictionary = data.get("keybinds", {})
	for id: String in keybinds:
		if saved_kb.has(id):
			keybinds[id] = int(saved_kb[id])


func save_settings() -> void:
	if suppress:
		return
	var data := {
		"ui_scale": ui_scale,
		"master_volume": master_volume,
		"fullscreen": fullscreen,
		"res_w": res_w,
		"res_h": res_h,
		"vsync": vsync,
		"show_zone_banner": show_zone_banner,
		"show_chat": show_chat,
		"show_hover_tooltip": show_hover_tooltip,
		"show_fps": show_fps,
		"minimap_lock_north": minimap_lock_north,
		"fps_limit": fps_limit,
		"auto_eat_enabled": auto_eat_enabled,
		"auto_eat_threshold": auto_eat_threshold,
		"auto_retaliate": auto_retaliate,
		"pixelation": pixelation,
		"view_distance": view_distance,
		"cam_rotate_speed": cam_rotate_speed,
		"keybinds": keybinds,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write settings file")
		return
	f.store_string(JSON.stringify(data))
	f.close()


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, UI_SCALE_MIN, UI_SCALE_MAX)
	save_settings()
	changed.emit(&"ui_scale")


func set_pixelation(value: float) -> void:
	pixelation = clampf(value, 0.0, 1.0)
	save_settings()
	changed.emit(&"pixelation")


# Bridge the "Pixel size" dropdown (discrete level index) to the stored `pixelation` float,
# so the dropdown is the UI but saves stay a plain 0..1 number (no save-format change).
func pixel_level() -> int:
	var max_idx := PIXEL_SIZE_OPTIONS.size() - 1
	return clampi(int(round(pixelation * float(max_idx))), 0, max_idx)


func set_pixel_level(idx: int) -> void:
	var max_idx := PIXEL_SIZE_OPTIONS.size() - 1
	set_pixelation(float(clampi(idx, 0, max_idx)) / float(max_idx))


func set_view_distance(value: float) -> void:
	view_distance = clampf(value, 0.0, 1.0)
	save_settings()
	changed.emit(&"view_distance")


func set_cam_rotate_speed(value: float) -> void:
	cam_rotate_speed = clampf(value, CAM_ROTATE_SPEED_MIN, CAM_ROTATE_SPEED_MAX)
	save_settings()
	changed.emit(&"cam_rotate_speed")


func set_minimap_lock_north(on: bool) -> void:
	minimap_lock_north = on
	save_settings()
	changed.emit(&"minimap_lock_north")


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	save_settings()
	_apply_audio()
	changed.emit(&"master_volume")


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	save_settings()
	_apply_display()
	changed.emit(&"fullscreen")


# Which RESOLUTION_OPTIONS entry the current res_w/res_h matches (0 = Auto).
func resolution_index() -> int:
	for opt: Dictionary in RESOLUTION_OPTIONS:
		if int(opt["w"]) == res_w and int(opt["h"]) == res_h:
			return int(opt["value"])
	return 0


func set_resolution_index(idx: int) -> void:
	for opt: Dictionary in RESOLUTION_OPTIONS:
		if int(opt["value"]) == idx:
			res_w = int(opt["w"])
			res_h = int(opt["h"])
			break
	save_settings()
	_apply_display()
	changed.emit(&"resolution")


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	save_settings()
	_apply_display()
	changed.emit(&"vsync")


func set_show_zone_banner(enabled: bool) -> void:
	show_zone_banner = enabled
	save_settings()
	changed.emit(&"show_zone_banner")


func set_auto_retaliate(enabled: bool) -> void:
	auto_retaliate = enabled
	save_settings()
	changed.emit(&"auto_retaliate")


func set_show_chat(enabled: bool) -> void:
	show_chat = enabled
	save_settings()
	changed.emit(&"show_chat")


func set_show_hover_tooltip(enabled: bool) -> void:
	show_hover_tooltip = enabled
	save_settings()
	changed.emit(&"show_hover_tooltip")


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	save_settings()
	changed.emit(&"show_fps")


func set_fps_limit(value: int) -> void:
	if not _is_valid_fps_limit(value):
		return
	fps_limit = value
	save_settings()
	_apply_fps()
	changed.emit(&"fps_limit")


func _default_keybinds() -> Dictionary:
	var d := {}
	for a: Dictionary in KEYBIND_ACTIONS:
		d[str(a["id"])] = int(a["default"])
	return d


## The Key keycode bound to an action id (0 if unbound/unknown).
func keybind(id: String) -> int:
	return int(keybinds.get(id, 0))


func set_keybind(id: String, keycode: int) -> void:
	keybinds[id] = keycode
	save_settings()
	changed.emit(&"keybinds")


func apply_all() -> void:
	_apply_audio()
	_apply_display()
	_apply_fps()


func _is_valid_fps_limit(value: int) -> bool:
	for opt: Dictionary in FPS_LIMIT_OPTIONS:
		if int(opt["value"]) == value:
			return true
	return false


func _apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))


var _display_applied_once := false

func _apply_display() -> void:
	# "Fullscreen" here means windowed-fullscreen (a MAXIMIZED window that keeps the OS
	# title bar) — never borderless exclusive fullscreen. Off = a normal resizable window.
	# The game ALWAYS launches maximized UNLESS an explicit Resolution is saved: the first
	# apply (at startup) otherwise ignores a saved windowed preference so a stale save can
	# never shrink it back to the small window; the toggle only takes effect in-session.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var first_apply := not _display_applied_once
	_display_applied_once = true
	var concrete := res_w > 0 and res_h > 0
	if fullscreen or (first_apply and not concrete):
		# Fullscreen (maximized) wins over a windowed resolution while it's on.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	elif concrete:
		_apply_windowed_resolution()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


# Size the window to the chosen Resolution (clamped to the display) and centre it. Window size
# is in pixels — on a HiDPI screen those are physical pixels (the screen reports e.g. 3456 wide),
# so the listed sizes scale the game smaller/larger within that. Skips gracefully on headless,
# where screen metrics are zero.
func _apply_windowed_resolution() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var w := res_w
	var h := res_h
	if screen.size.x > 0 and screen.size.y > 0:
		w = mini(w, int(screen.size.x))
		h = mini(h, int(screen.size.y))
	var size := Vector2i(maxi(640, w), maxi(360, h))
	DisplayServer.window_set_size(size)
	if screen.size.x > 0 and screen.size.y > 0:
		DisplayServer.window_set_position(Vector2i(screen.position) + (Vector2i(screen.size) - size) / 2)


func _apply_fps() -> void:
	Engine.max_fps = fps_limit
