extends Control
## Imota MVP — Melvor-style single screen. Everything is built in code; the
## scene file is just this root Control. The UI only listens to EventBus and
## calls autoload methods: all game logic lives in the sims.

const NodeIconScript := preload("res://scripts/ui/node_icon.gd")

const COL_BG := Color(0.094, 0.102, 0.125)
const COL_PANEL := Color(0.13, 0.14, 0.175)
const COL_PANEL2 := Color(0.165, 0.18, 0.22)
const COL_ACCENT := Color(0.85, 0.72, 0.3)
const COL_TEXT_DIM := Color(0.62, 0.65, 0.72)
const COL_HP := Color(0.75, 0.25, 0.25)
const COL_XP := Color(0.35, 0.62, 0.3)

const TIER_COLORS: Array[Color] = [
	Color(0.55, 0.36, 0.2),   # 1+   bronze
	Color(0.62, 0.62, 0.66),  # 10+  iron/steel
	Color(0.36, 0.62, 0.26),  # 20+  green
	Color(0.25, 0.5, 0.75),   # 40+  blue
	Color(0.55, 0.3, 0.75),   # 60+  purple
	Color(0.85, 0.55, 0.15),  # 80+  orange
	Color(0.85, 0.25, 0.35),  # 100+ red
	Color(0.3, 0.85, 0.8),    # 150+ cyan
]

const GATHER_SKILLS := ["woodcutting", "mining", "fishing", "foraging"]
const GATHER_ICON := {"woodcutting": "tree", "mining": "rock", "fishing": "fish", "foraging": "bush"}
const CRAFT_SKILLS := ["cooking", "smithing", "crafting", "fletching", "alchemy", "prayer"]
const CRAFT_ICON := {
	"cooking": "pot", "smithing": "anvil", "crafting": "gem", "fletching": "bow",
	"alchemy": "flask", "prayer": "candle",
}
const STYLE_ICON := {"melee": "sword", "range": "bow", "mage": "staff"}

var skill_rows: Dictionary = {}    # skill -> {"level": Label, "bar": ProgressBar}
var req_buttons: Array = []        # [{button, check: Callable}] re-enabled on level up

var coins_label: Label
var hp_bar: ProgressBar
var hp_label: Label
var slots_label: Label
var activity_label: Label
var node_icon: Control
var action_bar: ProgressBar
var enemy_box: VBoxContainer
var enemy_bar: ProgressBar
var enemy_label: Label
var feed: RichTextLabel
var stop_button: Button
var inv_list: VBoxContainer
var bank_list: VBoxContainer
var equip_list: VBoxContainer
var train_select: OptionButton

var feed_lines: PackedStringArray = []


func _ready() -> void:
	_build_ui()
	var eb := EventBus
	eb.xp_gained.connect(_on_xp_gained)
	eb.level_up.connect(_on_level_up)
	eb.inventory_changed.connect(_refresh_inventory)
	eb.bank_changed.connect(_refresh_bank)
	eb.equipment_changed.connect(_refresh_equipment)
	eb.coins_changed.connect(func(_g: int) -> void: _refresh_top_bar())
	eb.hp_changed.connect(func(_c: int, _m: int) -> void: _refresh_top_bar())
	eb.activity_started.connect(_on_activity_started)
	eb.activity_stopped.connect(_on_activity_stopped)
	eb.action_progress.connect(func(f: float) -> void: action_bar.value = f)
	eb.loot_gained.connect(func(item: String, qty: int) -> void: _push_feed("[color=#8c8]+%d %s[/color]" % [qty, item]))
	eb.combat_log.connect(func(t: String) -> void: _push_feed(t))
	eb.enemy_hp_changed.connect(_on_enemy_hp)
	eb.enemy_respawning.connect(func(s: float) -> void: _push_feed("[color=#789]Respawning in %.0fs...[/color]" % s))
	eb.player_died.connect(func(k: String) -> void: _push_feed("[color=#e55]Defeated by %s — combat stopped.[/color]" % k))
	eb.game_loaded.connect(_refresh_all)
	_refresh_all()


# ------------------------------------------------------------------ build ----

func _panel_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _make_panel(c: Color = COL_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(c))
	return p


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 8)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)

	col.add_child(_build_top_bar())

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(_build_skills_panel())
	row.add_child(_build_center_panel())
	row.add_child(_build_right_tabs())

	col.add_child(_build_picker())


func _build_top_bar() -> Control:
	var panel := _make_panel(COL_PANEL2)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	panel.add_child(bar)

	var title := Label.new()
	title.text = "IMOTA"
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.add_theme_font_size_override("font_size", 22)
	bar.add_child(title)

	coins_label = Label.new()
	bar.add_child(coins_label)

	hp_label = Label.new()
	bar.add_child(hp_label)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(140, 0)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("fill", _bar_fill(COL_HP))
	bar.add_child(hp_bar)

	slots_label = Label.new()
	bar.add_child(slots_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func() -> void:
		SaveManager.save_game()
		_push_feed("[color=#789]Game saved.[/color]"))
	bar.add_child(save_btn)
	return panel


func _bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(3)
	return sb


func _build_skills_panel() -> Control:
	var panel := _make_panel()
	panel.custom_minimum_size = Vector2(250, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var header := Label.new()
	header.text = "Skills"
	header.add_theme_color_override("font_color", COL_ACCENT)
	list.add_child(header)

	for skill: String in GameState.SKILLS:
		var srow := VBoxContainer.new()
		srow.add_theme_constant_override("separation", 1)
		var hrow := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = skill.capitalize()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(lbl)
		var lvl := Label.new()
		lvl.add_theme_color_override("font_color", COL_ACCENT)
		hrow.add_child(lvl)
		srow.add_child(hrow)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", _bar_fill(COL_XP))
		srow.add_child(bar)
		list.add_child(srow)
		skill_rows[skill] = {"level": lvl, "bar": bar}
	return panel


func _build_center_panel() -> Control:
	var panel := _make_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	activity_label = Label.new()
	activity_label.text = "Idle — pick an activity below"
	activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	activity_label.add_theme_font_size_override("font_size", 17)
	box.add_child(activity_label)

	var icon_center := CenterContainer.new()
	node_icon = NodeIconScript.new()
	icon_center.add_child(node_icon)
	box.add_child(icon_center)

	action_bar = ProgressBar.new()
	action_bar.max_value = 1.0
	action_bar.show_percentage = false
	action_bar.custom_minimum_size = Vector2(0, 14)
	action_bar.add_theme_stylebox_override("fill", _bar_fill(COL_ACCENT))
	box.add_child(action_bar)

	enemy_box = VBoxContainer.new()
	enemy_label = Label.new()
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_box.add_child(enemy_label)
	enemy_bar = ProgressBar.new()
	enemy_bar.show_percentage = false
	enemy_bar.custom_minimum_size = Vector2(0, 12)
	enemy_bar.add_theme_stylebox_override("fill", _bar_fill(COL_HP))
	enemy_box.add_child(enemy_bar)
	enemy_box.visible = false
	box.add_child(enemy_box)

	feed = RichTextLabel.new()
	feed.bbcode_enabled = true
	feed.scroll_following = true
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed.add_theme_color_override("default_color", COL_TEXT_DIM)
	box.add_child(feed)

	stop_button = Button.new()
	stop_button.text = "Stop"
	stop_button.disabled = true
	stop_button.pressed.connect(func() -> void:
		TickSim.stop()
		CombatSim.stop()
		RecipeSim.stop())
	box.add_child(stop_button)
	return panel


func _build_right_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(310, 0)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.name = "Inventory"
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_list = VBoxContainer.new()
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_list)
	tabs.add_child(inv_scroll)

	var bank_scroll := ScrollContainer.new()
	bank_scroll.name = "Bank"
	bank_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bank_list = VBoxContainer.new()
	bank_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_scroll.add_child(bank_list)
	tabs.add_child(bank_scroll)

	var eq_scroll := ScrollContainer.new()
	eq_scroll.name = "Equipment"
	eq_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	equip_list = VBoxContainer.new()
	equip_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_scroll.add_child(equip_list)
	tabs.add_child(eq_scroll)

	var shop_scroll := ScrollContainer.new()
	shop_scroll.name = "Shop"
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var shop_list := VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_scroll.add_child(shop_list)
	var shop_tools: Array = DataRegistry.tools.values()
	shop_tools.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	for t: Dictionary in shop_tools:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (Lvl %d)" % [t["name"], int(t["level"])]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.tooltip_text = "Tool power %d — sells for %d coins" % [int(t["progress"]), int(t["value"])]
		row.add_child(lbl)
		var tool_name: String = t["name"]
		var price: int = int(t["value"])
		row.add_child(_mini_button("Buy (%d)" % price, func() -> void:
			if GameState.buy_item(tool_name, 1):
				_push_feed("[color=#8c8]Bought %s.[/color]" % tool_name)
			else:
				_push_feed("[color=#e55]Can't afford %s (%d coins).[/color]" % [tool_name, price])))
		shop_list.add_child(row)
	tabs.add_child(shop_scroll)
	return tabs


func _build_picker() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 230)

	for skill: String in GATHER_SKILLS:
		var flow := _picker_tab(tabs, skill.capitalize())
		for node: Dictionary in DataRegistry.gather_nodes.get(skill, []):
			var btn := _picker_button(
				"%s\nLvl %d" % [node["name"], int(node["level"])],
				GATHER_ICON[skill], _tier_color(int(node["level"])))
			btn.tooltip_text = "%s\nGives: %s\n%d XP per item" % [node["name"], ", ".join(PackedStringArray(node["items"])), int(node["xp"])]
			var node_name: String = node["name"]
			var skill_copy := skill
			btn.pressed.connect(func() -> void: TickSim.start_gather(skill_copy, node_name))
			var req_level: int = int(node["level"])
			_register_req(btn, func() -> bool: return GameState.level(skill_copy) >= req_level)
			flow.add_child(btn)

	var combat_flow := _picker_tab(tabs, "Combat")
	var train_row := HBoxContainer.new()
	var train_lbl := Label.new()
	train_lbl.text = "Train:"
	train_row.add_child(train_lbl)
	train_select = OptionButton.new()
	for s: String in ["Attack", "Strength", "Defence", "Ranged", "Magic"]:
		train_select.add_item(s)
	train_row.add_child(train_select)
	# The flow container is inside a scroll; put the train selector above it.
	var combat_parent: Control = combat_flow.get_parent().get_parent()
	if combat_parent is VBoxContainer:
		combat_parent.add_child(train_row)
		combat_parent.move_child(train_row, 0)
	var sorted_enemies: Array = DataRegistry.enemies.values()
	sorted_enemies.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	for e: Dictionary in sorted_enemies:
		var style: String = str(e["style"]).to_lower()
		var icon: String = "sword"
		for key: String in STYLE_ICON:
			if style.contains(key):
				icon = STYLE_ICON[key]
		var btn := _picker_button(
			"%s\nLvl %d %s%s" % [e["name"], int(e["level"]), e["style"], " [BOSS]" if e["isBoss"] else ""],
			icon, _tier_color(int(e["level"])))
		var drop_names: PackedStringArray = []
		for d: Dictionary in e["drops"]:
			drop_names.append(str(d["item"]))
		btn.tooltip_text = "%s — HP %d, hits %.0f every %.1fs\nSlayer req: %d\nDrops: %s" % [
			e["name"], int(e["maxHealth"]), float(e["damage"]), float(e["cooldown"]),
			int(e["beastMasteryReq"]), ", ".join(drop_names)]
		var enemy_name: String = e["name"]
		btn.pressed.connect(func() -> void:
			CombatSim.start_combat(enemy_name, train_select.get_item_text(train_select.selected).to_lower()))
		var slayer_req: int = int(e["beastMasteryReq"])
		_register_req(btn, func() -> bool: return GameState.level("slayer") >= slayer_req)
		combat_flow.add_child(btn)

	for skill: String in CRAFT_SKILLS:
		var flow := _picker_tab(tabs, skill.capitalize())
		for r: Dictionary in DataRegistry.recipes_by_skill.get(skill, []):
			var btn := _picker_button(
				"%s\nLvl %d" % [r["name"], int(r["levelReq"])],
				CRAFT_ICON[skill], _tier_color(int(r["levelReq"])))
			var input_strs: PackedStringArray = []
			for input: Dictionary in r["inputs"]:
				input_strs.append("%dx %s" % [int(input["qty"]), input["item"]])
			btn.tooltip_text = "%s\nNeeds: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
				r["name"], ", ".join(input_strs), int(r["output"]["qty"]),
				r["output"]["item"], float(r["xp"]), float(r["time"])]
			var skill_copy := skill
			var recipe_name: String = r["name"]
			btn.pressed.connect(func() -> void: RecipeSim.start_craft(skill_copy, recipe_name))
			var req_level: int = int(r["levelReq"])
			_register_req(btn, func() -> bool: return GameState.level(skill_copy) >= req_level)
			flow.add_child(btn)
	return tabs


func _picker_tab(tabs: TabContainer, title: String) -> HFlowContainer:
	var wrap := VBoxContainer.new()
	wrap.name = title
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	tabs.add_child(wrap)
	return flow


func _picker_button(text: String, icon_kind: String, tier: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 64)
	btn.clip_text = true
	var inner := HBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ic: Control = NodeIconScript.new()
	ic.set("kind", icon_kind)
	ic.set("tier_color", tier)
	ic.scale = Vector2(0.55, 0.55)
	ic.custom_minimum_size = Vector2(44, 64)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(ic)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(lbl)
	btn.add_child(inner)
	return btn


func _register_req(btn: Button, check: Callable) -> void:
	btn.disabled = not bool(check.call())
	req_buttons.append({"button": btn, "check": check})


func _tier_color(level: int) -> Color:
	var idx := 0
	for threshold: int in [10, 20, 40, 60, 80, 100, 150]:
		if level >= threshold:
			idx += 1
	return TIER_COLORS[idx]


# ---------------------------------------------------------------- refresh ----

func _refresh_all() -> void:
	_refresh_top_bar()
	_refresh_skills()
	_refresh_inventory()
	_refresh_bank()
	_refresh_equipment()
	_refresh_req_buttons()


func _refresh_top_bar() -> void:
	coins_label.text = "Coins: %d" % GameState.coins
	hp_label.text = "HP %d/%d" % [GameState.current_hp, GameState.max_hp()]
	hp_bar.max_value = GameState.max_hp()
	hp_bar.value = GameState.current_hp
	slots_label.text = "Bag %d/%d" % [GameState.inventory.size(), GameState.max_inventory_slots()]


func _refresh_skills() -> void:
	for skill: String in skill_rows:
		_update_skill_row(skill)


func _update_skill_row(skill: String) -> void:
	var row: Dictionary = skill_rows[skill]
	var lvl := GameState.level(skill)
	var lvl_label: Label = row["level"]
	lvl_label.text = str(lvl)
	var bar: ProgressBar = row["bar"]
	var cur := float(DataRegistry.xp_for_level(lvl))
	var next := float(DataRegistry.xp_for_level(lvl + 1))
	bar.max_value = maxf(next - cur, 1.0)
	bar.value = GameState.xp(skill) - cur


func _refresh_inventory() -> void:
	_refresh_top_bar()
	_clear(inv_list)
	for stack: Dictionary in GameState.inventory:
		var item_id: String = stack["id"]
		var item_name := DataRegistry.item_display_name(item_id)
		var qty: int = int(stack["qty"])
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s x%d" % [item_name, qty]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.tooltip_text = _item_tooltip(item_name)
		row.add_child(lbl)
		if DataRegistry.food_hp.has(item_id):
			row.add_child(_mini_button("Eat", func() -> void:
				if GameState.eat(item_id):
					_push_feed("[color=#8c8]Ate %s (+%d HP).[/color]" % [item_name, int(DataRegistry.food_hp[item_id])])))
		var slot := GameState.slot_for_item(item_name)
		var item := DataRegistry.get_item(item_name)
		if not item.is_empty() and slot not in ["Food", "Potion", "Lockpick", "Slate"]:
			row.add_child(_mini_button("Equip", func() -> void:
				if not GameState.equip(item_name):
					_push_feed("[color=#e55]Can't equip %s (level requirement).[/color]" % item_name)))
		row.add_child(_mini_button("Bank", func() -> void: GameState.deposit(item_name, GameState.count_item(item_name))))
		row.add_child(_mini_button("Sell", func() -> void: GameState.sell_item(item_name, GameState.count_item(item_name))))
		inv_list.add_child(row)
	if not GameState.inventory.is_empty():
		var all_btn := Button.new()
		all_btn.text = "Deposit All"
		all_btn.pressed.connect(func() -> void: GameState.deposit_all())
		inv_list.add_child(all_btn)


func _refresh_bank() -> void:
	_clear(bank_list)
	var names: Array = GameState.bank.keys()
	names.sort()
	for item_id: String in names:
		var item_name := DataRegistry.item_display_name(item_id)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s x%d" % [item_name, int(GameState.bank[item_id])]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.tooltip_text = _item_tooltip(item_name)
		row.add_child(lbl)
		row.add_child(_mini_button("Take", func() -> void: GameState.withdraw(item_id, int(GameState.bank.get(item_id, 0)))))
		bank_list.add_child(row)


func _refresh_equipment() -> void:
	_clear(equip_list)
	for slot: String in GameState.EQUIPMENT_SLOTS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var worn_id: String = str(GameState.equipment.get(slot, ""))
		var worn := DataRegistry.item_display_name(worn_id) if not worn_id.is_empty() else "—"
		lbl.text = "%s: %s" % [slot, worn]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		if worn != "—":
			lbl.tooltip_text = _item_tooltip(worn)
		row.add_child(lbl)
		if GameState.equipment.has(slot):
			var slot_copy := slot
			row.add_child(_mini_button("X", func() -> void: GameState.unequip(slot_copy)))
		equip_list.add_child(row)
	var stats := Label.new()
	stats.text = "\nMelee: +%.0f dmg, +%.0f%% acc\nRanged: +%.0f dmg, +%.0f%% acc\nMagic: +%.0f dmg, +%.0f%% acc\nDmg reduction: %.1f%%" % [
		GameState.equipment_damage(), GameState.equipment_accuracy() * 100.0,
		GameState.equipment_range_damage(), GameState.equipment_range_accuracy() * 100.0,
		GameState.equipment_magic_damage(), GameState.equipment_magic_accuracy() * 100.0,
		GameState.equipment_damage_reduction()]
	stats.add_theme_color_override("font_color", COL_TEXT_DIM)
	equip_list.add_child(stats)


func _item_tooltip(item_name: String) -> String:
	var item := DataRegistry.get_item(item_name)
	if item.is_empty():
		return item_name
	var lines: PackedStringArray = [item_name]
	var info: String = str(item.get("info", ""))
	if not info.is_empty():
		lines.append(info)
	lines.append("Value: %d" % int(item.get("value", 0)))
	for stat: Array in [["damage", "Melee dmg"], ["accuracy", "Melee acc"],
			["rangeDamage", "Ranged dmg"], ["magicDamage", "Magic dmg"],
			["damageReduction", "Dmg reduction"], ["progress", "Tool power"]]:
		var v: float = float(item.get(stat[0], 0))
		if v != 0.0:
			lines.append("%s: %s" % [stat[1], str(v)])
	var reqs: Dictionary = item.get("reqs", {})
	for skill: String in reqs:
		lines.append("Requires %s %d" % [skill.capitalize(), int(reqs[skill])])
	return "\n".join(lines)


func _mini_button(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(on_press)
	return btn


func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		child.queue_free()


func _refresh_req_buttons() -> void:
	for entry: Dictionary in req_buttons:
		var btn: Button = entry["button"]
		var check: Callable = entry["check"]
		btn.disabled = not bool(check.call())


# ----------------------------------------------------------------- events ----

func _on_xp_gained(skill: String, _amount: float) -> void:
	if skill_rows.has(skill):
		_update_skill_row(skill)


func _on_level_up(skill: String, new_level: int) -> void:
	_push_feed("[color=#fd5]%s level up! Now %d.[/color]" % [skill.capitalize(), new_level])
	if skill_rows.has(skill):
		_update_skill_row(skill)
	_refresh_req_buttons()
	if skill == "hitpoints":
		_refresh_top_bar()


func _on_activity_started(kind: String, label: String) -> void:
	activity_label.text = label
	stop_button.disabled = false
	node_icon.set("animate", true)
	node_icon.set("shake", kind == "combat")
	enemy_box.visible = kind == "combat"
	match kind:
		"gather":
			var skill: String = TickSim.skill
			node_icon.set("kind", GATHER_ICON.get(skill, "tree"))
			node_icon.set("tier_color", _tier_color(int(TickSim.node.get("level", 1))))
		"combat":
			var style: String = str(CombatSim.enemy.get("style", "Melee")).to_lower()
			var icon := "sword"
			for key: String in STYLE_ICON:
				if style.contains(key):
					icon = STYLE_ICON[key]
			node_icon.set("kind", icon)
			node_icon.set("tier_color", _tier_color(int(CombatSim.enemy.get("level", 1))))
		"craft":
			var skill: String = str(RecipeSim.recipe.get("skill", "cooking"))
			node_icon.set("kind", CRAFT_ICON.get(skill, "pot"))
			node_icon.set("tier_color", _tier_color(int(RecipeSim.recipe.get("levelReq", 1))))
	_push_feed("[color=#adf]%s[/color]" % label)


func _on_activity_stopped(reason: String) -> void:
	if reason == "switching":
		return
	activity_label.text = "Idle — pick an activity below"
	stop_button.disabled = true
	action_bar.value = 0.0
	node_icon.set("animate", false)
	enemy_box.visible = false


func _on_enemy_hp(current: float, max_hp: float) -> void:
	enemy_bar.max_value = max_hp
	enemy_bar.value = current
	if CombatSim.active:
		enemy_label.text = "%s  %.0f / %.0f" % [str(CombatSim.enemy.get("name", "")), current, max_hp]


func _push_feed(line: String) -> void:
	feed_lines.append(line)
	if feed_lines.size() > 120:
		feed_lines = feed_lines.slice(feed_lines.size() - 120)
	feed.text = "\n".join(feed_lines)
