extends Node
class_name HudPopups
## The HUD's shared content popup (bank / shop / slayer / NPC dialog / farming / obelisks / recipe
## list / skill guide), extracted from osrs_hud.gd. Self-contained: owns its PopupPanel + scrolling
## list + title and builds each screen's rows from live GameState/sim data. osrs_hud creates one,
## sets `world`, calls build(), and forwards its open_*() methods here. Chat messages go out on
## EventBus.combat_log (the HUD's chatbox listens), so this never reaches back into the HUD.

const UiScale := preload("res://scripts/ui/ui_scale.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")
const STONE := UiTheme.STONE
const STONE_DARK := UiTheme.STONE_DARK

var world: Node2D = null          # set by osrs_hud; popups use it for world-facing actions
var hud = null                    # owning osrs_hud, for the shared click-marker FX
var popup: PopupPanel
var popup_list: VBoxContainer
var popup_title: Label


func setup(w: Node2D, h: Node) -> void:
	world = w
	hud = h


## Re-apply the UI scale to the popup window (called by the HUD when settings change).
func scale() -> void:
	_scale_popup(popup)


func _style(c: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	return UiTheme.padded_style(c, border)


func _apply_default_fonts(root: Control) -> void:
	var fs := UiScale.i(14)
	root.add_theme_font_size_override("font_size", fs)
	root.add_theme_font_size_override("normal_font_size", fs)


func _scale_popup(p: Window) -> void:
	if p != null:
		p.content_scale_factor = GameSettings.ui_scale


func build() -> void:
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


func _open_popup(title: String) -> void:
	popup_title.text = title
	for c: Node in popup_list.get_children():
		c.queue_free()
	_scale_popup(popup)
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
		# Every node, level order: icon + name, whole row clicks to auto-gather. Rows above the
		# player's level are faded + non-interactive (locked).
		for n: Dictionary in sorted:
			var unlocked: bool = lvl >= int(n["level"])
			var give_names: PackedStringArray = []
			for it: String in n["items"]:
				give_names.append(DataRegistry.item_display_name(it))
			var icon_item := str(n["items"][0]) if not (n["items"] as Array).is_empty() else ""
			var title := str(n.get("displayName", n["name"]))
			var tip := "Gives: %s\n%.0f XP per gather" % [", ".join(give_names), float(n["xp"])]
			if not unlocked:
				tip += "\nRequires %s level %d" % [skill.capitalize(), int(n["level"])]
			var node_name := str(n["name"])
			var skill_copy := skill
			var act := func() -> void:
				if world != null:
					EventBus.gather_requested.emit(skill_copy, node_name)
					popup.hide()
			popup_list.add_child(_skill_guide_row(int(n["level"]), icon_item, title, unlocked, tip, act))

	var recipes: Array = DataRegistry.recipes_by_skill.get(skill, [])
	if not recipes.is_empty():
		any = true
		var head := Label.new()
		head.text = "— Recipes (made at a %s station) —" % skill.capitalize()
		head.add_theme_color_override("font_color", Color(0.7, 0.62, 0.4))
		popup_list.add_child(head)
		for r: Dictionary in recipes:
			var unlocked: bool = lvl >= int(r["levelReq"])
			var input_strs: PackedStringArray = []
			for input: Dictionary in r["inputs"]:
				input_strs.append("%dx %s" % [int(input["qty"]), DataRegistry.item_display_name(input["item"])])
			var title := str(r.get("displayName", r["name"]))
			var tip := "Needs: %s\nMakes: %dx %s\n%.0f XP, %.1fs" % [
				", ".join(input_strs), int(r["output"]["qty"]), DataRegistry.item_display_name(r["output"]["item"]),
				float(r["xp"]), float(r["time"])]
			if not unlocked:
				tip += "\nRequires %s level %d" % [skill.capitalize(), int(r["levelReq"])]
			var recipe_name := str(r["name"])
			var skill_copy2 := skill
			var act := func() -> void:
				if world != null:
					EventBus.station_requested.emit(skill_copy2, recipe_name)
					popup.hide()
			popup_list.add_child(_skill_guide_row(int(r["levelReq"]), str(r["output"]["item"]), title, unlocked, tip, act))

	if not any:
		var lbl := Label.new()
		if skill in ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "prayer", "slayer"]:
			lbl.text = "Train %s by fighting monsters in the world.\nHigher-level zones hold stronger foes." % skill.capitalize()
		else:
			lbl.text = "%s sites appear in the world as you explore.\n(This skill's sim is still on the roadmap.)" % skill.capitalize()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		popup_list.add_child(lbl)


## One skill-guide row, HUD style: [Lvl N] [resource art] [name]. The whole row is a clickable
## panel that fires the auto-skill action (gather / station). Locked rows (player level below the
## requirement) are faded and inert. icon_item is the resource (fish / ore / herb / log / product)
## whose procedural ItemIcon art is drawn.
func _skill_guide_row(level: int, icon_item: String, title: String, unlocked: bool, tooltip: String, on_click: Callable) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _style(Color(0.20, 0.19, 0.17) if unlocked else Color(0.14, 0.13, 0.12)))
	row.tooltip_text = tooltip
	if unlocked:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				hud.show_ui_click_marker(e.global_position)
				on_click.call())
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks fall through to the row panel
	hb.add_theme_constant_override("separation", UiScale.i(8))
	var lv := Label.new()
	lv.text = "Lvl %d" % level
	lv.custom_minimum_size = UiScale.v2(Vector2(46, 0))
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_theme_color_override("font_color", Color(0.84, 0.78, 0.52) if unlocked else Color(0.5, 0.48, 0.42))
	hb.add_child(lv)
	var icon := ItemIcon.new()
	icon.kind = ItemIcon.classify(icon_item, DataRegistry.get_item(icon_item))
	icon.tint = ItemIcon.material_color(icon_item)
	icon.custom_minimum_size = UiScale.v2(Vector2(26, 26))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)
	var nm := Label.new()
	nm.text = title
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_color_override("font_color", Color(0.93, 0.91, 0.8) if unlocked else Color(0.55, 0.55, 0.52))
	hb.add_child(nm)
	row.add_child(hb)
	if not unlocked:
		row.modulate.a = 0.5
	return row


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
				EventBus.combat_log.emit("[color=#9ad29a]New Slayer task: kill %d %s.[/color]" % [
					int(t["required"]), DataRegistry.enemy_display_name(str(t["monster"]))])
			open_npc_dialog(npc_id))
		popup_list.add_child(get_btn)
	else:
		var t: Dictionary = GameState.slayer_task
		var tl := Label.new()
		tl.text = "Current task: %s   (%d / %d)" % [
			DataRegistry.enemy_display_name(str(t["monster"])), int(t["done"]), int(t["required"])]
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
		UiTheme.list_row(popup_list, "%s x%d" % [item_name, int(GameState.bank[item_id])], "Take",
			func() -> void:
				GameState.withdraw(item_id, int(GameState.bank.get(item_id, 0)))
				open_bank())


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
				EventBus.combat_log.emit("[color=#1a6e1a]Bought %s.[/color]" % tool_name)
				open_shop()
			else:
				EventBus.combat_log.emit("[color=#a01010]You can't afford that.[/color]"))
		row.add_child(buy)
		popup_list.add_child(row)


# ---------------------------------------------------------------- refresh ----

