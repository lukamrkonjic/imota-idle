extends RefCounted
class_name HudEquipmentTab
## Equipment side-panel tab: an OSRS-style paper-doll of worn slots (worn items show
## their icon, empty slots a dim silhouette) plus a tool row (axe/pick/rod/lens). Clicking
## a worn slot unequips it. Owns its list + refresh; the HUD drives refresh() from its
## equipment_changed / game_loaded dispatch.

const UiScale := preload("res://scripts/ui/ui_scale.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")

# Worn-slot grid layout (blank = spacer) and the tool row below it.
const _EQUIP_LAYOUT := [
	["", "Helm", ""],
	["Cape", "Amulet", "Ammunition"],
	["Weapon", "Body", "Shield"],
	["Gloves", "Boots", "Ring"],
]
const _TOOL_SLOTS := ["Axe", "Pickaxe", "Rod", "Lens"]
# Empty-slot silhouette icon per slot.
const _SLOT_ICON := {
	"Helm": "helm", "Body": "body", "Boots": "boots", "Weapon": "sword",
	"Shield": "shield", "Ring": "ring", "Gloves": "gloves", "Cape": "cape",
	"Amulet": "ring", "Ammunition": "arrow", "Axe": "axe", "Pickaxe": "pickaxe",
	"Rod": "staff", "Lens": "gem",
}

var hud  # the OSRS HUD (untyped — the WorldFx3D `_ctx` pattern)
var _list: VBoxContainer


func _init(h) -> void:
	hud = h


func build() -> Control:
	var eq_scroll := ScrollContainer.new()
	eq_scroll.name = "Equipment"
	eq_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_scroll.add_child(_list)
	return eq_scroll


func refresh() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiScale.i(6))
	grid.add_theme_constant_override("v_separation", UiScale.i(6))
	for row: Array in _EQUIP_LAYOUT:
		for slot: String in row:
			grid.add_child(_make_slot(slot))
	var center := CenterContainer.new()
	center.add_child(grid)
	_list.add_child(center)
	var tools_lbl := Label.new()
	tools_lbl.text = "Tools"
	tools_lbl.add_theme_font_size_override("font_size", UiScale.i(11))
	tools_lbl.add_theme_color_override("font_color", Color(0.7, 0.66, 0.55))
	_list.add_child(tools_lbl)
	var tgrid := GridContainer.new()
	tgrid.columns = 4
	tgrid.add_theme_constant_override("h_separation", UiScale.i(6))
	for slot: String in _TOOL_SLOTS:
		tgrid.add_child(_make_slot(slot))
	var tcenter := CenterContainer.new()
	tcenter.add_child(tgrid)
	_list.add_child(tcenter)


func _make_slot(slot: String) -> Control:
	if slot.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size = UiScale.v2(Vector2(50, 50))
		return spacer
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", hud._style(hud.STONE_DARK))
	panel.custom_minimum_size = UiScale.v2(Vector2(50, 50))
	var worn_id: String = str(GameState.equipment.get(slot, ""))
	var icon := ItemIcon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if worn_id.is_empty():
		icon.kind = _SLOT_ICON.get(slot, "misc")
		icon.tint = Color(0.36, 0.34, 0.31)  # dim silhouette
		hud.world_tooltip.attach(panel, {"title": slot, "subtitle": "Empty"})
	else:
		var worn := DataRegistry.item_display_name(worn_id)
		icon.kind = ItemIcon.classify(worn, DataRegistry.get_item(worn_id))
		icon.tint = ItemIcon.material_color(worn)
		hud.world_tooltip.attach(panel, {"title": worn, "subtitle": slot, "action": "Click to unequip"})
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var slot_copy := slot
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameState.unequip(slot_copy))
	panel.add_child(icon)
	return panel
