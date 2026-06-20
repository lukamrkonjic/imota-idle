extends RefCounted
class_name HudMagicTab
## Magic side-panel tab — a placeholder spellbook until Magic combat lands. Self-contained:
## it builds its own Control and needs no refresh. Holds a back-reference to the HUD only
## for the shared world_tooltip. One of the per-tab components osrs_hud orchestrates.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var hud  # the OSRS HUD (no class_name, so untyped — the WorldFx3D `_ctx` pattern)


func _init(h) -> void:
	hud = h


func build() -> Control:
	var box := VBoxContainer.new()
	box.name = "Magic"
	var head := Label.new()
	head.text = "Spellbook"
	head.add_theme_font_size_override("font_size", UiScale.i(15))
	head.add_theme_color_override("font_color", Color(0.7, 0.55, 0.95))
	box.add_child(head)
	for s: Array in [
		["Wind Strike", 1], ["Confuse", 3], ["Water Strike", 5], ["Earth Strike", 9],
		["Fire Strike", 13], ["Bind", 20], ["High Alchemy", 55],
	]:
		var row := Label.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_font_size_override("font_size", UiScale.i(12))
		var unlocked := GameState.level("magic") >= int(s[1])
		row.text = "%s  (Lvl %d)" % [str(s[0]), int(s[1])]
		row.add_theme_color_override("font_color",
			Color(0.9, 0.9, 0.8) if unlocked else Color(0.45, 0.45, 0.45))
		hud.world_tooltip.attach(row, {
			"title": str(s[0]), "subtitle": "Level %d" % int(s[1]),
			"action": "Unlocked" if unlocked else "Locked — needs Magic %d" % int(s[1])})
		box.add_child(row)
	var note := Label.new()
	note.text = "Select Magic in the Combat tab to cast while fighting (coming soon)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", UiScale.i(10))
	note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	box.add_child(note)
	return box
