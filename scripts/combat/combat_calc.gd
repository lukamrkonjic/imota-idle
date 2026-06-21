extends RefCounted
class_name CombatCalc
## Pure, side-effect-free OSRS-inspired combat math. Every function is static and
## deterministic given its inputs (the only randomness is via an injected RNG), so
## the whole thing is unit-testable in isolation (see validate.gd combat tests).
##
## Structure (why each piece matters):
##   accuracy  = effective ATTACK × (relevant attack bonus + 64)  vs  enemy defence roll
##   max hit   = floor(0.5 + effective STRENGTH × (str bonus + 64) / 640)
##   +8/+9     = baseline effective levels;  +64 = baseline gear scaling;
##   /640      = damage scale;  floor + 0.5 = integer damage breakpoints.
## Weak weapons stay weak via a LOW strength bonus, never a hard per-weapon cap.
##
## TUNING: change values in combat_constants.gd, not here. Raising MAX_HIT_DIVISOR
## lowers all damage; raising EQUIPMENT_ROLL_BASE flattens the gap between gear tiers;
## the +8/+9 bases set how much low-level play already "works".

const K := preload("res://scripts/combat/combat_constants.gd")


## Effective level = floor(level × prayer) + temporary bonus + style bonus + 8.
## Used for BOTH effective Attack (accuracy) and effective Strength (max hit).
static func effective_level(level: int, prayer_mult := 1.0, temp_bonus := 0, style_bonus := 0) -> int:
	return int(floor(float(level) * prayer_mult)) + temp_bonus + style_bonus + K.EFFECTIVE_PLAYER_LEVEL_BASE


## Player maximum attack roll = effectiveAttack × (relevant attack bonus + 64).
static func max_attack_roll(effective_attack: int, relevant_attack_bonus: int) -> int:
	return effective_attack * (relevant_attack_bonus + K.EQUIPMENT_ROLL_BASE)


## Melee/ranged/magic maximum hit = floor(0.5 + effStr × (strBonus + 64) / 640).
static func max_hit(effective_strength: int, strength_bonus: int) -> int:
	return int(floor(K.MAX_HIT_ROUNDING_OFFSET
		+ float(effective_strength) * float(strength_bonus + K.EQUIPMENT_ROLL_BASE) / K.MAX_HIT_DIVISOR))


## NPC maximum defence roll = (defenceLevel + 9) × (relevant defence bonus + 64).
static func enemy_defence_roll(defence_level: int, relevant_defence_bonus: int) -> int:
	return (defence_level + K.EFFECTIVE_NPC_DEFENCE_BASE) * (relevant_defence_bonus + K.EQUIPMENT_ROLL_BASE)


## Hit chance from the two rolls (OSRS piecewise), clamped to [0,1].
static func hit_chance(attack_roll: int, defence_roll: int) -> float:
	var hc: float
	if attack_roll > defence_roll:
		hc = 1.0 - float(defence_roll + 2) / float(2 * (attack_roll + 1))
	else:
		hc = float(attack_roll) / float(2 * (defence_roll + 1))
	return clampf(hc, 0.0, 1.0)


## Uniform base damage in [0, maxHit] (a landed hit may still roll 0).
static func roll_base_damage(max_hit_value: int, rng: RandomNumberGenerator) -> int:
	if max_hit_value <= 0:
		return 0
	return rng.randi_range(0, max_hit_value)


# --- damage modifier pipeline ------------------------------------------------
# ONE documented order (matches the worked example in the spec):
#   product of all multipliers -> floor -> subtract flat reduction -> clamp [0, cap].
# i.e. flat damage reduction is applied AFTER flooring the multiplied damage.

static func finalize_damage(base_roll: int, crit_mult := 1.0, special_mult := 1.0,
		player_mult := 1.0, enemy_taken_mult := 1.0, enemy_flat_reduction := 0) -> int:
	var dmg := float(base_roll) * crit_mult * special_mult * player_mult * enemy_taken_mult
	dmg = floor(dmg)
	dmg -= float(enemy_flat_reduction)
	return clampi(int(dmg), 0, K.GLOBAL_DAMAGE_CAP)


## Resolve a crit roll. Returns [did_crit, multiplier_to_apply].
static func roll_crit(crit_chance: float, crit_mult: float, rng: RandomNumberGenerator) -> Array:
	var cc := clampf(crit_chance, 0.0, K.MAX_CRIT_CHANCE)
	if rng.randf() < cc:
		return [true, clampf(crit_mult, 1.0, K.MAX_CRIT_MULTIPLIER)]
	return [false, 1.0]


# --- speed & DPS -------------------------------------------------------------

static func ticks_to_ms(ticks: int) -> int:
	return ticks * K.TICK_DURATION_MS


static func ticks_to_seconds(ticks: int) -> float:
	return float(ticks * K.TICK_DURATION_MS) / 1000.0


## Average per-hit multiplier from crits: 1 + critChance × (critMult - 1).
static func average_crit_multiplier(crit_chance: float, crit_mult: float) -> float:
	return 1.0 + clampf(crit_chance, 0.0, K.MAX_CRIT_CHANCE) * (clampf(crit_mult, 1.0, K.MAX_CRIT_MULTIPLIER) - 1.0)


## Expected damage of one attack = hitChance × (maxHit/2) × avgCritMult.
static func expected_damage_per_attack(hit_chance_value: float, max_hit_value: int, avg_crit_mult := 1.0) -> float:
	return hit_chance_value * (float(max_hit_value) / 2.0) * avg_crit_mult


## Expected damage per second = expected per-attack damage / attack interval (s).
static func expected_dps(hit_chance_value: float, max_hit_value: int, attack_ticks: int, avg_crit_mult := 1.0) -> float:
	var interval := ticks_to_seconds(attack_ticks)
	if interval <= 0.0:
		return 0.0
	return expected_damage_per_attack(hit_chance_value, max_hit_value, avg_crit_mult) / interval
