extends CanvasLayer
## OSRS-style interface over the isometric world: hover text top-left,
## minimap + HP orb top-right, stone side panel with tabs bottom-right,
## parchment chatbox bottom-left. Pure view layer â€” only talks to autoloads.

const STONE := Color(0.24, 0.22, 0.20)
const STONE_DARK := Color(0.16, 0.15, 0.14)
const PARCHMENT := Color(0.84, 0.79, 0.65)
const PARCHMENT_DARK := Color(0.55, 0.45, 0.3)
const TEXT_DARK := Color(0.15, 0.1, 0.05)
const HOVER_YELLOW := Color(1.0, 1.0, 0.4)
const UiScale := preload("res://scripts/ui/ui_scale.gd")
const WorldHoverTooltipScript := preload("res://scripts/ui/world_hover_tooltip.gd")
const ClickMarkerNode := preload("res://scripts/ui/click_marker_node.gd")
const AdminMenu := preload("res://scripts/ui/admin_menu.gd")
const WorldMapPanel := preload("res://scripts/ui/world_map_panel.gd")
# Procedural HUD widgets, extracted to their own files (scripts/ui/widgets/).
const TabIcon := preload("res://scripts/ui/widgets/tab_icon.gd")
const StatusOrb := preload("res://scripts/ui/widgets/status_orb.gd")
const IconButton := preload("res://scripts/ui/widgets/icon_button.gd")
const MinimapPanel := preload("res://scripts/ui/widgets/minimap.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")  # preload, not class_name, so a fresh launch never fails to resolve it


var world: Node2D = null

var hud_root: Control
var hover_label: Label
var world_tooltip: PanelContainer
var chat: RichTextLabel
var chat_lines: PackedStringArray = []
var minimap: Control
var hp_orb: Control
var coins_label: Label
var _side_tabs: TabContainer
var _tab_icons: Array = []          # TabIcon widgets, index-aligned with the tabs
var _combat_tab: HudCombatTab       # per-tab components (scripts/ui/tabs/) the HUD orchestrates
var _skills_tab: HudSkillsTab
var _inventory_tab: HudInventoryTab
var _equipment_tab: HudEquipmentTab
var _prayer_tab: HudPrayerTab
var _magic_tab: HudMagicTab
var prayer_orb: Control
var run_orb: Control
var popup: PopupPanel
var popup_list: VBoxContainer
var popup_title: Label
var zone_label: Label
var layer_label: Label
var chat_panel: PanelContainer
var settings_popup: PopupPanel
var game_menu_popup: PopupPanel
var admin_menu: AdminMenu
var world_map: WorldMapPanel
var fps_label: Label
var tile_debug_label: Label
var _hud_tl: Control
var _hud_tr: Control
var _hud_bl: Control
var _hud_br: Control
var _hud_tc: Control
var _hud_scale_layers: Array[Control] = []
var _settings_scale_slider: HSlider
var _settings_scale_value: Label
var _settings_volume_slider: HSlider
var _settings_volume_value: Label
var _settings_fullscreen: CheckBox
var _settings_vsync: CheckBox
var _settings_zone_banner: CheckBox
var _settings_chat: CheckBox
var _settings_tooltip: CheckBox
var _settings_show_fps: CheckBox
var _settings_minimap_lock: CheckBox
var _settings_auto_retaliate: CheckBox
var _settings_fps_limit: OptionButton
var _keybind_buttons: Dictionary = {}  # action id -> rebind Button
var _rebinding_action := ""             # action id currently capturing a key, or ""
var _fps_sample_us: int = 0
var _frame_ms_smooth: float = 16.0
const FPS_SAMPLE_BLEND := 0.15


func _ready() -> void:
	_build()
	var eb := EventBus
	eb.combat_log.connect(_push_chat)
	eb.loot_gained.connect(func(item: String, qty: int) -> void:
		_push_chat("[color=#1a6e1a]+%d %s[/color]" % [qty, DataRegistry.item_display_name(item)]))
	eb.level_up.connect(func(skill: String, lvl: int) -> void:
		_push_chat("[color=#a05400]Congratulations, your %s level is now %d![/color]" % [skill.capitalize(), lvl])
		_skills_tab.refresh())
	eb.xp_gained.connect(func(skill: String, _a: float) -> void: _skills_tab.update_cell(skill))
	eb.inventory_changed.connect(func() -> void: _inventory_tab.refresh())
	eb.equipment_changed.connect(func() -> void:
		_equipment_tab.refresh()
		_combat_tab.refresh())
	eb.coins_changed.connect(func(_g: int) -> void: _refresh_coins())
	eb.hp_changed.connect(func(_c: int, _m: int) -> void: hp_orb.queue_redraw())
	eb.activity_started.connect(func(_k: String, label: String) -> void: _push_chat("[color=#444]%s[/color]" % label))
	eb.game_loaded.connect(_refresh_all)
	eb.zone_changed.connect(func(zone_name: String, req: int) -> void:
		zone_label.text = "%s  ·  Lvl %d" % [zone_name, req])
	eb.world_layer_changed.connect(func(layer: int) -> void:
		var cfg: Dictionary = WorldGen.reg.cave_layers.get(layer, {})
		layer_label.text = "" if layer == 0 else str(cfg.get("name", "Underground")))
	eb.obelisk_unlocked.connect(func(name: String) -> void:
		_push_chat("[color=#5a3a8a]Obelisk attuned: %s[/color]" % name))
	_refresh_all()
	_push_chat("Welcome to Imota.")
	_push_chat("[color=#444]Tip: click a skill in the Skills tab to auto-walk to its nodes and stations.[/color]")
	get_tree().node_added.connect(_on_node_added_click_marker)
	_wire_all_click_markers(self)
	GameSettings.changed.connect(_apply_hud_from_settings)
	_apply_hud_from_settings()
	_build_fps_overlay()
	world_map = WorldMapPanel.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	world_map.setup(self)


## Captures the next key while a settings rebind row is armed. Runs ahead of GUI /
## unhandled input so the chosen key rebinds instead of triggering its old action.
func _input(event: InputEvent) -> void:
	if _rebinding_action == "":
		# Map toggle is handled here in _input (ahead of GUI / unhandled input) so a focused
		# HUD control or CanvasLayer input ordering can't swallow the M key — unless we're
		# actually typing into a text field.
		if event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_M or event.physical_keycode == KEY_M):
			var fo := get_viewport().gui_get_focus_owner()
			if not (fo is LineEdit or fo is TextEdit):
				world_map.toggle()
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: int = (event as InputEventKey).keycode
	if kc != KEY_ESCAPE:
		GameSettings.set_keybind(_rebinding_action, kc)
	_rebinding_action = ""
	_refresh_keybind_buttons()
	get_viewport().set_input_as_handled()


## Press M to toggle the full-world map; Esc closes it when open. Configurable
## bindings (Hide HUD, …) are read from GameSettings.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE and world_map.visible:
		world_map.visible = false
		get_viewport().set_input_as_handled()
	elif event.keycode == GameSettings.keybind("hide_hud"):
		hud_root.visible = not hud_root.visible
		get_viewport().set_input_as_handled()


func bind_world(w: Node2D) -> void:
	world = w


func set_hover_text(text: String) -> void:
	hover_label.text = text


func update_world_tooltip(entity: Node2D) -> void:
	# A hovered UI control (inventory item, equipment slot, prayer/spell row) owns the
	# tooltip via attach(); the world picker still finds geometry behind the HUD every
	# frame, so it must stand down here instead of yanking the UI tooltip away.
	if world_tooltip.is_ui_owned():
		hover_label.text = "Walk here"
		hover_label.show()
		return
	if entity == null:
		world_tooltip.hide_for_world()
		hover_label.text = "Walk here"
		hover_label.show()
		return
	if GameSettings.show_hover_tooltip:
		hover_label.hide()
		var content: Dictionary = {}
		if entity.has_method("tooltip_content"):
			content = entity.tooltip_content()
		world_tooltip.show_for(world, entity, content)
		world_tooltip.follow_entity()
	else:
		world_tooltip.hide_for_world()
		hover_label.text = entity.call("action_text")
		hover_label.show()


func update_tile_debug(world_pos: Vector2) -> void:
	if tile_debug_label == null or world == null:
		return
	var d: Dictionary = WorldGen.tile_debug_at(world_pos, int(world.get("current_layer")))
	if d.is_empty():
		tile_debug_label.text = "Tile: (off map)"
		return
	var sub_line := "" if str(d["sub_biome"]).is_empty() else "  Sub: %s" % d["sub_biome"]
	var tile_elev: int = WorldGen.elevation_at(world_pos)
	var player_elev: int = WorldGen.elevation_at(world.player.position) if world.player != null else 0
	tile_debug_label.text = (
		"Tile (%d, %d)  %s\nParent: %s%s  ·  Zone: %s (lvl %d)\nWalk: %s  Water: %s  ·  Elev: %d\nPlayer elev: %d"
		% [
			int(d["tile"].x), int(d["tile"].y), d["tile_name"],
			d["parent_biome"], sub_line, d["zone"], int(d["zone_lvl"]),
			"yes" if d["walkable"] else "no",
			"yes" if d["water"] else "no",
			tile_elev, player_elev,
		]
	)


## The skill the player is training in combat. Reads GameState (the persisted source
## of truth, set whenever the Combat tab's selector changes) so callers never depend
## on the OptionButton widget existing.
func train_style() -> String:
	return GameState.combat_style


func show_ui_click_marker(screen_pos: Vector2) -> void:
	var marker := ClickMarkerNode.new()
	hud_root.add_child(marker)
	marker.position = screen_pos
	marker.call("begin", true)


## One listener for every BaseButton under this HUD layer (inventory refreshes,
## popups, etc.). Non-button click targets (tab bar, skill cells) keep a
## single gui_input hook where they are built.
func _wire_all_click_markers(root: Node) -> void:
	_try_wire_click_marker(root)
	for child: Node in root.get_children():
		_wire_all_click_markers(child)


func _on_node_added_click_marker(node: Node) -> void:
	_try_wire_click_marker(node)


func _try_wire_click_marker(node: Node) -> void:
	if not is_ancestor_of(node):
		return
	if not node is BaseButton or node.has_meta(&"click_fx"):
		return
	node.set_meta(&"click_fx", true)
	node.pressed.connect(func() -> void:
		show_ui_click_marker(get_viewport().get_mouse_position()))


# ------------------------------------------------------------------ build ----

func _style(c: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
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


func _build() -> void:
	layer = 10
	# Single full-rect root: anchored children lay out against the viewport
	# reliably, including window resizes.
	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(hud_root)
	_apply_default_fonts(hud_root)

	# Top-right last so its buttons sit above other full-screen scale layers.
	_hud_tl = _make_hud_scale_layer("HudTopLeft", Vector2(0.0, 0.0))
	_hud_bl = _make_hud_scale_layer("HudBottomLeft", Vector2(0.0, 1.0))
	_hud_br = _make_hud_scale_layer("HudBottomRight", Vector2(1.0, 1.0))
	_hud_tc = _make_hud_scale_layer("HudTopCenter", Vector2(0.5, 0.0))
	_hud_tr = _make_hud_scale_layer("HudTopRight", Vector2(1.0, 0.0))

	# Hover text (top-left, like the OSRS action text).
	hover_label = Label.new()
	hover_label.text = "Walk here"
	_anchor(hover_label, Control.PRESET_TOP_LEFT, Vector2(10, 8), Vector2(280, 24))
	hover_label.add_theme_font_size_override("font_size", UiScale.i(15))
	hover_label.add_theme_color_override("font_color", HOVER_YELLOW)
	hover_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hover_label.add_theme_constant_override("shadow_offset_x", 1)
	hover_label.add_theme_constant_override("shadow_offset_y", 1)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_tl.add_child(hover_label)

	world_tooltip = WorldHoverTooltipScript.new()
	world_tooltip.name = "WorldTooltip"
	hud_root.add_child(world_tooltip)

	_build_minimap_cluster()
	admin_menu = AdminMenu.new()
	admin_menu.setup(self)

	# Zone banner (top-center): procedural area name + level requirement.
	zone_label = Label.new()
	zone_label.text = ""
	zone_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	zone_label.offset_left = UiScale.f(-240.0)
	zone_label.offset_right = UiScale.f(240.0)
	zone_label.offset_top = UiScale.f(8.0)
	zone_label.offset_bottom = UiScale.f(34.0)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.add_theme_font_size_override("font_size", UiScale.i(16))
	zone_label.add_theme_color_override("font_color", Color(0.93, 0.85, 0.55))
	zone_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	zone_label.add_theme_constant_override("shadow_offset_x", 1)
	zone_label.add_theme_constant_override("shadow_offset_y", 1)
	zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_tc.add_child(zone_label)

	layer_label = Label.new()
	layer_label.text = ""
	layer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	layer_label.offset_left = UiScale.f(-240.0)
	layer_label.offset_right = UiScale.f(240.0)
	layer_label.offset_top = UiScale.f(34.0)
	layer_label.offset_bottom = UiScale.f(56.0)
	layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer_label.add_theme_font_size_override("font_size", UiScale.i(12))
	layer_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.8))
	layer_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_tc.add_child(layer_label)

	_build_side_panel()
	_build_chatbox()
	_build_popup()
	_build_settings_popup()
	_build_game_menu()


## Anchor a control to a corner with an offset rect (offsets are relative to
## the anchor corner; positive x/y point into the viewport from top-left).
func _apply_default_fonts(root: Control) -> void:
	var fs := UiScale.i(14)
	root.add_theme_font_size_override("font_size", fs)
	root.add_theme_font_size_override("normal_font_size", fs)


func _anchor(ctrl: Control, preset: int, top_left: Vector2, size: Vector2) -> void:
	var tl := UiScale.v2(top_left)
	var sz := UiScale.v2(size)
	ctrl.set_anchors_preset(preset)
	ctrl.offset_left = tl.x
	ctrl.offset_top = tl.y
	ctrl.offset_right = tl.x + sz.x
	ctrl.offset_bottom = tl.y + sz.y
	ctrl.custom_minimum_size = sz


func _make_hud_scale_layer(layer_name: String, pivot_corner: Vector2) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE lets clicks reach sibling layers behind (PASS only forwards to parent).
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_meta("pivot_corner", pivot_corner)
	layer.resized.connect(_on_hud_scale_layer_resized.bind(layer))
	hud_root.add_child(layer)
	_hud_scale_layers.append(layer)
	_on_hud_scale_layer_resized(layer)
	return layer


func _on_hud_scale_layer_resized(layer: Control) -> void:
	var corner: Vector2 = layer.get_meta("pivot_corner")
	layer.pivot_offset = Vector2(layer.size.x * corner.x, layer.size.y * corner.y)


## OSRS-style interface panel: a content area driven by a row of drawn icon tabs
## along the bottom (Combat / Skills / Inventory / Equipment / Prayer / Magic).
func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(STONE, STONE_DARK))
	_anchor(panel, Control.PRESET_BOTTOM_RIGHT, Vector2(-300, -478), Vector2(274, 446))
	_hud_br.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiScale.i(4))
	panel.add_child(col)

	# The built-in tab bar is hidden; our drawn icon row drives current_tab.
	var tabs := TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			show_ui_click_marker(event.global_position))
	col.add_child(tabs)
	_side_tabs = tabs

	_combat_tab = HudCombatTab.new(self)
	tabs.add_child(_combat_tab.build())
	_skills_tab = HudSkillsTab.new(self)
	tabs.add_child(_skills_tab.build())
	_inventory_tab = HudInventoryTab.new(self)
	tabs.add_child(_inventory_tab.build())
	_equipment_tab = HudEquipmentTab.new(self)
	tabs.add_child(_equipment_tab.build())
	_prayer_tab = HudPrayerTab.new(self)
	tabs.add_child(_prayer_tab.build())
	_magic_tab = HudMagicTab.new(self)
	tabs.add_child(_magic_tab.build())

	# Icon tab row (OSRS sits these under the panel). One per content tab.
	var bar := GridContainer.new()
	bar.columns = 6
	bar.add_theme_constant_override("h_separation", UiScale.i(2))
	col.add_child(bar)
	var defs := [
		["combat", "Combat"], ["skills", "Skills"], ["inventory", "Inventory"],
		["equipment", "Equipment"], ["prayer", "Prayer"], ["magic", "Magic"],
	]
	_tab_icons.clear()
	for i: int in defs.size():
		var ico := TabIcon.new()
		ico.kind = str(defs[i][0])
		ico.tooltip_text = str(defs[i][1])
		var idx := i
		ico.on_press = func() -> void:
			show_ui_click_marker(get_viewport().get_mouse_position())
			_select_side_tab(idx)
		bar.add_child(ico)
		_tab_icons.append(ico)
	_select_side_tab(_startup_side_tab())  # default Inventory (like OSRS); --hud-tab=N overrides for render checks


## Which side tab to open on launch. Honors a `--hud-tab=N` dev flag (0=Combat … 5=Magic)
## so a headless render can capture any tab; defaults to Inventory.
func _startup_side_tab() -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hud-tab="):
			return clampi(int(a.trim_prefix("--hud-tab=")), 0, 5)
	return 2


func _select_side_tab(idx: int) -> void:
	if _side_tabs == null:
		return
	_side_tabs.current_tab = idx
	for i: int in _tab_icons.size():
		_tab_icons[i].set_active(i == idx)


func _build_chatbox() -> void:
	chat_panel = PanelContainer.new()
	chat_panel.add_theme_stylebox_override("panel", _style(PARCHMENT, PARCHMENT_DARK))
	_anchor(chat_panel, Control.PRESET_BOTTOM_LEFT, Vector2(10, -186), Vector2(540, 165))
	_hud_bl.add_child(chat_panel)
	chat = RichTextLabel.new()
	chat.bbcode_enabled = true
	chat.scroll_following = true
	chat.add_theme_color_override("default_color", TEXT_DARK)
	chat.add_theme_font_size_override("normal_font_size", UiScale.i(13))
	chat_panel.add_child(chat)


func _build_popup() -> void:
	popup = PopupPanel.new()
	popup.add_theme_stylebox_override("panel", _style(STONE, STONE_DARK))
	var box := VBoxContainer.new()
	_apply_default_fonts(box)
	box.custom_minimum_size = UiScale.v2(Vector2(420, 430))
	popup_title = Label.new()
	popup_title.add_theme_font_size_override("font_size", UiScale.i(16))
	popup_title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	box.add_child(popup_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	popup_list = VBoxContainer.new()
	popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(popup_list)
	box.add_child(scroll)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: popup.hide())
	box.add_child(close)
	popup.add_child(box)
	add_child(popup)


func _build_settings_popup() -> void:
	settings_popup = PopupPanel.new()
	settings_popup.add_theme_stylebox_override("panel", _style(STONE, STONE_DARK))
	var box := VBoxContainer.new()
	_apply_default_fonts(box)
	box.custom_minimum_size = UiScale.v2(Vector2(380, 500))
	box.add_theme_constant_override("separation", UiScale.i(8))

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", UiScale.i(16))
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	box.add_child(title)

	var scale_row := _add_settings_slider_row(
		box, "HUD / UI size", GameSettings.UI_SCALE_MIN, GameSettings.UI_SCALE_MAX,
		0.01, GameSettings.ui_scale,
		func(v: float) -> String: return "%d%%" % int(roundf(v * 100.0)),
		func(v: float) -> void: GameSettings.set_ui_scale(v))
	_settings_scale_slider = scale_row[0] as HSlider
	_settings_scale_value = scale_row[1] as Label

	var volume_row := _add_settings_slider_row(
		box, "Master volume", 0.0, 1.0, 0.01, GameSettings.master_volume,
		func(v: float) -> String: return "%d%%" % int(roundf(v * 100.0)),
		func(v: float) -> void: GameSettings.set_master_volume(v))
	_settings_volume_slider = volume_row[0] as HSlider
	_settings_volume_value = volume_row[1] as Label

	# Pixelation: 0 = native (no pixelation), 1 = really crunchy (A Short Hike-style).
	_add_settings_slider_row(
		box, "Pixelation", 0.0, 1.0, 0.01, GameSettings.pixelation,
		func(v: float) -> String: return "Native" if v < 0.01 else "%d%%" % int(roundf(v * 100.0)),
		func(v: float) -> void: GameSettings.set_pixelation(v))

	# View distance: how far the world renders before fading into the haze. Higher
	# costs more; the label shows the approximate visible radius in tiles.
	_add_settings_slider_row(
		box, "View distance", 0.0, 1.0, 0.05, GameSettings.view_distance,
		func(v: float) -> String: return "%d tiles" % int(roundf(lerpf(34.0, 64.0, v))),
		func(v: float) -> void: GameSettings.set_view_distance(v))

	# Camera rotation: how fast the arrow keys orbit/tilt the camera (1.0 = default).
	_add_settings_slider_row(
		box, "Camera rotation", GameSettings.CAM_ROTATE_SPEED_MIN, GameSettings.CAM_ROTATE_SPEED_MAX, 0.05, GameSettings.cam_rotate_speed,
		func(v: float) -> String: return "%.2fx" % v,
		func(v: float) -> void: GameSettings.set_cam_rotate_speed(v))

	_settings_fullscreen = _add_settings_checkbox(box, "Fullscreen", GameSettings.fullscreen,
		func(on: bool) -> void: GameSettings.set_fullscreen(on))
	_settings_vsync = _add_settings_checkbox(box, "VSync", GameSettings.vsync,
		func(on: bool) -> void: GameSettings.set_vsync(on))
	_settings_zone_banner = _add_settings_checkbox(box, "Zone banner", GameSettings.show_zone_banner,
		func(on: bool) -> void: GameSettings.set_show_zone_banner(on))
	_settings_chat = _add_settings_checkbox(box, "Chat box", GameSettings.show_chat,
		func(on: bool) -> void: GameSettings.set_show_chat(on))
	_settings_tooltip = _add_settings_checkbox(box, "Entity tooltips", GameSettings.show_hover_tooltip,
		func(on: bool) -> void: GameSettings.set_show_hover_tooltip(on))
	_settings_show_fps = _add_settings_checkbox(box, "Show FPS", GameSettings.show_fps,
		func(on: bool) -> void: GameSettings.set_show_fps(on))
	_settings_minimap_lock = _add_settings_checkbox(box, "Lock minimap rotation", GameSettings.minimap_lock_north,
		func(on: bool) -> void: GameSettings.set_minimap_lock_north(on))
	_settings_auto_retaliate = _add_settings_checkbox(box, "Auto retaliate", GameSettings.auto_retaliate,
		func(on: bool) -> void: GameSettings.set_auto_retaliate(on))
	_settings_fps_limit = _add_settings_option_row(
		box, "FPS limit", GameSettings.FPS_LIMIT_OPTIONS, GameSettings.fps_limit,
		func(value: int) -> void: GameSettings.set_fps_limit(value))

	var kb_title := Label.new()
	kb_title.text = "Key bindings"
	kb_title.add_theme_font_size_override("font_size", UiScale.i(14))
	kb_title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	box.add_child(kb_title)
	for action: Dictionary in GameSettings.KEYBIND_ACTIONS:
		_add_keybind_row(box, str(action["id"]), str(action["label"]))
	_refresh_keybind_buttons()

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: settings_popup.hide())
	box.add_child(close)
	settings_popup.add_child(box)
	add_child(settings_popup)


## OSRS-style minimap cluster: a left column of status orbs (HP / Prayer / Run),
## the circular minimap, and a row of action buttons (Bank / Slayer / World map).
func _build_minimap_cluster() -> void:
	var cluster := Control.new()
	cluster.name = "MinimapCluster"
	_anchor(cluster, Control.PRESET_TOP_RIGHT, Vector2(-252, 8), Vector2(252, 210))
	_hud_tr.add_child(cluster)

	# Minimap (right).
	var map_panel := MinimapPanel.new()
	map_panel.setup(self)
	map_panel.position = UiScale.v2(Vector2(88, 0))
	cluster.add_child(map_panel)
	minimap = map_panel.minimap

	# Status orbs (left column), OSRS-style.
	hp_orb = StatusOrb.new()
	hp_orb.kind = "hp"
	hp_orb.position = UiScale.v2(Vector2(6, 2))
	hp_orb.tooltip_text = "Hitpoints"
	cluster.add_child(hp_orb)

	prayer_orb = StatusOrb.new()
	prayer_orb.kind = "prayer"
	prayer_orb.position = UiScale.v2(Vector2(6, 48))
	prayer_orb.tooltip_text = "Prayer"
	cluster.add_child(prayer_orb)

	run_orb = StatusOrb.new()
	run_orb.kind = "run"
	run_orb.position = UiScale.v2(Vector2(6, 94))
	run_orb.tooltip_text = "Run energy — click to toggle run, right-click to rest"
	cluster.add_child(run_orb)

	coins_label = Label.new()
	coins_label.position = UiScale.v2(Vector2(2, 142))
	coins_label.custom_minimum_size = UiScale.v2(Vector2(82, 20))
	coins_label.size = coins_label.custom_minimum_size
	coins_label.add_theme_font_size_override("font_size", UiScale.i(11))
	coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	coins_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(coins_label)

	# Action buttons under the minimap.
	var bank := IconButton.new()
	bank.kind = "bank"
	bank.label = "Bank"
	bank.tooltip_text = "Auto-walk to the nearest bank"
	bank.position = UiScale.v2(Vector2(88, 166))
	bank.on_press = func() -> void:
		if world != null:
			EventBus.bank_requested.emit()
	cluster.add_child(bank)

	var slay := IconButton.new()
	slay.kind = "slayer"
	slay.label = "Slayer"
	slay.tooltip_text = "Slayer master — browse monsters you can fight"
	slay.position = UiScale.v2(Vector2(140, 166))
	slay.on_press = func() -> void:
		open_slayer()
	cluster.add_child(slay)

	var map_btn := IconButton.new()
	map_btn.kind = "map"
	map_btn.label = "Map"
	map_btn.tooltip_text = "Open the world map (M)"
	map_btn.position = UiScale.v2(Vector2(192, 166))
	map_btn.on_press = func() -> void:
		if world_map != null:
			world_map.toggle()
	cluster.add_child(map_btn)


func _build_game_menu() -> void:
	game_menu_popup = PopupPanel.new()
	game_menu_popup.add_theme_stylebox_override("panel", _style(STONE, STONE_DARK))
	var box := VBoxContainer.new()
	_apply_default_fonts(box)
	box.custom_minimum_size = UiScale.v2(Vector2(240, 340))
	box.add_theme_constant_override("separation", UiScale.i(6))

	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", UiScale.i(16))
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Press Esc to close"
	hint.add_theme_font_size_override("font_size", UiScale.i(11))
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	box.add_child(hint)

	_add_game_menu_button(box, "Save Game", func() -> void:
		SaveManager.save_game()
		_push_chat("[color=#444]Game saved.[/color]")
		game_menu_popup.hide())
	_add_game_menu_button(box, "Bank", func() -> void:
		game_menu_popup.hide()
		if world != null:
			EventBus.bank_requested.emit())
	_add_game_menu_button(box, "Teleport", func() -> void:
		game_menu_popup.hide()
		open_obelisks())
	_add_game_menu_button(box, "Settings", func() -> void:
		game_menu_popup.hide()
		open_settings())
	_add_game_menu_button(box, "Admin", func() -> void:
		game_menu_popup.hide()
		admin_menu.open())

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func() -> void: game_menu_popup.hide())
	box.add_child(resume)

	game_menu_popup.add_child(box)
	add_child(game_menu_popup)


func _add_game_menu_button(parent: VBoxContainer, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(cb)
	parent.add_child(btn)


func toggle_game_menu() -> void:
	if game_menu_popup.visible:
		game_menu_popup.hide()
	else:
		game_menu_popup.popup_centered()


func _try_close_front_popup() -> bool:
	if admin_menu != null and admin_menu.is_open():
		admin_menu.close()
		return true
	if settings_popup != null and settings_popup.visible:
		settings_popup.hide()
		return true
	if popup != null and popup.visible:
		popup.hide()
		return true
	if game_menu_popup != null and game_menu_popup.visible:
		game_menu_popup.hide()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M:
		if world_map != null:
			world_map.toggle()
			get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_ESCAPE:
		return
	if world_map != null and world_map.visible:        # Esc closes the map first
		world_map.visible = false
		get_viewport().set_input_as_handled()
		return
	if _try_close_front_popup():
		get_viewport().set_input_as_handled()
		return
	toggle_game_menu()
	get_viewport().set_input_as_handled()


func _add_settings_slider_row(
	parent: VBoxContainer,
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	initial: float,
	format_value: Callable,
	on_changed: Callable,
) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiScale.i(10))
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = UiScale.f(140.0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = initial
	var value_lbl := Label.new()
	value_lbl.text = format_value.call(initial)
	value_lbl.custom_minimum_size.x = UiScale.f(48.0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		value_lbl.text = format_value.call(v)
		on_changed.call(v))
	row.add_child(slider)
	row.add_child(value_lbl)
	parent.add_child(row)
	return [slider, value_lbl]


func _add_settings_checkbox(
	parent: VBoxContainer,
	label_text: String,
	initial: bool,
	on_changed: Callable,
) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = initial
	cb.toggled.connect(on_changed)
	parent.add_child(cb)
	return cb


func _add_settings_option_row(
	parent: VBoxContainer,
	label_text: String,
	options: Array,
	current_value: int,
	on_changed: Callable,
) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiScale.i(10))
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = UiScale.f(140.0)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_idx := 0
	for i: int in options.size():
		var entry: Dictionary = options[i]
		opt.add_item(str(entry["label"]))
		opt.set_item_metadata(i, int(entry["value"]))
		if int(entry["value"]) == current_value:
			selected_idx = i
	opt.selected = selected_idx
	opt.item_selected.connect(func(idx: int) -> void: on_changed.call(int(opt.get_item_metadata(idx))))
	row.add_child(opt)
	parent.add_child(row)
	return opt


## A rebind row: action label on the left, a button showing the bound key. Pressing
## the button arms capture (_input grabs the next key, Esc cancels).
func _add_keybind_row(parent: VBoxContainer, id: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiScale.i(10))
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = UiScale.f(140.0)
	row.add_child(lbl)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		_rebinding_action = id
		_refresh_keybind_buttons())
	row.add_child(btn)
	parent.add_child(row)
	_keybind_buttons[id] = btn


func _refresh_keybind_buttons() -> void:
	for id: String in _keybind_buttons:
		var btn: Button = _keybind_buttons[id]
		if id == _rebinding_action:
			btn.text = "Press a key…  (Esc to cancel)"
		else:
			var kc := GameSettings.keybind(id)
			btn.text = OS.get_keycode_string(kc) if kc != 0 else "Unbound"


func _build_fps_overlay() -> void:
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(fps_label, Control.PRESET_TOP_LEFT, Vector2(10, 36), Vector2(168, 20))
	fps_label.add_theme_font_size_override("font_size", UiScale.i(13))
	fps_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_label.visible = false
	add_child(fps_label)

	tile_debug_label = Label.new()
	tile_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(tile_debug_label, Control.PRESET_TOP_LEFT, Vector2(10, 58), Vector2(360, 52))
	tile_debug_label.add_theme_font_size_override("font_size", UiScale.i(11))
	tile_debug_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.95))
	tile_debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(tile_debug_label)


func _process(_delta: float) -> void:
	# Live Devotion readout: PrayerSim drains every frame but only emits prayer_changed on
	# toggle/empty, so refresh the number here while the Prayer tab is open.
	if _prayer_tab != null:
		_prayer_tab.update_devotion()
	if fps_label == null:
		return
	if not GameSettings.show_fps:
		fps_label.visible = false
		_fps_sample_us = 0
	else:
		var now_us := Time.get_ticks_usec()
		if _fps_sample_us > 0:
			var frame_ms := clampf(float(now_us - _fps_sample_us) / 1000.0, 0.1, 5000.0)
			_frame_ms_smooth = lerpf(_frame_ms_smooth, frame_ms, FPS_SAMPLE_BLEND)
			var fps := 1000.0 / _frame_ms_smooth
			fps_label.text = "%d FPS  %.1f ms" % [int(roundf(fps)), _frame_ms_smooth]
			var col := Color(0.75, 1.0, 0.75)
			if _frame_ms_smooth > 33.0:
				col = Color(1.0, 0.45, 0.45)
			elif _frame_ms_smooth > 20.0:
				col = Color(1.0, 0.9, 0.4)
			fps_label.add_theme_color_override("font_color", col)
		_fps_sample_us = now_us
		fps_label.visible = true
	if world != null:
		update_tile_debug(world.get_global_mouse_position())


func open_settings() -> void:
	_settings_scale_slider.value = GameSettings.ui_scale
	_settings_scale_value.text = "%d%%" % int(roundf(GameSettings.ui_scale * 100.0))
	_settings_volume_slider.value = GameSettings.master_volume
	_settings_volume_value.text = "%d%%" % int(roundf(GameSettings.master_volume * 100.0))
	_settings_fullscreen.button_pressed = GameSettings.fullscreen
	_settings_vsync.button_pressed = GameSettings.vsync
	_settings_zone_banner.button_pressed = GameSettings.show_zone_banner
	_settings_chat.button_pressed = GameSettings.show_chat
	_settings_tooltip.button_pressed = GameSettings.show_hover_tooltip
	_settings_show_fps.button_pressed = GameSettings.show_fps
	_settings_minimap_lock.button_pressed = GameSettings.minimap_lock_north
	_settings_auto_retaliate.button_pressed = GameSettings.auto_retaliate
	_select_settings_fps_limit(GameSettings.fps_limit)
	settings_popup.popup_centered()


func _select_settings_fps_limit(value: int) -> void:
	for i: int in _settings_fps_limit.item_count:
		if int(_settings_fps_limit.get_item_metadata(i)) == value:
			_settings_fps_limit.select(i)
			return


func _apply_hud_from_settings(_property: StringName = &"") -> void:
	var scale_vec := Vector2(GameSettings.ui_scale, GameSettings.ui_scale)
	for layer: Control in _hud_scale_layers:
		layer.scale = scale_vec
	if zone_label:
		zone_label.visible = GameSettings.show_zone_banner
	if layer_label:
		layer_label.visible = GameSettings.show_zone_banner
	if chat_panel:
		chat_panel.visible = GameSettings.show_chat
	if not GameSettings.show_hover_tooltip:
		world_tooltip.hide_tooltip()


# ----------------------------------------------------------------- popups ----

func _open_popup(title: String) -> void:
	popup_title.text = title
	for c: Node in popup_list.get_children():
		c.queue_free()
	popup.popup_centered()


func open_recipes(skill: String) -> void:
	_open_popup("%s (Lvl %d)" % [skill.capitalize(), GameState.level(skill)])
	for r: Dictionary in DataRegistry.recipes_by_skill.get(skill, []):
		var input_strs: PackedStringArray = []
		for input: Dictionary in r["inputs"]:
			input_strs.append("%dx %s" % [int(input["qty"]), DataRegistry.item_display_name(input["item"])])
		var btn := Button.new()
		btn.text = "%s  (Lvl %d)" % [r.get("displayName", r["name"]), int(r["levelReq"])]
		btn.tooltip_text = "Needs: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
			", ".join(input_strs), int(r["output"]["qty"]), DataRegistry.item_display_name(r["output"]["item"]),
			float(r["xp"]), float(r["time"])]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = GameState.level(skill) < int(r["levelReq"])
		var skill_copy := skill
		var rname: String = r["name"]
		btn.pressed.connect(func() -> void:
			if RecipeSim.start_craft(skill_copy, rname):
				popup.hide())
		popup_list.add_child(btn)


## OSRS-style skill guide: every unlock for the skill in level order. Gather
## nodes get a "Go" button that auto-walks to the nearest node and gathers
## (switching nodes on depletion); recipes get a "Make" button that walks to
## the nearest matching station and starts crafting.
func open_skill_guide(skill: String) -> void:
	# Farming has its own plot panel rather than a node/recipe list.
	if skill == "farming":
		open_farming()
		return
	_open_popup("%s Guide — level %d" % [skill.capitalize(), GameState.level(skill)])
	var lvl := GameState.level(skill)
	var any := false

	var nodes: Array = DataRegistry.gather_nodes.get(skill, [])
	if not nodes.is_empty():
		any = true
		var sorted := nodes.duplicate()
		sorted.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
		# Spoiler-free (spec §3c): show unlocked nodes plus only the NEXT one as a
		# teaser; everything further out stays hidden until reachable.
		var node_teaser_shown := false
		for n: Dictionary in sorted:
			var unlocked: bool = lvl >= int(n["level"])
			if not unlocked:
				if node_teaser_shown:
					continue
				node_teaser_shown = true
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = "Lvl %d  %s" % [int(n["level"]), str(n.get("displayName", n["name"]))]
			var give_names: PackedStringArray = []
			for it: String in n["items"]:
				give_names.append(DataRegistry.item_display_name(it))
			lbl.tooltip_text = "Gives: %s\n%.0f XP per gather" % [", ".join(give_names), float(n["xp"])]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			lbl.add_theme_color_override("font_color",
				Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
			row.add_child(lbl)
			var go := Button.new()
			go.text = "Go"
			go.tooltip_text = "Auto-walk to the nearest %s and gather" % str(n.get("displayName", n["name"]))
			go.disabled = not unlocked
			var node_name := str(n["name"])
			var skill_copy := skill
			go.pressed.connect(func() -> void:
				if world != null:
					EventBus.gather_requested.emit(skill_copy, node_name)
					popup.hide())
			row.add_child(go)
			popup_list.add_child(row)

	var recipes: Array = DataRegistry.recipes_by_skill.get(skill, [])
	if not recipes.is_empty():
		any = true
		var head := Label.new()
		head.text = "— Recipes (made at a %s station) —" % skill.capitalize()
		head.add_theme_color_override("font_color", Color(0.7, 0.62, 0.4))
		popup_list.add_child(head)
		var recipe_teaser_shown := false
		for r: Dictionary in recipes:
			var unlocked: bool = lvl >= int(r["levelReq"])
			if not unlocked:
				if recipe_teaser_shown:
					continue
				recipe_teaser_shown = true
			var row := HBoxContainer.new()
			var lbl := Label.new()
			var input_strs: PackedStringArray = []
			for input: Dictionary in r["inputs"]:
				input_strs.append("%dx %s" % [int(input["qty"]), DataRegistry.item_display_name(input["item"])])
			lbl.text = "Lvl %d  %s" % [int(r["levelReq"]), str(r.get("displayName", r["name"]))]
			lbl.tooltip_text = "Needs: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
				", ".join(input_strs), int(r["output"]["qty"]), DataRegistry.item_display_name(r["output"]["item"]),
				float(r["xp"]), float(r["time"])]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			lbl.add_theme_color_override("font_color",
				Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
			row.add_child(lbl)
			var make := Button.new()
			make.text = "Make"
			make.tooltip_text = "Auto-walk to the nearest station and craft"
			make.disabled = not unlocked
			var recipe_name := str(r["name"])
			var skill_copy2 := skill
			make.pressed.connect(func() -> void:
				if world != null:
					EventBus.station_requested.emit(skill_copy2, recipe_name)
					popup.hide())
			row.add_child(make)
			popup_list.add_child(row)

	if not any:
		var lbl := Label.new()
		if skill in ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "prayer", "slayer"]:
			lbl.text = "Train %s by fighting monsters in the world.\nHigher-level zones hold stronger foes." % skill.capitalize()
		else:
			lbl.text = "%s sites appear in the world as you explore.\n(This skill's sim is still on the roadmap.)" % skill.capitalize()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		popup_list.add_child(lbl)


## Farming panel: shows each plot's state and the seeds you can plant now
## (Farming level met + seed in inventory). Background growth runs on the tick.
func open_farming() -> void:
	_open_popup("Farming — level %d  (%d/%d plots used)" % [
		GameState.level("farming"), FarmingSim.ready_count(), FarmingSim.plot_count])
	for i: int in FarmingSim.plots.size():
		var p: Dictionary = FarmingSim.plots[i]
		var lbl := Label.new()
		if p.is_empty():
			lbl.text = "Plot %d: empty" % (i + 1)
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
		else:
			var pct := int(100.0 * float(p["age"]) / maxf(float(p["grow"]), 1.0))
			lbl.text = "Plot %d: %s — growing %d%%" % [i + 1, DataRegistry.item_display_name(str(p["crop"])), pct]
			lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.45))
		popup_list.add_child(lbl)
	var head := Label.new()
	head.text = "— Plant a seed —"
	head.add_theme_color_override("font_color", Color(0.7, 0.62, 0.4))
	popup_list.add_child(head)
	var seeds: Array = FarmingSim.crops.keys()
	seeds.sort_custom(func(a, b): return int(FarmingSim.crops[a].get("levelReq", 1)) < int(FarmingSim.crops[b].get("levelReq", 1)))
	var teaser := false
	for seed_name: String in seeds:
		var req := int(FarmingSim.crops[seed_name].get("levelReq", 1))
		var unlocked := GameState.level("farming") >= req
		if not unlocked:
			if teaser:
				continue
			teaser = true
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var have := GameState.count_item(seed_name)
		lbl.text = "Lvl %d  %s (x%d)" % [req, DataRegistry.item_display_name(seed_name), have]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
		row.add_child(lbl)
		var plant := Button.new()
		plant.text = "Plant"
		plant.disabled = not unlocked or have <= 0
		var sname := seed_name
		plant.pressed.connect(func() -> void:
			if FarmingSim.plant(sname):
				open_farming())
		row.add_child(plant)
		popup_list.add_child(row)


## Slayer master: the bestiary gated by Slayer level (spoiler-free, spec §3c).
## Clicking a monster arms combat against that type (the §3b Slayer exception).
func open_slayer() -> void:
	var slvl := GameState.level("slayer")
	_open_popup("Slayer Master — level %d" % slvl)
	var list: Array = DataRegistry.enemies.values()
	list.sort_custom(func(a, b):
		return int(a.get("beastMasteryReq", 0)) < int(b.get("beastMasteryReq", 0)))
	var teaser := false
	for e: Dictionary in list:
		var req := int(e.get("beastMasteryReq", 0))
		var unlocked := slvl >= req
		if not unlocked:
			if teaser:
				continue
			teaser = true
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Lvl %d  %s%s" % [int(e.get("level", 1)),
			DataRegistry.enemy_display_name(str(e["name"])),
			"  [BOSS]" if bool(e.get("isBoss", false)) else ""]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.tooltip_text = "Slayer req: %d" % req
		lbl.add_theme_color_override("font_color",
			Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
		row.add_child(lbl)
		var go := Button.new()
		go.text = "Fight"
		go.disabled = not unlocked
		var ename: String = str(e["name"])
		go.pressed.connect(func() -> void:
			if CombatSim.start_combat(ename, GameState.combat_style):
				popup.hide())
		row.add_child(go)
		popup_list.add_child(row)


## Generic NPC dialog (the reusable framework — shopkeepers/quest-givers slot in by `type`).
## Driven by data/npcs.json: shows the NPC's name + greeting, then type-specific options.
func open_npc_dialog(npc_id: String) -> void:
	var npc: Dictionary = DataRegistry.npcs.get(npc_id, {})
	if npc.is_empty():
		return
	_open_popup(str(npc.get("name", "Stranger")))
	var greet := Label.new()
	greet.text = str(npc.get("greeting", ""))
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7))
	popup_list.add_child(greet)
	match str(npc.get("type", "")):
		"slayer_master":
			_npc_slayer_options(npc_id)


func _npc_slayer_options(npc_id: String) -> void:
	var pts := Label.new()
	pts.text = "Slayer points: %d   ·   Slayer level %d" % [GameState.slayer_points, GameState.level("slayer")]
	pts.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	popup_list.add_child(pts)
	if GameState.slayer_task.is_empty():
		var get_btn := Button.new()
		get_btn.text = "Get a Slayer task"
		get_btn.pressed.connect(func() -> void:
			GameState.assign_slayer_task()
			var t: Dictionary = GameState.slayer_task
			if not t.is_empty():
				_push_chat("[color=#9ad29a]New Slayer task: kill %d %s.[/color]" % [
					int(t["required"]), str(t["monster"])])
			open_npc_dialog(npc_id))
		popup_list.add_child(get_btn)
	else:
		var t: Dictionary = GameState.slayer_task
		var tl := Label.new()
		tl.text = "Current task: %s   (%d / %d)" % [
			str(t["monster"]), int(t["done"]), int(t["required"])]
		popup_list.add_child(tl)
		var cancel := Button.new()
		cancel.text = "Cancel task"
		cancel.pressed.connect(func() -> void:
			GameState.cancel_slayer_task()
			open_npc_dialog(npc_id))
		popup_list.add_child(cancel)
	var browse := Button.new()
	browse.text = "Browse monsters to fight"
	browse.pressed.connect(open_slayer)
	popup_list.add_child(browse)


## Teleport list: every obelisk the player has attuned to.
func open_obelisks() -> void:
	_open_popup("Teleport Obelisks")
	var unlocked: Array = WorldGen.unlocked_obelisks()
	if unlocked.is_empty():
		var lbl := Label.new()
		lbl.text = "No obelisks attuned yet.\nFind teleport obelisks out in the world and click them."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		popup_list.add_child(lbl)
		return
	for o: Dictionary in unlocked:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(o["name"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var tp := Button.new()
		tp.text = "Teleport"
		var pos: Vector2 = o["pos"]
		tp.pressed.connect(func() -> void:
			if world != null:
				EventBus.teleport_requested.emit(pos)
				popup.hide())
		row.add_child(tp)
		popup_list.add_child(row)


func open_bank() -> void:
	_open_popup("Bank")
	var dep := Button.new()
	dep.text = "Deposit inventory"
	dep.pressed.connect(func() -> void:
		GameState.deposit_all()
		open_bank())
	popup_list.add_child(dep)
	var names: Array = GameState.bank.keys()
	names.sort()
	for item_id: String in names:
		var item_name := DataRegistry.item_display_name(item_id)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s x%d" % [item_name, int(GameState.bank[item_id])]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var take := Button.new()
		take.text = "Take"
		take.pressed.connect(func() -> void:
			GameState.withdraw(item_id, int(GameState.bank.get(item_id, 0)))
			open_bank())
		row.add_child(take)
		popup_list.add_child(row)


func open_shop() -> void:
	_open_popup("Tool Shop â€” %d coins" % GameState.coins)
	var stock: Array = DataRegistry.tools.values()
	stock.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	for t: Dictionary in stock:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (Lvl %d, power %d)" % [DataRegistry.item_display_name(t["name"]), int(t["level"]), int(t["progress"])]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var buy := Button.new()
		buy.text = "%d" % int(t["value"])
		var tool_name: String = t["name"]
		buy.pressed.connect(func() -> void:
			if GameState.buy_item(tool_name, 1):
				_push_chat("[color=#1a6e1a]Bought %s.[/color]" % tool_name)
				open_shop()
			else:
				_push_chat("[color=#a01010]You can't afford that.[/color]"))
		row.add_child(buy)
		popup_list.add_child(row)


# ---------------------------------------------------------------- refresh ----

func _refresh_all() -> void:
	_skills_tab.refresh()
	_inventory_tab.refresh()
	_equipment_tab.refresh()
	_combat_tab.refresh()
	_refresh_coins()
	hp_orb.queue_redraw()


func _refresh_coins() -> void:
	coins_label.text = "%d coins" % GameState.coins


func _push_chat(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > 100:
		chat_lines = chat_lines.slice(chat_lines.size() - 100)
	chat.text = "\n".join(chat_lines)
