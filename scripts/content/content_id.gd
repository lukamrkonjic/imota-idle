extends RefCounted
class_name ContentId
## Stable internal ids for game content. Display names are presentation only.

const PREFIX_ITEM := "item."
const PREFIX_NODE := "node."
const PREFIX_ENEMY := "enemy."
const PREFIX_RECIPE := "recipe."


static func slug(text: String) -> String:
	var s := text.strip_edges().to_lower()
	s = s.replace("'", "")
	s = s.replace("-", "_")
	var out := ""
	var prev_us := false
	for i: int in s.length():
		var c: String = s[i]
		if c == " ":
			if not prev_us:
				out += "_"
				prev_us = true
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			prev_us = false
		elif c == "_":
			if not prev_us:
				out += "_"
				prev_us = true
	while out.begins_with("_"):
		out = out.substr(1)
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	return out if not out.is_empty() else "unknown"


static func item_id(display_name: String) -> String:
	return PREFIX_ITEM + slug(display_name)


static func node_id(skill: String, node_name: String) -> String:
	return PREFIX_NODE + slug(skill) + "." + slug(node_name)


static func enemy_id(display_name: String) -> String:
	return PREFIX_ENEMY + slug(display_name)


static func recipe_id(skill: String, recipe_name: String) -> String:
	return PREFIX_RECIPE + slug(skill) + "." + slug(recipe_name)


static func is_stable_id(value: String) -> bool:
	return value.begins_with(PREFIX_ITEM) or value.begins_with(PREFIX_NODE) \
		or value.begins_with(PREFIX_ENEMY) or value.begins_with(PREFIX_RECIPE)
