extends RefCounted
class_name HudInventoryTab
## Inventory side-panel tab: a fixed 4×7 (28-slot) grid like OSRS. Left-click equips/eats,
## right-click opens the deposit/sell/alch menu. Owns its grid + refresh + slot actions;
## the HUD drives refresh() from its inventory_changed / game_loaded dispatch and lends its
## node for popups + chat.

const UiScale := preload("res://scripts/ui/ui_scale.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")

var hud  # the OSRS HUD (untyped — the WorldFx3D `_ctx` pattern)
var _grid: GridContainer


func _init(h) -> void:
	hud = h


func build() -> Control:
	var inv_wrap := VBoxContainer.new()
	inv_wrap.name = "Inventory"
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", UiScale.i(2))
	_grid.add_theme_constant_override("v_separation", UiScale.i(2))
	inv_wrap.add_child(_grid)
	var hint := Label.new()
	hint.text = "Left-click: equip/eat.  Right-click: more."
	hint.add_theme_font_size_override("font_size", UiScale.i(10))
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	inv_wrap.add_child(hint)
	return inv_wrap


func refresh() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	for i: int in GameState.max_inventory_slots():
		var btn := Button.new()
		btn.custom_minimum_size = UiScale.v2(Vector2(60, 48))
		if i < GameState.inventory.size():
			var stack: Dictionary = GameState.inventory[i]
			var item_id: String = stack["id"]
			var item_name := DataRegistry.item_display_name(item_id)
			hud.world_tooltip.attach(btn, {"title": item_name})
			# Procedural type icon, recolored by material tier (name on hover).
			var icon := ItemIcon.new()
			icon.kind = ItemIcon.classify(item_name, DataRegistry.get_item(item_id))
			icon.tint = ItemIcon.material_color(item_name)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_top = UiScale.i(2)
			icon.offset_bottom = UiScale.i(-11)
			btn.add_child(icon)
			var qty := int(stack["qty"])
			if qty > 1:
				var ql := Label.new()
				ql.text = _fmt_qty(qty)
				ql.add_theme_font_size_override("font_size", UiScale.i(11))
				ql.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
				ql.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
				ql.add_theme_constant_override("outline_size", UiScale.i(3))
				ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ql.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				ql.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				btn.add_child(ql)
			btn.gui_input.connect(_on_slot_input.bind(item_id))
			btn.pressed.connect(_default_action.bind(item_id))
		else:
			btn.disabled = true
		_grid.add_child(btn)


func _default_action(item_id: String) -> void:
	var item_name := DataRegistry.item_display_name(item_id)
	if DataRegistry.food_hp.has(item_id):
		if GameState.eat(item_id):
			hud._push_chat("[color=#1a6e1a]You eat the %s. (+%d HP)[/color]" % [item_name, int(DataRegistry.food_hp[item_id])])
		else:
			hud._push_chat("[color=#444]You're already at full health.[/color]")
		return
	if DataRegistry.item_def(item_id).is_equippable():
		if GameState.equip(item_id):
			hud._push_chat("[color=#444]Equipped %s.[/color]" % item_name)
		else:
			hud._push_chat("[color=#a01010]You can't equip that yet (level requirement).[/color]")


func _on_slot_input(event: InputEvent, item_id: String) -> void:
	var item_name := DataRegistry.item_display_name(item_id)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var menu := PopupMenu.new()
		menu.add_item("Deposit all", 0)
		menu.add_item("Sell all (%d each)" % DataRegistry.item_value(item_name), 1)
		menu.add_item("High Alch (%d coins)" % int(floor(float(DataRegistry.item_value(item_id)) * GameState.HIGH_ALCH_RATE)), 2)
		menu.id_pressed.connect(func(id: int) -> void:
			var qty := GameState.count_item(item_name)
			if id == 0:
				hud._push_chat("[color=#444]No bank chest here — use the one in town.[/color]")
				GameState.deposit(item_name, qty)
			elif id == 1:
				GameState.sell_item(item_name, qty)
				hud._push_chat("[color=#1a6e1a]Sold %d %s.[/color]" % [qty, item_name])
			else:
				if GameState.high_alch(item_id):
					hud._push_chat("[color=#5a3a8a]High Alched %s.[/color]" % item_name)
				else:
					hud._push_chat("[color=#a01010]Need Magic %d to High Alch.[/color]" % GameState.HIGH_ALCH_LEVEL)
			menu.queue_free())
		hud.add_child(menu)
		menu.popup(Rect2i(Vector2i(hud.get_viewport().get_mouse_position()), Vector2i.ZERO))


## Compact stack count (OSRS-ish): raw under 100k, then K / M.
static func _fmt_qty(q: int) -> String:
	if q >= 1000000:
		return "%.1fM" % (q / 1000000.0)
	if q >= 100000:
		return "%dK" % (q / 1000)
	return str(q)
