# Imota — Phased Build Plan (AI implementation prompt)

You are implementing the Imota redesign. This document is your execution order. The
**authoritative design detail** lives in `docs/IMOTA_REDESIGN_SPEC.md` (Part I = core loop,
Part II = depth systems, §0.5 = save stability). The **binding constraints** live in
`AGENTS.md`. Read both before writing code, then work **one phase at a time**.

This plan also fixes the project's current mishaps: content and skills were copied directly
from Bloobs Adventure Idle (names + name-derived ids), the inventory/currency/XP-curve are
still Bloobs-shaped, and offline progress is still present. Those are corrected in Phases 0–3.

## How to work (every phase)

1. Implement only the current phase. Keep the architecture: **one sim layer, dumb UI**; all
   truth in `autoload/*`, UI listens to `EventBus`; content stays **data-driven** from
   `data/*.json`; **keep the existing tick timer**.
2. **Save safety is non-negotiable** (Steam Early Access, live saves). Obey `AGENTS.md`:
   stable ids are a permanent contract; renames touch `displayName` only; any id change or
   removal needs a `content_aliases.json` entry **and** a `save_migration.gd` step. If you
   are unsure whether a change is save-safe, **STOP and flag it — do not guess**.
3. End every phase with the gate:
   - Run `res://tools/validate.tscn` headless; fix all failures before continuing.
   - Add/extend tests in `tools/validate.tscn` covering the phase's new logic, including a
     **load-a-previous-version-save → zero "unknown item/dropped" warnings** check whenever
     ids/skills/data change.
   - Smoke-launch the game (per `AGENTS.md`) unless the phase is data/docs only.
4. Record load-bearing decisions in the relevant `docs/*` file (decision → why →
   consequence). Update `save_migration.gd`'s `CURRENT_SCHEMA`/`CURRENT_GAME_VERSION` whenever
   the save shape changes.
5. Do not start the next phase until the current one is green.

---

## Phase 0 — Foundations & save-safety net  *(must come first)*

Goal: make all later changes save-safe and surface existing breakage.

- Run the current test suite and catalogue every failure/warning as the baseline.
- **Replace name-derived ids with opaque stable numeric ids** (OSRS-style, e.g. `item.1001`):
  - Add a persistent **id registry** so ids are assigned once and **preserved across
    re-imports** (the importer only mints ids for genuinely new content, never re-derives).
  - Stamp an explicit, frozen `id` into every item/enemy/node/recipe in `data/*.json`.
  - Authoring cross-references (recipes/drops/nodes referencing items by name) and
    `displayName` stay on top and resolve to ids at load — keep data files human-readable.
- **Migration:** live EA saves hold the old slug-ids (`item.suncoil_logs`). Add a
  `save_migration.gd` step mapping old slug-ids → new numeric ids, with `content_aliases.json`
  entries, and bump the schema.
- **Test:** save round-trip + load-old-save-with-zero-warnings checks in `validate.tscn`.

Gate: tests green, old saves load clean.

## Phase 1 — Mechanical globals (de-Bloobs the frame)

Per spec §0, §1. All small, data/constant-level, individually testable.

- Inventory **24 → 28** slots.
- Currency **Gold → Coins** everywhere (state, UI, drops, shops, save field + migration).
- Level cap **1000 → 99**; regenerate `data/xp_table.json` from the **OSRS formula × S**,
  `S = 1.25` exposed as a constant (`maxLevel: 99`).
- **Remove offline progress** entirely from `SaveManager` and any callers.

Gate: tests updated for 28 slots / new curve / no-offline; green.

## Phase 2 — Skill roster overhaul (de-Bloobs the skills)

Per spec §2. Replace the Bloobs skill set with OSRS names + our deltas.

- Final skills: Attack, Strength, Defence, Hitpoints, Ranged, Magic, **Prayer**, **Slayer**,
  Woodcutting, Mining, Fishing, **Foraging** (gather only, no potions), Thieving, **Hunter**,
  **Farming**, Smithing, Cooking, Firemaking, Fletching, Crafting, **Alchemy**, Agility.
- Map old keys: devotion→prayer, tracking→hunter, dexterity→agility, homesteading→farming,
  herbology→**alchemy**; keep foraging as gathering. **Beastmastery is not a skill** — fold
  its level-lock into **Slayer** (per-enemy requirement field).
- Defer Construction, Runecraft. Re-home or shelve leftover `imbuing`/`soulbinding` recipes
  (flag, don't silently drop content).
- **Migration:** rewrite old skill keys in saves → new keys; bump schema; zero data loss.

Gate: skill-key migration test (old save → all XP/levels preserved under new keys).

## Phase 3 — Content de-Bloobsification (IP rename pass)

Per spec §7. Ids are already frozen (Phase 0), so this is **`displayName`-only** and fully
save-safe.

- Rename **every Bloobs-original** item, node, fish, herb, ore, tree, enemy and **boss** to
  an original name (e.g. Suncoil → Elderlog) via an auditable **rename map** consumed by the
  importer / a one-shot pass. Keep OSRS-shared generic tiers (Oak, Iron, Mithril, …).
- Update name-based cross-references consistently (or alias them).
- Confirm `displayName != legacy key`, ids unchanged, saves intact.

Gate: rename-integrity test (every id still resolves; no save churn).

## Phase 4 — Idle automation framework  *(backbone of the game)*

Per spec §21, §3. Everything later plugs into this.

- A single **Activity/Task manager**: one active activity (gather/combat/craft) + intent
  persistence; **Farming runs as a separate background sim** (§6 below).
- Built-in automations: auto-walk, auto-gather-switch-to-nearest-same-type, auto-loot,
  auto-bank-when-full, auto-eat, auto-retaliate, auto-sip-potion.
- **Intent-gating:** auto-gather only starts from the skill→level-unlocks→select flow;
  combat requires manual click on an enemy (or Slayer-dialog click) then auto-continues.
- **Spoiler-free dialogs:** hide not-yet-unlocked nodes/monsters/bosses.
- **Bank icon by the minimap** → auto-path to nearest bank.
- **Stop conditions** with surfaced reasons: AFK, death, depletion, full+no-bank, out of
  inputs/food/prayer.

Gate: headless task-manager tests (start/stop/switch/stop-reasons).

## Phase 5 — Combat depth

Per spec §5, §12.

- **Per-hit XP** (OSRS-style: combat skill ∝ damage, + Hitpoints share) — replace on-kill XP.
- **Combat styles** route XP (accurate/aggressive/defensive/controlled; ranged/magic variants).
- **Per-weapon attack speed** (ticks); **auto-eat** threshold; **combat potions**; **Prayer**
  in combat (points/drain/protection/offensive, Protect Item).
- **Death:** respawn full HP; destroy the item in **one random equipped slot** (empty slot =
  no loss; **Protect Item** prayer negates); loose inventory safe.
- **Combat level** derived stat; **drop tiers** (always/common/rare + rare-drop table +
  tertiary pet/clue rolls); loot rolls on kill.

Gate: combat-math tests (XP routing, death-slot logic, drop rolls).

## Phase 6 — New & changed skill loops

Per spec §16. Each must be "set it and it runs."

- **Prayer:** bury bones / altar offering activity → XP; unlock prayers.
- **Alchemy:** potion recipes via `RecipeSim` (Foraging/Farming inputs) → buffs; **High
  Alchemy** (item → Coins).
- **Farming:** dedicated **FarmingSim** — plant → **background tick growth while doing other
  activities** → auto-harvest; tunable plot count; respects no-offline.
- **Hunter:** intent-gated auto-track/trap in zones → products.
- **Agility:** auto-course activity + passive run-energy meta-skill that speeds auto-nav.

Gate: per-skill loop tests; farming background-growth test.

## Phase 7 — Economy, items, equipment

Per spec §18, §19.

- NPC shops (tools/supplies/seeds; sell-back), High-Alch sink, fixed stock from
  `data/tools.json`. **Equipment loadout presets** (skilling↔combat quick-swap). Bank
  upgrades (tabs/search/deposit-all/value). Stackable rules; item quality tiers.

Gate: economy/loadout tests.

## Phase 8 — World, areas & travel

Per spec §17, §5. Required for the auto-idle to function.

- **Fixed spawn zones** for every node and monster type (no random spawns).
- **Region gating** (quest/level/combat-level); **fast travel/teleports** between unlocked
  hubs; minimap + world map with discovered/undiscovered state.

Gate: nearest-of-type lookup + area-unlock tests.

## Phase 9 — Progression meta

Per spec §13, §15.

- **Quests:** objectives + requirements + rewards + Quest Points; idle-friendly auto-progress;
  spoiler-safe quest log; quests can unlock skills/areas/recipes/monsters.
- **Collection Log** (auto-record uniques, completion %, milestone perks) and
  **Achievements/Milestones**.

Gate: quest-state + collection-log persistence tests.

## Phase 10 — Feedback, AFK/Rested XP, onboarding, stats

Per spec §8, §9, §22, §23, §25.

- **Level-up feedback:** unlock-list dialog when something unlocks, else simple chat line;
  always confetti over the player + 2–3 s jingle.
- **AFK → Rested XP:** AFK trigger pauses the game; on return grant a time-scaled Rested-XP
  buff (WoW-style) that drains while active; show it in UI. (No offline simulation.)
- **Rare-drop banner + sound**, floating XP, hitsplats; **settings** (volume, notifications,
  AFK/auto-eat thresholds, confirmations); **onboarding** guided first session; **statistics**
  (XP/hr, kills, drops).

Gate: feedback/AFK/onboarding tests where headless-testable.

## Phase 11 — Post-launch depth (design now, build later)

Per spec §14, §20, §12. Achievement Diaries (tiered regional tasks + perks), Pets & skill
capes, special attacks, optional Hardcore/Ironman mode.

---

## Cross-cutting acceptance (all phases)

- `tools/validate.tscn` passes; new logic covered by tests.
- Loading a save from the previous released version succeeds with **zero** save-loss warnings.
- No Bloobs-original names remain in shipped content; no Bloobs skill names remain.
- Ids are opaque/numeric/frozen; no id is name-derived; no removed id is reused.
- Offline progress is gone; the tick timer is unchanged; UI holds no game logic.
