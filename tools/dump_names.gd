extends SceneTree
## Throwaway: print enemy names (boss-flagged) and item-name token frequencies
## to help author the rename map. Run with --script, output to stdout.

func _init() -> void:
	var enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var bosses: Array = []
	var normals: Array = []
	for name: String in enemies:
		if bool(enemies[name].get("isBoss", false)):
			bosses.append("%s (lvl %d)" % [name, int(enemies[name].get("level", 0))])
		else:
			normals.append(name)
	bosses.sort()
	normals.sort()
	print("=== BOSSES (%d) ===" % bosses.size())
	for b: String in bosses:
		print(b)
	print("=== NORMAL ENEMIES (%d) ===" % normals.size())
	print(", ".join(normals))
	quit(0)
