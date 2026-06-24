extends RefCounted
class_name ContentRename
## Applies the IP rename map (data/rename_map.json) to a display name. Display
## names only — ids and the legacy `name` field stay frozen (spec §7), so this
## is fully save-safe. Shared by tools/apply_renames.gd and the importer.

const MAP_PATH := "res://data/rename_map.json"


static func load_map() -> Dictionary:
	var parsed := JsonIO.read_dict(MAP_PATH)
	if not parsed.has("tokens"):
		parsed["tokens"] = {}
	if not parsed.has("exact"):
		parsed["exact"] = {}
	return parsed


## Returns the renamed display name for `original`. Exact full-name overrides win;
## otherwise each whole word is run through the token map (so "Cerulium Bar" and
## "Cerulium Pickaxe" both follow "Cerulium" -> "Azurite").
static func rename(original: String, map: Dictionary) -> String:
	var exact: Dictionary = map.get("exact", {})
	if exact.has(original):
		return str(exact[original])
	# Substring pass: apply the exact (boss / named-enemy) overrides even when the
	# name is embedded in a derived item — e.g. "<Boss>'s Soul" or
	# "Corrupted <Boss>'s Soul". Longest keys first so a full boss phrase wins over
	# a shorter name contained inside it.
	var working := original
	var ekeys: Array = exact.keys()
	ekeys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for k: String in ekeys:
		if working.contains(k):
			working = working.replace(k, str(exact[k]))
	var tokens: Dictionary = map.get("tokens", {})
	if tokens.is_empty():
		return working
	# Split on spaces but preserve them; replace only whole words (trailing
	# punctuation like a comma is kept).
	var words := working.split(" ")
	var out: PackedStringArray = []
	for w: String in words:
		var lead := ""
		var trail := ""
		var core := w
		while core.length() > 0 and not _is_word_char(core[0]):
			lead += core[0]
			core = core.substr(1)
		while core.length() > 0 and not _is_word_char(core[core.length() - 1]):
			trail = core[core.length() - 1] + trail
			core = core.substr(0, core.length() - 1)
		if tokens.has(core):
			core = str(tokens[core])
		out.append(lead + core + trail)
	return " ".join(out)


static func _is_word_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
