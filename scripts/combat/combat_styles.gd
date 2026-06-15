extends RefCounted
class_name CombatStyles
## Maps the selected training skill (the combat "style") to the per-hit XP
## targets. Modular hook: future styles (a melee "controlled" split, defensive
## variants that also feed Defence, etc.) just return more weighted targets here
## without CombatSim changing. Weights sum to 1.0.
##
## Placeholder coefficients — tune later (spec §11/§12 open decisions).

# XP per point of damage dealt, OSRS-style: the trained skill + a Hitpoints share.
const XP_PER_DAMAGE := 4.0
const HP_XP_PER_DAMAGE := 1.33


## Returns [[skill, weight], ...] for the trained combat skill.
static func xp_targets(train_skill: String) -> Array:
	match train_skill:
		"attack", "strength", "defence", "ranged", "magic":
			return [[train_skill, 1.0]]
		"controlled":  # reserved: future melee controlled style
			return [["attack", 1.0 / 3.0], ["strength", 1.0 / 3.0], ["defence", 1.0 / 3.0]]
		_:
			return [["attack", 1.0]]
