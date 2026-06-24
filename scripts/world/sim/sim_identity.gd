extends RefCounted
class_name SimIdentity
## Deterministic sim-player identity factory. Given (world_seed, home chunk, slot) it always
## produces the SAME name / look / levels — so the cast of characters is reproducible per world
## and costs nothing to persist (docs/SIM_PLAYERS_PLAN.md §5). Data lives in
## res://data/sim_players/{names,looks,dialogue}.json and is loaded once, cached statically.

const WG := preload("res://scripts/worldgen/wg.gd")
const SimPlayer := preload("res://scripts/world/sim/sim_player.gd")

static var _names: Dictionary = {}
static var _looks: Dictionary = {}
static var _dialogue: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_names = JsonIO.read_dict("res://data/sim_players/names.json")
	_looks = JsonIO.read_dict("res://data/sim_players/looks.json")
	_dialogue = JsonIO.read_dict("res://data/sim_players/dialogue.json")


static func dialogue() -> Dictionary:
	_ensure_loaded()
	return _dialogue


## Build a sim-player whose identity is fully determined by the world + its home slot.
static func build(world_seed: int, cx: int, cy: int, slot: int, home: Vector2) -> SimPlayer:
	_ensure_loaded()
	var s: int = WG.hash_i(world_seed, cx * 131 + slot, cy * 17 + 911)
	var sim := SimPlayer.new()
	sim.seed = s
	sim.slot_key = "%d:%d:%d" % [cx, cy, slot]
	sim.home = home

	sim.pname = _pick_name(s)
	# Level curve: most sims are low-mid level, a rare few are veterans — so a crowd reads
	# as a believable mix (squared roll biases low; the +3 floor keeps everyone past tutorial).
	var lr := WG.r01(s, 7)
	sim.combat_level = clampi(3 + int(lr * lr * 97.0), 3, 99)
	sim.levels = _make_levels(s, sim.combat_level)
	sim.skin = _pick_skin(s)
	sim.loadout = _pick_loadout(s, sim.combat_level)
	sim.personality = WG.r01(s, 21)
	sim.walk_speed = 28.0 + WG.r01(s, 23) * 10.0   # 28..38 px/s, around the player's 34
	return sim


static func _pick_name(s: int) -> String:
	var leet: Array = _names.get("leet", [])
	var names: Array = _names.get("names", [])
	var suffixes: Array = _names.get("suffixes", [""])
	# ~18% get a clan-tag / leetspeak handle; the rest a fantasy name with an occasional suffix.
	if not leet.is_empty() and WG.r01(s, 31) < 0.18:
		return str(leet[WG.hash_i(s, 32) % leet.size()])
	if names.is_empty():
		return "Adventurer"
	var base := str(names[WG.hash_i(s, 33) % names.size()])
	if not suffixes.is_empty():
		var suf := str(suffixes[WG.hash_i(s, 34) % suffixes.size()])
		if not suf.is_empty():
			return "%s %s" % [base, suf] if suf.length() > 2 else base + suf
	return base


## Flavour skill levels: a chosen "main" gathering skill peaks, combat skills sit near the
## combat level, everything else is low. Surfaced only if a sim is inspected later.
static func _make_levels(s: int, cl: int) -> Dictionary:
	var gather := ["woodcutting", "mining", "fishing"]
	var main := str(gather[WG.hash_i(s, 41) % gather.size()])
	var out := {
		main: clampi(cl + 5 + int(WG.r01(s, 42) * 20.0), 1, 99),
		"attack": clampi(cl - int(WG.r01(s, 43) * 6.0), 1, 99),
		"strength": clampi(cl - int(WG.r01(s, 44) * 6.0), 1, 99),
		"defence": clampi(cl - int(WG.r01(s, 45) * 8.0), 1, 99),
		"hitpoints": clampi(cl + 2, 1, 99),
	}
	return out


static func _pick_skin(s: int) -> Color:
	var skins: Array = _looks.get("skins", [])
	if skins.is_empty():
		return Color(0.93, 0.78, 0.62)
	return Color.from_string(str(skins[WG.hash_i(s, 51) % skins.size()]), Color(0.93, 0.78, 0.62))


## Choose an outfit tier by level, then one variant within it — and inject deterministic
## tints for cloth pieces so capes/robes aren't all the same colour. Returns a fresh dict
## (never mutates the cached JSON).
static func _pick_loadout(s: int, cl: int) -> Dictionary:
	var tiers: Array = _looks.get("tiers", [])
	var tier: Dictionary = {}
	for t: Dictionary in tiers:
		if cl <= int(t.get("maxLevel", 999)):
			tier = t
			break
	if tier.is_empty() and not tiers.is_empty():
		tier = tiers.back()
	var outfits: Array = tier.get("outfits", [])
	if outfits.is_empty():
		return {}
	var chosen: Dictionary = outfits[WG.hash_i(s, 61) % outfits.size()]
	var cape_tints: Array = _looks.get("capeTints", [])
	var robe_tints: Array = _looks.get("robeTints", [])
	var cape_c: Color = _tint_from(cape_tints, s, 62, Color(0.6, 0.2, 0.18))
	var robe_c: Color = _tint_from(robe_tints, s, 63, Color(0.45, 0.35, 0.6))
	var out: Dictionary = {}
	for slot: String in chosen:
		var spec: Dictionary = (chosen[slot] as Dictionary).duplicate()
		var kind := str(spec.get("kind", ""))
		if kind == "cape":
			spec["tint"] = cape_c
		elif kind in ["robe_top", "robe_bottom", "wizard_hat", "hood"]:
			spec["tint"] = robe_c
		out[slot] = spec
	return out


static func _tint_from(arr: Array, s: int, salt: int, fallback: Color) -> Color:
	if arr.is_empty():
		return fallback
	return Color.from_string(str(arr[WG.hash_i(s, salt) % arr.size()]), fallback)
