# Imota — Redesign Implementation Spec

> A step-by-step build prompt. Imota is an OSRS-inspired, semi-idle incremental RPG
> in Godot 4, built on imported Bloobs Adventure Idle data. This spec replaces the
> Bloobs prestige/offline model with classic OSRS 1–99 leveling, an intent-gated
> auto-play ("legal bot") idle loop, and a WoW-style Rested-XP system. **All
> Bloobs-original content names must be renamed for IP reasons.**

---

## 0. Ground rules (apply everywhere)

| Rule | Value |
|---|---|
| Engine tick | **Keep the existing tick timer** in `TickSim`/`CombatSim`/`RecipeSim`. Do not change the action-duration math except where noted. |
| Level cap | **1–99 per skill** (drop the Bloobs 1–1000 prestige curve for now; design so it can extend to 120/prestige later). |
| Inventory | **28 slots** (was 24). |
| Currency | Rename **Gold → Coins** everywhere (state, UI, drops, shop). |
| Offline progress | **Removed entirely.** No fast-forward on load. |
| One sim layer, dumb UI | Preserve the architecture: all truth in `autoload/*` sims; UI only listens to `EventBus`. |
| Source of truth | Item stats, recipe I/O, drop tables, node yields, enemy numbers stay **data-driven** from `data/*.json`. Don't hard-code lists. |

---

## 1. XP & leveling

- Base: the **OSRS experience formula** —
  `osrsXp(L) = floor( (1/4) * Σ_{i=1..L-1} floor( i + 300 · 2^(i/7) ) )`.
- **Slowdown:** `xpRequired[L] = round( osrsXp(L) · S )`, where `S` is a single tunable
  multiplier. **Start `S = 1.25`.** Expose `S` as a constant so balancing is one knob.
- Build the table to level 99, write it to `data/xp_table.json` (`maxLevel: 99`).
- Keep `DataRegistry.xp_for_level` / `level_for_xp` as-is; they already read the table.

---

## 2. Skill roster

Use **OSRS skill names** with these deltas. Final set (22 skills):

| Group | Skills |
|---|---|
| Combat | Attack, Strength, Defence, Hitpoints, Ranged, Magic, **Prayer** (was Bloobs *devotion*), **Slayer** |
| Gathering | Woodcutting, Mining, Fishing, **Foraging** (was *herblore/herbology* — **gathers herbs/plants, makes NO potions**), Thieving, **Hunter** (was Bloobs *tracking*), **Farming** (was Bloobs *homesteading*) |
| Artisan | Smithing, Cooking, Firemaking, Fletching, Crafting, **Alchemy** (NEW — the potion-making split out of Foraging) |
| Utility | Agility (was Bloobs *dexterity*) |

**Deferred (add later):** Construction, Runecraft.

Mapping notes for the importer/rename pass:
- Bloobs `herbology` (potion recipes) → **Alchemy**.
- Bloobs `foraging` (bush/mushroom/berry nodes) → **Foraging** (gathering only).
- Bloobs `devotion` → **Prayer**; `tracking` → **Hunter**; `dexterity` → **Agility**;
  `homesteading` → **Farming**.
- Bloobs `beastmastery` is **not a standalone skill** — its level-lock mechanic folds
  into **Slayer** (see §5).
- Bloobs `imbuing` / `soulbinding`: keep their recipes but file under the nearest
  surviving skill (Alchemy or Crafting) or shelve until a home skill exists — **flag,
  don't silently drop content.**

---

## 3. The idle / auto-play model — *the core draw of Imota*

The game plays itself like a bot, **but only after the player declares intent.** Two
distinct flows:

### 3a. Gathering (fully auto, intent-gated)

The required sequence before any auto-gathering starts:
1. Player opens the **skill list**.
2. Opens the **level-unlocks dialog** for a specific skill (e.g. Woodcutting).
3. **Selects a specific resource** they've unlocked (e.g. a tree type).
4. Game **auto-navigates** the player to the **nearest spawn** of that resource.
5. **Auto-performs** the action (chop/mine/fish/forage) using the existing tick loop.
6. On depletion, **auto-switches to another nearby node of the same type** and repeats.
7. Loop continues **until** either: the player goes **AFK too long** (→ §8 Rested XP), or
   the player **navigates to something else** / picks a new intent.

Reuse `world_auto_task_controller` (auto-walk + find-nearest-site + auto-bank) and
`world_activity_controller`. The gating is a UI precondition: auto-gather is only
callable from the skill-unlocks dialog selection, not from a raw world click.

### 3b. Combat (manual engage, then auto-continue)

- **No auto-pathing to start a fight.** The player must **manually walk to an enemy and
  click one**. From then on the game **auto-continues killing enemies of that same type**.
- **Exception:** opening the **Slayer dialog → finding the monster → clicking it** also
  arms the auto-continue (still respects the manual-feel: it then routes/fights that type).
- Keep the existing aggro logic in `world_activity_controller._check_aggro` for ambient
  danger, but player-initiated combat is the primary path.

### 3c. Spoiler-free unlocks dialogs

In every selection dialog (skills, Slayer), **hide content the player has not yet
unlocked** — locked trees, ores, fish, herbs, monsters, bosses must **not appear** (no
greyed-out "Lv 90 ???" rows that spoil what's coming). Show only what is currently
reachable, plus at most the *next* unlock as a teaser if desired (confirm later).

### 3d. Bank access

- Add a **bank icon next to the minimap.** Clicking it auto-paths the player to the
  nearest bank (reuse `world_auto_task_controller.auto_bank`).

---

## 4. Nodes (gather content)

- Keep the node model: tool `progress` damages a node per tick; per damage threshold →
  award resource + XP. Keep current action-speed formula.
- Nodes spawn in **designated world spots** (already sectored). Auto-gather hops between
  same-type nodes in a locality (§3a step 6).
- **Rename all Bloobs-original node names** (see §7). OSRS-generic tiers (Oak, Willow,
  Maple, Yew, Copper, Tin, Iron, Coal, Mithril, Adamantite, Gold, Silver) **may keep
  their OSRS names** since Imota is OSRS-inspired; only **Bloobs-unique flavor names**
  must change.

---

## 5. Enemies & Slayer

- **Spawn in fixed zones, never random.** Each monster type has designated spawn
  area(s). This is **mandatory** — the auto-idle "find nearest enemy of this type"
  feature is impossible with random spawns.
- **Slayer holds ALL monsters** (not the OSRS subset). Slayer is the master bestiary +
  the unlock gate.
- **Beastmastery lock → Slayer requirement:** each enemy carries a Slayer-level
  requirement (port Bloobs `beastMasteryReq`). The player cannot engage a monster until
  Slayer level ≥ its requirement. Locked monsters are **hidden** in the Slayer dialog (§3c).
- **Combat XP = OSRS style, earned per hit during the fight** (not lump-sum on kill).
  Apply OSRS-style: the trained combat skill gains XP proportional to damage dealt, plus
  Hitpoints XP proportional to damage (e.g. 4× dmg to combat skill, 1.33× dmg to HP — tune
  to feel). **Change `CombatSim` away from on-kill XP to per-hit XP.**
- **Kill rewards = OSRS-style loot:** roll the per-enemy drop table on death (keep the
  parsed `drops` tables). Rewards **vary per enemy**. Coins are a drop like any other.
- Keep respawn timers (normal vs boss). Keep the combat triangle, accuracy/damage
  formulas, DR cap, miss-streak pity, double-hit — unless a number needs rebalancing for
  the 1–99 curve.

---

## 6. Skill interdependency (content graph)

Wire outputs into downstream skills wherever it's natural, OSRS-style:

- **Mining** → ores → **Smithing** → bars → weapons/armor/tools.
- **Woodcutting** → logs → **Firemaking** (burn) and **Fletching** (bows/arrows/shafts).
- **Fishing** → raw fish → **Cooking** → food (heals HP; has `hpValue`).
- **Foraging** → herbs/plants → **Alchemy** → potions/buffs.
- **Farming** → grown crops → Cooking / Alchemy inputs.
- **Hunter** → creature products → Crafting / Cooking.
- **Slayer/Combat** → bones → **Prayer**; rare drops → gear.

Every gather feeds an artisan; every artisan feeds combat or economy. Validate the graph
has no dead-end resources.

---

## 7. Content renaming (IP requirement)

> The dev permitted using the data but **asked not to rip names directly.**

- **Rename every Bloobs-original** tree, ore, fish, herb, plant, mushroom, item, monster
  and **boss** to a new original name. Example: `Suncoil → Elderlog`.
- **Keep** OSRS-shared generic tier names (Oak, Iron, Mithril, etc.) — those come from the
  OSRS side of the inspiration, not Bloobs.
- Implement as a **rename map** consumed by `tools/import_bloobs_data.gd` (or a one-shot
  rename pass over `data/*.json` + `content_aliases.json`), so it's auditable and the
  `displayName` differs from the legacy key. Keep stable ids stable so saves survive.
- Bosses get fully new names too.
- Deliver the rename map as data, not scattered string literals.

Starter examples (extend into a full table — these set the tone, not the limit):

| Bloobs (unique) | Imota |
|---|---|
| Suncoil (Tree/Logs) | Elderlog |
| Lunarwood | *(new)* |
| Aether Tree / Aether Core | *(new)* |
| Cerulium / Sanguinite / Aeronite / Necrosis / Phantom / Karinite / Taigite / Cryxcite / Aurite / Sunwrought (ores) | *(new tier names)* |
| Bloobberry | *(new berry name)* |
| Aurelion the Sunbound Pharaoh (boss) | *(new boss name)* |

---

## 8. AFK → Rested XP (replaces offline progress)

- Maintain an **AFK timer** (copy Bloobs' AFK trigger behavior/threshold).
- When AFK kicks in: **pause the game** (sims stop; no offline simulation).
- Compute time-away on return and grant **Rested XP** (WoW-style): a temporary
  **XP-gain buff** whose **magnitude/duration scales with how long the player was AFK**
  (e.g. accrue a pool that drains as bonus XP while active, with a cap). Tune the
  accrual rate and cap as constants.
- Surface remaining Rested XP in the UI (e.g. a small bar/indicator).

---

## 9. Level-up feedback

On every skill level-up:
1. **If the new level unlocks something** (a craftable, a node, a monster, gear): show an
   **OSRS-style "Congratulations!" unlock dialog** listing what's newly available
   (mirrors the attached Smithing screenshot — "You can now smelt…", "You can now
   smith…", etc.).
2. **If nothing new unlocks:** show the **simple line in the bottom-left chat/log
   location** — "Congratulations, you just advanced a Fishing level. Your Fishing level
   is now 20." (mirrors the attached Fishing message).
3. **Always:** spawn **confetti over the player** sprite, and play a **short memorable
   level-up jingle (2–3 s)**.

Drive all of this from the existing `EventBus.level_up` signal; compute "what unlocked"
by diffing content gated at `new_level` for that skill.

---

## 10. Suggested implementation order (step by step)

1. **Constants & globals:** inventory 28, Coins rename, cap 99, remove offline-progress
   code path in `SaveManager`.
2. **XP table:** implement OSRS formula × `S=1.25`, regenerate `data/xp_table.json`.
3. **Skill roster:** update `GameState.SKILLS` to the §2 set; migrate Bloobs skill keys
   (devotion→prayer, tracking→hunter, dexterity→agility, homesteading→farming,
   herbology→alchemy); fold beastmastery into a Slayer requirement field.
4. **Content rename pass:** build the rename map; apply via importer/aliases; verify saves
   still load (stable ids).
5. **Combat XP rework:** per-hit XP in `CombatSim`; loot on kill stays.
6. **Enemy spawn zones:** ensure every monster type has fixed spawn area(s); expose
   "nearest enemy of type" lookup.
7. **Slayer system:** all-monsters bestiary + level-gate + hidden-until-unlocked dialog;
   click-to-arm auto-continue.
8. **Idle gating:** wire gather auto-play strictly behind the skill→unlocks→select flow;
   spoiler-free dialogs; bank icon by minimap.
9. **AFK + Rested XP:** AFK trigger → pause → accrue/drain rested-XP buff with UI.
10. **Level-up feedback:** unlock-dialog vs chat-line branch, confetti, jingle.
11. **Interdependency audit:** confirm the §6 content graph end-to-end.
12. **Tests:** extend `tools/validate.tscn` for the new curve, 28 slots, per-hit XP,
    Slayer gating, rename integrity, no-offline.

---

## 11. Open decisions to confirm during build

- Exact `S` slowdown value (start 1.25) and whether it varies by skill group.
- Per-hit XP coefficients (combat-skill multiplier, HP multiplier).
- AFK threshold and Rested-XP accrual rate / cap / drain rate.
- Home skill for leftover Bloobs `imbuing` / `soulbinding` recipes.
- Whether dialogs show a single "next unlock" teaser or hide everything locked.
- Final boss/content rename table (full list).
