# Data gaps — Imota vs. the Bloobs export

Facts that could not be recovered from `bloobs-export` or the decompiled C#
(scene-embedded Unity data), and what Imota does instead.

| Gap | What's missing | What Imota does |
|-----|----------------|-----------------|
| Gather node XP | `Trees.xpOnChop` / fishing & mining equivalents are per-scene-instance values; only the code default (`25`) survives decompilation. | `xp = round(25 + (level-1) * 1.5)` per award, calibrated to the code default at level 1. See `tools/import_bloobs_data.gd::gather_xp_for_level`. |
| ~~Gathering tools~~ | *Resolved:* tools are **smithing/crafting recipe outputs** (Bronze→Sunwrought axes/pickaxes/rods/lenses with real `progress` 25→140), not separate store assets. | Real items used everywhere; `tools.json` is just the shop's stock list filtered from them. |
| Node health ranges | `Trees.minHealth/maxHealth` are scene values. | Irrelevant in the menu UI (node switching is instant); the milestone rule (1 resource per 100 damage) is ported exactly. |
| Magic spells | `SpellData` assets are scene-embedded (`spells.json` is empty). | Magic combat uses equipment `magicDamage`/`magicAccuracy` + level, per the mechanics.json note. Spell instances can be added to `data/` later. |
| Player base crit | `CombatManager.criticalHitChance` initial value is serialized in-scene. | `0.01` base + item `critalChance`, matching enemy base crit. |
| Base inventory size | `InventorySystem.baseInventorySize` is serialized in-scene. | 24 slots. |
| Respawn for non-boss | Code shows the boss branch (60s) explicitly; the 10s base is the field default. | 10s normal / 60s boss. |
| Player HP regen | Out-of-combat regen rate is scene data. | 1 HP / 3s out of combat. |
| Enemy attack ranges/movement | World-positioning logic (move-to-enemy, ranged distance). | Not applicable until Phase 5 (isometric world). |
| Thieving/Tracking/Farming timers | Per-target timers are scene data. | Phase 4: derived from level entries in `text-parsed.json`, calibrated like gather XP. |

Mechanics that **are** faithful ports (sources in code comments):

- XP table (`xp-tables.json`, exact), level-up loop.
- Enemy stats: every bestiary entry verified against `HP = level*4` etc. at validate time.
- Chop/mine/fish action speed: `clamp(1.495 - 0.005*(level-1), min 1.0)`.
- Gather milestone: tool `progress` damage per action, award per 100 damage.
- Player accuracy `0.3 + 0.01*level + equipment`, miss-streak pity (+0.1 @3, +0.2 @6).
- Damage roll `rand(0.6x..1.2x)`, crit `2.0x`, first-hit-deals-1 quirk.
- Combat triangle 1.25x; accuracy overflow → double-hit chance (cap 25%).
- Player attack interval 3s; enemy cooldown/accuracy/crit from bestiary data.
- Recipes: inputs/outputs/XP/timers/level reqs from `recipes-full.json` (exact).
- Equipment slot inference: name-substring rules ported verbatim.
