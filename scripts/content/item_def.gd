extends RefCounted
class_name ItemDef
## Typed view over a data/items.json entry. The equipment/combat paths read typed fields
## here instead of stringly-keyed dict lookups (which fail silently on a typo). The raw dict
## stays reachable via `raw` for the still-incremental migration of the rest of the codebase.
## See docs/content/SCHEMA.md for the field reference.

var raw: Dictionary = {}
var id: String = ""
var name: String = ""            # frozen legacy key
var display_name: String = ""
var value: int = 0
var category: String = ""        # material / equipment / tool / consumable
var slot: String = ""            # worn/tool slot, or a consumable pseudo-slot, or ""
var combat_style: String = ""    # explicit melee/ranged/magic on weapons
var attack_speed: int = 0        # ticks; 0 = use the default
var reqs: Dictionary = {}


static func from_dict(d: Dictionary) -> ItemDef:
	var it := ItemDef.new()
	if d.is_empty():
		return it
	it.raw = d
	it.id = str(d.get("id", ""))
	it.name = str(d.get("name", ""))
	it.display_name = str(d.get("displayName", it.name))
	it.value = int(d.get("value", 0))
	it.category = str(d.get("category", ""))
	it.slot = str(d.get("slot", ""))
	it.combat_style = str(d.get("combatStyle", ""))
	it.attack_speed = int(d.get("attackSpeed", 0))
	it.reqs = d.get("reqs", {})
	return it


func is_empty() -> bool:
	return id.is_empty()


## True if this item is WORN gear — i.e. real equipment or a gather tool (data category),
## NOT a consumable pseudo-slot (Potion/Slate/Lockpick) or a material. Category-driven, so a
## name collision can never make a material look equippable.
func is_equippable() -> bool:
	return category == "equipment" or category == "tool"


## Combat style from explicit data, then stat-based (range/magic damage), then melee.
## NEVER name-inferred — a substring like "staff"/"knife" must not decide combat math.
func weapon_style() -> String:
	if combat_style == "melee" or combat_style == "ranged" or combat_style == "magic":
		return combat_style
	if int(raw.get("rangeDamage", 0)) > 0:
		return "ranged"
	if int(raw.get("magicDamage", 0)) > 0:
		return "magic"
	return "melee"


## A stat-block field (accuracy/damage/damageReduction/…) as a float, 0 if absent.
func stat(field: String) -> float:
	return float(raw.get(field, 0))
