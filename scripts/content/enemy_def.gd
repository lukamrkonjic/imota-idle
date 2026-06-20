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
	e.combat_xp = float(d.get("combatXp", 0.0))
	e.hitpoints_xp = float(d.get("hitpointsXp", 0.0))
	e.slayer_req = float(d.get("beastMasteryReq", 0.0))
	e.slayer_xp = float(d.get("beastMasteryXp", 0.0))
	e.is_boss = bool(d.get("isBoss", false))
	e.drops = d.get("drops", [])
	return e


func is_empty() -> bool:
	return id.is_empty()
