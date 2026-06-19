extends Node
## Player state: skill XP/levels, inventory, bank, equipment, coins, HP.

const SaveMigration := preload("res://autoload/save_migration.gd")
const PrayerLore := preload("res://scripts/skills/prayer_lore.gd")
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
var combat_style: String = "attack"   # trained combat skill (persisted, spec §12)
var active_prayers: Array = []         # names of prayers toggled on (combat hooks)
var devotion: float = -1.0             # current Devotion points (-1 = uninit -> full on first use)
var slayer_task: Dictionary = {}       # {monster, required, done} or {} when none
var slayer_points: int = 0             # currency earned from completing slayer tasks
var _slayer_rng := RandomNumberGenerator.new()
var run_energy: float = 100.0          # Agility meta-stat (spec §16); speeds auto-nav
var player_pos: Vector2 = Vector2.INF  # last world position; Vector2.INF = "use spawn" (new game)
var _death_rng := RandomNumberGenerator.new()

# High Alchemy (spec §16/§18): the item->coins magic sink. Placeholder numbers.
const HIGH_ALCH_LEVEL := 55
const HIGH_ALCH_RATE := 0.6
const HIGH_ALCH_XP := 65.0
const RUN_REGEN_PER_SEC := 0.5

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
	combat_style = "attack"
	active_prayers = []
	devotion = -1.0   # lazily filled to full on first read
	slayer_task = {}
	slayer_points = 0
	run_energy = 100.0
	player_pos = Vector2.INF
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
	regen_run_energy(delta)


# ---------------------------------------------------------------- skills ----

func level(skill: String) -> int:
	# Clamp to the cap: pre-cap saves (and the old admin "max") stored levels up
	# to 1000, which read back as 1000+ damage. The cap is 99 everywhere now.
	return mini(int(skills[skill]["level"]), DataRegistry.max_level)


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
func meets_requirements(item: Dictionary) -> bool:
	var reqs: Dictionary = item.get("reqs", {})
	for skill: String in reqs:
		if level(skill) < int(reqs[skill]):
			return false
	return true


func equip(item_name_or_id: String) -> bool:
	var item := DataRegistry.item_def(item_name_or_id)
	if item.is_empty() or count_item(item_name_or_id) <= 0:
		return false
	if not meets_requirements(item.raw):
		return false
	if not item.is_equippable():
		return false  # materials / consumables (incl. Potion/Slate/Lockpick) are not worn gear
	if not remove_item(item.id, 1):
		return false
	# Swap in place: the new item just vacated an inventory slot, so the previously-worn
	# item goes back into that freed slot. This can't destroy the old gear even on a full
	# inventory (the old unequip-first path overwrote the slot and lost the worn item).
	var prev: String = str(equipment.get(item.slot, ""))
	if not prev.is_empty():
		add_item(prev, 1)
	equipment[item.slot] = item.id
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


## Combat style dictated by the EQUIPPED WEAPON: "ranged" for a bow/crossbow,
## "magic" for a staff/wand, else "melee". This overrides which stat the player is
## set to train — a bow always shoots at range, it can't be swung as a melee weapon.
func weapon_combat_style() -> String:
	var wid := str(equipment.get("Weapon", ""))
	if wid.is_empty():
		return "melee"
	return DataRegistry.item_def(wid).weapon_style()


func equipment_bonus_xp(skill: String) -> float:
	var total := 0.0
	for slot: String in equipment:
		total += float(DataRegistry.get_item(equipment[slot]).get("bonusXp", {}).get(skill, 0.0))
	return total


## Gather-tool power: damage dealt to a node per action (Trees.ReduceHealth).
func tool_progress(skill: String) -> int:
	# Toolless gather skills (hunter traps / thieving bare hands) carry a base "competence"
	# from SkillRegistry (baseProgress) so the loop yields without equipped gear. Tool skills
	# read the `progress` of the item in their gather slot (Axe/Pickaxe/Rod/Lens).
	var base := SkillRegistry.base_progress(skill)
	if base > 0:
		return base
	var slot := SkillRegistry.tool_slot(skill)
	if slot.is_empty() or not equipment.has(slot):
		return 0
	return int(DataRegistry.get_item(equipment[slot]).get("progress", 0))


## The best food to eat right now: the smallest heal that still covers the HP
## deficit (least waste), falling back to the largest heal if nothing covers it.
## Returns "" when the inventory holds no food.
func best_food_id() -> String:
	var deficit := max_hp() - current_hp
	var best := ""
	var best_heal := 0
	var best_fit := ""
	var best_fit_heal := 1 << 30
	for stack: Dictionary in inventory:
		var id: String = stack["id"]
		var heal := int(DataRegistry.food_hp.get(id, 0))
		if heal <= 0:
			continue
		if heal > best_heal:
			best_heal = heal
			best = id
		if heal >= deficit and heal < best_fit_heal:
			best_fit_heal = heal
			best_fit = id
	return best_fit if not best_fit.is_empty() else best


## Auto-eat the best food if HP is at/below `threshold` (fraction of max). Returns
## true if something was eaten. Used by the idle combat loop (spec §12).
func auto_eat(threshold: float = 0.5) -> bool:
	if current_hp >= max_hp():
		return false
	if float(current_hp) > threshold * float(max_hp()):
		return false
	var food := best_food_id()
	if food.is_empty():
		return false
	return eat(food)


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


# ---------------------------------------------------------------- combat ----

## OSRS combat-level formula over att/str/def/hp/range/magic/prayer. Derived
## display stat used for area/monster soft-gating (spec §12).
func combat_level() -> int:
	var att := float(level("attack"))
	var stg := float(level("strength"))
	var def := float(level("defence"))
	var hp := float(level("hitpoints"))
	var rng := float(level("ranged"))
	var mag := float(level("magic"))
	var pray := float(level("prayer"))
	var base := 0.25 * (def + hp + floorf(pray / 2.0))
	var melee := 0.325 * (att + stg)
	var ranged := 0.325 * (floorf(rng / 2.0) + rng)
	var magic := 0.325 * (floorf(mag / 2.0) + mag)
	return int(floorf(base + maxf(melee, maxf(ranged, magic))))


# OSRS-style timing: the game runs on 0.6s ticks and every action's speed is a
# whole number of ticks. A standard melee weapon is 4 ticks (2.4s).
const TICK := 0.6
const DEFAULT_ATTACK_TICKS := 4


## Snap a duration (seconds) to the nearest whole tick, minimum one tick.
static func snap_to_tick(seconds: float) -> float:
	return maxf(TICK, roundf(seconds / TICK) * TICK)


## Player attack speed in ticks — the equipped weapon's `attackSpeed` (ticks) if
## the data defines one, else the 4-tick default.
func attack_ticks() -> int:
	var spd := DataRegistry.item_def(str(equipment.get("Weapon", ""))).attack_speed
	return spd if spd > 0 else DEFAULT_ATTACK_TICKS


## Seconds between player attacks (attack speed in ticks × the tick length).
func attack_interval() -> float:
	return float(attack_ticks()) * TICK


func is_prayer_active(prayer_name: String) -> bool:
	return active_prayers.has(prayer_name)


# ----------------------------------------------------------------- Prayer ----
## Devotion points: max = Prayer level (1/level). Drained while prayers are active
## (PrayerSim), restored to full at an altar or on respawn.
func devotion_max() -> int:
	return maxi(1, level("prayer"))


## Lazily fill on first read so a fresh/legacy save starts with full Devotion.
func devotion_points() -> float:
	if devotion < 0.0:
		devotion = float(devotion_max())
	return devotion


## Toggle a prayer on/off. Off-on requires the level + some Devotion left, and turns
## off any already-active prayer in the same exclusivity group. Returns the new state.
func toggle_prayer(prayer_name: String) -> bool:
	var def: Dictionary = DataRegistry.prayers.get(prayer_name, {})
	if def.is_empty():
		return false
	if active_prayers.has(prayer_name):
		active_prayers.erase(prayer_name)
		EventBus.prayer_changed.emit()
		return false
	if level("prayer") < int(def.get("levelReq", 1)):
		EventBus.combat_log.emit("[color=#a01010]Prayer level %d required for %s.[/color]" % [int(def.get("levelReq", 1)), prayer_name])
		return false
	if devotion_points() <= 0.0:
		EventBus.combat_log.emit("[color=#a01010]You have no prayer points left — recharge at an altar.[/color]")
		return false
	var group := str(def.get("group", ""))
	if group != "":
		for other: String in active_prayers.duplicate():
			if str(DataRegistry.prayers.get(other, {}).get("group", "")) == group:
				active_prayers.erase(other)
	active_prayers.append(prayer_name)
	EventBus.prayer_changed.emit()
	EventBus.prayer_activated.emit(prayer_name)   # world activation FX
	return true


## Drain Devotion by the active prayers' total per-second cost; deactivate all at empty.
func drain_devotion(delta: float) -> void:
	if active_prayers.is_empty():
		return
	var rate := 0.0
	for n: String in active_prayers:
		rate += float(DataRegistry.prayers.get(n, {}).get("drain", 0.2))
	devotion = maxf(devotion_points() - rate * delta, 0.0)
	if devotion <= 0.0 and not active_prayers.is_empty():
		active_prayers.clear()
		EventBus.combat_log.emit("[color=#a01010]Your prayer points run out; your prayers fade.[/color]")
		EventBus.prayer_changed.emit()


## Passive regen toward max while no prayer is active, so points reflect your Prayer level
## instead of getting stuck at 0 after a drain. (Altars still snap to full instantly.)
const DEVOTION_REGEN_PER_SEC := 2.0
func regen_devotion(delta: float) -> void:
	var mx := float(devotion_max())
	if devotion_points() < mx:
		devotion = minf(devotion + DEVOTION_REGEN_PER_SEC * delta, mx)


func recharge_devotion() -> void:
	devotion = float(devotion_max())
	EventBus.prayer_changed.emit()


## Combined multiplier/bonus from active prayers for a given combat style.
func _prayer_field(field: String, style: String, base: float) -> float:
	var v := base
	for n: String in active_prayers:
		var def: Dictionary = DataRegistry.prayers.get(n, {})
		var ps := str(def.get("style", "any"))
		if ps != "any" and ps != style:
			continue
		if field == "dr":
			v += float(def.get("dr", 0.0))
		elif def.has(field):
			v *= float(def[field])
	return v


func prayer_accuracy_mult(style: String) -> float: return _prayer_field("accuracy", style, 1.0)
func prayer_damage_mult(style: String) -> float: return _prayer_field("damage", style, 1.0)
func prayer_dr_bonus() -> float: return _prayer_field("dr", "any", 0.0)
func prayer_melee_protect() -> float:
	for n: String in active_prayers:
		var m := float(DataRegistry.prayers.get(n, {}).get("meleeProtect", 0.0))
		if m > 0.0:
			return m
	return 1.0


# ----------------------------------------------------------------- Slayer ----
## Assign a new slayer task: a random eligible monster (within Slayer level, non-boss) and a
## kill count scaled by level. No-op (returns the current task) if one is already active.
func assign_slayer_task() -> Dictionary:
	if not slayer_task.is_empty():
		return slayer_task
	var slvl := level("slayer")
	var pool: Array = []
	for e: Dictionary in DataRegistry.enemies.values():
		if bool(e.get("isBoss", false)):
			continue
		if int(e.get("beastMasteryReq", 0)) > slvl:
			continue
		# Store the DISPLAY name — that's what EventBus.enemy_killed emits, so kills match.
		pool.append(str(e.get("displayName", e.get("name", ""))))
	if pool.is_empty():
		return {}
	var monster: String = pool[_slayer_rng.randi() % pool.size()]
	var required := 15 + slvl / 2 + _slayer_rng.randi() % 10
	slayer_task = {"monster": monster, "required": required, "done": 0}
	EventBus.slayer_changed.emit()
	return slayer_task


## A kill toward the active task. On completion: a Slayer XP bonus + Slayer points, task cleared.
func slayer_kill(enemy_name: String) -> void:
	if slayer_task.is_empty() or str(slayer_task.get("monster", "")) != enemy_name:
		return
	slayer_task["done"] = int(slayer_task["done"]) + 1
	if int(slayer_task["done"]) >= int(slayer_task["required"]):
		var pts := 8 + level("slayer") / 4
		slayer_points += pts
		add_xp("slayer", float(int(slayer_task["required"]) * 12))   # completion bonus
		EventBus.combat_log.emit("[color=#9ad29a]Slayer task complete! +%d Slayer points.[/color]" % pts)
		slayer_task = {}
	EventBus.slayer_changed.emit()


func cancel_slayer_task() -> void:
	slayer_task = {}
	EventBus.slayer_changed.emit()


# --------------------------------------------------------- skill loops (§16) ----

## Prayer: bury every bone in the inventory for Prayer XP. Returns how many were
## buried. (The "set it and it runs" Prayer activity, spec §16.)
func bury_bones() -> int:
	var buried := 0
	for stack: Dictionary in inventory.duplicate(true):
		var id: String = str(stack["id"])
		var item_name := str(DataRegistry.get_item(id).get("name", ""))
		if PrayerLore.is_bone(item_name):
			var qty := int(stack["qty"])
			if remove_item(id, qty):
				add_xp("prayer", PrayerLore.bone_xp(item_name) * float(qty))
				buried += qty
	if buried > 0:
		EventBus.combat_log.emit("[prayer] Buried %d bones." % buried)
	return buried


## High Alchemy: turn one item into coins (+ Magic XP). The economy's item sink.
func high_alch(item_name_or_id: String) -> bool:
	if level("magic") < HIGH_ALCH_LEVEL:
		EventBus.combat_log.emit("Magic level %d required for High Alchemy." % HIGH_ALCH_LEVEL)
		return false
	var id := DataRegistry.resolve_item_id(item_name_or_id)
	if id.is_empty() or count_item(id) <= 0:
		return false
	if not remove_item(id, 1):
		return false
	add_coins(int(floor(float(DataRegistry.item_value(id)) * HIGH_ALCH_RATE)))
	add_xp("magic", HIGH_ALCH_XP)
	return true


## Agility meta-stat: run energy drains while auto-navigating and regenerates
## otherwise; higher Agility makes it last longer (wired into nav later).
func use_run_energy(amount: float) -> void:
	run_energy = clampf(run_energy - amount, 0.0, 100.0)
	EventBus.run_energy_changed.emit(run_energy)


func regen_run_energy(delta: float) -> void:
	if run_energy >= 100.0:
		return
	var rate := RUN_REGEN_PER_SEC * (1.0 + float(level("agility")) * 0.01)
	run_energy = clampf(run_energy + rate * delta, 0.0, 100.0)
	EventBus.run_energy_changed.emit(run_energy)


## On death, destroy whatever is in ONE random equipment slot (empty slot = no
## loss). Returns the lost item's display name, or "" if nothing was lost. The
## Protect Item prayer is checked by the caller (spec §12 death handling).
func lose_random_equipped_slot(rng: RandomNumberGenerator = _death_rng) -> String:
	var slot: String = EQUIPMENT_SLOTS[rng.randi() % EQUIPMENT_SLOTS.size()]
	if not equipment.has(slot):
		return ""
	var id: String = str(equipment[slot])
	equipment.erase(slot)
	EventBus.equipment_changed.emit()
	return DataRegistry.item_display_name(id)


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


func admin_reset_skill(skill: String) -> void:
	if not skills.has(skill):
		return
	var base_lvl := 10 if skill == "hitpoints" else 1  # HP starts at 10 like a new save
	skills[skill]["level"] = base_lvl
	skills[skill]["xp"] = float(DataRegistry.xp_for_level(base_lvl))
	if skill == "hitpoints":
		current_hp = max_hp()
		EventBus.hp_changed.emit(current_hp, max_hp())
	EventBus.level_up.emit(skill, base_lvl)


func admin_reset_all_skills() -> void:
	for s: String in SKILLS:
		admin_reset_skill(s)


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
		"combat_style": combat_style,
		"run_energy": run_energy,
		"active_prayers": active_prayers.duplicate(),
		"devotion": devotion,
		"slayer_task": slayer_task.duplicate(),
		"slayer_points": slayer_points,
		# Vector2 has no JSON form; store [x, y], or null until the player has moved.
		"player_pos": ([player_pos.x, player_pos.y] if player_pos.is_finite() else null),
	}


func from_save_dict(d: Dictionary) -> void:
	d = SaveMigration.migrate_game_save(d)
	var loaded: Dictionary = d.get("skills", {})
	for s: String in SKILLS:
		if loaded.has(s):
			# Normalize pre-cap saves: clamp level to the cap and trim overflow XP
			# so a level-1000 save loads as a clean level 99.
			var cap := DataRegistry.max_level
			var lvl := mini(int(loaded[s]["level"]), cap)
			var sx := float(loaded[s]["xp"])
			if lvl >= cap:
				sx = minf(sx, float(DataRegistry.xp_for_level(cap)))
			skills[s] = {"xp": sx, "level": lvl}
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
		else:
			push_warning("Save load: unknown bank item '%s' skipped" % k)
	equipment = {}
	var saved_eq: Dictionary = d.get("equipment", {})
	for k: String in saved_eq:
		var item_id := DataRegistry.resolve_item_id(str(saved_eq[k]))
		if not item_id.is_empty():
			equipment[k] = item_id
		else:
			push_warning("Save load: unknown equipped item '%s' (slot %s) skipped" % [str(saved_eq[k]), k])
	coins = int(d.get("coins", d.get("gold", 0)))
	combat_style = str(d.get("combat_style", "attack"))
	run_energy = clampf(float(d.get("run_energy", 100.0)), 0.0, 100.0)
	var pp: Variant = d.get("player_pos", null)
	player_pos = Vector2(float(pp[0]), float(pp[1])) if (pp is Array and pp.size() == 2) else Vector2.INF
	active_prayers = []
	for pn: Variant in d.get("active_prayers", []):
		if DataRegistry.prayers.has(str(pn)):
			active_prayers.append(str(pn))
	devotion = float(d.get("devotion", -1.0))
	slayer_task = Dictionary(d.get("slayer_task", {})).duplicate()
	slayer_points = int(d.get("slayer_points", 0))
	current_hp = clampi(int(d.get("current_hp", max_hp())), 1, max_hp())
	EventBus.inventory_changed.emit()
	EventBus.bank_changed.emit()
	EventBus.equipment_changed.emit()
	EventBus.coins_changed.emit(coins)
	EventBus.hp_changed.emit(current_hp, max_hp())
