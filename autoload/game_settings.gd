extends Node
## Player preferences persisted to user://settings.json.

signal changed(property: StringName)

const SETTINGS_PATH := "user://settings.json"

const UI_SCALE_MIN := 0.85
const UI_SCALE_MAX := 1.45
const DEFAULT_UI_SCALE := 1.0
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_FPS_LIMIT := 60

const FPS_LIMIT_OPTIONS := [
	{"value": 30, "label": "30"},
	{"value": 60, "label": "60"},
	{"value": 120, "label": "120"},
	{"value": 144, "label": "144"},
	{"value": 0, "label": "Unlimited"},
]

# Rebindable key bindings. Add an entry here and the settings menu grows a rebind
# row for it automatically; handlers read the bound key via keybind(id).
const KEYBIND_ACTIONS := [
	{"id": "hide_hud", "label": "Hide HUD", "default": KEY_H},
]

var suppress := false  # headless tests set this so they never touch settings

var ui_scale: float = DEFAULT_UI_SCALE
var master_volume: float = DEFAULT_MASTER_VOLUME
var fullscreen: bool = false
var vsync: bool = true
var show_zone_banner: bool = true
var show_chat: bool = true
var show_hover_tooltip: bool = true
var show_fps: bool = false
var show_tile_debug: bool = true  # dev tile/zone/elev overlay (toggled from Admin)
var noclip: bool = false  # dev fly: straight-line move over any terrain + 2x speed (NOT persisted)
var fps_limit: int = DEFAULT_FPS_LIMIT

# Idle automation (spec §12, §21). Auto-eat the best food when HP drops to/below
# the threshold fraction of max during combat.
var auto_eat_enabled: bool = true
var auto_eat_threshold: float = 0.5

var keybinds: Dictionary = {}  # action id -> Key keycode


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	keybinds = _default_keybinds()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	ui_scale = clampf(float(data.get("ui_scale", DEFAULT_UI_SCALE)), UI_SCALE_MIN, UI_SCALE_MAX)
	master_volume = clampf(float(data.get("master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)
	fullscreen = bool(data.get("fullscreen", false))
	vsync = bool(data.get("vsync", true))
	show_zone_banner = bool(data.get("show_zone_banner", true))
	show_chat = bool(data.get("show_chat", true))
	show_hover_tooltip = bool(data.get("show_hover_tooltip", true))
	show_fps = bool(data.get("show_fps", false))
	show_tile_debug = bool(data.get("show_tile_debug", true))
	fps_limit = int(data.get("fps_limit", DEFAULT_FPS_LIMIT))
	if not _is_valid_fps_limit(fps_limit):
		fps_limit = DEFAULT_FPS_LIMIT
	auto_eat_enabled = bool(data.get("auto_eat_enabled", true))
	auto_eat_threshold = clampf(float(data.get("auto_eat_threshold", 0.5)), 0.0, 1.0)
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
		"vsync": vsync,
		"show_zone_banner": show_zone_banner,
		"show_chat": show_chat,
		"show_hover_tooltip": show_hover_tooltip,
		"show_fps": show_fps,
		"show_tile_debug": show_tile_debug,
		"fps_limit": fps_limit,
		"auto_eat_enabled": auto_eat_enabled,
		"auto_eat_threshold": auto_eat_threshold,
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


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	save_settings()
	_apply_display()
	changed.emit(&"vsync")


func set_show_zone_banner(enabled: bool) -> void:
	show_zone_banner = enabled
	save_settings()
	changed.emit(&"show_zone_banner")


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


func set_show_tile_debug(enabled: bool) -> void:
	show_tile_debug = enabled
	save_settings()
	changed.emit(&"show_tile_debug")


## Dev fly toggle — not persisted (always off on a fresh launch).
func set_noclip(enabled: bool) -> void:
	noclip = enabled
	changed.emit(&"noclip")


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


func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_fps() -> void:
	Engine.max_fps = fps_limit
