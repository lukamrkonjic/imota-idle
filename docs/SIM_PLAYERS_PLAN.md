# Sim-Players — Plan & Feasibility

> Goal: make Imota feel **populated and alive** — a single-player world that reads like a
> living MMO. AI "sim-players" wander organically, skill at resource nodes, chat and react
> socially (Erenshor-style), and PvP each other + the player in a wilds biome.
>
> Reference studied: **2009scape**'s bot framework (`core/game/bots/*`, `content/global/bots/*`)
> and **Erenshor** (a single-player game whose entire "playerbase" is simulated NPCs).

---

## 1. Verdict: is it doable without major performance hiccups?

**Yes — comfortably, for a realistic concurrent count (~20–60 visible sim-players), and with no
deep engine work for v1.** Two facts make this cheap:

1. **The render pipeline already does the hard part.** `MoverRenderer3D.update()` iterates
   `world.entities` every frame, builds a procedural rig per mover (`MoverMeshes.enemy_rig`), and
   poses it (`mover_rig.gd`). The world **already animates ~178–495 movers per frame today**
   (enemies, bounded by `WG.ACTIVE_RADIUS` 4–7 chunks) with **no LOD and no instancing**. A
   sim-player is just *one more humanoid mover* — the same shape as the player rig. Adding a few
   dozen is well inside the envelope the engine already sustains.

2. **The "brain" is nearly free if we budget it.** 2009scape's key lesson is a hard cap:
   `botPulsesTriggeredThisTick >= 75` → only 75 bot brains *think* per game tick; the rest wait,
   plus random idle rolls. Our tick is `GameState.TICK = 0.6s`. A budgeted state-machine tick over
   even 100 bots at 0.6 s is microseconds.

### The one thing to actively manage: **draw calls**
Each humanoid rig is **~21–40 uninstanced `MeshInstance3D` nodes** (`mover_meshes.gd`). 60 sim-players
≈ **+1,300–2,400 draw calls**. That's the real cost, not CPU. Mitigations (all cheap, and they help
enemies too):

- **Spawn/cull by the existing active radius.** Bots only exist & render near the camera, exactly
  like enemies (`ACTIVE_RADIUS`). Distant bots are *simulated abstractly* (a position + activity),
  not rigged.
- **Hard cap on concurrent rigged bots** (config, e.g. `MAX_VISIBLE_SIMS = 40`).
- **Animation LOD (new, optional, benefits everything):** skip the per-frame pose for movers that
  are far / off-camera. Today every mover poses every frame regardless of distance — adding a
  distance/frustum gate in `MoverRenderer3D._animate_mover` is a net win for the whole game.

**Bottom line:** piggyback the proven mover pipeline + a budgeted brain + the active-radius cull.
No networking exists (fully local), no offline catch-up — so there's no hidden simulation tax.

---

## 2. The core design decision (and recommendation)

**2009scape bots are *real players*** — `AIPlayer extends Player`, real skills, real inventory, a
real Grand Exchange. They must be, because it's an actual shared-economy MMO. That realness is why
their combat/skilling reuse the live player systems.

**We are single-player.** We don't need a second real economy — we need *believable theater*, which
is exactly the **Erenshor model**. So:

> **Recommendation: sim-players are presentation + social theater, with their own lightweight
> state — NOT a second instance of the real player economy.**

| | 2009scape (real) | Imota recommendation (theater) |
|---|---|---|
| Identity/levels | full `Player` + skills | lightweight `SimPlayer` struct (name, look, skill levels, hp) |
| Skilling | drives real `TickSim`/inventory/bank | *plays the gather animation* + rolls fake XP/levels for its own identity |
| Combat/PvP | real `CombatSim` 1‑on‑1 | lightweight HP exchange using the **extracted damage formula** (pure function) |
| Economy | real GE offers | none in v1 (optional later: fake GE chatter) |

This avoids the only real refactors the audit flagged — decoupling the **singleton** `CombatSim`
(`var enemy: EnemyDef`, player-vs-one-enemy) and threading per-entity `GameState` — by **not using
those singletons for bots at all**. The player's economy stays untouched (and saves stay safe).

We keep 2009scape's *structure* (entity-as-mover, intent-queue brain, per-tick budget, data-driven
identity, wilderness PvP) without its *coupling*.

---

## 3. Architecture mapping (2009scape → Imota)

| 2009scape | Imota hook | Status |
|---|---|---|
| `AIPlayer extends Player` (real entity, fake session) | `SimPlayer` = `WorldEntity` reusing the **player rig** (`MoverMeshes.player_rig`, equipment sockets) instead of `enemy_rig` | rig + sockets exist; new entity kind |
| `ArtificialSession` (no-op network) | N/A — no networking | free |
| `Script.tick()` state machine | `SimBrain.think()` — picks next intent | build |
| `BotScriptPulse` + `75/tick` budget | `SimDirector` — owns the bot list, spawns/culls by `ACTIVE_RADIUS`, ticks N brains/tick | build |
| `ScriptAPI.walkTo` / `randomWalkTo` | `PathFinder.find_path(from, to)` (AStar2D, respects water/cliffs/`MAX_CLIMB_STEP`) | **exists, bot-ready** |
| `ScriptAPI.getNearestNode` | `WorldGen.find_nearest_poi(layer, pos, types)`; + small "nearest gather site" query | exists (+minor add) |
| `ScriptAPI.interact` (chop/mine/fish) | play the matching `mover_rig` gather pose; bots don't touch real `TickSim` | rig poses exist |
| `ScriptAPI.attackNpcInRadius` | lightweight `SimCombat` using extracted damage formula | build (formula exists in `combat_sim.gd`/`COMBAT.md`) |
| `ScriptAPI.sendChat` | speech bubble (new) + optional feed line via `EventBus.combat_log` | build (trivial) |
| `CombatBot` + `WildernessZone` | `danger:"wilderness"` regions (e.g. **Dreadmoor**, already authored) | zone authored; PvP logic new |
| `botnames.txt` / `bot_dialogue.json` / appearance+equipment tiers | `data/sim_players/{names,dialogue,looks}.json` | build (data) |

---

## 4. What already exists in our codebase (the green lights)

- **Mover pipeline** — `world.entities` (`scripts/world/world.gd`) → `MoverRenderer3D`
  (`scripts/render/mover_renderer_3d.gd`, `_mover_nodes` dict, per-frame `_animate_mover`). Reuses
  the **player rig** with equipment sockets and a full humanoid pose set (`mover_rig.gd`).
- **Wander** — `world_activity_controller._update_wander` already moves mobs to random points within
  a radius (home + `wander_to` + `wander_t`). Directly repurposable; upgrade straight-line → pathed.
- **Pathfinding** — `PathFinder.find_path(from_world, to_world)` (`scripts/worldgen/path_finder.gd`):
  AStar2D over walkable tiles, rejects water/hazard/blocked/over-elevation, climb-limited, snaps to
  nearest reachable. Returns world-space waypoints. **Exactly what bots need.**
- **Named destinations** — worldspec `anchors[]` (settlements/landmarks, `data/world/worldspec/*.json`)
  + POIs (`data/world/pois.json`), queried via `WorldGen.find_nearest_poi(...)`.
- **Skill model** — 22 skills, XP table; `TickSim.start_gather(skill, node)` is a clean public API
  (we mirror its *roll*, we don't drive it for bots).
- **Damage formula** — OSRS-style accuracy/max-hit lives in `combat_sim.gd` (+ `docs/COMBAT.md`).
  Extract it to a **pure `CombatMath` helper** usable by both player combat and `SimCombat`.
- **Wilds** — worldspec schema already supports `"danger": "wilderness"` ("where players fight
  players"); **The Dreadmoor** is authored precedent. Biomes live in `data/world/biomes.json`.
- **Float-text pattern for speech bubbles** — `world_visual_controller.show_xp_float()` creates a
  `Label`, tweens it up and fades it; `hit_splat.gd` anchors a splat that follows an entity. Speech
  bubbles are the same recipe.
- **Nameplates** — `WorldEntity.label` / `sub_label` already render over entities.
- **Determinism** — seeded worldgen (`wg.hash_i` / `wg.r01`) → reproducible bot identities/spawns.

### Gaps to build
- `SimPlayer` entity kind + `SimDirector` + `SimBrain` (the new subsystem).
- Speech-bubble node (trivial, copy `show_xp_float`).
- "Nearest gather site" query helper (small).
- `CombatMath` extraction (refactor, keeps player combat identical).
- Sim-player data files (names/looks/dialogue) + a deterministic identity registry.

---

## 5. Save-safety & persistence (HARD RULE: never break a player save)

Per `docs/SAVE_FORMAT.md` and the save-safety contract, sim-players **must not live in
`save.json` (player state)**. Instead:

- **Identity is deterministic, not saved.** A sim-player's name/look/home/levels derive from
  `wg.hash_i(world_seed, home_chunk, slot)`. Same seed → same cast of characters, regenerated for
  free each session. No migration risk.
- **Only deltas persist, in the world layer.** If a bot has mutable state worth keeping (e.g. it
  "died" in the wilds and is on a respawn timer, or a reserved name), store it in `world.json`
  (`WorldStore`) under a `sims` key — additive, schema-versioned, degrades gracefully if absent.
- v1 can be **fully stateless** (bots regenerate each load) — simplest and save-proof.

---

## 6. Phased implementation plan

Each phase is independently shippable and visibly improves "aliveness."

### Phase 0 — Foundation: a single sim-player stands in the world
- `SimPlayer` data struct (RefCounted): `name`, `look` (skin/hair/equipment ids), `levels`,
  `hp`, `home`, `personality` seed.
- New `WorldEntity` kind `"sim"`; `MoverRenderer3D` routes `"sim"` → **player rig** (not enemy rig),
  applies the look + equipment via the existing sockets; nameplate from `label`.
- `SimDirector` (autoload or world-owned node): holds the bot list; spawns/despawns by
  `ACTIVE_RADIUS`; per-tick **brain budget**.
- **Exit check:** one named, equipped humanoid idles believably near camp, with a nameplate.

### Phase 1 — Organic movement (the "alive" baseline)
- `SimBrain` v1: a day-in-the-life loop — pick a destination (`find_nearest_poi` / anchor /
  resource area), `find_path` to it, walk the waypoints at player pace, idle, repeat. Random idle
  rolls (2009scape-style) so they don't march robotically.
- Upgrade the wander system to **pathed** movement (reuse `_update_wander`'s state, swap
  straight-line for `find_path` legs).
- **Exit check:** a handful of bots roam roads/towns naturally, never walking into the sea or up
  cliffs.

### Phase 2 — Skilling theater
- Bots route to gather sites and **play the matching gather pose** (chop/mine/fish — poses already
  exist) for a believable duration, then move on. They roll fake XP toward *their own* identity
  levels (visible if inspected); they do **not** touch the real economy.
- Optional flourish: occasional "resource gained" emote / floaty.
- **Exit check:** bots cluster at a forest/mine and look like they're grinding.

### Phase 3 — Social (the Erenshor feel)
- **Speech bubbles:** new lightweight bubble node (copy `show_xp_float`), word-wrapped, above the
  rig, lifetime-scaled to length.
- **Dialogue engine:** `data/sim_players/dialogue.json` (greetings, smalltalk, skill chatter,
  reactions) with `@name` templating like 2009scape. Trigger on: proximity to the player or another
  bot, world events (level-up, a kill nearby, weather), and idle smalltalk. Gate by
  `otherPlayersNearby()`-style checks so chatter is contextual, not constant.
- **Grouping/following (Erenshor):** bots occasionally pair up, follow, or "party" toward a shared
  goal; greet the player and tag along briefly.
- Optional: surface some bot chatter in the chat feed (`EventBus.combat_log`) for MMO ambience.
- **Exit check:** standing in town, you see name-tagged players chatting, grouping, reacting to you.

### Phase 4 — PvP in the Wilds
- Author/confirm a `danger:"wilderness"` biome (Dreadmoor precedent). Add a `WorldGen.is_pvp_at(pos)`
  helper reading the region's `danger` tag.
- Extract `CombatMath` (accuracy + max-hit + damage) from `combat_sim.gd` as a pure function.
- `SimCombat`: lightweight HP exchange between two `SimPlayer`s (and the player) using `CombatMath`
  on tick cadence; reuse `hit_splat` for damage numbers; loser "dies" → ragdoll/topple
  (`_death_anim`), drops a theatrical loot pile, respawns at edge after a timer.
- Player↔bot PvP: in the wilds, bots may aggro the player (and vice-versa) using the same path.
- Risk/skull flavor (visual only in v1).
- **Exit check:** the wilds feel dangerous — bots fight bots, occasionally jump you, drop loot.

### Phase 5 — Persistence, density & polish
- Deterministic identity registry; optional `world.json sims` deltas (respawn timers, reserved
  names, notable "famous" bots).
- **Density curves:** more bots in towns/GE-like hubs, fewer in deep wilderness; population scales
  with `ACTIVE_RADIUS` so the *world* feels full while *concurrent rigged* count stays capped.
- Perf: ship the **animation LOD** gate; verify draw-call budget with the existing perf logger.
- Tiered looks/equipment by level (2009scape `noob`→`intermediate`→… appearance tiers), so a level-3
  bot and a level-90 bot read differently at a glance.

---

## 7. Performance budget (concrete)

| Item | Cost | Mitigation |
|---|---|---|
| Rig draw calls | ~21–40 per humanoid, uninstanced | active-radius cull + `MAX_VISIBLE_SIMS` cap + animation LOD |
| Per-frame pose | ~50 trig ops/mover | LOD gate (skip far/offscreen); negligible at capped counts |
| Brain tick | state machine @ 0.6 s | per-tick brain budget (à la `75/tick`); stagger |
| Pathfinding | AStar over loaded chunks | path **once per leg**, not per frame; stagger repaths; cap length |
| Memory | ~21–40 nodes/rig | capped concurrent rigs; abstract (un-rigged) distant bots |
| Save | none (deterministic) / tiny additive deltas | world-layer only; degrades gracefully |

The engine already sustains ~200–500 animated movers. A capped ~40 visible sim-players is a
**fraction of the existing load**; the budgeted brain and once-per-leg pathing keep CPU flat.

---

## 8. Risks & open questions

**Risks**
- *Draw-call creep* if the visible cap is set too high on low-end machines → keep `MAX_VISIBLE_SIMS`
  conservative + ship animation LOD alongside.
- *Pathfinder churn* if every bot repaths every frame → enforce once-per-leg + staggering.
- *Uncanny robotic motion* → random idle rolls, varied speeds, personality seeds, contextual chatter.
- *Scope creep toward a real economy* → hold the line on the **theater** model for v1.

**Open questions for you**
1. **Realness dial:** pure theater (recommended, cheapest) vs. eventually let bots use the *real*
   GE/economy (big refactor, only worth it if you want player↔bot trading)?
2. **Concurrent target:** what "feels populated" for you — ~20 near towns, ~40, more?
3. **Wilds loot stakes:** when a bot kills you in the wilds, real consequences for the *player*
   (drop items, OSRS-style) or purely cosmetic bot-on-bot stakes?
4. **Chat surface:** speech bubbles only, or also pump bot chatter into the chat feed for MMO ambience?

---

## 9. TL;DR

Doable, and a great fit. Reuse the **mover pipeline** (already proven at hundreds of rigs), borrow
2009scape's **intent-queue brain + per-tick budget**, and follow **Erenshor's theater model** so we
don't fork the economy or break saves. The only active perf lever is **draw calls**, handled by the
same active-radius cull enemies already use plus a visible cap and a cheap animation-LOD gate. Build
it in shippable phases: *stand → roam → skill → socialize → PvP-in-the-wilds → polish.*
