extends RefCounted
class_name CombatConstants
## Central home for every combat-formula constant — no magic numbers scattered
## through the combat code. Tune balance HERE (see docs notes in combat_calc.gd).
## OSRS-inspired structure; values are ours, not copied content.

const EFFECTIVE_PLAYER_LEVEL_BASE := 8      # baseline effective level every player gets (+8)
const EFFECTIVE_NPC_DEFENCE_BASE := 9       # baseline effective defence every NPC gets (+9)
const EQUIPMENT_ROLL_BASE := 64             # baseline equipment scaling in every roll (+64)
const MAX_HIT_DIVISOR := 640.0              # scales resulting max damage
const MAX_HIT_ROUNDING_OFFSET := 0.5        # shifts the integer max-hit breakpoints
const TICK_DURATION_MS := 600               # one game tick = 0.6s
const GLOBAL_DAMAGE_CAP := 9999             # anti-bug ceiling only; should not affect normal play

const DEFAULT_CRIT_CHANCE := 0.05           # 5% if a weapon doesn't specify
const DEFAULT_CRIT_MULTIPLIER := 1.5        # 1.5x if a weapon doesn't specify
const MAX_CRIT_CHANCE := 0.50               # ordinary cap (specials may exceed by design)
const MAX_CRIT_MULTIPLIER := 3.0

# Attack types & weapon categories — the canonical id sets the rest of the system keys off.
const ATTACK_TYPES: PackedStringArray = ["stab", "slash", "crush", "ranged", "magic"]
const MELEE_ATTACK_TYPES: PackedStringArray = ["stab", "slash", "crush"]
const WEAPON_CATEGORIES: PackedStringArray = [
	"dagger", "sword", "scimitar", "mace", "battleaxe", "two_handed",
	"bow", "crossbow", "staff", "unarmed",
]
