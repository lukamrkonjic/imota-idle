extends RefCounted
class_name HudPrayerTab
## Prayer side-panel tab (placeholder until the Prayer sim lands, spec §6/§16): a
## data-driven toggle list of the prayers that unlock per Prayer level. Owns its own
## widgets + refresh and listens to EventBus directly, so the HUD just builds it and
## pokes the cheap per-frame devotion number. One of the per-tab components.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var hud  # the OSRS HUD (untyped — the WorldFx3D `_ctx` pattern)
var _rows: VBoxContainer        # the toggle list, rebuilt on prayer/level change
var _devotion_lbl: Label


func _init(h) -> void:
	hud = h


func build() -> Control:
	var box := VBoxContainer.new()
	box.name = "Prayer"
	var head := Label.new()
	head.text = "Prayers"
	head.add_theme_font_size_override("font_size", UiScale.i(15))
	head.add_theme_color_override("font_color", Color(0.6, 0.78, 0.95))
	box.add_child(head)
	_devotion_lbl = Label.new()
	_devotion_lbl.add_theme_font_size_override("font_size", UiScale.i(12))
	_devotion_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(_devotion_lbl)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	var bury := Button.new()
	bury.text = "Bury all bones"
	bury.tooltip_text = "Bury every bone in your inventory for Prayer XP"
	bury.pressed.connect(func() -> void:
		var n := GameState.bury_bones()
		hud._push_chat("[color=#444]Buried %d bones.[/color]" % n if n > 0 else "[color=#444]No bones to bury.[/color]"))
	box.add_child(bury)
	if not EventBus.prayer_changed.is_connected(refresh):
		EventBus.prayer_changed.connect(refresh)
		EventBus.level_up.connect(func(s: String, _l: int) -> void:
			if s == "prayer":
				refresh())
	refresh()
	return box


## Rebuild the toggle list from data/prayers.json with current unlock/active state.
func refresh() -> void:
	if _rows == null or not is_instance_valid(_rows):
		return
	_devotion_lbl.text = "Prayer: %d / %d" % [int(GameState.devotion_points()), GameState.devotion_max()]
	for c: Node in _rows.get_children():
		c.queue_free()
	var defs: Dictionary = DataRegistry.prayers
	var names: Array = defs.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(defs[a].get("levelReq", 1)) < int(defs[b].get("levelReq", 1)))
	for name: String in names:
		var def: Dictionary = defs[name]
		var req := int(def.get("levelReq", 1))
		var unlocked := GameState.level("prayer") >= req
		var active := GameState.is_prayer_active(name)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = active
		btn.disabled = not unlocked
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s%s  (Lvl %d)" % ["● " if active else "○ ", name, req]
		btn.add_theme_font_size_override("font_size", UiScale.i(12))
		var fx := []
		if def.has("accuracy"): fx.append("+%d%% accuracy" % int(round((float(def["accuracy"]) - 1.0) * 100.0)))
		if def.has("damage"): fx.append("+%d%% damage" % int(round((float(def["damage"]) - 1.0) * 100.0)))
		if def.has("dr"): fx.append("+%d%% damage reduction" % int(def["dr"]))
		if def.has("meleeProtect"): fx.append("-%d%% melee damage taken" % int(round((1.0 - float(def["meleeProtect"])) * 100.0)))
		if name == "Protect Item": fx.append("keep an item on death")
		btn.tooltip_text = "%s\nStyle: %s · Drain: %.2f/s\n%s" % [
			name, str(def.get("style", "any")).capitalize(), float(def.get("drain", 0.2)),
			", ".join(fx) if not fx.is_empty() else "—"]
		var nm := name
		btn.pressed.connect(func() -> void: GameState.toggle_prayer(nm))
		_rows.add_child(btn)


## Cheap per-frame update of just the devotion number (it regenerates over time); skips
## the full row rebuild. The HUD calls this from its central refresh while the tab shows.
func update_devotion() -> void:
	if _devotion_lbl != null and is_instance_valid(_devotion_lbl) and _devotion_lbl.is_visible_in_tree():
		_devotion_lbl.text = "Prayer: %d / %d" % [int(GameState.devotion_points()), GameState.devotion_max()]
