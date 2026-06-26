# Safe editing rules

Follow these on every gameplay change. They exist to protect saves, the scene graph, and the
single-owner architecture.

## Reuse, never duplicate
- There is exactly ONE of each core system. Do not add a second: inventory/player-state
  (`GameState`), event hub (`EventBus`), data registry (`DataRegistry`), gather sim (`TickSim`),
  combat sim (`CombatSim`), craft sim (`RecipeSim`), world gen (`WorldGen`), HUD (`osrs_hud.gd`),
  3D coordinator (`world_render_3d.gd`), path controller (`world_path_controller.gd`), activity
  controller (`world_activity_controller.gd`). Check `FILE_OWNERSHIP_MAP.md` before creating anything.
- Content is data. Add items/nodes/enemies/recipes/prayers/crops via `data/*.json`, not new classes.

## Don't rename load-bearing names
Renaming any of these requires updating EVERY reference (and often a save migration). Avoid unless
truly necessary:
- Scene node names in `world.tscn`/`world.gd` (`World`, `HUD`, `Player`, `Entities`, `Chunks`,
  `ClickFX`, `WorldRender3D`).
- Autoload names (`project.godot`).
- `class_name`s used as bare types (renaming also needs `--headless --path . --import` to refresh the
  global-class cache, or you get "Identifier not declared").
- `EventBus` signal names + argument lists.
- `GameState` save keys, `data/*.json` `id`/`name`, skill keys.
- HUD-exposed methods (`open_bank`, `train_style`, …) and controller method names called from
  `world.gd`.

## Saves are sacred
- New persisted field: add to `to_save_dict`, read with a default in `from_save_dict`. Bump
  `SaveMigration.CURRENT_SCHEMA` only if old data needs re-derivation. Add a validate round-trip.
- Never change an existing `id`/`name`/skill key/save key without a migration + alias.
- To rename what the player sees, change `displayName` / `data/rename_map.json` (the frozen `id`/
  `name` stay).
- Honor `suppress` flags (`SaveManager`, `GameSettings`, `WorldGen.store`) in any persistence code so
  tools/tests never write real saves.

## Process discipline
- Before editing a feature, read its `FEATURE_MAP.md` row + system doc, THEN open the real files and
  confirm method/signal names still exist. Don't edit from memory.
- Make the smallest change that fits the existing pattern. Match surrounding style (tabs, typing,
  comment density).
- Before adding an item/tool/action, follow the existing item/tool/action pattern
  (`COMMON_TASK_RECIPES.md`).
- Before changing player behavior, inspect the whole chain: `world_input_controller` →
  `world_activity_controller` → `world_path_controller` → `player_avatar` → (render) `mover_renderer_3d`/
  `mover_rig`. Animation issues are usually in the render layer, not gameplay.
- UI updates via `EventBus` signals, not polling.
- Gameplay logic stays in the 2D layer; `scripts/render/` is cosmetic.

## After editing
- Run `godot --headless --path . res://tools/validate.tscn` → must print `ALL TESTS PASSED`. If you
  can't run it, say so in your report and list what you'd have run.
- For 3D/visual edits also try `-- --force3d` (wiring smoke) and/or a `*_shoot`/`*_preview` tool.
- After adding a new `class_name` or `.glb`, run `--headless --path . --import` once.
- Update the wiki: `FEATURE_MAP.md`, `FILE_OWNERSHIP_MAP.md`, the system doc, and `OPEN_QUESTIONS.md`
  if you changed structure/behavior or discovered something uncertain.

## Git
- Commit/push only when asked. Branch off `main` if needed. End commit messages with the project's
  `Co-Authored-By` line (see existing history).

## Things that look risky (read first)
- `TROUBLESHOOTING.md` (signal/scene-ref/animation gotchas) and `OPEN_QUESTIONS.md` (unverified
  areas, possible duplication) before touching combat formulas, the render camera, save schema, or
  worldgen.
