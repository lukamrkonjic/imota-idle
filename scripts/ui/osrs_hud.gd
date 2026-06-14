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

const SKILL_ABBREV := {
	"attack": "Atk", "strength": "Str", "defence": "Def", "hitpoints": "HP",
	"ranged": "Rng", "magic": "Mag", "devotion": "Dev", "beastmastery": "BM",
	"woodcutting": "WC", "mining": "Min", "fishing": "Fsh", "foraging": "For",
	"thieving": "Thv", "dexterity": "Dex", "tracking": "Trk", "homesteading": "Hms",
	"cooking": "Cook", "smithing": "Smth", "firemaking": "FM", "fletching": "Flt",
	"crafting": "Crft", "herbology": "Herb", "imbuing": "Imb", "soulbinding": "Soul",
}

var world: Node2D = null

var hud_root: Control
var hover_label: Label
var world_tooltip: PanelContainer
var chat: RichTextLabel
var chat_lines: PackedStringArray = []
var minimap: Control
var hp_orb: Control
var inv_grid: GridContainer
var equip_list: VBoxContainer
var skill_cells: Dictionary = {}  # skill -> Label
var train_select: OptionButton
var combat_info: Label
var coins_label: Label
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
var _settings_fps_limit: OptionButton
var _fps_sample_us: int = 0
var _frame_ms_smooth: float = 16.0
const FPS_SAMPLE_BLEND := 0.15


func _ready() -> void:
	_build()
	var eb := EventBus
	eb.combat_log.connect(_push_chat)
	eb.loot_gained.connect(func(item: String, qty: int) -> void:
		_push_chat("[color=#1a6e1a]+%d %s[/color]" % [qty, item]))
	eb.level_up.connect(func(skill: String, lvl: int) -> void:
		_push_chat("[color=#a05400]Congratulations, your %s level is now %d![/color]" % [skill.capitalize(), lvl])
		_refresh_skills())
	eb.xp_gained.connect(func(skill: String, _a: float) -> void: _update_skill_cell(skill))
	eb.inventory_changed.connect(_refresh_inventory)
	eb.equipment_changed.connect(func() -> void:
		_refresh_equipment()
		_refresh_combat_info())
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


## Press M to toggle the full-world map; Esc closes it when open.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_M:
		world_map.toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and world_map.visible:
		world_map.visible = false
		get_viewport().set_input_as_handled()


func bind_world(w: Node2D) -> void:
	world = w


func set_hover_text(text: String) -> void:
	hover_label.text = text


func update_world_tooltip(entity: Node2D) -> void:
	if entity == null:
		world_tooltip.hide_tooltip()
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
		world_tooltip.hide_tooltip()
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


func train_style() -> String:
	return train_select.get_item_text(train_select.selected).to_lower()


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


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(STONE, STONE_DARK))
	_anchor(panel, Control.PRESET_BOTTOM_RIGHT, Vector2(-326, -454), Vector2(300, 420))
	_hud_br.add_child(panel)

	var tabs := TabContainer.new()
	tabs.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			show_ui_click_marker(event.global_position))
	panel.add_child(tabs)

	# Combat tab.
	var combat_box := VBoxContainer.new()
	combat_box.name = "Combat"
	var train_row := HBoxContainer.new()
	var tl := Label.new()
	tl.text = "Train:"
	train_row.add_child(tl)
	train_select = OptionButton.new()
	for s: String in ["Attack", "Strength", "Defence", "Ranged", "Magic"]:
		train_select.add_item(s)
	train_row.add_child(train_select)
	combat_box.add_child(train_row)
	combat_info = Label.new()
	combat_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_info.add_theme_font_size_override("font_size", UiScale.i(13))
	combat_box.add_child(combat_info)
	tabs.add_child(combat_box)

	# Skills tab: OSRS-style 3x8 grid. Clicking a cell opens the skill guide
	# with all unlocks and auto-walk actions.
	var skills_grid := GridContainer.new()
	skills_grid.name = "Skills"
	skills_grid.columns = 3
	for skill: String in GameState.SKILLS:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", _style(STONE_DARK))
		cell.custom_minimum_size = UiScale.v2(Vector2(92, 42))
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var skill_copy := skill
		cell.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_ui_click_marker(event.global_position)
				open_skill_guide(skill_copy))
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", UiScale.i(12))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lbl)
		skills_grid.add_child(cell)
		skill_cells[skill] = lbl
	tabs.add_child(skills_grid)

	# Inventory tab: 4x7 grid like OSRS.
	var inv_wrap := VBoxContainer.new()
	inv_wrap.name = "Inventory"
	inv_grid = GridContainer.new()
	inv_grid.columns = 4
	inv_wrap.add_child(inv_grid)
	var hint := Label.new()
	hint.text = "Left-click: equip/eat. Right-click: more."
	hint.add_theme_font_size_override("font_size", UiScale.i(10))
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	inv_wrap.add_child(hint)
	tabs.add_child(inv_wrap)

	# Equipment tab.
	var eq_scroll := ScrollContainer.new()
	eq_scroll.name = "Equip"
	eq_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	equip_list = VBoxContainer.new()
	equip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_scroll.add_child(equip_list)
	tabs.add_child(eq_scroll)


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
	_settings_fps_limit = _add_settings_option_row(
		box, "FPS limit", GameSettings.FPS_LIMIT_OPTIONS, GameSettings.fps_limit,
		func(value: int) -> void: GameSettings.set_fps_limit(value))

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: settings_popup.hide())
	box.add_child(close)
	settings_popup.add_child(box)
	add_child(settings_popup)


func _build_minimap_cluster() -> void:
	var cluster := Control.new()
	cluster.name = "MinimapCluster"
	_anchor(cluster, Control.PRESET_TOP_RIGHT, Vector2(-218, 8), Vector2(218, 162))
	_hud_tr.add_child(cluster)

	hp_orb = HpOrb.new()
	hp_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_orb.position = UiScale.v2(Vector2(0, 6))
	hp_orb.custom_minimum_size = UiScale.v2(Vector2(52, 52))
	hp_orb.size = hp_orb.custom_minimum_size
	cluster.add_child(hp_orb)

	coins_label = Label.new()
	coins_label.position = UiScale.v2(Vector2(0, 58))
	coins_label.custom_minimum_size = UiScale.v2(Vector2(84, 22))
	coins_label.size = coins_label.custom_minimum_size
	coins_label.add_theme_font_size_override("font_size", UiScale.i(12))
	coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	coins_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(coins_label)

	var map_panel := MinimapPanel.new()
	map_panel.setup(self)
	map_panel.position = UiScale.v2(Vector2(62, 0))
	cluster.add_child(map_panel)
	minimap = map_panel.minimap


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
			world.call("auto_bank"))
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
			input_strs.append("%dx %s" % [int(input["qty"]), input["item"]])
		var btn := Button.new()
		btn.text = "%s  (Lvl %d)" % [r["name"], int(r["levelReq"])]
		btn.tooltip_text = "Needs: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
			", ".join(input_strs), int(r["output"]["qty"]), r["output"]["item"],
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
	_open_popup("%s Guide — level %d" % [skill.capitalize(), GameState.level(skill)])
	var lvl := GameState.level(skill)
	var any := false

	var nodes: Array = DataRegistry.gather_nodes.get(skill, [])
	if not nodes.is_empty():
		any = true
		var sorted := nodes.duplicate()
		sorted.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
		for n: Dictionary in sorted:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			var unlocked: bool = lvl >= int(n["level"])
			lbl.text = "Lvl %d  %s" % [int(n["level"]), str(n["name"])]
			lbl.tooltip_text = "Gives: %s\n%.0f XP per gather" % [", ".join(PackedStringArray(n["items"])), float(n["xp"])]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			lbl.add_theme_color_override("font_color",
				Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
			row.add_child(lbl)
			var go := Button.new()
			go.text = "Go"
			go.tooltip_text = "Auto-walk to the nearest %s and gather" % str(n["name"])
			go.disabled = not unlocked
			var node_name := str(n["name"])
			var skill_copy := skill
			go.pressed.connect(func() -> void:
				if world != null:
					world.call("auto_gather", skill_copy, node_name)
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
		for r: Dictionary in recipes:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			var unlocked: bool = lvl >= int(r["levelReq"])
			var input_strs: PackedStringArray = []
			for input: Dictionary in r["inputs"]:
				input_strs.append("%dx %s" % [int(input["qty"]), input["item"]])
			lbl.text = "Lvl %d  %s" % [int(r["levelReq"]), str(r["name"])]
			lbl.tooltip_text = "Needs: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
				", ".join(input_strs), int(r["output"]["qty"]), r["output"]["item"],
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
					world.call("auto_station", skill_copy2, recipe_name)
					popup.hide())
			row.add_child(make)
			popup_list.add_child(row)

	if not any:
		var lbl := Label.new()
		if skill in ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "devotion", "beastmastery"]:
			lbl.text = "Train %s by fighting monsters in the world.\nHigher-level zones hold stronger foes." % skill.capitalize()
		else:
			lbl.text = "%s sites appear in the world as you explore.\n(This skill's sim is still on the roadmap.)" % skill.capitalize()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		popup_list.add_child(lbl)


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
				world.call("teleport_to", pos)
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
		lbl.text = "%s (Lvl %d, power %d)" % [t["name"], int(t["level"]), int(t["progress"])]
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
	_refresh_skills()
	_refresh_inventory()
	_refresh_equipment()
	_refresh_combat_info()
	_refresh_coins()
	hp_orb.queue_redraw()


func _refresh_coins() -> void:
	coins_label.text = "%d coins" % GameState.coins


func _refresh_skills() -> void:
	for skill: String in skill_cells:
		_update_skill_cell(skill)


func _update_skill_cell(skill: String) -> void:
	var lbl: Label = skill_cells[skill]
	var lvl := GameState.level(skill)
	lbl.text = "%s\n%d" % [SKILL_ABBREV.get(skill, skill), lvl]
	var cur := float(DataRegistry.xp_for_level(lvl))
	var next := float(DataRegistry.xp_for_level(lvl + 1))
	var frac := clampf((GameState.xp(skill) - cur) / maxf(next - cur, 1.0), 0.0, 1.0)
	lbl.tooltip_text = "%s â€” level %d\n%.0f XP (%.0f%% to next)" % [skill.capitalize(), lvl, GameState.xp(skill), frac * 100.0]


static func _abbrev(item_name: String) -> String:
	var words := item_name.split(" ", false)
	var out := ""
	for w: String in words:
		out += w[0]
		if out.length() >= 3:
			break
	return out


func _refresh_inventory() -> void:
	for c: Node in inv_grid.get_children():
		c.queue_free()
	for i: int in GameState.max_inventory_slots():
		var btn := Button.new()
		btn.custom_minimum_size = UiScale.v2(Vector2(64, 50))
		if i < GameState.inventory.size():
			var stack: Dictionary = GameState.inventory[i]
			var item_id: String = stack["id"]
			var item_name := DataRegistry.item_display_name(item_id)
			btn.text = "%s\n%d" % [_abbrev(item_name), int(stack["qty"])]
			btn.tooltip_text = item_name
			# OSRS-ish color coding by hash so stacks are tellable apart.
			var h := _hash_color(item_name)
			btn.add_theme_color_override("font_color", h)
			btn.add_theme_color_override("font_hover_color", h.lightened(0.3))
			btn.gui_input.connect(_on_inv_slot_input.bind(item_id))
			btn.pressed.connect(_inv_default_action.bind(item_id))
		else:
			btn.disabled = true
		inv_grid.add_child(btn)


static func _hash_color(s: String) -> Color:
	var h := float(hash(s) % 360) / 360.0
	return Color.from_hsv(h, 0.45, 0.95)


func _inv_default_action(item_id: String) -> void:
	var item_name := DataRegistry.item_display_name(item_id)
	if DataRegistry.food_hp.has(item_id):
		if GameState.eat(item_id):
			_push_chat("[color=#1a6e1a]You eat the %s. (+%d HP)[/color]" % [item_name, int(DataRegistry.food_hp[item_id])])
		else:
			_push_chat("[color=#444]You're already at full health.[/color]")
		return
	var slot := GameState.slot_for_item(item_name)
	if slot not in ["Food", "Potion", "Lockpick", "Slate"]:
		if GameState.equip(item_id):
			_push_chat("[color=#444]Equipped %s.[/color]" % item_name)
		else:
			_push_chat("[color=#a01010]You can't equip that yet (level requirement).[/color]")


func _on_inv_slot_input(event: InputEvent, item_id: String) -> void:
	var item_name := DataRegistry.item_display_name(item_id)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var menu := PopupMenu.new()
		menu.add_item("Deposit all", 0)
		menu.add_item("Sell all (%dg each)" % DataRegistry.item_value(item_name), 1)
		menu.id_pressed.connect(func(id: int) -> void:
			var qty := GameState.count_item(item_name)
			if id == 0:
				_push_chat("[color=#444]No bank chest here â€” use the one in town.[/color]")
				GameState.deposit(item_name, qty)
			else:
				GameState.sell_item(item_name, qty)
				_push_chat("[color=#1a6e1a]Sold %d %s.[/color]" % [qty, item_name])
			menu.queue_free())
		add_child(menu)
		menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _refresh_equipment() -> void:
	for c: Node in equip_list.get_children():
		c.queue_free()
	for slot: String in GameState.EQUIPMENT_SLOTS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var worn_id: String = str(GameState.equipment.get(slot, ""))
		var worn := DataRegistry.item_display_name(worn_id) if not worn_id.is_empty() else "â€”"
		lbl.text = "%s: %s" % [slot, worn]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", UiScale.i(12))
		row.add_child(lbl)
		if GameState.equipment.has(slot):
			var btn := Button.new()
			btn.text = "X"
			var slot_copy := slot
			btn.pressed.connect(func() -> void: GameState.unequip(slot_copy))
			row.add_child(btn)
		equip_list.add_child(row)


func _refresh_combat_info() -> void:
	combat_info.text = "\nMelee: +%.0f dmg, +%.0f%% acc\nRanged: +%.0f dmg, +%.0f%% acc\nMagic: +%.0f dmg, +%.0f%% acc\nDmg reduction: %.1f%%\n\nClick an enemy in the world to fight." % [
		GameState.equipment_damage(), GameState.equipment_accuracy() * 100.0,
		GameState.equipment_range_damage(), GameState.equipment_range_accuracy() * 100.0,
		GameState.equipment_magic_damage(), GameState.equipment_magic_accuracy() * 100.0,
		GameState.equipment_damage_reduction()]


func _push_chat(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > 100:
		chat_lines = chat_lines.slice(chat_lines.size() - 100)
	chat.text = "\n".join(chat_lines)


# ------------------------------------------------------------ sub-widgets ----

class MinimapPanel extends Control:
	## OSRS-style minimap cluster: circular map with small orb zoom buttons on the rim.
	var hud: CanvasLayer
	var minimap: MinimapControl

	const MAP_SIZE := Vector2(150, 150)
	const ORB_SIZE := Vector2(24, 24)


	func setup(h: CanvasLayer) -> void:
		hud = h
		custom_minimum_size = UiScale.v2(Vector2(160, 162))
		size = custom_minimum_size

		minimap = MinimapControl.new()
		minimap.hud = hud
		minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap.position = UiScale.v2(Vector2(0, 0))
		minimap.custom_minimum_size = UiScale.v2(MAP_SIZE)
		minimap.size = minimap.custom_minimum_size
		add_child(minimap)

		var center := UiScale.v2(MAP_SIZE * 0.5)
		var rim := UiScale.f(MAP_SIZE.x * 0.5 - 4.0)

		var zoom_out := _make_orb_button("−")
		zoom_out.tooltip_text = "Zoom out (see more)"
		zoom_out.position = center + Vector2(-rim * 0.72, rim * 0.72) - UiScale.v2(ORB_SIZE * 0.5)
		zoom_out.pressed.connect(minimap.zoom_out)
		add_child(zoom_out)

		var zoom_in := _make_orb_button("+")
		zoom_in.tooltip_text = "Zoom in (see less)"
		zoom_in.position = center + Vector2(rim * 0.72, rim * 0.72) - UiScale.v2(ORB_SIZE * 0.5)
		zoom_in.pressed.connect(minimap.zoom_in)
		add_child(zoom_in)


	func _make_orb_button(label: String) -> Button:
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = UiScale.v2(ORB_SIZE)
		btn.size = btn.custom_minimum_size
		btn.add_theme_font_size_override("font_size", UiScale.i(14))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.18, 0.16, 0.14)
		normal.border_color = Color(0.55, 0.5, 0.35)
		normal.set_border_width_all(UiScale.i(2))
		normal.set_corner_radius_all(UiScale.i(12))
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", normal)
		btn.add_theme_stylebox_override("pressed", normal)
		btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
		return btn


class MinimapControl extends Control:
	## Terrain minimap: paints the loaded chunks' ground tiles (so rivers,
	## biomes, and cave walls show up), then entity and POI dots.
	const WG := preload("res://scripts/worldgen/wg.gd")
	const BASE_SCALE := 0.052
	const TILE_PX := 3.0
	const ZOOM_MIN := -2
	const ZOOM_MAX := 5
	var hud: CanvasLayer
	var zoom_level := 0
	var _t := 0.0

	func zoom_in() -> void:
		zoom_level = mini(ZOOM_MAX, zoom_level + 1)
		queue_redraw()

	func zoom_out() -> void:
		zoom_level = maxi(ZOOM_MIN, zoom_level - 1)
		queue_redraw()

	func _view_scale() -> float:
		return BASE_SCALE * pow(1.35, float(zoom_level))

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.25:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var r := size.x / 2.0
		var c := size / 2.0
		draw_circle(c, r, Color(0.08, 0.09, 0.08, 0.95))
		if hud != null and hud.world != null:
			_draw_terrain(c, r)
			_draw_dots(c, r)
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(0.55, 0.5, 0.35), 2.5)
		draw_circle(c, 3.0, Color.WHITE)

	func _draw_terrain(c: Vector2, r: float) -> void:
		var player: Node2D = hud.world.player
		var reg: RefCounted = WorldGen.reg
		var scale := _view_scale()
		var px := WG.TILE * scale * TILE_PX / 2.5
		var limit_sq := (r - 2.0) * (r - 2.0)
		for chunk: RefCounted in hud.world.chunk_manager.loaded_chunks():
			for ty: int in 16:
				for tx: int in 16:
					var gtx: int = chunk.cx * WG.CHUNK_TILES + tx
					var gty: int = chunk.cy * WG.CHUNK_TILES + ty
					var world_pos := WG.tile_to_world(gtx, gty)
					var rel := (world_pos - player.position) * scale * (TILE_PX / 2.5)
					if rel.length_squared() > limit_sq:
						continue
					var cols: Array = reg.tile_def(chunk.tile_id(tx, ty))["colors"]
					draw_rect(Rect2(c + rel - Vector2(px, px) * 0.5, Vector2(px, px)), cols[0])

	func _draw_dots(c: Vector2, r: float) -> void:
		var player: Node2D = hud.world.player
		var scale := _view_scale()
		for e: Node2D in hud.world.entities:
			# Only interactable entities get a dot; decorative props (walls, pillars,
			# houses, ruins) carry an empty action and would otherwise add hundreds of
			# pointless dots + iterations every redraw.
			var atype := str(e.action.get("type", ""))
			if atype.is_empty():
				continue
			var rel := (e.position - player.position) * scale * (TILE_PX / 2.5)
			if rel.length() > r - 5.0:
				continue
			var col := Color(0.9, 0.2, 0.2)
			match atype:
				"gather":
					col = {
						"woodcutting": Color(0.3, 0.8, 0.3), "mining": Color(0.7, 0.7, 0.75),
						"fishing": Color(0.35, 0.6, 0.95), "foraging": Color(0.65, 0.9, 0.3),
					}.get(str(e.action.get("skill", "")), Color.WHITE)
				"station":
					col = Color(1.0, 0.85, 0.2)
				"descend", "ascend":
					col = Color(0.75, 0.75, 0.8)
				"obelisk":
					col = Color(0.85, 0.4, 0.9)
				"landmark":
					col = Color.WHITE
				"hook":
					col = Color(0.78, 0.56, 0.34)
			draw_circle(c + rel, 2.0, col)


class HpOrb extends Control:
	func _draw() -> void:
		var r := size.x / 2.0
		var c := size / 2.0
		var frac := float(GameState.current_hp) / maxf(float(GameState.max_hp()), 1.0)
		draw_circle(c, r, Color(0.15, 0.05, 0.05))
		# Fill from the bottom up.
		var fill_h := size.y * frac
		draw_rect(Rect2(Vector2(0, size.y - fill_h), Vector2(size.x, fill_h)).intersection(Rect2(Vector2.ZERO, size)), Color(0.7, 0.12, 0.12))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(0.55, 0.5, 0.35), 2.5)
		var font := ThemeDB.fallback_font
		var text := str(GameState.current_hp)
		var fs := UiScale.i(14)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, c + Vector2(-tw / 2.0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
