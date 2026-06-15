extends Node
## keybind_test — verifies the Hide HUD keybind + rebind without interactive input,
## by feeding synthetic key events to the HUD's handlers.
##   godot --path . res://tools/keybind_test.tscn

var _world: Node2D


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	_run()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _run() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: CanvasLayer = _world.hud
	var ok := true

	# Default bind is H.
	var bind: int = GameSettings.keybind("hide_hud")
	print("hide_hud bound to: %s (%d)" % [OS.get_keycode_string(bind), bind])
	ok = ok and bind == KEY_H

	# H toggles hud_root visibility off then on.
	var root: Control = hud.hud_root
	var v0: bool = root.visible
	hud._unhandled_key_input(_key(KEY_H))
	var v1: bool = root.visible
	hud._unhandled_key_input(_key(KEY_H))
	var v2: bool = root.visible
	print("hud_root visible: %s -> %s -> %s" % [v0, v1, v2])
	ok = ok and v0 == true and v1 == false and v2 == true

	# Rebind to J: arm capture, feed J, confirm stored + J now toggles.
	hud._rebinding_action = "hide_hud"
	hud._input(_key(KEY_J))
	var rebound: int = GameSettings.keybind("hide_hud")
	print("after rebind, hide_hud = %s (%d)" % [OS.get_keycode_string(rebound), rebound])
	ok = ok and rebound == KEY_J
	hud._unhandled_key_input(_key(KEY_J))
	var v3: bool = root.visible
	hud._unhandled_key_input(_key(KEY_H))  # old key should NOT toggle now
	var v4: bool = root.visible
	print("J toggles (%s), old H no-ops (still %s)" % [v3 == false, v4])
	ok = ok and v3 == false and v4 == false

	# Tile debug overlay toggle (Admin setting).
	var dbg: Label = hud.tile_debug_label
	var d0: bool = dbg.visible
	GameSettings.set_show_tile_debug(false)
	var d1: bool = dbg.visible
	GameSettings.set_show_tile_debug(true)
	var d2: bool = dbg.visible
	print("tile_debug visible: %s -> %s -> %s" % [d0, d1, d2])
	ok = ok and d0 == true and d1 == false and d2 == true

	print("KEYBIND TEST: %s" % ("PASSED" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
