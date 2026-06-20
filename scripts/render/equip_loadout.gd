extends RefCounted
class_name EquipLoadout
## Derives a visible-equipment loadout ({slot: {kind, material, tint?}}) for a mover
## from game data: the player's worn items (GameState.equipment) or an enemy's combat
## archetype. PropMeshes.apply_equipment turns the loadout into meshes on the rig's
## sockets; slots the body can't support are dropped there. See
## docs/render_spike/MODELS_AND_EQUIPMENT.md.

# Metal tier by enemy combat level (low level = crude metal).
const TIERS := [[8, "bronze"], [16, "iron"], [30, "steel"], [50, "mithril"], [70, "adamant"]]
const MAGE_CLOTH := Color(0.42, 0.32, 0.6)        # generic mage purple
const GOBLIN_CLOTH := Color(0.33, 0.45, 0.3)      # goblin shamans: a mossy witch green


static func _tier(level: int) -> String:
	for t: Array in TIERS:
		if level <= int(t[0]):
			return str(t[1])
	return "rune"


# Visual metal grade by the item's data `tier` (1..8). Matches the canonical named
# metals exactly (bronze=1, iron=2, steel=3, mithril=4, adamant=5), so swapping name
# inference for this is regression-free — and the game's invented tier families
# (Zephite, Emberite, Glaciite, …) finally render at their real grade instead of all
# defaulting to iron-grey.
const TIER_METAL := ["bronze", "bronze", "iron", "steel", "mithril", "adamant", "rune", "rune", "gold"]


## Material for a worn item, most-authoritative source first:
##   1. explicit ItemDef.render_material  (per-item art override; rename-proof)
##   2. cloth/wood/leather family by name  (robes/bows keep their look at every tier)
##   3. the data `tier` ramp for metal gear (data-driven; replaces metal name-matching)
##   4. raw name inference                 (last-resort fallback)
static func _material(def: ItemDef, disp: String) -> String:
	if not def.render_material.is_empty():
		return def.render_material
	var fam := material_for(disp)
	if fam in ["cloth", "wood", "leather"]:
		return fam
	if def.tier > 0:
		return TIER_METAL[clampi(def.tier, 0, TIER_METAL.size() - 1)]
	return fam


## Visual mesh kind for a worn item: explicit ItemDef.render_kind if authored, else
## the supplied inferred fallback.
static func _kind(def: ItemDef, fallback: String) -> String:
	return def.render_kind if not def.render_kind.is_empty() else fallback


## Map an item display name to a material tier (metal/cloth/leather/wood).
static func material_for(item_name: String) -> String:
	var n := item_name.to_lower()
	for key: String in ["bronze", "iron", "steel", "mithril", "adamant", "rune", "gold", "leather"]:
		if n.contains(key):
			return key
	if n.contains("robe") or n.contains("cloth") or n.contains("mage") or n.contains("wizard"):
		return "cloth"
	if n.contains("staff") or n.contains("bow") or n.contains("wand"):
		return "wood"
	return "iron"


## Map a weapon item display name to a held-weapon kind.
static func weapon_kind(item_name: String) -> String:
	var n := item_name.to_lower()
	for kw: String in ["staff", "wand", "dagger", "scimitar", "spear", "axe", "mace", "bow"]:
		if n.contains(kw):
			return "bow" if kw == "bow" else ("sword" if kw == "scimitar" else kw)
	if n.contains("sword") or n.contains("blade") or n.contains("reaver"):
		return "sword"
	return "sword"


static func _is_cloth(item_name: String) -> bool:
	var n := item_name.to_lower()
	return n.contains("robe") or n.contains("cloth") or n.contains("hood") or n.contains("mage") or n.contains("wizard")


## The player's default outfit when a slot has nothing equipped — the adventurer's
## own clothes (leather jerkin + a travel cape) layered over the bare body. Worn
## armor overrides these per slot, so the outfit "lives separately" from the body
## and from equipped gear. Expand this for alternate player looks later.
static func player_default() -> Dictionary:
	# Showcase: a full bronze plate harness (horned great-helm + spiked pauldrons +
	# cape) so the 3D armour potential is visible by default. Worn items still
	# override per slot. Swap back to {"body": jerkin, "back": cape} for the plain look.
	return {
		"head": {"kind": "helm", "material": "bronze"},
		"body": {"kind": "chest", "material": "bronze"},
		"back": {"kind": "cape", "material": "cloth", "tint": Color(0.62, 0.15, 0.13)},
	}


## Loadout for the player: start from the default outfit, then let worn items
## override per slot. Maps the OSRS-style slots to render slots.
static func for_player(equipment: Dictionary) -> Dictionary:
	var ld: Dictionary = player_default()
	for slot: String in equipment:
		var id := str(equipment[slot])
		var def: ItemDef = DataRegistry.item_def(id)
		var disp := DataRegistry.item_display_name(id)
		var mat := _material(def, disp)
		match slot:
			"Weapon":
				ld["mainhand"] = {"kind": _kind(def, weapon_kind(disp)), "material": mat}
			"Shield":
				ld["offhand"] = {"kind": _kind(def, "shield"), "material": mat}
			"Helm":
				ld["head"] = {"kind": _kind(def, "hood" if _is_cloth(disp) else "helm"), "material": mat}
			"Body":
				ld["body"] = {"kind": _kind(def, "robe_top" if _is_cloth(disp) else "chest"), "material": mat}
			"Cape":
				var tint: Color = def.render_tint if def.render_tint.a > 0.0 else Color(0.6, 0.2, 0.18)
				var cape_mat: String = def.render_material if not def.render_material.is_empty() else "cloth"
				ld["back"] = {"kind": _kind(def, "cape"), "material": cape_mat, "tint": tint}
	return ld


## Loadout for an enemy from its combat archetype (style + name + level).
static func for_enemy(name: String, level: int) -> Dictionary:
	var data := DataRegistry.get_enemy(name)
	var style := str(data.get("style", "")).to_lower()
	var n := name.to_lower()
	var mat := _tier(level)
	if style.contains("mag") or n.contains("mage") or n.contains("shaman") or n.contains("wizard") or n.contains("warlock"):
		var robe := GOBLIN_CLOTH if n.contains("goblin") else MAGE_CLOTH
		return {
			"head": {"kind": "wizard_hat", "material": "cloth", "tint": robe},
			"body": {"kind": "robe_top", "material": "cloth", "tint": robe},
			"legs": {"kind": "robe_bottom", "material": "cloth", "tint": robe},
			"mainhand": {"kind": "raven_staff", "material": "wood"},
		}
	if style.contains("rang") or n.contains("ranger") or n.contains("archer") or n.contains("bow"):
		return {"mainhand": {"kind": "bow", "material": "wood"}}
	# Melee: a tiered weapon, plus a shield for the heavier fighter types.
	var ld := {"mainhand": {"kind": "sword", "material": mat}}
	if n.contains("fighter") or n.contains("warrior") or n.contains("guard") or n.contains("knight") or n.contains("brawler"):
		ld["offhand"] = {"kind": "shield", "material": mat}
	return ld
