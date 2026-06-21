# Combat system (OSRS-inspired)

Character levels, equipment bonuses, weapon speed and enemy defences all matter.
Accuracy and maximum damage are computed **separately**; weak weapons stay weak
because of a **low strength bonus**, never a hard per-weapon damage cap.

## Where things live

| Concern | File |
|---|---|
| Formula constants (tune here) | `scripts/combat/combat_constants.gd` |
| Pure formulas (effective levels, rolls, max hit, hit chance, DPS) | `scripts/combat/combat_calc.gd` |
| Attack styles (level bonuses + attack type) | `scripts/combat/attack_styles.gd` |
| Per-hit XP split | `scripts/combat/combat_styles.gd` |
| Weapon combat stats (+ legacy derivation) | `scripts/content/item_def.gd` |
| Enemy defence stats (+ legacy derivation) | `scripts/content/enemy_def.gd` |
| Equipment-bonus aggregation (one place) | `GameState.calculate_equipment_bonuses()` |
| Attack resolution + dev breakdown | `autoload/combat_sim.gd` |
| Unit tests | `tools/validate.gd` → `phase_combat_formulas()` |

## The math

```
effectiveAttack   = floor(attackLevel × prayer) + styleAttackBonus + 8
maxAttackRoll     = effectiveAttack × (relevantAttackBonus + 64)        # relevant = stab/slash/crush/ranged/magic
enemyDefenceRoll  = (defenceLevel + 9) × (relevantDefenceBonus + 64)
hitChance         = attackRoll>defRoll ? 1-(defRoll+2)/(2(attackRoll+1)) : attackRoll/(2(defRoll+1))   # clamp [0,1]

effectiveStrength = floor(strengthLevel × prayer) + styleStrengthBonus + 8
maxHit            = floor(0.5 + effectiveStrength × (strengthBonus + 64) / 640)
baseDamage        = randomInt(0, maxHit)        # a landed hit may still roll 0
```

Damage modifier pipeline (one documented order, matches the worked example):
`base × crit × special × playerMult × enemyTakenMult` → **floor** → **− enemy flat reduction** → clamp `[0, 9999]`.

Attack type is the weapon's **best** melee type (dagger→stab, scimitar→slash, mace→crush)
or ranged/magic; compared against the enemy's defence bonus **of that type**, so enemies
have weaknesses and switching weapons matters. Crits multiply the *rolled* damage
(default 5% @ 1.5×, caps 50% / 3×), not the max hit.

## Tuning constants (`combat_constants.gd`)

| Constant | Effect |
|---|---|
| `EFFECTIVE_PLAYER_LEVEL_BASE` (8) | baseline effective level — how much low-level play already works |
| `EFFECTIVE_NPC_DEFENCE_BASE` (9) | baseline NPC defence |
| `EQUIPMENT_ROLL_BASE` (64) | baseline gear scaling; raising it flattens gear-tier gaps |
| `MAX_HIT_DIVISOR` (640) | overall damage scale; **raise to lower all damage** |
| `MAX_HIT_ROUNDING_OFFSET` (0.5) | where integer max-hit breakpoints fall |
| `TICK_DURATION_MS` (600) | 0.6s/tick |
| `GLOBAL_DAMAGE_CAP` (9999) | anti-bug ceiling only |
| `DEFAULT_CRIT_CHANCE/MULT`, `MAX_CRIT_*` | crit defaults + ordinary caps |

Balance a weapon by its **expected DPS** (`CombatCalc.expected_dps`), not its max hit:
`hitChance × maxHit/2 × avgCritMult / attackIntervalSeconds`.

## Authoring weapons

Add the rich fields to a `data/items.json` weapon to override the derived values.
If absent, stats are **derived from `tier` + category** so all existing items work.

```jsonc
// dagger — fast, stab-accurate, low strength, higher crit
{ "weaponCategory": "dagger", "attackSpeed": 4,
  "attackBonuses": { "stab": 4, "slash": 2, "crush": -4, "ranged": 0, "magic": 1 },
  "strengthBonuses": { "melee": 3, "ranged": 0, "magic": 0 },
  "critChance": 0.10, "critMultiplier": 1.5 }
// scimitar — fast slash DPS
{ "weaponCategory": "scimitar", "attackSpeed": 4,
  "attackBonuses": { "stab": 3, "slash": 7, "crush": -2 }, "strengthBonuses": { "melee": 6 } }
// longsword — slower, balanced stab/slash
{ "weaponCategory": "sword", "attackSpeed": 5,
  "attackBonuses": { "stab": 6, "slash": 7, "crush": -2 }, "strengthBonuses": { "melee": 7 } }
// mace — crush, anti-armour, strong crit
{ "weaponCategory": "mace", "attackSpeed": 5,
  "attackBonuses": { "stab": -2, "slash": -1, "crush": 8 }, "strengthBonuses": { "melee": 6 },
  "critChance": 0.04, "critMultiplier": 2.0 }
// battleaxe — slow, high strength, big spikes
{ "weaponCategory": "battleaxe", "attackSpeed": 6,
  "attackBonuses": { "stab": -4, "slash": 8, "crush": 6 }, "strengthBonuses": { "melee": 10 },
  "critChance": 0.04, "critMultiplier": 1.75 }
```

Material tiers raise the bonuses on a deliberately accelerating curve (don't blind-multiply):
e.g. dagger stab/str — bronze 4/3, iron 5/4, steel 7/6, mithril 10/8, adamant 14/12, rune 20/18.

## Authoring enemies

```jsonc
// plate-armoured: strong vs slash/stab, WEAK vs crush + magic
{ "defenceLevel": 60,
  "defenceBonuses": { "stab": 80, "slash": 100, "crush": 20, "ranged": 90, "magic": -10 },
  "flatDamageReduction": 0, "damageTakenMultiplier": 1.0 }
```

Absent fields derive from `level` (uniform defence, no weakness), so all 120 legacy
enemies keep working.

## Dev breakdown

`CombatSim.combat_breakdown()` returns every input/output (effective levels, rolls,
hit chance, max hit, attack interval, crit, hit chance vs the current enemy, expected
DPS) so any result is explainable.
