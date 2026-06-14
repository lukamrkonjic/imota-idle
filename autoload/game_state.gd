extends Node
## Player state: skill XP/levels, inventory, bank, equipment, coins, HP.

const SaveMigration := preload("res://autoload/save_migration.gd")
## All mutation goes through methods here so EventBus signals stay accurate.

# OSRS-style 22-skill roster (Imota spec §2). Bloobs skill keys are migrated to
# these via SkillRemap (devotion->prayer, tracking->hunter, dexterity->agility,
# homesteading->farming, herbology->alchemy, beastmastery->slayer; imbuing/
# soulbinding fold into crafting). foraging stays (gathering only).
const SKILLS := [
	"attack", "strength", "defence", "hitpoints", "ranged", "magic",
	"prayer", "slayer",
	"woodcutting", "mining", "fishing", "foraging", "thieving", "hunter",
	"farming",
	"cooking", "smithing", "firemaking", "fletching", "crafting", "alchemy",
	"agility",
]

# OSRS-style fixed 28-slot inventory (Imota spec §0). Was a Bloobs-shaped 24.
const BASE_INVENTORY_SLOTS := 28

const EQUIPMENT_SLOTS := [
	"Helm", "Body", "Boots", "Weapon", "Shield", "Ring", "Gloves", "Cape",
	"Amulet", "Ammunition", "Axe", "Pickaxe", "Rod", "Lens",
]

var skills: Dictionary = {}      # skill -> {"xp": float, "level": int}
var inventory: Array = []        # [{ "id": String, "qty": int }] stacked by stable item id
var bank: Dictionary = {}        # item id -> qty
var equipment: Dictionary = {}   # slot -> item id
var coins: int = 0
var current_hp: int = 10

var _hp_regen_timer := 0.0


func _ready() -> void:
	reset_state()


func reset_state() -> void:
	skills = {}
	for s: String in SKILLS:
		skills[s] = {"xp": 0.0, "level": 1}
	# Hitpoints starts at 10 like OSRS; backfill the XP to match.
	skills["hitpoints"]["level"] = 10
	skills["hitpoints"]["xp"] = float(DataRegistry.xp_for_level(10))
	inventory = []
	bank = {}
	equipment = {}
	coins = 0
	# Starter kit: the Bronze tool set (real smithing-recipe items from the
	# export). Bronze Sword needs Attack 3 — it waits in the inventory; until
	# then the player fights unarmed (damage = 1 + Strength level).
	add_item("Bronze Axe", 1)
	add_item("Bronze Pickaxe", 1)
	add_item("Bronze Rod", 1)
	add_item("Bronze Lens", 1)
	add_item("Bronze Sword", 1)
	equip("Bronze Axe")
	equip("Bronze Pickaxe")
	equip("Bronze Rod")
	equip("Bronze Lens")
	current_hp = max_hp()


func _process(delta: float) -> void:
	# Slow out-of-combat regen (idle-friendly; exact source value is scene data).
	if not CombatSim.active and current_hp < max_hp():
		_hp_regen_timer += delta
		if _hp_regen_timer >= 3.0:
			_hp_regen_timer = 0.0
			set_hp(current_hp + 1)


# ---------------------------------------------------------------- skills ----

func level(skill: String) -> int:
	return int(skills[skill]["level"])


func xp(skill: String) -> float:
	return float(skills[skill]["xp"])


func add_xp(skill: String, amount: float) -> void:
	if amount <= 0.0 or not skills.has(skill):
		return
	var bonus := equipment_bonus_xp(skill)
	var total: float = amount * (1.0 + bonus)
	skills[skill]["xp"] += total
	EventBus.xp_gained.emit(skill, total)
	var lvl := int(skills[skill]["level"])
	while lvl < DataRegistry.max_level and skills[skill]["xp"] >= float(DataRegistry.xp_for_level(lvl + 1)):
		lvl += 1
		skills[skill]["level"] = lvl
		if skill == "hitpoints":
			set_hp(current_hp + 1)
		EventBus.level_up.emit(skill, lvl)


# ------------------------------------------------------------- inventory ----

func max_inventory_slots() -> int:
	return BASE_INVENTORY_SLOTS


func inventory_full() -> bool:
	return inventory.size() >= max_inventory_slots()


## Returns the quantity actually added (0 if the inventory is full).
## Accepts stable item id or legacy display name.
func add_item(item_name_or_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	if item_id.is_empty():
		push_warning("add_item: unknown item '%s'" % item_name_or_id)
		return 0
	for stack: Dictionary in inventory:
		if stack["id"] == item_id:
			stack["qty"] += qty
			EventBus.inventory_changed.emit()
			return qty
	if inventory_full():
		return 0
	inventory.append({"id": item_id, "qty": qty})
	EventBus.inventory_changed.emit()
	return qty


func remove_item(item_name_or_id: String, qty: int) -> bool:
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	if item_id.is_empty():
		return false
	for i: int in inventory.size():
		var stack: Dictionary = inventory[i]
		if stack["id"] == item_id:
			if stack["qty"] < qty:
				return false
			stack["qty"] -= qty
			if stack["qty"] <= 0:
				inventory.remove_at(i)
			EventBus.inventory_changed.emit()
			return true
	return false


func count_item(item_name_or_id: String) -> int:
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	for stack: Dictionary in inventory:
		if stack["id"] == item_id:
			return int(stack["qty"])
	return 0


# ------------------------------------------------------------------ bank ----

func deposit(item_name_or_id: String, qty: int) -> void:
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	if item_id.is_empty():
		return
	if remove_item(item_id, qty):
		bank[item_id] = int(bank.get(item_id, 0)) + qty
		EventBus.bank_changed.emit()


func deposit_all() -> void:
	for stack: Dictionary in inventory.duplicate():
		deposit(str(stack["id"]), int(stack["qty"]))


func withdraw(item_name_or_id: String, qty: int) -> void:
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	if item_id.is_empty():
		return
	var have := int(bank.get(item_id, 0))
	qty = mini(qty, have)
	if qty <= 0:
		return
	if add_item(item_id, qty) == qty:
		bank[item_id] = have - qty
		if bank[item_id] <= 0:
			bank.erase(item_id)
		EventBus.bank_changed.emit()


# ----------------------------------------------------------------- coins ----

func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	EventBus.coins_changed.emit(coins)


func sell_item(item_name: String, qty: int) -> void:
	qty = mini(qty, count_item(item_name))
	if qty > 0 and remove_item(item_name, qty):
		add_coins(DataRegistry.item_value(item_name) * qty)


func buy_item(item_name: String, qty: int) -> bool:
	var cost := DataRegistry.item_value(item_name) * qty
	if coins < cost:
		return false
	if add_item(item_name, qty) != qty:
		return false
	add_coins(-cost)
	return true


# ------------------------------------------------------------- equipment ----

## Slot inference ported from EquipmentSystem.GetEquipmentSlotForItem —
## Bloobs maps items to slots by name substring, in this priority order.
static func slot_for_item(item_name: String) -> String:
	var n := item_name.to_lower()
	if n == "herring":
		return "Food"
	for rule: Array in [
		["helm", "Helm"], ["hat", "Helm"], ["coif", "Helm"],
		["body", "Body"], ["tunic", "Body"], ["robe", "Body"],
		["boots", "Boots"], ["slippers", "Boots"], ["moccasins", "Boots"],
		["sword", "Weapon"], ["dagger", "Weapon"], ["scimitar", "Weapon"],
		["reaver", "Weapon"], ["shortbow", "Weapon"], ["bow", "Weapon"],
		["longbow", "Weapon"], ["staff", "Weapon"],
		["shield", "Shield"], ["ring", "Ring"],
		["gloves", "Gloves"], ["mitts", "Gloves"], ["wraps", "Gloves"],
		["cape", "Cape"], ["necklace", "Amulet"],
		["arrows", "Ammunition"],
		["pickaxe", "Pickaxe"], ["axe", "Axe"], ["rod", "Rod"], ["lens", "Lens"],
		["potion", "Potion"], ["lockpick", "Lockpick"], ["slate", "Slate"],
	]:
		if n.contains(rule[0]):
			return rule[1]
	return "Food"


func meets_requirements(item: Dictionary) -> bool:
	var reqs: Dictionary = item.get("reqs", {})
	for skill: String in reqs:
		if level(skill) < int(reqs[skill]):
			return false
	return true


func equip(item_name_or_id: String) -> bool:
	var item := DataRegistry.get_item(item_name_or_id)
	if item.is_empty() or count_item(item_name_or_id) <= 0:
		return false
	if not meets_requirements(item):
		return false
	var item_id: String = str(item["id"])
	var slot := slot_for_item(DataRegistry.item_display_name(item_id))
	if slot in ["Food", "Potion", "Lockpick", "Slate"]:
		return false  # consumable pseudo-slots are not worn gear (Phase 4)
	if equipment.has(slot):
		unequip(slot)
	if not remove_item(item_id, 1):
		return false
	equipment[slot] = item_id
	EventBus.equipment_changed.emit()
	return true


func unequip(slot: String) -> void:
	if not equipment.has(slot):
		return
	var item_id: String = equipment[slot]
	if add_item(item_id, 1) == 0:
		return  # inventory full — keep it equipped
	equipment.erase(slot)
	EventBus.equipment_changed.emit()


func _sum_equipment(field: String) -> float:
	var total := 0.0
	for slot: String in equipment:
		total += float(DataRegistry.get_item(equipment[slot]).get(field, 0))
	return total


func equipment_accuracy() -> float: return _sum_equipment("accuracy")
func equipment_damage() -> float: return _sum_equipment("damage")
func equipment_damage_reduction() -> float: return _sum_equipment("damageReduction")
func equipment_range_accuracy() -> float: return _sum_equipment("rangeAccuracy")
func equipment_range_damage() -> float: return _sum_equipment("rangeDamage")
func equipment_magic_accuracy() -> float: return _sum_equipment("magicAccuracy")
func equipment_magic_damage() -> float: return _sum_equipment("magicDamage")
func equipment_crit_chance() -> float: return _sum_equipment("critChance")


func equipment_bonus_xp(skill: String) -> float:
	var total := 0.0
	for slot: String in equipment:
		total += float(DataRegistry.get_item(equipment[slot]).get("bonusXp", {}).get(skill, 0.0))
	return total


## Gather-tool power: damage dealt to a node per action (Trees.ReduceHealth).
func tool_progress(skill: String) -> int:
	var slot: String = {
		"woodcutting": "Axe", "mining": "Pickaxe", "fishing": "Rod", "foraging": "Lens",
	}.get(skill, "")
	if slot.is_empty() or not equipment.has(slot):
		return 0
	return int(DataRegistry.get_item(equipment[slot]).get("progress", 0))


## Eat one unit of a cooked food item; heals the recipe's hpValue.
func eat(item_name_or_id: String) -> bool:
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	var heal := int(DataRegistry.food_hp.get(item_id, 0))
	if heal <= 0 or current_hp >= max_hp():
		return false
	if not remove_item(item_id, 1):
		return false
	set_hp(current_hp + heal)
	return true


# -------------------------------------------------------------------- hp ----

func max_hp() -> int:
	# Player max health equals the Hitpoints level (HitPointsSkill.Start).
	return level("hitpoints")


func set_hp(value: int) -> void:
	current_hp = clampi(value, 0, max_hp())
	EventBus.hp_changed.emit(current_hp, max_hp())


func admin_max_skill(skill: String) -> void:
	if not skills.has(skill):
		return
	var max_lvl := DataRegistry.max_level
	skills[skill]["level"] = max_lvl
	skills[skill]["xp"] = float(DataRegistry.xp_for_level(max_lvl))
	if skill == "hitpoints":
		current_hp = max_hp()
		EventBus.hp_changed.emit(current_hp, max_hp())
	EventBus.level_up.emit(skill, max_lvl)


func admin_max_all_skills() -> void:
	for s: String in SKILLS:
		admin_max_skill(s)


func admin_give_item(item_name_or_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var item_id := DataRegistry.resolve_item_id(item_name_or_id)
	if item_id.is_empty():
		return 0
	var added := add_item(item_name_or_id, qty)
	var left := qty - added
	if left > 0:
		bank[item_id] = int(bank.get(item_id, 0)) + left
		EventBus.bank_changed.emit()
	return qty


# ------------------------------------------------------------ save state ----

func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": SaveMigration.CURRENT_SCHEMA,
		"gameVersion": SaveMigration.CURRENT_GAME_VERSION,
		"skills": skills.duplicate(true),
		"inventory": inventory.duplicate(true),
		"bank": bank.duplicate(true),
		"equipment": equipment.duplicate(true),
		"coins": coins,
		"current_hp": current_hp,
	}


func from_save_dict(d: Dictionary) -> void:
	d = SaveMigration.migrate_game_save(d)
	var loaded: Dictionary = d.get("skills", {})
	for s: String in SKILLS:
		if loaded.has(s):
			skills[s] = {"xp": float(loaded[s]["xp"]), "level": int(loaded[s]["level"])}
	inventory = []
	for stack: Dictionary in d.get("inventory", []):
		var raw: String = str(stack.get("id", stack.get("name", "")))
		var item_id := DataRegistry.resolve_item_id(raw)
		if item_id.is_empty():
			push_warning("Save load: unknown inventory item '%s' skipped" % raw)
			continue
		inventory.append({"id": item_id, "qty": int(stack["qty"])})
	bank = {}
	var saved_bank: Dictionary = d.get("bank", {})
	for k: String in saved_bank:
		var item_id := DataRegistry.resolve_item_id(k)
		if not item_id.is_empty():
			bank[item_id] = int(saved_bank[k]) + int(bank.get(item_id, 0))
	equipment = {}
	var saved_eq: Dictionary = d.get("equipment", {})
	for k: String in saved_eq:
		var item_id := DataRegistry.resolve_item_id(str(saved_eq[k]))
		if not item_id.is_empty():
			equipment[k] = item_id
	coins = int(d.get("coins", d.get("gold", 0)))
	current_hp = clampi(int(d.get("current_hp", max_hp())), 1, max_hp())
	EventBus.inventory_changed.emit()
	EventBus.bank_changed.emit()
	EventBus.equipment_changed.emit()
	EventBus.coins_changed.emit(coins)
	EventBus.hp_changed.emit(current_hp, max_hp())
