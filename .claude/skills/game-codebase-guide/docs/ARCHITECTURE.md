# Architecture

## Layer model
- **Autoload layer** (`autoload/*.gd`): global singletons — data, state, sims, world gen, save,
  settings, events. Always available, no scene dependency.
- **2D gameplay layer** (`scripts/world/`): `scenes/world.tscn` root `World`
  (`scripts/world/world.gd`) + RefCounted controllers + `WorldEntity` nodes + sim players. This is
  the source of truth for positions, interaction, and gameplay.
- **3D render layer** (`scripts/render/`): `WorldRender3D` coordinator + subsystems. Reads the 2D
  layer each frame and draws a 3D pixel-art world into a low-res SubViewport. Cosmetic only.
- **UI layer** (`scripts/ui/`): the `$HUD` CanvasLayer (`osrs_hud.gd`) + tabs/widgets/popups, driven
  by `EventBus` signals.
- **Content layer** (`data/*.json` + `scripts/content/`): typed wrappers over JSON, indexed by
  `DataRegistry`.

## Boot → gameplay lifecycle
1. **Autoloads `_ready()`** in `project.godot` order: `EventBus` (signals), `DataRegistry`
   (`load_all()` reads every `data/*.json`, builds id indexes), `GameState`, `SkillRegistry`, the
   sims, `WorldGen` (`reg.load_all()`, `store.load_file()` reads `user://world.json`, sets up
   generator + baked world), `SaveManager`, `GameSettings`, `Weather`, `DayNight`, `Audio`.
2. **`scenes/world.tscn` loads** → `World._ready()` (`scripts/world/world.gd`):
   - `_build_scene()` creates child nodes IN CODE: `CanvasModulate`, `UnexploredBackdrop`,
     `Chunks` (ChunkManager), `BakeQueue`, `PerfLogger`, `Entities` (y-sorted), `Player`
     (PlayerAvatar) + its `Camera2D`, `ClickFX`, `Ambience`, `DawnMist`, `WeatherFx`, `BiomeDebug`,
     `WorldRender3D`, and `HUD` (CanvasLayer layer 10). The .tscn itself only contains the root.
   - `_init_controllers()` creates the RefCounted controllers and calls `setup(self)` on each:
     `_entity_spawner`, `_path_ctrl`, `_input_ctrl`, `_activity_ctrl`, `_auto_task_ctrl`,
     `_layer_ctrl`, `_visual_ctrl`, `_sim_director`, `_collision_ctrl`.
   - `_path_ctrl.rebuild()`, HUD `bind_world(self)`, and `player.arrived` connected to
     `_path_ctrl.on_waypoint_reached`.
   - `SaveManager.load_game()` restores `GameState` (and resumes any saved activity).
3. **Player spawn:** `WorldGen.spawn_position()` (or saved `player_pos`); chunks stream around the
   player via `chunk_manager.update_center()`.
4. **Gameplay loop:** `World._process(delta)` (gated by `gameplay_active`) ticks
   `_path_ctrl.process_tick(delta)`, `_visual_ctrl`, `_input_ctrl.update_hover()`,
   `_activity_ctrl.process_tick(delta)`, `_sim_director` (if `sims_enabled`), `_collision_ctrl`, plus
   `render_3d._process` when the 3D layer is active. The autoload sims (`TickSim`, `CombatSim`,
   `RecipeSim`, `PrayerSim`, `FarmingSim`) advance on their own `_process`.

## Input → action → reward (the central pipeline)
`world_input_controller.handle_input()` (left-click) → `entity_at()` picks an entity →
`world.begin_action(entity)` → `world_activity_controller.begin_action()` computes a stand tile by
action type → `world.walk_to_pos()` (`world_path_controller`, A*) → on `player.arrived`
`_path_ctrl._on_path_finished()` → `world_activity_controller.execute_action()` →
starts `TickSim.start_gather` / `CombatSim.start_combat` / `RecipeSim.start_craft` (or opens a UI for
banks/shops). Sims grant XP/items through `GameState`, which emits `EventBus` signals; the HUD
refreshes. Full trace in `DATA_FLOW.md` + `PLAYER_ACTIONS_AND_TOOLS.md`.

## Sims share a base
`TickSim` (gathering), `CombatSim`, `RecipeSim` extend a shared `ActivitySim` base (an `active`
flag, `advance(delta)`, `stop(reason)`, and `save_activity()`/`restore_activity()` so the current
activity survives save/load). `PrayerSim`/`FarmingSim` are passive `Node` autoloads that tick
GameState sub-state. Only one foreground activity runs at a time (starting one stops the others).

## Rendering
`WorldRender3D` (`scripts/render/world_render_3d.gd`) builds a `RenderViewportPresenter` (low-res
SubViewport), terrain mesher + manager, `WorldCameraRig3D`, `WorldAtmosphere` (sun/fog), the
`StaticPropBatcher` (MultiMesh props), `MoverRenderer3D` (animated player/enemy rigs),
`FishingDecor3D` (bubble spots), `PickingProjector3D`, `WorldFx3D`. It runs only when 3D is active
(headless tests use the 2D substrate unless `--force3d`). Meshes are procedural (`prop_meshes.gd`,
`mover_meshes.gd`) or imported `.glb`. See `ANIMATION_AND_SPRITES.md`.

## Persistence
`SaveManager` writes `user://save.json` (`GameState.to_save_dict` + activity + farming) and triggers
`WorldGen.save_world()` → `user://world.json` (explored-chunk snapshots, depletions, obelisks).
`SaveMigration` upgrades old saves by schema version. The baked finite world ships read-only in
`data/world/baked/`. See `SAVE_LOAD_AND_PERSISTENCE.md`.
