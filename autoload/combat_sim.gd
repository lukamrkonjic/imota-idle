extends Node
## Continuous combat simulation, ported from CombatManager + BasicEnemy.
##
## Player attack loop fires every ATTACK_INTERVAL (CombatManager's combat
## coroutine waits 3s between attacks). Enemies attack on their own cooldown
## from the bestiary data. Kills award the data's Combat/HitPoints/Beast
## Mastery XP, roll the parsed drop table, then start the respawn timer
## (10s normal / 60s boss, BasicEnemy.RecalculateStats).

const CombatStyles := preload("res://scripts/combat/combat_styles.gd")
const DropRoller := preload("res://scripts/combat/drop_roller.gd")

const ATTACK_INTERVAL := 3.0  # default; per-weapon speed comes from GameState.attack_interval()
const PLAYER_BASE_CRIT := 0.01
const PLAYER_CRIT_MULTIPLIER := 2.0
const PLAYER_DR_CAP := 80.0  # percent; cap so high-tier gear can't zero damage

var active := false
var enemy: Dictionary = {}
var enemy_hp := 0.0
var train_skill := "attack"  # attack | strength | defence | ranged | magic

var player_timer := 0.0
var enemy_timer := 0.0
var respawn_timer := 0.0
var respawning := false
var first_attack_done := false
var miss_streak := 0.0
var kills := 0

var rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if active:
		advance(delta)


func start_combat(enemy_name: String, p_train_skill: String = "attack") -> bool:
	var e := DataRegistry.get_enemy(enemy_name)
	if e.is_empty():
		return false
	# Per-enemy Slayer gate (spec §5). Currently OFF for every mob: the gate reads
	# an explicit optional "slayerReq" which no enemy sets yet, so it defaults to 0.
	# Re-enable it on specific enemies later by adding "slayerReq" to enemies.json.
	# (The legacy beastMasteryReq values stay in the data as a reference for that.)
	var slayer_req := int(e.get("slayerReq", 0))
	if slayer_req > GameState.level("slayer"):
		EventBus.combat_log.emit("Slayer level %d required for %s" % [slayer_req, enemy_name])
		return false
	stop("switching")
	TickSim.stop("switching")
	RecipeSim.stop("switching")
	enemy = e
	train_skill = p_train_skill
	GameState.combat_style = p_train_skill  # remember the style across sessions
	enemy_hp = float(e["maxHealth"])
	# Land the opening hit one tick after engaging (like clicking an NPC in OSRS),
	# rather than waiting a full weapon cycle.
	player_timer = maxf(0.0, GameState.attack_interval() - GameState.TICK)
	enemy_timer = 0.0
	respawning = false
	first_attack_done = false
	miss_streak = 0.0
	kills = 0
	active = true
	EventBus.activity_started.emit("combat", "Fighting %s (training %s)" % [enemy_name, train_skill.capitalize()])
	EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy["maxHealth"]))
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	enemy = {}
	EventBus.activity_stopped.emit(reason)


func advance(delta: float) -> void:
	if not active:
		return
	if respawning:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawning = false
			enemy_hp = float(enemy["maxHealth"])
			first_attack_done = false
			player_timer = 0.0
			enemy_timer = 0.0
			EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy["maxHealth"]))
		return
	player_timer += delta
	enemy_timer += delta
	var interval := GameState.attack_interval()
	if player_timer >= interval:
		player_timer -= interval
		_player_attack()
		if not active or respawning:
			return
	var cooldown := GameState.snap_to_tick(float(enemy["cooldown"]))
	if enemy_timer >= cooldown:
		enemy_timer -= cooldown
		_enemy_attack()
		_auto_eat()
	# No action-progress bar in combat — the head bar is for skilling only.


## Idle survival: after taking a hit, eat the best food if HP fell to/below the
## configured threshold (spec §12). Keeps idle combat alive instead of dying.
func _auto_eat() -> void:
	if not active or not GameSettings.auto_eat_enabled:
		return
	if GameState.auto_eat(GameSettings.auto_eat_threshold):
		EventBus.combat_log.emit("You eat to %d HP." % GameState.current_hp)


# ---------------------------------------------------------- player stats ----

func _style() -> String:
	if train_skill in ["attack", "strength", "defence"]:
		return "melee"
	return train_skill  # "ranged" or "magic"


## AttackSkill: accuracy = 0.3 + 0.01 * level (cap 1000) + equipment accuracy.
func player_accuracy() -> float:
	match _style():
		"ranged":
			return 0.3 + 0.01 * mini(GameState.level("ranged"), 1000) + GameState.equipment_range_accuracy()
		"magic":
			return 0.3 + 0.01 * mini(GameState.level("magic"), 1000) + GameState.equipment_magic_accuracy()
		_:
			return 0.3 + 0.01 * mini(GameState.level("attack"), 1000) + GameState.equipment_accuracy()


## StrengthSkill: damage = 1 + 1 * level + equipment damage (per style).
func player_damage() -> float:
	match _style():
		"ranged":
			return 1.0 + float(GameState.level("ranged")) + GameState.equipment_range_damage()
		"magic":
			return 1.0 + float(GameState.level("magic")) + GameState.equipment_magic_damage()
		_:
			return 1.0 + float(GameState.level("strength")) + GameState.equipment_damage()


## Combat triangle (GetCombatTriangleDamageMultiplier): melee beats Range
## enemies, ranged beats Mage enemies, magic beats Melee enemies — 1.25x.
func triangle_multiplier() -> float:
	var enemy_style: String = str(enemy["style"]).to_lower()
	var s := _style()
	if (s == "melee" and enemy_style.contains("range")) \
			or (s == "ranged" and enemy_style.contains("mag")) \
			or (s == "magic" and enemy_style.contains("melee")):
		return 1.25
	return 1.0


## Accuracy overflow past 100% becomes a double-hit chance, capped at 25%
## (CombatManager: clamp01((accuracy-1) * 0.125), max 0.25).
func double_hit_chance() -> float:
	return minf(clampf((player_accuracy() - 1.0) * 0.125, 0.0, 1.0), 0.25)


func crit_chance() -> float:
	return clampf(PLAYER_BASE_CRIT + GameState.equipment_crit_chance(), 0.0, 1.0)


# --------------------------------------------------------------- attacks ----

func _player_attack() -> void:
	var acc := player_accuracy()
	# Miss-streak pity (CombatManager.meleeAccuracyBias): +10% after 3 misses,
	# +20% after 6.
	if miss_streak >= 3.0:
		acc += 0.1
	if miss_streak >= 6.0:
		acc += 0.2
	var hit := rng.randf() < acc
	if hit:
		miss_streak = 0.0
	else:
		miss_streak += 1.0
		EventBus.combat_log.emit("You miss.")
		EventBus.combat_hit_splat.emit(0, true, false)
		return
	_apply_player_hit()
	if active and not respawning and rng.randf() < double_hit_chance():
		EventBus.combat_log.emit("Double hit!")
		_apply_player_hit()


func _apply_player_hit() -> void:
	var dmg: float
	var is_crit := false
	if not first_attack_done:
		# Quirk ported from CombatManager.HandleAttack: the opening hit of a
		# fight always deals 1.
		dmg = 1.0
		first_attack_done = true
	else:
		var base := player_damage()
		is_crit = rng.randf() < crit_chance()
		if is_crit:
			dmg = base * PLAYER_CRIT_MULTIPLIER
		else:
			dmg = rng.randf_range(base * 0.6, base * 1.2)
	dmg *= triangle_multiplier()
	# Enemy damage reduction is a flat percent from the bestiary.
	dmg *= 1.0 - float(enemy["damageReduction"]) / 100.0
	dmg = maxf(roundf(dmg * 10.0) / 10.0, 0.0)
	# Per-hit XP (OSRS-style, spec §5/§12): the trained combat skill scales with
	# damage dealt, plus a Hitpoints share. Replaces the old lump-sum on-kill XP.
	var landed := minf(dmg, enemy_hp)  # damage past the enemy's remaining HP earns no XP
	if landed > 0.0:
		for t: Array in CombatStyles.xp_targets(train_skill):
			GameState.add_xp(str(t[0]), landed * CombatStyles.XP_PER_DAMAGE * float(t[1]))
		GameState.add_xp("hitpoints", landed * CombatStyles.HP_XP_PER_DAMAGE)
	enemy_hp = maxf(enemy_hp - dmg, 0.0)
	EventBus.combat_log.emit("You hit %s for %.1f%s" % [_enemy_name(), dmg, " (CRIT!)" if is_crit else ""])
	EventBus.combat_hit_splat.emit(int(roundf(dmg)), dmg <= 0.0, false)
	EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy["maxHealth"]))
	if enemy_hp <= 0.0:
		_on_enemy_killed()


func _enemy_attack() -> void:
	if rng.randf() >= float(enemy["accuracy"]):
		EventBus.combat_log.emit("%s misses you." % _enemy_name())
		EventBus.combat_hit_splat.emit(0, true, true)
		return
	var dmg := float(enemy["damage"])
	if rng.randf() < float(enemy["critChance"]):
		dmg *= float(enemy["critMultiplier"])
	var dr := minf(GameState.equipment_damage_reduction(), PLAYER_DR_CAP)
	dmg *= 1.0 - dr / 100.0
	var final := maxi(int(ceil(dmg)), 0)
	GameState.set_hp(GameState.current_hp - final)
	EventBus.combat_hit_splat.emit(final, final <= 0, true)
	EventBus.combat_log.emit("%s hits you for %d" % [_enemy_name(), final])
	if GameState.current_hp <= 0:
		_on_player_died()


func _on_enemy_killed() -> void:
	kills += 1
	EventBus.combat_log.emit("%s defeated!" % _enemy_name())
	# Combat + Hitpoints XP are now awarded per hit (see _apply_player_hit).
	# Slayer XP is still a per-kill reward (OSRS-style).
	GameState.add_xp("slayer", float(enemy["beastMasteryXp"]))
	_roll_drops()
	EventBus.enemy_killed.emit(_enemy_name())
	respawning = true
	respawn_timer = 60.0 if enemy["isBoss"] else 10.0
	EventBus.enemy_respawning.emit(respawn_timer)


func _roll_drops() -> void:
	var loot: Array = DropRoller.roll(enemy["drops"], rng)
	loot.append_array(DropRoller.roll_tertiary(enemy, rng))
	for d: Dictionary in loot:
		var qty := int(d["qty"])
		if GameState.add_item(d["item"], qty) > 0:
			EventBus.loot_gained.emit(d["item"], qty)
		else:
			EventBus.combat_log.emit("Inventory full — %s lost!" % DataRegistry.item_display_name(d["item"]))


## Death (spec §12, decided): respawn full HP; destroy ONE random equipped slot
## (empty slot = no loss; Protect Item prayer negates). Loose inventory is safe.
func _on_player_died() -> void:
	var killer := _enemy_name()
	EventBus.combat_log.emit("You were defeated by %s!" % killer)
	stop("player_died")
	GameState.set_hp(GameState.max_hp())
	if GameState.is_prayer_active("Protect Item"):
		EventBus.combat_log.emit("Protect Item saved your gear.")
	else:
		var lost := GameState.lose_random_equipped_slot(rng)
		if not lost.is_empty():
			EventBus.combat_log.emit("[death] You lost your %s!" % lost)
	EventBus.player_died.emit(killer)


## Display name for the current enemy (Bloobs-renamed); never the raw legacy name.
func _enemy_name() -> String:
	return str(enemy.get("displayName", enemy.get("name", "?")))
