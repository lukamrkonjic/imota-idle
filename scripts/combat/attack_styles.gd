extends RefCounted
class_name AttackStyles
## Attack styles: small effective-level bonuses + which attack TYPE a swing uses.
## Mapped from the existing combat-style dropdown (the trained skill) so no new UI
## is required, while still giving OSRS-style accurate/aggressive/defensive trade-offs.
## XP distribution itself lives in combat_styles.gd (xp_targets).

# trained skill -> { name, atk/str/def effective-LEVEL bonus }. These are the
# "+3 accurate / +3 aggressive / +3 defensive / +1+1+1 controlled" style bonuses.
const PRESETS := {
	"attack":     {"name": "Accurate", "atk": 3, "str": 0, "def": 0},
	"strength":   {"name": "Aggressive", "atk": 0, "str": 3, "def": 0},
	"defence":    {"name": "Defensive", "atk": 0, "str": 0, "def": 3},
	"controlled": {"name": "Controlled", "atk": 1, "str": 1, "def": 1},
	"ranged":     {"name": "Accurate", "atk": 3, "str": 0, "def": 0},
	"magic":      {"name": "Accurate", "atk": 3, "str": 0, "def": 0},
}


static func preset(train_skill: String) -> Dictionary:
	return PRESETS.get(train_skill, PRESETS["attack"])


static func attack_level_bonus(train_skill: String) -> int:
	return int(preset(train_skill)["atk"])


static func strength_level_bonus(train_skill: String) -> int:
	return int(preset(train_skill)["str"])


static func defence_level_bonus(train_skill: String) -> int:
	return int(preset(train_skill)["def"])


static func style_name(train_skill: String) -> String:
	return str(preset(train_skill)["name"])


## The attack TYPE a weapon swings with: ranged/magic for those styles, else the
## melee type (stab/slash/crush) the weapon is BEST at — so a scimitar slashes, a
## mace crushes, and switching weapons is how you exploit an enemy's weakness.
static func attack_type(weapon: ItemDef) -> String:
	match weapon.weapon_style():
		"ranged": return "ranged"
		"magic": return "magic"
	var ab := weapon.attack_bonuses()
	var best := "slash"
	var best_v := -2147483648
	for t: String in ["stab", "slash", "crush"]:
		if int(ab[t]) > best_v:
			best_v = int(ab[t])
			best = t
	return best
