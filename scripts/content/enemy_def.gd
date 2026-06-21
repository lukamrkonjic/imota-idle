extends RefCounted
class_name EnemyDef
## Typed view over a data/enemies.json entry — combat reads typed fields instead of stringly-
## keyed dict lookups (the densest such access in the codebase). `slayer_*` expose the legacy
## `beastMastery*` data (Beastmastery folds into Slayer). See docs/content/SCHEMA.md.

var raw: Dictionary = {}
var id: String = ""
var name: String = ""
var display_name: String = ""
var level: int = 0
var max_health: int = 0
var style: String = ""
var accuracy: float = 0.0
var damage: float = 0.0
var damage_reduction: float = 0.0
var crit_chance: float = 0.0
var crit_multiplier: float = 1.0
var cooldown: float = 0.0
# OSRS-inspired defence. Authored in JSON (defenceLevel / defenceBonuses /
# flatDamageReduction / damageTakenMultiplier) or DERIVED from `level` when absent,
# so all 120 legacy enemies work. defenceBonuses keys: stab/slash/crush/ranged/magic.
var defence_level: int = 0
var defence_bonuses: Dictionary = {}
var flat_damage_reduction: int = 0
var damage_taken_multiplier: float = 1.0
var combat_xp: float = 0.0
var hitpoints_xp: float = 0.0
var slayer_req: float = 0.0
var slayer_xp: float = 0.0
var is_boss: bool = false
var drops: Array = []


static func from_dict(d: Dictionary) -> EnemyDef:
	var e := EnemyDef.new()
	if d.is_empty():
		return e
	e.raw = d
	e.id = str(d.get("id", ""))
	e.name = str(d.get("name", ""))
	e.display_name = str(d.get("displayName", e.name))
	e.level = int(d.get("level", 0))
	e.max_health = int(d.get("maxHealth", 0))
	e.style = str(d.get("style", ""))
	e.accuracy = float(d.get("accuracy", 0.0))
	e.damage = float(d.get("damage", 0.0))
	e.damage_reduction = float(d.get("damageReduction", 0.0))
	e.crit_chance = float(d.get("critChance", 0.0))
	e.crit_multiplier = float(d.get("critMultiplier", 1.0))
	e.cooldown = float(d.get("cooldown", 0.0))
	e.defence_level = int(d.get("defenceLevel", d.get("level", 0)))
	e.flat_damage_reduction = int(d.get("flatDamageReduction", 0))
	e.damage_taken_multiplier = float(d.get("damageTakenMultiplier", 1.0))
	e.defence_bonuses = EnemyDef._defence_bonuses(d, e.level)
	e.combat_xp = float(d.get("combatXp", 0.0))
	e.hitpoints_xp = float(d.get("hitpointsXp", 0.0))
	e.slayer_req = float(d.get("beastMasteryReq", 0.0))
	e.slayer_xp = float(d.get("beastMasteryXp", 0.0))
	e.is_boss = bool(d.get("isBoss", false))
	e.drops = d.get("drops", [])
	return e


func is_empty() -> bool:
	return id.is_empty()


## Relevant defence bonus for an incoming attack type (stab/slash/crush/ranged/magic).
func defence_bonus(attack_type: String) -> int:
	return int(defence_bonuses.get(attack_type, 0))


## JSON defenceBonuses if authored (enables weaknesses), else a uniform bonus
## derived from level so legacy enemies have sane, scaling defence.
static func _defence_bonuses(d: Dictionary, level: int) -> Dictionary:
	var src: Variant = d.get("defenceBonuses", null)
	var base := int(round(float(level) * 0.5))   # uniform, no weakness, for legacy mobs
	var out := {"stab": base, "slash": base, "crush": base, "ranged": base, "magic": base}
	if src is Dictionary:
		for k: String in out:
			out[k] = int((src as Dictionary).get(k, out[k]))
	return out
