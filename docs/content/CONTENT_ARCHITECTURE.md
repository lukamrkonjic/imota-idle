# Imota — Content Architecture (Phase 2)

Target design for the re-originated content database. Pure design — no data/code changed
yet. Builds on `CONTENT_AUDIT.md`. Decisions locked with the owner:
- **Wire all 22 skills** (including new mechanics for the currently dead/inert ones).
- **Aggressive re-originate**: purge orphans + IP-derivative imports, author a tight,
  interconnected ~200-item economy; save-safe via the deprecation/alias layer.
- **Scarcity is spatial + regrow-gated**, not just drop-rate.
- OSRS reference patterns: **held** (path empty); designed from Bloobs scope + general
  scapelike structure. No copied OSRS/Bloobs expression.

Numbers below tagged `balanceStatus: provisional` are starting points to validate against
real kill-times/XP rates in Phase 9, not final.

---

## 1. Design principles (Imota-specific)
1. **One source + one use minimum** per item; key materials get 2–3 relationships.
2. **Cross-skill loops over vertical silos** — gather → refine → produce → (combat secondary) → upgrade.
3. **Scarcity by place & time, not just %**: commons are everywhere and regrow fast; premium
   nodes/bosses are few, in specific biomes/POIs, with long respawns (`skill_sites.json` +
   `pois.json` + depletion timers already support this).
4. **Sidegrades stay relevant**; not every tier is a strict replacement.
5. **Original generics**: keep folkloric creatures/material families (Logs, Bones, ores,
   bronze→iron→steel→mithril→…); give them original descriptions/variants. No proper-named
   imports, no soul/golden systems.
6. **No offline** — balance on active + automation only.

---

## 2. Final skill list & roles (all 22 wired)

| Skill | Type | Role in the economy | New mechanic needed? |
|-------|------|---------------------|----------------------|
| attack/strength/defence | melee combat | accuracy/damage/defence; trained by fighting | no |
| ranged | ranged combat | needs ammo (fletching/crafting) | no |
| magic | magic combat | needs charges/runes-equivalent (crafting/alchemy) | no |
| hitpoints | passive | HP pool; trained by all combat | no |
| **prayer** | combat-support | spend a Prayer resource for timed buffs | **YES — activation system** |
| **slayer** | combat-support | tasks gate premium kills + unlock signature drops | **YES — task system** |
| woodcutting | gathering | logs (fuel, fletching, fires) | no |
| mining | gathering | ores + essence-stone (smithing, magic charges) | no |
| fishing | gathering | raw fish (cooking food) | no |
| foraging | gathering | herbs/plants (alchemy, cooking) | no |
| **hunter** | gathering | trap creatures → hides/feathers/secondary mats | **YES — trap loop** |
| **thieving** | gathering | steal coins/cloth/keys from humanoid sites | **YES — steal action** |
| farming | gathering/prod | grow herbs/logs-saplings/secondary crops (feeds alchemy/cooking) | extend existing FarmingSim |
| cooking | production | raw fish/meat + foraged → food (heals, sustains combat) | no |
| **firemaking** | production/utility | burn logs → embers/ash (alchemy reagent, light-gated nodes) | **YES — burn action + use** |
| smithing | production | ores → bars → metal gear/tools/ammo | no |
| fletching | production | logs → bows/shafts/arrows (ranged ammo) | no |
| crafting | production | hides/cloth/gems → armour/jewellery/magic foci | no |
| alchemy | production | herbs + embers + essences → potions/charges/upgrades | no |
| **agility** | utility | unlock map shortcuts; passive run-energy/efficiency | **YES — shortcut/efficiency** |

> New-mechanic skills are **provisional design** here; each is its own implementation pass
> with code (sims/controllers), not just data. Sequenced after the data foundation so the
> economy can exist first and the mechanics plug into it.

---

## 3. Skill interaction matrix (target loops)

Canonical loops (each arrow = a real item dependency to author):

```
woodcutting → logs ──┬→ firemaking → embers/ash → alchemy (reagent)
                     ├→ fletching → bows + shafts ─→ ranged
                     └→ farming (saplings)            ↑
mining → ore → smithing → bars → melee gear, tools, arrowheads ┘
mining → essence-stone → alchemy/crafting → magic charges → magic
foraging → herbs ─┐
farming  → herbs ─┴→ alchemy → potions (combat sustain) + gear upgrades
fishing → raw fish ┐
hunter  → meat/hide ┴→ cooking → food → all combat
hunter  → hides/feathers → crafting (armour) + fletching (flights)
combat  → bones → prayer (resource/altar) ; → hides/scales/cores → crafting/smithing/alchemy upgrades
thieving → coins/cloth/keys → crafting (cloth gear) + access (keys → POIs/bosses)
slayer task → permission + signature drops → upgrade components
agility → shortcuts → faster gathering/boss access (efficiency, not power)
boss → rare core ─→ smithing frame + alchemy infusion + rare wood handle = niche BiS
```

**Connection health target:** every skill both *consumes* and *feeds* at least one other
skill. The Phase 3/9 validator computes per-skill in/out connection counts and warns on any
skill with <2 economy links (today: firemaking/thieving/hunter/agility = 0).

---

## 4. Level-band model
11 bands (audit confirmed content should *not* all sit at 99). Each gathering/production
skill gets ≥1 unlock per band it participates in, **plus** a 90+ aspirational goal that is an
efficiency/rare-node/masterwork goal rather than "yet another tier".

`1-9 intro · 10-19 specialize · 20-29 first upgrades · 30-39 early established · 40-49 mid
transition · 50-59 specialization · 60-69 advanced · 70-79 late foundations · 80-89 elite ·
90-94 mastery · 95-99 aspirational`. Add a `levelBand` field to content for validation.

---

## 5. Material-tier model (metal example; mirror for wood/leather/cloth/gem)
~8 tiers across 1–99, NOT one every 10 levels (avoids bloat); some bands add efficiency/recipes
instead of a new metal.

| Tier | ~Level | Metal family (original generics) | Notes |
|------|-------:|----------------------------------|-------|
| 1 | 1 | Copper/Tin → Bronze | starter |
| 2 | 10 | Iron | + needs firemaking-charcoal to smelt (cross-skill) |
| 3 | 20 | Steel | |
| 4 | 30 | a dark-iron tier | sidegrade: heavier/slower |
| 5 | 45 | Mithril-equivalent (rename to original) | |
| 6 | 60 | a silvered/alloy tier | needs an alchemy flux |
| 7 | 75 | a volcanic/ashen alloy | needs boss-dropped core to *finish* top pieces |
| 8 | 90 | masterwork | recipe + rare wood/gem + infusion; chase |

Each tier: gathering source, refine step, ≥2 recipes, a combat-drop tie-in (e.g. a creature
that "wears" or hoards it), and a reason low tiers persist (used as a sub-component later —
e.g. bronze nails/rivets in a high-tier recipe).

---

## 6. Equipment progression model
Confirmed styles from code: **melee, ranged, magic** (no summoning/pets in code — not designed
around). Slots from `_EQUIP_LAYOUT`: Helm, Cape, Amulet, Ammunition, Weapon, Body, Shield,
Gloves, Boots, Ring + tool slots (Axe, Pickaxe, Rod, Lens).

- Each style: a clean tier ladder (≈8 weapon tiers) **interleaved with sidegrades**: accuracy
  vs damage weapons, fast/weak vs slow/strong, a crit-focused niche, an enemy-type specialist
  (e.g. anti-undead), and 1–2 boss-finished BiS-with-a-niche per late band.
- Armour: a defensive ladder + a few set bonuses (2/4-piece) authored as `tags`+a bonus rule.
- **Target: ~120–150 equipment pieces** total across styles/slots (down from 390), each with a
  reason to exist. Validator flags strictly-dominated pieces unless tagged intentional sidegrade.

---

## 7. Monster & boss progression
- **~90–110 normal monsters** across bands (down from 85 normal today, re-originated), each with
  a defined role (food/material/secondary/skill-trainer/specialist) and a **thematic** drop table
  — no uniform template. Drop tables: guaranteed remains + 1–2 commons + 1 uncommon cross-skill
  mat + a signature ingredient + optional low-rate gear/recipe + optional very-rare chase.
- **~16–20 bosses** (down from 35), each with: entry gate (level/slayer/key/POI), a mechanical
  trait (enrage, summon, phases, drain), a farming reason, and ≥1 **economy-linked** exclusive
  (a core/component finished by non-combat skills — not a complete BiS).
- **Spatial scarcity:** premium creatures live in specific biomes/POIs; bosses gated by access
  (key/agility shortcut/slayer) + respawn cooldown, so they can't be trivially chain-farmed.

---

## 8. Prayer model (NEW activation system — provisional)
Prayer is currently display-only. Design:
- **Resource:** "Devotion" points, restored by burying bones (already a button) and at shrines;
  drained per second while a prayer is active.
- **Activation:** toggle prayers (mutually-exclusive within a group; a few stackable utilities),
  wired through `GameState.active_prayers` (the field exists, unused) → read by `combat_sim`.
- **~18–24 prayers** across tiers: early utility (drain reduction, bury yield), defensive
  (damage reduction per style), offensive (accuracy/damage per style — balanced across melee/
  ranged/magic), resource (gather-yield, food-save), midgame specialization, 2–3 aspirational
  90+ prayers unlocked by boss tomes/skill milestones. Original names/effects/levels only.

## 9. Slayer model (NEW task system — provisional)
- A task-giver grants a target creature + count; completing tasks awards slayer XP + unlocks
  permission to harm certain "slayer-only" premium creatures and their signature drops.
- Slayer level gates premium targets (the `slayerReq`/`beastMasteryReq` fields already exist).
- Keeps premium drops behind *effort* (tasks) not just luck.

## 10. New gather/utility loops (provisional, code passes)
- **Hunter:** place/check traps at hunter sites → hides, feathers, meat, rare pelts.
- **Thieving:** steal from humanoid POIs → coins, cloth, keys (key → gated POIs/bosses), with a
  failure/stun chance.
- **Firemaking:** burn logs → embers/ash (alchemy reagent) + light braziers that unlock
  dark/cave nodes for a duration.
- **Agility:** shortcuts on the map (cross gaps) + passive run-energy/gather-tick efficiency.
- **Farming:** extend existing FarmingSim to herbs, saplings, and a secondary cooking crop.

---

## 11. Rarity model
| Rarity | Intent | Indicative chance (provisional) | Use for |
|--------|--------|--------------------------------:|---------|
| common | every short session | 1 in 1–8 | base mats |
| uncommon | a moderate session | 1 in 10–40 | cross-skill mats |
| rare | a noticeable goal | 1 in 80–250 | recipes, components |
| very rare | long-term chase | 1 in 400–1500 | sidegrades, prestige |
| exceptional | major prestige | 1 in 2000–6000 | optional BiS, collectibles |
| boss-exclusive | per-boss | varies + bad-luck protection | boss cores |

Rules: **mandatory progression never gated behind very-rare+ luck** (use slayer tasks, fragments,
or token/pity for those). Add `rarity` field; mandatory items tagged so the validator errors if
a required item sits behind extreme rarity. Boss cores use **fragments or a pity counter**.

## 12. Drop-table & recipe rules
- Drops reference **stable item ids** (migrate from display-name refs); reverse indexes
  (`item.dropSources`, `item.usedInRecipes`, `item.skillSources`) are **generated**, not stored.
- No two normal monsters share an identical drop set. Every drop has a thematic justification.
- Every recipe: valid inputs (all exist), an output with a use, monotonic-ish level/value vs
  inputs; validator flags circular/impossible recipes.

## 13. Naming guide (from current tone: cozy-but-earthy, light fantasy, OSRS-ish clarity)
- **Generics stay plain**: "Boar Hide", "Oak Logs", "Iron Bar" — not "Vharakian War-Pelt".
- Descriptive variants for tiers ("Ashen …", "Riverbed …"), a *limited* set of memorable proper
  names for **bosses only** (original, not "X the Y-born" Bloobs cadence), thematic material
  families. snake_case ids (`boar_hide`, `ashen_alloy_bar`, `prayer_steadfast_ward`,
  `boss_mire_sovereign`). Names original; no encoding balance in display text.

## 14. Target counts (provisional; quality over quota)
| Type | Target | (today) |
|------|-------:|--------:|
| Items+materials (active) | ~180–240 | 1803 |
| Equipment pieces | ~120–150 | 390 |
| Consumables/utility | ~50–70 | — |
| Normal monsters | ~90–110 | 85 |
| Elites/minibosses | ~12–18 | — |
| Bosses | ~16–20 | 35 |
| Prayers | ~18–24 | 0 active |
| Recipes | ~200–280 | 775 |
| Gather actions | ~120–160 | 167 |

## 15. Expansion strategy
- Content is data (`data/*.json`) + generated indexes → new regions/tiers/bosses are additive
  files, no restructuring.
- Reserve id-space per family; new tiers slot above without renaming.
- Deprecation/alias layer (`content_aliases.json`/`rename_map.json`) keeps saves valid forever.
- Each future "region pack" = a biome + node set + monster set + 1–2 bosses + a material family
  + recipes, dropped in and validated by `validate:content`.

---

## Open items / assumptions to confirm
- New mechanics (prayer activation, slayer tasks, hunter/thieving/firemaking/agility) are
  **code**, not just data — biggest risk/effort; sequenced as their own passes after the data
  foundation. Flag if you'd rather stage some to a later milestone despite "wire all 22".
- OSRS reference cross-check pending the corrected path.
- All `provisional` numbers validated in Phase 9 against measured kill-time/XP rates.
