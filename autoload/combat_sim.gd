extends ActivitySim
## Continuous combat simulation, ported from CombatManager + BasicEnemy.
##
## Player attack loop fires every ATTACK_INTERVAL (CombatManager's combat
## coroutine waits 3s between attacks). Enemies attack on their own cooldown
## from the bestiary data. Kills award the data's Combat/HitPoints/Beast
## Mastery XP, roll the parsed drop table, then start the respawn timer
## (10s normal / 60s boss, BasicEnemy.RecalculateStats).

const CombatStyles := preload("res://scripts/combat/combat_styles.gd")
const DropRoller := preload("res://scripts/combat/drop_roller.gd")
const CombatCalc := preload("res://scripts/combat/combat_calc.gd")
const AttackStyles := preload("res://scripts/combat/attack_styles.gd")

const ATTACK_INTERVAL := 3.0  # default; per-weapon speed comes from GameState.attack_interval()
const PLAYER_BASE_CRIT := 0.01
const PLAYER_CRIT_MULTIPLIER := 2.0
const PLAYER_DR_CAP := 80.0  # percent; cap so high-tier gear can't zero damage
const ENEMY_REACT_DELAY := 1.2  # seconds before a mob first retaliates (aggro reaction)

# Hit-chance & damage balance (was scattered as inline literals). OSRS-ish:
const BASE_ACCURACY := 0.3            # accuracy floor at level 1, before gear
const ACCURACY_PER_LEVEL := 0.01      # +1% hit chance per combat level
const ACCURACY_LEVEL_CAP := 1000      # level past which accuracy stops scaling
const DAMAGE_MIN_MULT := 0.6          # a non-crit hit rolls 60%..120% of base damage
const DAMAGE_MAX_MULT := 1.2
const COMBAT_TRIANGLE_BONUS := 1.25   # melee>ranged>magic>melee damage multiplier
const MISS_STREAK_PITY := 3.0         # forced-hit pity after this many consecutive misses

# `active` + register + _process come from ActivitySim.
var enemy: EnemyDef = EnemyDef.new()
var enemy_hp := 0.0
var train_skill := "attack"  # attack | strength | defence | ranged | magic

var player_timer := 0.0
var enemy_timer := 0.0
# Whether the player auto-attacks this fight. Always true when YOU started it (you
# clicked the enemy). When a mob engages YOU (aggro), it's the auto-retaliate setting:
# off = the mob attacks but you stand your ground until you click it back. The enemy
# ALWAYS attacks regardless — auto-retaliate is a player-only toggle.
var player_retaliating := true
# Set by the enemy AI each tick: the mob only lands hits while in attack range. The
# cooldown keeps counting while it chases, so it strikes the moment it's back in range.
var enemy_in_range := true
var respawn_timer := 0.0
var respawning := false
var first_attack_done := false
var miss_streak := 0.0
var kills := 0

var rng := RandomNumberGenerator.new()


func start_combat(enemy_name: String, p_train_skill: String = "attack", player_initiated := true) -> bool:
	var e := DataRegistry.get_enemy(enemy_name)
	if e.is_empty():
		return false
	# Per-enemy Slayer gate (spec §5). Currently OFF for every mob: the gate reads
	# an explicit optional "slayerReq" which no enemy sets yet, so it defaults to 0.
	# Re-enable it on specific enemies later by adding "slayerReq" to enemies.json.
	# (The legacy beastMasteryReq values stay in the data as a reference for that.)
	var slayer_req := int(e.get("slayerReq", 0))
	if slayer_req > GameState.level("slayer"):
		EventBus.combat_log.emit("Slayer level %d required for %s" % [slayer_req, str(e.get("displayName", enemy_name))])
		return false
	stop("switching")
	_stop_others()
	enemy = EnemyDef.from_dict(e)
	train_skill = p_train_skill
	GameState.combat_style = p_train_skill  # remember the style across sessions
	enemy_hp = float(enemy.max_health)
	# Land the opening hit one tick after engaging (like clicking an NPC in OSRS),
	# rather than waiting a full weapon cycle.
	player_timer = maxf(0.0, GameState.attack_interval() - GameState.TICK)
	# The enemy retaliates one short reaction beat after engaging — NOT a full weapon
	# cooldown PLUS the delay. (The old `-ENEMY_REACT_DELAY` start pushed the first
	# swing to cooldown+1.2s ~= 3.6s, so anything that died in a few hits never got to
	# attack back.) Now its first swing lands ~ENEMY_REACT_DELAY after engage, then it
	# attacks every tick-snapped cooldown.
	enemy_timer = GameState.snap_to_tick(float(enemy.cooldown)) - ENEMY_REACT_DELAY
	# You always fight when you start it; if a mob aggro'd you, auto-retaliate decides
	# whether you swing back automatically (the mob attacks either way).
	player_retaliating = player_initiated or GameSettings.auto_retaliate
	enemy_in_range = true   # the AI updates this each tick; assume adjacent at engage
	respawning = false
	first_attack_done = false
	miss_streak = 0.0
	kills = 0
	active = true
	EventBus.activity_started.emit("combat", "Fighting %s (training %s)" % [_enemy_name(), train_skill.capitalize()])
	EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy.max_health))
	return true


func stop(reason: String = "stopped") -> void:
	if not active:
		return
	active = false
	enemy = EnemyDef.new()
	EventBus.activity_stopped.emit(reason)


func advance(delta: float) -> void:
	if not active:
		return
	if respawning:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawning = false
			enemy_hp = float(enemy.max_health)
			first_attack_done = false
			player_timer = 0.0
			enemy_timer = 0.0
			EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy.max_health))
		return
	player_timer += delta
	enemy_timer += delta
	var interval := GameState.attack_interval()
	if player_timer >= interval:
		player_timer -= interval
		# Auto-retaliate off + the mob started it: you hold your ground (don't swing
		# back) until you click it. The enemy still attacks below.
		if player_retaliating:
			_player_attack()
			if not active or respawning:
				return
	var cooldown := GameState.snap_to_tick(float(enemy.cooldown))
	if enemy_timer >= cooldown:
		# The mob only LANDS a hit while it's in attack range. While it's chasing the
		# player back into range (enemy_in_range = false) the cooldown stays full so it
		# strikes the instant it catches up — it doesn't bank up a burst of free hits.
		if enemy_in_range:
			enemy_timer -= cooldown
			_enemy_attack()
			_auto_eat()
		else:
			enemy_timer = cooldown
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
	# The equipped weapon dictates melee/ranged/magic — a bow always shoots, even if
	# the player is set to train a melee stat. Falls back to the training style when
	# unarmed or holding a plain melee weapon.
	var ws := GameState.weapon_combat_style()
	if ws != "melee":
		return ws
	if train_skill in ["attack", "strength", "defence"]:
		return "melee"
	return train_skill  # "ranged" or "magic"


## --- OSRS-inspired player combat rolls (see scripts/combat/combat_calc.gd) ----

func _weapon() -> ItemDef:
	return DataRegistry.item_def(str(GameState.equipment.get("Weapon", "")))


## The attack TYPE this weapon swings with: stab/slash/crush/ranged/magic.
func attack_type() -> String:
	return AttackStyles.attack_type(_weapon())


func _attack_skill() -> String:
	match _style():
		"ranged": return "ranged"
		"magic": return "magic"
		_: return "attack"


## strengthBonuses key for the current style (melee/ranged/magic).
func _strength_key() -> String:
	match _style():
		"ranged": return "ranged"
		"magic": return "magic"
		_: return "melee"


## Effective Attack = floor(level × prayer) + style level bonus + 8.
func player_effective_attack() -> int:
	return CombatCalc.effective_level(GameState.level(_attack_skill()),
		GameState.prayer_accuracy_mult(_style()), 0, AttackStyles.attack_level_bonus(train_skill))


## Effective Strength = floor(level × prayer) + style level bonus + 8.
func player_effective_strength() -> int:
	var skill := "strength" if _strength_key() == "melee" else _strength_key()
	return CombatCalc.effective_level(GameState.level(skill),
		GameState.prayer_damage_mult(_style()), 0, AttackStyles.strength_level_bonus(train_skill))


## Maximum attack roll = effectiveAttack × (relevant attack bonus + 64).
func player_attack_roll() -> int:
	var totals := GameState.calculate_equipment_bonuses()
	return CombatCalc.max_attack_roll(player_effective_attack(), int(totals["attack"][attack_type()]))


## Maximum hit = floor(0.5 + effStr × (strBonus + 64) / 640).
func player_max_hit() -> int:
	var totals := GameState.calculate_equipment_bonuses()
	return CombatCalc.max_hit(player_effective_strength(), int(totals["strength"][_strength_key()]))


## Hit chance vs the CURRENT enemy's defence for this attack type (0..1).
func player_hit_chance() -> float:
	var atype := attack_type()
	var def_roll := CombatCalc.enemy_defence_roll(enemy.defence_level, enemy.defence_bonus(atype))
	return CombatCalc.hit_chance(player_attack_roll(), def_roll)


func player_crit_chance() -> float:
	return clampf(_weapon().weapon_crit_chance() + GameState.equipment_crit_chance(), 0.0, 1.0)


func player_crit_multiplier() -> float:
	return _weapon().weapon_crit_multiplier()


## Dev/debug combat breakdown — every input + output of the calc so a result is
## explainable. Includes vs-enemy rolls + expected DPS when a fight is active.
func combat_breakdown() -> Dictionary:
	var totals := GameState.calculate_equipment_bonuses()
	var atype := attack_type()
	var ticks := _weapon().attack_ticks()
	var mh := player_max_hit()
	var crit_c := player_crit_chance()
	var crit_m := player_crit_multiplier()
	var acm := CombatCalc.average_crit_multiplier(crit_c, crit_m)
	var out := {
		"weapon": _weapon().display_name if not _weapon().is_empty() else "Unarmed",
		"weapon_category": _weapon().weapon_category(),
		"style": AttackStyles.style_name(train_skill), "attack_type": atype,
		"attack_level": GameState.level(_attack_skill()),
		"effective_attack": player_effective_attack(),
		"attack_bonus": int(totals["attack"][atype]),
		"max_attack_roll": player_attack_roll(),
		"strength_level": GameState.level("strength" if _strength_key() == "melee" else _strength_key()),
		"effective_strength": player_effective_strength(),
		"strength_bonus": int(totals["strength"][_strength_key()]),
		"max_hit": mh, "avg_successful_damage": float(mh) / 2.0,
		"attack_ticks": ticks, "attack_interval_s": CombatCalc.ticks_to_seconds(ticks),
		"crit_chance": crit_c, "crit_multiplier": crit_m, "avg_crit_mult": acm,
	}
	if not enemy.is_empty():
		var hc := player_hit_chance()
		out["enemy"] = enemy.display_name
		out["enemy_defence_level"] = enemy.defence_level
		out["enemy_defence_bonus"] = enemy.defence_bonus(atype)
		out["max_defence_roll"] = CombatCalc.enemy_defence_roll(enemy.defence_level, enemy.defence_bonus(atype))
		out["hit_chance"] = hc
		out["expected_dps"] = CombatCalc.expected_dps(hc, mh, ticks, acm)
	return out


## Combat triangle (GetCombatTriangleDamageMultiplier): melee beats Range
## enemies, ranged beats Mage enemies, magic beats Melee enemies — 1.25x.
func triangle_multiplier() -> float:
	var enemy_style: String = str(enemy.style).to_lower()
	var s := _style()
	if (s == "melee" and enemy_style.contains("range")) \
			or (s == "ranged" and enemy_style.contains("mag")) \
			or (s == "magic" and enemy_style.contains("melee")):
		return COMBAT_TRIANGLE_BONUS
	return 1.0


# --------------------------------------------------------------- attacks ----

## Player damage feedback: melee/magic pop the splat immediately; ranged flies an
## arrow to the target first, and the arrow triggers the splat on arrival, so the
## hit lands in sync with the attack tick that fired it.
func _emit_player_splat(amount: int, miss: bool) -> void:
	if _style() == "ranged":
		EventBus.combat_ranged_shot.emit(amount, miss)
	else:
		EventBus.combat_hit_splat.emit(amount, miss, false)


## Stage 1-7: pick attack type, roll accuracy vs the enemy's defence for that type.
func _player_attack() -> void:
	if _style() == "ranged":
		GameState.remove_item("Arrows", 1)  # spend one arrow per shot (no-op if none)
	var acc := player_hit_chance()
	# Miss-streak pity (CombatManager.meleeAccuracyBias): +10% after 3 misses, +20% after 6.
	if miss_streak >= MISS_STREAK_PITY:
		acc += 0.1
	if miss_streak >= 6.0:
		acc += 0.2
	if rng.randf() >= clampf(acc, 0.0, 1.0):
		miss_streak += 1.0
		EventBus.combat_log.emit("You miss.")
		_emit_player_splat(0, true)
		return
	miss_streak = 0.0
	_apply_player_hit()


## Stage 8-16: roll damage 0..maxHit, crit, modifier pipeline, apply + XP.
func _apply_player_hit() -> void:
	var base := CombatCalc.roll_base_damage(player_max_hit(), rng)
	var crit: Array = CombatCalc.roll_crit(player_crit_chance(), player_crit_multiplier(), rng)
	var is_crit: bool = crit[0]
	# Modifier pipeline: base × crit × combat-triangle (player mult) × enemy taken-mult,
	# floor, then subtract enemy flat reduction, clamp [0, global cap]. Enemy resistance
	# is the NEW damageTakenMultiplier (default 1.0) + flatDamageReduction — NOT the legacy
	# sub-1% damageReduction, which would floor every max-hit-1 hit down to zero.
	var dmg := CombatCalc.finalize_damage(base, float(crit[1]), 1.0, triangle_multiplier(),
		enemy.damage_taken_multiplier, enemy.flat_damage_reduction)
	# Per-hit XP: damage past the enemy's remaining HP earns no XP.
	var landed := mini(dmg, int(ceil(enemy_hp)))
	if landed > 0:
		for t: Array in CombatStyles.xp_targets(train_skill):
			GameState.add_xp(str(t[0]), float(landed) * CombatStyles.XP_PER_DAMAGE * float(t[1]))
		GameState.add_xp("hitpoints", float(landed) * CombatStyles.HP_XP_PER_DAMAGE)
	enemy_hp = maxf(enemy_hp - float(dmg), 0.0)
	EventBus.combat_log.emit("You hit %s for %d%s" % [_enemy_name(), dmg, " (CRIT!)" if is_crit else ""])
	_emit_player_splat(dmg, dmg <= 0)
	EventBus.enemy_hp_changed.emit(enemy_hp, float(enemy.max_health))
	if enemy_hp <= 0.0:
		_on_enemy_killed()


func _enemy_attack() -> void:
	if rng.randf() >= float(enemy.accuracy):
		EventBus.combat_log.emit("%s misses you." % _enemy_name())
		EventBus.combat_hit_splat.emit(0, true, true)
		return
	var dmg := float(enemy.damage)
	if rng.randf() < float(enemy.crit_chance):
		dmg *= float(enemy.crit_multiplier)
	# Protect-from-Melee prayer cuts incoming melee damage.
	if str(enemy.style).to_lower().contains("melee"):
		dmg *= GameState.prayer_melee_protect()
	# Defence prayers add to damage reduction (still capped).
	var dr := minf(GameState.equipment_damage_reduction() + GameState.prayer_dr_bonus(), PLAYER_DR_CAP)
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
	GameState.add_xp("slayer", float(enemy.slayer_xp))
	_roll_drops()
	EventBus.enemy_killed.emit(_enemy_name())
	respawning = true
	respawn_timer = 60.0 if enemy.is_boss else 10.0
	EventBus.enemy_respawning.emit(respawn_timer)


func _roll_drops() -> void:
	var loot: Array = DropRoller.roll(enemy.drops, rng)
	loot.append_array(DropRoller.roll_tertiary(enemy.raw, rng))
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
	return enemy.display_name if not enemy.is_empty() else "?"


func save_activity() -> Dictionary:
	return {"kind": "combat", "enemy_id": enemy.id, "train": train_skill} if active else {}


func restore_activity(data: Dictionary) -> void:
	# Do NOT auto-resume a fight on load. Unlike gather/craft (you reload standing at the
	# node), a fight is bound to a live world enemy entity that may not exist at spawn —
	# resuming the data-only fight produces a "ghost" enemy that keeps hitting you with
	# nothing on screen. Combat must be re-engaged by clicking an actual world enemy.
	# (Also clears the stale combat activity baked into older saves.)
	if str(data.get("kind", "")) != "combat":
		return
