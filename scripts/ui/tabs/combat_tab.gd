extends RefCounted
class_name HudCombatTab
## Combat side-panel tab: the training-style selector, a live equipment/combat-stat
## readout, and a Slayer Master button. Owns its widgets + build()/refresh(); the HUD
## drives refresh() from its central EventBus dispatch (equipment_changed, game_loaded).

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var hud  # the OSRS HUD (untyped — the WorldFx3D `_ctx` pattern)
var _train_select: OptionButton
var _info: Label


func _init(h) -> void:
	hud = h


func build() -> Control:
	var combat_box := VBoxContainer.new()
	combat_box.name = "Combat"
	var train_row := HBoxContainer.new()
	var tl := Label.new()
	tl.text = "Train:"
	train_row.add_child(tl)
	_train_select = OptionButton.new()
	for s: String in ["Attack", "Strength", "Defence", "Ranged", "Magic"]:
		_train_select.add_item(s)
	_train_select.item_selected.connect(func(idx: int) -> void:
		GameState.set_combat_style(_train_select.get_item_text(idx).to_lower())
		refresh())
	train_row.add_child(_train_select)
	combat_box.add_child(train_row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", UiScale.i(13))
	combat_box.add_child(_info)
	var slayer := Button.new()
	slayer.text = "Slayer Master"
	slayer.tooltip_text = "Talk to the Slayer Master: get a task, check progress, browse targets"
	slayer.pressed.connect(func() -> void: hud.open_npc_dialog("slayer_master"))
	combat_box.add_child(slayer)
	return combat_box


func refresh() -> void:
	if _info == null or not is_instance_valid(_info):
		return
	_info.text = "Combat level: %d\n\nMelee: +%.0f dmg, +%.0f%% acc\nRanged: +%.0f dmg, +%.0f%% acc\nMagic: +%.0f dmg, +%.0f%% acc\nDmg reduction: %.1f%%\n\nClick an enemy in the world to fight." % [
		GameState.combat_level(),
		GameState.equipment_damage(), GameState.equipment_accuracy() * 100.0,
		GameState.equipment_range_damage(), GameState.equipment_range_accuracy() * 100.0,
		GameState.equipment_magic_damage(), GameState.equipment_magic_accuracy() * 100.0,
		GameState.equipment_damage_reduction()]
	# Keep the style dropdown in sync with the persisted combat style.
	for i: int in _train_select.item_count:
		if _train_select.get_item_text(i).to_lower() == GameState.combat_style:
			_train_select.selected = i
			break
