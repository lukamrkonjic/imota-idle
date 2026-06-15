# Imota — Phases 5–11 Plan (modular, slice-first)

> Companion to `docs/IMOTA_BUILD_PLAN.md` (the phase backlog) and
> `docs/IMOTA_REDESIGN_SPEC.md` (the design detail). Phases 0–4 are done. This
> document plans 5–11 for an **early-production** codebase: build **whole thin
> slices**, keep every system **modular and swappable**, and assume the **map and
> every system will still change**.

## Guiding principles

1. **Slices over perfection.** Each phase ships a playable end-to-end slice; depth
   is added by later iteration, never up front. "Done" = the slice runs and is
   tested, not "the system is final."
2. **Modular subsystems, thin interfaces.** Every system is its own module
   (autoload or `RefCounted`) that: reads truth from `GameState`/`DataRegistry`,
   emits via `EventBus`, persists via `SaveMigration`, and is **headless-testable
   in isolation**. A module can be rewritten without touching its callers.
3. **Data-driven & map-agnostic.** Numbers, tables, zones, quests, drops live in
   `data/*.json`. World features key off **zone/content tags**, never hard-coded
   coordinates, so the unfinished map can be re-laid out freely.
4. **Save-safety is still non-negotiable.** Every new persisted field = schema bump
   + migration + a `validate.tscn` check. Stable ids only.
5. **One sim layer, dumb UI.** New logic lives in autoload modules; UI listens.

## Scaffolding to add first (small, unblocks everything)

These three are the load-bearing modules the phases plug into — build them thin,
then let each phase extend them:

- **`ActivityManager`** (new autoload) — owns the single active intent
  (gather / combat / craft / prayer) and the surfaced **stop-reasons**. Wraps the
  existing `TickSim`/`CombatSim`/`RecipeSim` behind one `start/stop/switch` API.
  Farming runs as a *separate* background sim (it's the one always-on system).
  *(spec §21 — the backbone.)*
- **`DropRoller`** (`RefCounted`) — the single place that rolls a drop table with
  tiers (always / common / rare + shared rare-drop table) and independent
  **tertiary rolls** (pets, clues). Combat uses it now; gathering/clues reuse it.
- **`Modifiers`** (`RefCounted` buff stack) — one generic timed-stat-buff system.
  Rested XP, combat potions, prayers, and diary perks are all just *sources* that
  push buffs into it. Build once, reuse five times.

---

## Phase 5 — Combat depth  *(slice: "a fight that feels OSRS")*

Per spec §5, §12. Make the existing fight loop deep without new screens.

- **Modules:** `CombatStyles` (style → which skill gets the per-hit XP, table-
  driven); per-hit XP in `CombatSim` (replaces on-kill XP; combat-skill ∝ damage +
  HP share); weapon **`attackSpeed`** (data field, ticks, default fallback);
  **Prayer-in-combat** hooks (drain points, protection/offensive, Protect Item);
  **death handler** (respawn full HP, destroy one *random equipped slot*, empty =
  safe, Protect Item negates); **`CombatLevel`** derived stat; `DropRoller` tiers.
- **Data:** item `attackSpeed`; `data/rare_drop_table.json`; styles as data/const.
- **Save:** selected combat style; (death loss is immediate, no new field).
- **Gate:** XP-routing per style, death-slot RNG, drop-tier rolls, combat-level
  formula.

## Phase 6 — New & changed skill loops  *(slice: "every skill runs itself")*

Per spec §16. Each loop is a thin module on `ActivityManager`/`RecipeSim`.

- **Modules:** `Prayer` (bury-bones activity → XP, unlocks prayers from §5);
  `Alchemy` (potion recipes via `RecipeSim`; **High Alchemy** item→coins sink);
  **`FarmingSim`** (NEW autoload — plots, **background growth on the global tick**
  while any other activity runs, auto-harvest; respects no-offline); `Hunter`
  (intent-gated trap/track loop reusing the gather auto-nav); `Agility`
  (auto-course + a passive **run-energy** meta-stat that speeds auto-navigation).
- **Data:** bones→Prayer XP, potion recipes (already re-homed to Alchemy), seeds /
  crops / growth ticks, hunter creatures, agility courses.
- **Save:** farming plots (seed + plant-tick + plot count), run energy, prayer
  points; schema bump.
- **Gate:** per-skill loop tests; **farming background-growth** test (grows while a
  different activity runs; no growth while the game is closed).

## Phase 7 — Economy, items, equipment  *(slice: "gear up and spend")*

Per spec §18, §19.

- **Modules:** `Shop` (NPC stock from data + sell-back); High-Alch sink (shared
  with Alchemy); **`LoadoutPresets`** (named equip sets, quick-swap when intent
  changes — high value for a bot-style game); `BankUpgrades` (tabs / search /
  deposit-all / total value); item quality tiers (display + loot juice).
- **Data:** `data/shops.json` (stock per area), quality tiers on items.
- **Save:** loadout presets, bank tabs; schema bump.
- **Gate:** economy / loadout / bank tests.

## Phase 8 — World, areas & travel  *(slice: "a world you can traverse")* — **map-tolerant**

Per spec §17, §5. **Everything keys off zone/content tags in data, not
coordinates**, so the unfinished map can be re-laid out without breaking gating.

- **Modules:** `ZoneRegistry` (data-tagged regions + unlock gates by quest / skill
  / combat level); `SpawnZones` (every node & monster type → fixed zones, with the
  "nearest of type" lookup the auto-idle needs — partly in `WorldGen` already);
  `FastTravel` (teleports between unlocked hubs); `MapState` (discovered /
  undiscovered).
- **Save:** unlocked areas / teleports, discovered map; schema bump.
- **Gate:** nearest-of-type + area-unlock tests.

## Phase 9 — Progression meta  *(slice: "goals to chase")*

Per spec §13, §15.

- **Modules:** `Quests` (data-driven objectives + requirements + rewards + Quest
  Points; **idle auto-progress** by listening to `EventBus` — level-ups, kills,
  gathers — so most quests tick themselves); `CollectionLog` (auto-records uniques
  by source, completion %); `Achievements`/milestones.
- **Data:** `data/quests.json`; collection groups derived from drop tables/nodes.
- **Save:** quest state + QP, collection log, achievements; schema bump.
- **Gate:** quest-state + collection-log persistence tests.

## Phase 10 — Feedback, AFK/Rested XP, onboarding, stats  *(slice: "it feels alive")*

Per spec §8, §9, §22, §23, §25.

- **Modules:** `LevelUpFeedback` (unlock-diff dialog vs chat line + confetti +
  jingle off `EventBus.level_up`); **AFK + Rested XP** (AFK pause → accrue/drain an
  XP buff via the `Modifiers` stack — no offline sim); `Notifications` (rare-drop
  banner + sound, floating XP, hitsplats); Settings expansion (volumes, thresholds,
  toggles); `Onboarding` (guided first session); `Statistics` (xp/hr, kills, drops).
- **Save:** rested-XP pool, statistics; schema bump.
- **Gate:** the headless-testable feedback / AFK / onboarding bits.

## Phase 11 — Post-launch depth  *(design now, build later)*

Per spec §14, §20, §12. **Achievement Diaries** (per-region tiered tasks → perks
via `Modifiers`); **Pets & skill capes** (tertiary hooks already in `DropRoller`);
**Special attacks** (spec/energy bar on `Modifiers`); optional **Hardcore/Ironman**
mode flag. Add the hooks during earlier phases; flesh out after launch.

---

## Suggested milestone order (playable slices)

The phases can ship in number order, but if you want each checkpoint to be *fun to
play*, group them:

| Milestone | Phases | Why it's a slice |
|---|---|---|
| **M1 — Core loop is fun** | 5 + the §9 level-up juice from 10 | Combat feels complete and rewarding. |
| **M2 — Idle engine is whole** | 6 + 7 | Every skill runs itself; economy closes the loop. |
| **M3 — Direction & goals** | 8 + 9 | A traversable world with quests/collection to chase. |
| **M4 — Long-tail depth** | 11 (+ rest of 10) | Diaries, pets, prestige, polish. |

## Cross-cutting acceptance (every phase)

- `validate.tscn` green; new module covered by isolated headless tests.
- Previous-version save loads with **zero** loss warnings; schema bumped + migrated.
- New system is a module behind a thin interface; UI holds no game logic.
- World features key off data tags, not coordinates (map can still change).
