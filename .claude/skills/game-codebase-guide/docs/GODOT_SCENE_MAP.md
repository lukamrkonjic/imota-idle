# Godot scene map

## Scenes that ship in the game
- **`scenes/world.tscn`** — the ONLY gameplay scene (`run/main_scene`). Its `.tscn` contains just the
  root node `World` (Node2D, script `scripts/world/world.gd`). Everything else is created in code in
  `World._build_scene()`. Do not expect child nodes in the editor — read `world.gd`.
- `scenes/preview/pixel3d_preview.tscn` — a render/preview sandbox (not gameplay).

Everything under `tools/*.tscn` is a dev tool/test harness (validate, world_editor, *_preview,
*_shoot, smoke tests). They are NOT part of the shipped game but are how you test it.

## `world.tscn` runtime node tree (built in `world.gd`)
Root `World` (Node2D) creates these children in code (names are referenced by code — **do not
rename without updating `world.gd`**):

| Node | Type | Script / role |
|---|---|---|
| `CanvasModulate` | CanvasModulate | ambient tint |
| `UnexploredBackdrop` | Node2D | fog-of-war backdrop (`UnexploredBackdrop`) |
| `Chunks` | ChunkManager | terrain streaming (`scripts/worldgen/chunk_manager.gd`) → `world.chunk_manager` |
| `BakeQueue` | Node | async prop bake queue |
| `PerfLogger` | Node | perf metrics |
| `Entities` | Node2D (y-sort) | parent of all `WorldEntity` + sims → interaction layer |
| `Player` | PlayerAvatar | `scripts/world/player_avatar.gd` → `world.player`; owns the `Camera2D` |
| `ClickFX` | Node2D | transient click markers / projectiles / hitsplats |
| `Ambience` | Node2D | ambient audio/particles |
| `DawnMist` | CanvasLayer | dawn-mist shader overlay |
| `WeatherFx` | CanvasLayer | rain/snow particles |
| `BiomeDebug` | Node2D | F6 biome debug overlay |
| `WorldRender3D` | Node | `scripts/render/world_render_3d.gd` → `world.render_3d` (null in pure 2D/headless) |
| `HUD` | CanvasLayer (layer 10) | `scripts/ui/osrs_hud.gd` → `world.hud` |

The 3D world (terrain, props, movers, water, bubbles) is NOT in this tree — it lives inside the
`SubViewport` created by `RenderViewportPresenter` under `WorldRender3D`.

## Do-not-rename list (hardcoded references)
- Node names above (`World`, `HUD`, `Player`, `Entities`, `Chunks`, `ClickFX`, `WorldRender3D`).
- Autoload names in `project.godot` (`EventBus`, `GameState`, …).
- `class_name`s used as bare types across files (e.g. `WorldEntity`, `PlayerAvatar`,
  `WorldRender3D`, `FishingDecor3D`, `ItemDef`, `GatherNodeDef`, …). Renaming a `class_name` breaks
  every bare reference AND requires regenerating the Godot global-class cache
  (`--headless --path . --import`).
- `EventBus` signal names, `GameState` save keys, `data/*.json` `id`/`name` fields.

## Adding a node/scene
- Prefer adding to the code-built tree in `world.gd` (a new controller as RefCounted, or a child node
  in `_build_scene()`), matching the existing pattern. Don't add a competing root scene.
- A new prop/visual usually does NOT need a node — it's a `WorldEntity` (data) rendered by the 3D
  layer, or a procedural mesh in `prop_meshes.gd`. See `WORLD_MAP_AND_NODES.md` /
  `ANIMATION_AND_SPRITES.md`.
