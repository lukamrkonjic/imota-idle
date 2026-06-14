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

## 0.5 Content & save stability (Steam Early Access — crucial)

Imota ships in Early Access with **live player saves**. No content change may corrupt or
silently delete an existing save. This is a release blocker, not a nice-to-have. The full
operational rule lives in `AGENTS.md` ("Save-game safety"); the rationale:

- **Saves store stable `id` + quantity only** — inventory `[{"id","qty"}]`, bank keyed by
  id, equipment slot→id. **Stats are never stored**; they re-read from `data/*.json` each
  load. So stats/drops/recipe-I/O/XP/yields are **always free to rebalance**.
- **The id is the contract.** Once an id ships, it is permanent. Display names
  (`displayName`) are presentation-only and change freely — this is what makes the IP
  rename pass (§7) safe.
- **Id scheme: opaque stable numbers, OSRS-style** (e.g. `item.1001`), assigned **once via
  a persistent id registry**, never derived from the name, never reused after removal. The
  importer preserves existing assignments and only mints ids for new content. Authoring
  cross-references (recipes/drops/nodes by name) and `displayName` sit on top and resolve
  to ids at load, so data files stay human-readable.
- **Today's footgun:** ids are currently *derived from names* (`ContentId.slug` →
  `item.suncoil_logs`) because data files lack explicit `id` fields. A bare rename would
  change the id and break saves. **Fix before any renaming:** (1) mint a frozen numeric id
  for every existing item/enemy/node/recipe into an id registry + the data files; (2) ship
  a `save_migration.gd` step mapping the old slug-ids in live EA saves → the new numeric
  ids (with `content_aliases.json` entries), proven by a load test in `tools/validate.tscn`.
  This decouples id from name permanently *and* protects current players.
- **Changing or removing an id** requires both a `data/content_aliases.json` mapping and a
  `autoload/save_migration.gd` migration (bump `CURRENT_SCHEMA`), proven by a check in
  `tools/validate.tscn`. Never rename/remove an id bare.
- **Acceptance gate:** loading a previous-version save must produce **zero** "unknown
  item / dropped from inventory" warnings.

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

---
---

# Part II — Systems the core loop needs around it

> Part I is the moment-to-moment loop. Part II is everything that gives the game depth,
> goals, and a reason to keep idling. Each item is tagged **[MVP]** (build with the core)
> or **[Later]** (design now, implement after launch). Adapt every OSRS system to the
> **semi-idle** frame — if it can't "set it and it keeps running / auto-resolves," redesign it.

## 12. Combat depth

- **Combat styles & XP routing [MVP].** The chosen weapon style decides which skill gets
  the per-hit XP (OSRS model):
  - Melee: **Accurate→Attack, Aggressive→Strength, Defensive→Defence, Controlled→split**.
  - Ranged: **Accurate→Ranged, Rapid→Ranged (faster), Longrange→Ranged+Defence**.
  - Magic: spell-based→**Magic** (+Defence on defensive cast).
  - Hitpoints always gains a share. A style selector lives in the combat UI; the auto-loop
    just keeps the selected style.
- **Weapon attack speed [MVP, decision].** Currently a flat 3 s. OSRS weapons have
  per-weapon tick speeds (daggers fast, mauls slow). Recommend **per-weapon `attackSpeed`
  (in ticks)** so weapon choice is a real trade-off; fall back to a default if data lacks it.
- **Auto-eat [MVP — essential for idle].** In the combat loop, when HP drops below a
  configurable threshold (e.g. 50%), automatically eat the best available food from
  inventory. Without this, idle combat is just "fight until death." Expose the threshold in
  settings. If no food remains and HP is critical → **retreat/stop** instead of dying
  (configurable).
- **Combat potions [MVP].** Alchemy-made potions give **timed stat boosts** (attack/strength/
  defence/ranged/magic, HP restore, etc.). Auto-drink option for idle (re-sip when the boost
  expires while food/potions remain).
- **Prayer in combat [MVP].** Prayer points drain over time while prayers are active;
  protection prayers reduce/negate enemy damage of a style; offensive prayers boost accuracy/
  damage; **Protect Item** prevents the on-death equipment loss (§12 death handling). Recharge
  at an altar. Auto-manage option for idle (toggle prayers, stop when out of points). See §16
  for how Prayer is *trained*.
- **Auto-retaliate [MVP].** Always on in the idle loop.
- **Special attacks [Later].** Spec/energy bar, weapon-specific specials.
- **Death handling [MVP — decided].** No offline. On death → respawn at a fixed point, full
  HP. **Item loss: pick one random *equipment slot* and destroy whatever is in it** — armor,
  weapon, cape, ammunition/tablets, equipped food/consumable, etc. If the chosen slot is
  **empty, nothing is lost.** If the **Protect Item** prayer (see §12 Prayer / §16) is
  active, nothing is lost. Only equipped items are at risk — loose inventory is safe. This
  keeps stakes real without gutting a full loadout, and makes Protect Item a meaningful
  prayer choice for risky idle combat.
- **Combat level [MVP].** Derived display stat (OSRS formula over att/str/def/hp/range/magic/
  prayer). Use it for area/monster soft-gating and UI.
- **Drop mechanics [MVP].** Per-enemy table with tiers: **always** (bones, ashes),
  **common/uncommon/rare**, and a shared **rare drop table** for high-value rolls.
  **Tertiary rolls** independent of the main table: pets, clue scrolls, resource bonuses.
  Show drop-rate on hover where known.

## 13. Quests

- **Quest system [MVP-lite, then expand].** A quest = ordered **objectives** + **requirements**
  (skill levels, items, prior quests, combat/quest-point thresholds, area access) +
  **rewards** (XP lamps, items, coins, unlocks, new areas, skill/feature unlocks). Track a
  **Quest Points** total used as a gate elsewhere.
- **Idle adaptation.** Objectives are mostly "reach skill X", "gather/craft N of Y", "kill
  N of Z", "reach area W" — things the idle loop can **auto-progress** and tick off, plus
  occasional click-to-advance story beats. Avoid OSRS-style manual puzzle steps that can't idle.
- **Quest log UI:** active/completed/available filtered by met requirements; locked quests
  hidden or shown as "?" per the spoiler rule (§3c). Quests can **unlock skills, areas,
  shops, monsters, recipes**.

## 14. Achievement Diaries / Task lists [Later, design now]

- Per-**region** tiered task sets (**Easy/Medium/Hard/Elite**) — e.g. "Train Mining to 30 in
  the Northern Hills," "Kill the regional boss." Completing a tier grants **permanent perks**
  (XP/rate boosts, better drops, travel discounts in that region). Strong long-term idle goals.

## 15. Collection Log & Achievements [MVP-lite]

- **Collection Log:** auto-records every unique item/resource/drop obtained, grouped by
  source (each monster, each gather node, each boss). Tracks **completion %** and grants
  cosmetic/perk milestones. Big retention driver for idle games.
- **Achievements/Milestones:** total-level/total-XP milestones, "first 99," boss kill counts,
  etc., with notifications.

## 16. Defining the new / changed skills' loops

Each skill needs a concrete "set it and it runs" loop:

- **Prayer [MVP].** Bury bones / offer at an altar → XP (auto-consume bones from inventory as
  an activity). Levels unlock prayers usable in combat (§12). Bones come from combat (§6).
- **Alchemy [MVP].** Potion recipes via `RecipeSim` (inputs from Foraging/Farming herbs +
  secondaries) → timed brew → potion output + XP, auto-repeat. Also home for **High Alchemy**
  (item → Coins) tying the skill to the economy. Houses ex-`herbology` recipes.
- **Farming [MVP — decided].** Plant seed in a **plot** → grows over many ticks →
  auto-harvest yield + XP. **Growth runs in the background while the player does any other
  activity** (gather/fight/craft) — it advances on the global tick, so it respects the
  no-offline rule (no growth while the game is closed) yet gives a genuine passive layer.
  Plot count is tunable (start small, expand via unlocks). Seed sources: Foraging/Hunter/
  shops. A dedicated **FarmingSim** runs independently of the single-active-activity manager
  (§21) since it's the one background system.
- **Hunter [MVP/Later].** Auto-track/trap a chosen creature type in its zone → products
  (for Crafting/Cooking). Same intent-gated auto-nav as gathering (§3a).
- **Agility [decision].** Idle role is unclear in OSRS terms. Recommend: an **auto-run
  course** activity (loop a circuit for XP) that also raises a passive **run-energy / movement-
  speed** stat speeding all auto-navigation — making it a meta-skill that improves idle
  efficiency. Confirm.

## 17. World, travel & areas [MVP]

- **Regions/areas** with **unlock gating** (by quest, combat level, or skill level). New areas
  hold higher-tier nodes, monsters, and bosses. Difficulty radiates outward.
- **Fast travel / teleports** between unlocked hubs (idle games shouldn't make you watch long
  walks). Bank icon by minimap (§3d). World map + minimap with discovered/undiscovered areas.
- **Locality is mandatory:** every node and monster type has fixed spawn zones so "nearest of
  type" auto-nav works (§4, §5).

## 18. Economy & shops [MVP]

- **Coins**, NPC **shops** (buy tools/supplies/seeds; sell-back at reduced value), and
  **High Alchemy** (§16) as the item→coins sink. **No Grand Exchange** (single-player) — use
  fixed NPC shop stock + the tool ladder already in `data/tools.json`. Item values and stack
  rules from data. Consider a simple **sell-all junk** convenience.

## 19. Items, inventory & equipment systems [MVP]

- **Stackable vs non-stackable** items; equipment requirements (already in data).
- **Equipment loadout presets [MVP]** — quick-swap sets (skilling tools vs combat gear) so the
  idle loop can switch automatically when the player changes intent. High value for a bot-style
  game.
- **Bank:** tabs, search, deposit-all, withdraw-X, total value. Auto-deposit on bank trips.
- **Item quality/rarity tiers** for display/loot juice.
- **Skilling/combat gear XP bonuses** already exist (`bonusXp`) — surface them; optionally add
  OSRS-style **skilling outfits** (full-set bonus) [Later].

## 20. Pets & cosmetics [Later, hooks now]

- **Pets:** rare tertiary rolls while skilling/fighting bosses (Bloobs has pet data). Cosmetic
  follower + small perk. **Skill capes** at 99 (cosmetic + minor perk). Add the drop hooks now,
  flesh out later.

## 21. Idle automation framework [MVP — the backbone]

A single **Activity/Task manager** owns the current intent and drives everything:
- One active activity at a time (gather / combat / craft / prayer / farming background).
- Built-in automations: **auto-walk, auto-gather-switch, auto-loot, auto-bank-when-full,
  auto-eat, auto-sip-potion, auto-retaliate.**
- **Stop conditions** (with reasons surfaced to the player): AFK timeout (→ Rested XP),
  death, global depletion with no respawn, inventory full + no reachable bank, out of inputs/
  food/prayer.
- **Notifications/log:** level-ups, rare drops, task complete, death, inventory full, AFK
  start/end, quest progress. This is the player's primary feedback while idling.

## 22. Feedback & game feel [MVP]

- Level-up dialog/chat + confetti + jingle (§9). **Rare-drop banner + distinct sound.**
  Floating XP drops, combat hitsplats, gather/craft progress on the player. **Settings** for
  sound volume, which notifications fire, AFK threshold, auto-eat threshold, confirmation
  prompts.

## 23. Onboarding [MVP-lite]

- Starter kit (already defined). A short **guided first session**: open skill list → pick first
  tree → watch auto-gather → first level-up → first craft → first fight. Teaches the
  intent-gating without a wall of text.

## 24. Persistence — new save fields [MVP]

Saves must cover everything above: quests + quest points, achievement diaries, collection log,
achievements/milestones, prayer state, **farming plots (with in-progress growth timers)**,
rested-XP pool, unlocked areas/teleports, equipment loadout presets, settings, statistics
(XP/hr, kill counts, drops). Version + migrate (`save_migration.gd`).

## 25. Statistics & analytics [Later]

- Per-skill XP/hr, time played, kills per monster, items gathered, coins earned, drop logs.
  Feeds the collection log and player goal-setting; also useful for balancing `S` and rates.

---

## Updated build order (insert after Part I step 12)

13. **Idle automation framework (§21)** — the task manager + auto-eat/auto-bank/auto-loot;
    everything else plugs into it.
14. **Combat depth (§12)** — styles/XP routing, attack speed, auto-eat, potions, prayer hooks,
    death handling, combat level.
15. **New-skill loops (§16)** — Prayer, Alchemy (+High Alch), Farming plots, Hunter, Agility.
16. **Economy & shops (§18)**, **loadout presets (§19)**, **bank upgrades**.
17. **World/areas & travel (§17)** — region gating + teleports.
18. **Quests (§13)**, then **Collection Log/Achievements (§15)**.
19. **Feedback/juice (§22)**, **onboarding (§23)**, **stats (§25)**.
20. **Achievement Diaries (§14)**, **Pets/capes (§20)** as post-launch depth.
21. Extend `tools/validate.tscn` for each new system; extend `save_migration.gd`.

## Added open decisions

- Respawn point location(s) per area. *(Item-loss policy decided: random equipped slot,
  empty = safe, Protect Item negates — §12.)*
- Per-weapon attack speeds vs keeping a flat interval.
- Auto-eat / auto-potion default thresholds.
- Farming: starting plot count + unlock cadence. *(Background-growth-while-busy decided: yes
  — §16.)*
- Agility's idle role (recommend run-energy meta-skill + auto-course).
- High Alchemy rate/value formula.
- Whether quests gate skills/areas hard, or only grant bonuses.
- Hardcore/Ironman mode existence.
