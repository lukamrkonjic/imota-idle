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
var tier: int = 0                # material/power tier 0..8 (drives the visual metal grade)
var reqs: Dictionary = {}
# Optional visual authoring for the 3D renderer (EquipLoadout). When set, these win
# over name inference, so renaming an item never changes how it looks. Empty = let
# EquipLoadout fall back to inferring from the display name.
var render_kind: String = ""     # mesh kind: sword/axe/bow/staff/helm/hood/chest/robe_top/...
var render_material: String = ""  # visual tier: bronze/iron/steel/mithril/adamant/rune/cloth/wood/...
var render_tint: Color = Color(0, 0, 0, 0)  # cloth/gem colour override (a==0 -> none)


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
	it.tier = int(d.get("tier", 0))
	it.reqs = d.get("reqs", {})
	it.render_kind = str(d.get("renderKind", ""))
	it.render_material = str(d.get("renderMaterial", ""))
	it.render_tint = _parse_color(d.get("renderTint", null))
	return it


## Parse an optional colour authored as [r,g,b] / [r,g,b,a] (0..1) or "#rrggbb".
## Returns a fully-transparent colour (a==0) when absent, which callers treat as "unset".
static func _parse_color(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() >= 4 else 1.0)
	if v is String and (v as String).begins_with("#"):
		return Color.html(v)
	return Color(0, 0, 0, 0)


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


# --- OSRS-inspired combat stats ----------------------------------------------
# Weapons may declare rich combat stats in JSON (attackBonuses / strengthBonuses /
# weaponCategory / critChance / critMultiplier / allowedAttackStyles). When ABSENT
# they are DERIVED from `tier` + category so all legacy items work in the new
# combat math without a data rewrite. Author exact values per weapon to override.

const _CC := preload("res://scripts/combat/combat_constants.gd")

# category -> { acc:[stab,slash,crush] weights, str: melee tilt, speed, crit, critx }
const _CAT_PROFILE := {
	"dagger":     {"acc": [1.0, 0.45, -0.6], "str": 0.7, "speed": 4, "crit": 0.10, "critx": 1.5},
	"sword":      {"acc": [0.9, 0.95, -0.3], "str": 0.95, "speed": 5, "crit": 0.05, "critx": 1.5},
	"scimitar":   {"acc": [0.45, 1.0, -0.3], "str": 0.85, "speed": 4, "crit": 0.05, "critx": 1.5},
	"mace":       {"acc": [-0.3, -0.15, 1.0], "str": 0.85, "speed": 5, "crit": 0.04, "critx": 2.0},
	"battleaxe":  {"acc": [-0.5, 1.0, 0.8], "str": 1.4, "speed": 6, "crit": 0.04, "critx": 1.75},
	"two_handed": {"acc": [-0.4, 1.0, 0.85], "str": 1.6, "speed": 7, "crit": 0.04, "critx": 1.75},
	"bow":        {"acc": [0, 0, 0], "str": 0.0, "speed": 4, "crit": 0.05, "critx": 1.5},
	"crossbow":   {"acc": [0, 0, 0], "str": 0.0, "speed": 5, "crit": 0.06, "critx": 1.6},
	"staff":      {"acc": [0, 0, 0], "str": 0.0, "speed": 5, "crit": 0.05, "critx": 1.5},
	"unarmed":    {"acc": [0.2, 0.2, 0.2], "str": 0.2, "speed": 4, "crit": 0.02, "critx": 1.5},
}


## Weapon category (drives the derived stat shape + allowed styles). JSON wins; else
## inferred from renderKind, then name keywords, then combatStyle.
func weapon_category() -> String:
	var c := str(raw.get("weaponCategory", ""))
	if c in _CC.WEAPON_CATEGORIES:
		return c
	var hay := (render_kind + " " + name + " " + display_name).to_lower()
	for kw: Array in [["scimitar", "scimitar"], ["dagger", "dagger"], ["knife", "dagger"],
			["battleaxe", "battleaxe"], ["battle axe", "battleaxe"], ["warhammer", "mace"],
			["hammer", "mace"], ["mace", "mace"], ["greatsword", "two_handed"], ["godsword", "two_handed"],
			["2h", "two_handed"], ["two-hand", "two_handed"], ["crossbow", "crossbow"], ["bow", "bow"],
			["staff", "staff"], ["wand", "staff"], ["longsword", "sword"], ["sword", "sword"], ["axe", "battleaxe"]]:
		if hay.contains(str(kw[0])):
			return str(kw[1])
	match weapon_style():
		"ranged": return "bow"
		"magic": return "staff"
		_: return "sword" if slot == "Weapon" else "unarmed"


## Accelerating tier curves so higher tiers pull ahead (not a blind multiply).
func _acc_base() -> int:
	var t := float(tier)
	return int(round(2.0 + t * 2.2 + t * t * 0.22))


func _str_base() -> int:
	var t := float(tier)
	return int(round(1.0 + t * 1.7 + t * t * 0.17))


## {stab,slash,crush,ranged,magic} accuracy bonuses (JSON override or derived).
func attack_bonuses() -> Dictionary:
	if raw.has("attackBonuses"):
		return _fill_attack(raw["attackBonuses"])
	var out := {"stab": 0, "slash": 0, "crush": 0, "ranged": 0, "magic": 0}
	if slot != "Weapon":
		return out   # legacy armour/jewellery: no attack bonus unless authored
	var cat := weapon_category()
	var p: Dictionary = _CAT_PROFILE.get(cat, _CAT_PROFILE["unarmed"])
	match weapon_style():
		"ranged": out["ranged"] = _acc_base()
		"magic": out["magic"] = _acc_base()
		_:
			var ab := _acc_base()
			var w: Array = p["acc"]
			out["stab"] = int(round(ab * float(w[0])))
			out["slash"] = int(round(ab * float(w[1])))
			out["crush"] = int(round(ab * float(w[2])))
	return out


## {melee,ranged,magic} strength bonuses (JSON override or derived).
func strength_bonuses() -> Dictionary:
	if raw.has("strengthBonuses"):
		return _fill_strength(raw["strengthBonuses"])
	var out := {"melee": 0, "ranged": 0, "magic": 0}
	if slot != "Weapon":
		return out
	var p: Dictionary = _CAT_PROFILE.get(weapon_category(), _CAT_PROFILE["unarmed"])
	match weapon_style():
		"ranged": out["ranged"] = _str_base()
		"magic": out["magic"] = _str_base()
		_: out["melee"] = int(round(_str_base() * float(p["str"])))
	return out


## {stab,slash,crush,ranged,magic} DEFENCE bonuses (JSON override or derived from
## tier for worn armour — weapons contribute ~none).
func defence_bonuses() -> Dictionary:
	if raw.has("defenceBonuses"):
		return _fill_attack(raw["defenceBonuses"])
	var out := {"stab": 0, "slash": 0, "crush": 0, "ranged": 0, "magic": 0}
	if not is_equippable() or slot == "Weapon" or slot.is_empty():
		return out
	var d := int(round(float(tier) * 2.0 + float(raw.get("damageReduction", 0)) * 0.5))
	for k: String in ["stab", "slash", "crush", "ranged"]:
		out[k] = d
	out["magic"] = int(round(d * 0.4))   # most armour is weaker to magic
	return out


func weapon_crit_chance() -> float:
	if raw.has("critChance") and float(raw["critChance"]) > 0.0:
		return float(raw["critChance"])
	return float(_CAT_PROFILE.get(weapon_category(), _CAT_PROFILE["unarmed"]).get("crit", _CC.DEFAULT_CRIT_CHANCE))


func weapon_crit_multiplier() -> float:
	if raw.has("critMultiplier") and float(raw["critMultiplier"]) > 1.0:
		return float(raw["critMultiplier"])
	return float(_CAT_PROFILE.get(weapon_category(), _CAT_PROFILE["unarmed"]).get("critx", _CC.DEFAULT_CRIT_MULTIPLIER))


## Attack-speed in ticks: explicit `attackSpeed`, else the category default.
func attack_ticks() -> int:
	if attack_speed > 0:
		return attack_speed
	return int(_CAT_PROFILE.get(weapon_category(), _CAT_PROFILE["unarmed"]).get("speed", 4))


static func _fill_attack(d: Variant) -> Dictionary:
	var s: Dictionary = d if d is Dictionary else {}
	return {"stab": int(s.get("stab", 0)), "slash": int(s.get("slash", 0)),
		"crush": int(s.get("crush", 0)), "ranged": int(s.get("ranged", 0)), "magic": int(s.get("magic", 0))}


static func _fill_strength(d: Variant) -> Dictionary:
	var s: Dictionary = d if d is Dictionary else {}
	return {"melee": int(s.get("melee", 0)), "ranged": int(s.get("ranged", 0)), "magic": int(s.get("magic", 0))}
