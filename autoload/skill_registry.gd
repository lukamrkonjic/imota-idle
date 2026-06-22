extends Node
## Single source of truth for SKILL METADATA (data/skills.json): display name, abbrev,
## icon, theme colour, kind (combat/gather/production/support), and the gather/production
## hooks (tool slot, action verb, animation, stationless flag). The skill KEY set and save
## contract still live in GameState.SKILLS; this only adds the presentation/behaviour
## metadata that used to be smeared across osrs_hud (3 parallel dicts), game_state
## (tool_progress slot map), the auto-task controller (GATHER_VERB), world_entity (a
## divergent GATHER_VERB copy), and player_avatar (the anim match). Edit one JSON file now.

var _meta: Dictionary = {}      # skill key -> metadata dict
var _ids: Array = []            # skill keys, ordered by `order`


func _ready() -> void:
	_load()
	# Guard against drift: the metadata set must exactly match the save-contract roster.
	var roster := {}
	for s: String in GameState.SKILLS:
		roster[s] = true
		if not _meta.has(s):
			push_warning("SkillRegistry: skill '%s' in GameState.SKILLS has no data/skills.json entry" % s)
	for s: String in _meta:
		if not roster.has(s):
			push_warning("SkillRegistry: data/skills.json has unknown skill '%s' (not in GameState.SKILLS)" % s)


func _load() -> void:
	var path := "res://data/skills.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_meta = parsed if parsed is Dictionary else {}
	_ids = _meta.keys()
	_ids.sort_custom(func(a, b): return int(_meta[a].get("order", 0)) < int(_meta[b].get("order", 0)))


## Skill keys in display order.
func ids() -> Array:
	return _ids


func has(skill: String) -> bool:
	return _meta.has(skill)


func meta(skill: String) -> Dictionary:
	return _meta.get(skill, {})


func display_name(skill: String) -> String:
	return str(meta(skill).get("name", skill.capitalize()))


func abbrev(skill: String) -> String:
	return str(meta(skill).get("abbrev", skill.substr(0, 3).capitalize()))


func icon(skill: String) -> String:
	return str(meta(skill).get("icon", "misc"))


# Authored skill icons (assets/skill_icons/<skill>.png, imported as textures). Cached; null when
# an icon is missing so callers can fall back to the procedural ItemIcon glyph.
const SKILL_ICON_DIR := "res://assets/skill_icons"
var _icon_tex: Dictionary = {}   # skill -> Texture2D (or null)

func icon_texture(skill: String) -> Texture2D:
	if _icon_tex.has(skill):
		return _icon_tex[skill]
	var tex: Texture2D = null
	var path := "%s/%s.png" % [SKILL_ICON_DIR, skill]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icon_tex[skill] = tex   # cache misses too, so we only probe once
	return tex


func color(skill: String) -> Color:
	var c: Array = meta(skill).get("color", [])
	if c.size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.72, 0.72, 0.74)


func kind(skill: String) -> String:
	return str(meta(skill).get("kind", ""))


func is_gather(skill: String) -> bool:
	return kind(skill) == "gather"


func is_production(skill: String) -> bool:
	return kind(skill) == "production"


func is_combat(skill: String) -> bool:
	return kind(skill) == "combat"


## Gather action verb (Chop / Mine / Steal / …). Falls back to "Gather".
func verb(skill: String) -> String:
	return str(meta(skill).get("verb", "Gather"))


## Player animation mode for a gather skill (chop / mine / fish / forage / gather).
func anim(skill: String) -> String:
	return str(meta(skill).get("anim", "gather"))


## Equipment slot whose `progress` powers this gather skill ("" if it needs no tool).
func tool_slot(skill: String) -> String:
	return str(meta(skill).get("tool", ""))


## Base gather power for a toolless skill (hunter/thieving), 0 if it uses a tool.
func base_progress(skill: String) -> int:
	return int(meta(skill).get("baseProgress", 0))


func is_stationless(skill: String) -> bool:
	return bool(meta(skill).get("stationless", false))
