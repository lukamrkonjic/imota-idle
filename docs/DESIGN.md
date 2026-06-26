# Imota — design pillars & decision index

The "read this first" map of what Imota is and why it's built the way it is. When
a decision shapes how features should be designed or implemented, it belongs in
one of these docs — start here, then follow the link.

| Topic | Doc |
|---|---|
| **Game vision & pillars** | this file |
| **World vision** — tiles, living non-circular geography, seamless expansion | [WORLD_DESIGN.md](WORLD_DESIGN.md) |
| **World generation** — determinism, passes, snapshots, baking | [WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md) |
| **3D camera / terrain coverage** — low forward views, streaming and fallback | [RENDER_DECISIONS.md](RENDER_DECISIONS.md) |
| **Isometric pixel art** — drawing/adding props, houses, structures, decor | [ART_GUIDE.md](ART_GUIDE.md) |
| **Shadows** — the one global stylized sun | [SHADOWS.md](SHADOWS.md) |
| **Code architecture** — sims, autoloads, UI split | [ARCHITECTURE.md](ARCHITECTURE.md), [../README.md](../README.md) |
| **Content authoring** — items/nodes/enemies/recipes | [CONTENT_GUIDE.md](CONTENT_GUIDE.md) |
| **Data provenance & gaps** | [DATA_GAPS.md](DATA_GAPS.md) |
| **Save format & migration** | [SAVE_FORMAT.md](SAVE_FORMAT.md) |

## What Imota is

A **single-player, semi-idle, OSRS-inspired incremental RPG** in Godot 4. It
recreates the systems and numbers of **Bloobs Adventure Idle** (its skills,
items, recipes, enemies and XP curve were imported from a data export — see
[DATA_GAPS.md](DATA_GAPS.md)) and combines them with **OSRS-style skilling** and
a **stronger idle layer**, all set in a **living, explorable, RuneScape-like
world** you walk through rather than a menu of activities.

It is Steam-bound and standalone; treat it as its own game, not a mod.

## Design pillars

These are the load-bearing decisions. New features should reinforce them.

1. **OSRS-style breadth of skills, classic XP curve.** 16 skills across
   gathering, artisan and combat (below). The level/XP table runs to 1000 and is
   the OSRS-style exponential curve. Gear/tools gate by level; combat uses the
   familiar attack/strength/defence/hitpoints/ranged/magic split.

2. **Faithful to the Bloobs content lineage.** Item stats, recipe inputs/outputs,
   drop tables, node yields and enemy numbers come from the imported data, not
   invented per-feature. When adding content, extend the data files
   ([CONTENT_GUIDE.md](CONTENT_GUIDE.md)); don't hard-code lists in code.

3. **More idle than OSRS.** The world keeps playing itself: auto-gather and
   auto-task controllers walk the player to the nearest valid node and keep
   working; the three sims advance on a fixed timestep; and **offline progress**
   fast-forwards the active activity on load (12h cap). The player sets an intent
   and the game grinds it out — see "The idle model" below.

4. **One simulation layer, dumb UI.** All game truth lives in the autoload sims
   ([ARCHITECTURE.md](ARCHITECTURE.md)); the UI only listens to `EventBus` and
   renders. Never put game logic in a Control. This keeps headless tests
   (`tools/validate.tscn`) authoritative.

5. **A living, expandable world — not a circle, not a menu.** The map is a
   handcrafted irregular continent you explore, with difficulty radiating
   outward and room to bolt on new regions, biomes and whole new worlds as
   content grows — the way RuneScape expanded over time. This is important enough
   to have its own doc: [WORLD_DESIGN.md](WORLD_DESIGN.md).

6. **Coherent procedural pixel art.** Every prop/structure/creature is drawn in
   code in one isometric pixel style, lit by one global sun, from one palette —
   no sprite assets, no per-object lighting. See [ART_GUIDE.md](ART_GUIDE.md) and
   [SHADOWS.md](SHADOWS.md).

## The skills

| Group | Skills |
|---|---|
| Gathering | woodcutting, mining, fishing, foraging, thieving |
| Artisan | smithing, cooking, crafting, fletching, firemaking |
| Combat | attack, strength, defence, hitpoints, ranged, magic, beastmastery |

Gathering skills consume world nodes (trees/rocks/fishing spots/bushes) that
deplete and respawn; artisan skills convert items via recipes; combat resolves
continuously against world creatures. All three are driven by the sims, so all
three idle.

## The idle model

| System | Role |
|---|---|
| `TickSim` | gathering loop — tool power damages a node, awards per threshold |
| `CombatSim` | continuous combat — timed player/enemy swings, drops, respawn |
| `RecipeSim` | production — inputs → timer → output + XP, auto-repeat |
| `world_auto_task_controller` / `world_activity_controller` | walk to and keep working the nearest valid node/target for the chosen activity |
| `SaveManager` offline progress | on load, fast-forward the active activity by time-away (capped at 12h, stepped) |

Design consequence: **every activity must be expressible as "set it and it keeps
running"** — gather, fight, or craft. If a feature can't idle, it fights pillar 3;
prefer designs where the player picks a target/recipe and the sim does the rest.

## Where things live

- Game data: `data/*.json` (items, enemies, recipes, gather_nodes, tools, xp_table).
- Sims/state: `autoload/*.gd`.
- World/render: `scripts/world/**`, `scripts/worldgen/**`, `shaders/`.
- World authoring: `data/world/**` + the editor `tools/world_editor.tscn`.
- Tests: `tools/validate.tscn` (run headless after any code/data change).
