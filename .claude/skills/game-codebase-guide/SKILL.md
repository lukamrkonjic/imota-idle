---
name: game-codebase-guide
description: >
  REQUIRED before adding, changing, or debugging ANY gameplay functionality in this
  Godot 4.6 game (Imota). Explains where every system lives, how systems talk to each
  other, and the exact patterns to extend them without inventing parallel systems or
  breaking saves. Use for: items, tools, inventory, skills, gathering, mining, fishing,
  combat, stations/recipes, prayer, farming, movement, camera, world/chunks, NPCs/sims,
  UI/HUD, save/load, animations, the world editor, and 3D rendering.
---

# Imota Codebase Guide (skill)

You are editing **Imota**, an OSRS-inspired semi-idle RPG in **Godot 4.6** (GDScript only).
This skill is the map. The wiki lives in `.claude/skills/game-codebase-guide/docs/`. Treat it as
authoritative; it is grounded in real files. When code and docs disagree, the code wins — then
**fix the doc**.

## When this skill is mandatory

Use it BEFORE any task that adds/changes/debugs gameplay: a new item/tool/node/enemy/recipe, a
player action or animation, a UI panel, a save field, world/chunk content, movement/camera, or any
"why does X behave like Y" debugging. For pure docs/comment typo fixes you may skip it.

## Core architecture in 8 lines (read DATA_FLOW.md + ARCHITECTURE.md for detail)

1. **Autoloads are the backbone** (see `project.godot [autoload]`): `EventBus` (signal hub, no
   state), `GameState` (all player state + the save dict), `DataRegistry` (loads every `data/*.json`,
   resolves stable ids), `SkillRegistry`, the sims `TickSim`/`CombatSim`/`RecipeSim`/`PrayerSim`/
   `FarmingSim`, `WorldGen`, `SaveManager`, `GameSettings`, `Weather`, `DayNight`, `Audio`.
2. **Content is data, not code.** Items/enemies/recipes/nodes/skills/prayers live in `data/*.json`
   and are looked up by `DataRegistry`. Add content by editing JSON, not by writing new classes.
3. **The world is one scene**, `scenes/world.tscn` → root `World` (`scripts/world/world.gd`). Almost
   everything (player, chunks, HUD, controllers, 3D renderer) is built in code in `world.gd`, not in
   the .tscn. The HUD is a `CanvasLayer` at `$HUD` (`scripts/ui/osrs_hud.gd`).
4. **Controllers are RefCounted helpers** on `world.gd` (`_input_ctrl`, `_path_ctrl`,
   `_activity_ctrl`, `_auto_task_ctrl`, `_layer_ctrl`, `_visual_ctrl`, `_sim_director`,
   `_collision_ctrl`, `_entity_spawner`) — NOT scene nodes.
5. **Input is code, not InputMap.** There is no `[input]` section. Clicks/keys are handled in
   `scripts/world/world_input_controller.gd` + `osrs_hud.gd`, with remappable keys via `GameSettings`.
6. **Interaction lifecycle:** click entity → `world.begin_action` → `world_activity_controller`
   picks a stand tile → walk (`world_path_controller`) → on arrival `execute_action` starts the right
   sim (TickSim/CombatSim/RecipeSim). Sims grant XP/items via `GameState` and fire `EventBus` signals
   the HUD listens to.
7. **The 3D look is a separate render layer** (`scripts/render/`, coordinator
   `world_render_3d.gd`). It reads the 2D entity/sim state and draws it; gameplay logic lives in the
   2D layer. Meshes are procedural (`prop_meshes.gd`, `mover_meshes.gd`) or `.glb` (see GLB guide).
8. **Saves must never break.** `GameState.to_save_dict`/`from_save_dict` + `SaveMigration` (schema
   versions) + content aliases. Every load path degrades gracefully. `tools/validate.tscn` gates it.

## REQUIRED workflow (follow in order)

1. **Classify the task.** Which feature area? (item / tool / node / enemy / recipe / skill / combat /
   movement / camera / UI / save / world / NPC / animation / render / editor).
2. **Read `docs/INDEX.md` and `docs/FEATURE_MAP.md`.** Find the feature's row → its primary files,
   signals, data, dependents.
3. **Read the matching system doc(s)** from `docs/` (e.g. `INVENTORY_ITEMS_AND_RESOURCES.md`,
   `PLAYER_ACTIONS_AND_TOOLS.md`, `SAVE_LOAD_AND_PERSISTENCE.md`, `UI_AND_HUD.md`,
   `WORLD_MAP_AND_NODES.md`, `ANIMATION_AND_SPRITES.md`, `SIGNALS_AND_EVENTS.md`).
4. **Inspect the ACTUAL source files** named in those docs before editing. Confirm method/signal
   names still exist. Never edit from memory of the doc alone.
5. **Read `docs/SAFE_EDITING_RULES.md`** and make the **smallest** change that fits the existing
   pattern. Reuse the existing manager/signal/resource. Do NOT create a parallel system. For a
   step-by-step, use `docs/COMMON_TASK_RECIPES.md`.
6. **Run validation.** `godot --headless --path . res://tools/validate.tscn` must print
   `ALL TESTS PASSED`. For 3D/visual changes, also smoke-test with `--force3d`. If you can't run it,
   say so explicitly in your report.
7. **Update the wiki** if you changed architecture, file ownership, signals, save fields, or feature
   behavior (`FEATURE_MAP.md`, `FILE_OWNERSHIP_MAP.md`, the relevant system doc, and `OPEN_QUESTIONS.md`).
8. **Report** changed files, what validation you ran + its result, and any risks.

## Hard rules (full list in SAFE_EDITING_RULES.md)

- **Add content via `data/*.json`**, not new code. Items keep a frozen `name` + stable `id`; rename
  only `displayName` (via `data/rename_map.json`) — never the `id`/`name` (breaks saves).
- **Reuse, don't duplicate.** There is exactly one of each: inventory (`GameState`), event hub
  (`EventBus`), gather sim (`TickSim`), combat sim (`CombatSim`), craft sim (`RecipeSim`), data
  registry (`DataRegistry`), world generator (`WorldGen`), HUD (`osrs_hud.gd`), 3D coordinator
  (`world_render_3d.gd`). Do not add a second.
- **Never rename** a node in `scenes/world.tscn` (`World`, `HUD`, …), an `EventBus` signal, a
  `GameState` save key, a `data/*.json` `id`/`name`, or an autoload — unless you update every
  reference AND add a save migration.
- **Saves:** new persisted field → add to `to_save_dict` + a defaulted read in `from_save_dict`; bump
  `SaveMigration.CURRENT_SCHEMA` only if old saves need re-derivation. Test the round-trip in
  `tools/validate.gd`.
- **UI updates via `EventBus` signals**, not polling — connect a refresh handler.
- **Gameplay is the 2D layer; the 3D renderer is cosmetic.** Don't put game logic in `scripts/render/`.

## Doc index (load what the task needs)

- `PROJECT_OVERVIEW.md` — what the game is, engine, run/test commands.
- `ARCHITECTURE.md` — boot → world load → spawn → gameplay loop; layers.
- `FEATURE_MAP.md` — every system: files, classes, scenes, methods, signals, data, deps. **Start here.**
- `GODOT_SCENE_MAP.md` — `world.tscn` tree + code-built nodes; what not to rename.
- `AUTOLOADS_AND_GLOBALS.md` — every autoload's role + key API.
- `DATA_FLOW.md` — how a click/tick flows through the systems.
- `SIGNALS_AND_EVENTS.md` — full `EventBus` signal list: emitter → listener.
- `INPUT_ACTIONS.md` — code-based input + `GameSettings` keybinds (no InputMap).
- `INVENTORY_ITEMS_AND_RESOURCES.md` — items/tools/recipes/`DataRegistry`/ids/renames.
- `PLAYER_ACTIONS_AND_TOOLS.md` — the click→walk→act pipeline, tools, gather/combat/craft start.
- `UI_AND_HUD.md` — HUD build, tabs, widgets, popups, refresh signals.
- `SAVE_LOAD_AND_PERSISTENCE.md` — save format, migration, save-safety contract.
- `WORLD_MAP_AND_NODES.md` — WorldGen, chunks, sites, POIs, baked world, the editor.
- `ANIMATION_AND_SPRITES.md` — 3D render pipeline, rigs, gather/combat poses, decor, shaders.
- `ADDING_NEW_FEATURES.md` — decision tree: where does my feature go?
- `SAFE_EDITING_RULES.md` — the rules above, expanded.
- `COMMON_TASK_RECIPES.md` — step-by-step for frequent tasks.
- `TROUBLESHOOTING.md` — common breakages + how to debug.
- `OPEN_QUESTIONS.md` — unverified/risky areas; check before trusting.
- `FILE_OWNERSHIP_MAP.md` — which file owns which responsibility.
- `GLOSSARY.md` — project terms.

Also: `docs/` at repo root (NOT this wiki) has human design docs (`ARCHITECTURE.md`, `COMBAT.md`,
`SAVE_FORMAT.md`, `GLB_IMPORT_GUIDE.md`, `SHADOWS.md`, `ART_GUIDE.md`, `WORLDGEN_GUIDE.md`). They are
useful background but may lag the code; this wiki is the AI-facing source of truth.
