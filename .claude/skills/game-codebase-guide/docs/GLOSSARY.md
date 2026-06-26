# Glossary

Project-specific terms, grounded in the code.

- **Autoload** — a Godot singleton from `project.godot [autoload]` (e.g. `GameState`, `EventBus`).
  Globally accessible; the backbone of the game. See `AUTOLOADS_AND_GLOBALS.md`.
- **EventBus** — `autoload/event_bus.gd`, the stateless signal hub all systems use to communicate.
- **GameState** — `autoload/game_state.gd`, all player state (skills/inventory/bank/equipment/coins/
  hp/prayer/run/slayer/pos) and the save serialization (`to_save_dict`/`from_save_dict`).
- **DataRegistry** — `autoload/data_registry.gd`, loads all `data/*.json` and resolves items/nodes/
  recipes/enemies by stable id or legacy name.
- **Stable id** — an immutable content id like `item.acadia_logs` / `enemy.1001` (prefixes in
  `scripts/content/content_id.gd`). Saves store ids, never display names. Never change one.
- **`name` vs `displayName`** — `name` is the frozen legacy key (load-bearing, never rename);
  `displayName` is what the player sees (rewritable via `data/rename_map.json`).
- **Sim** — an `ActivitySim`-based autoload that runs a timed loop: `TickSim` (gather), `CombatSim`,
  `RecipeSim`. Only one foreground sim runs at a time. `PrayerSim`/`FarmingSim` are passive.
- **ActivitySim** — shared base for the foreground sims (`active`, `advance`, `stop`,
  `save_activity`/`restore_activity`).
- **WorldEntity** — `scripts/world/world_entity.gd`, a clickable world object (tree/rock/fish/enemy/
  station/npc/sim/…) carrying a `kind` + an `action` dict.
- **Action dict** — the `action` on a `WorldEntity`: `{type:"gather"|"enemy"|"station"|"npc"|…, …}`.
  Drives the click→walk→act pipeline.
- **Site** — a gather resource entry in `chunk.sites` (`{skill,node,level,kind,tx,ty,resources,
  respawn_sec,available,…}`). Spawned by `skill_site_spawner.gd`.
- **Node (gather node)** — a harvestable definition in `data/gather_nodes.json` (`GatherNodeDef`).
  NOT a Godot scene-tree node. Context disambiguates.
- **Chunk** — a square tile region (`scripts/worldgen/chunk.gd`) holding tiles/biomes/elev + sites/
  pois/monsters. Streamed by `ChunkManager`.
- **Baked world** — the authored finite continent in `data/world/baked/<id>.world` (read-only).
  "The world is baked" = changes need a re-bake (`tools/world_bake.tscn`).
- **Snapshot** — a saved explored-chunk delta in `user://world.json` (`WorldStore`).
- **Controller** — a RefCounted helper on `world.gd` (`_input_ctrl`, `_path_ctrl`, `_activity_ctrl`,
  …). NOT a scene node.
- **Tool slot / progress** — gather tools sit in slots Axe/Pickaxe/Rod/Lens; `progress` (from
  `data/tools.json`) sets gather speed; `GameState.tool_progress(skill)` gates `start_gather`.
- **Stand tile / `exact_stand`** — where the player stops to act (adjacent to a node, or the water's
  edge for fishing). `exact_stand` makes the path end exactly on that tile.
- **Work pose** — the per-skill gather animation in `mover_rig._pose_gather_work`
  ("chop"/"mine"/"fish_rod"/"fish_kneel"/"forage"/"trap"/"steal").
- **Mover** — an animated 3D rig (player/enemy) drawn by `mover_renderer_3d.gd`. **Decor/prop** —
  static batched mesh from `prop_meshes.gd`/`static_prop_batcher.gd`.
- **Presenter / pixelation** — the low-res SubViewport upscale + palette posterize in
  `render_viewport_presenter.gd` that makes the pixel-art look.
- **`fish_school` node** — an invisible water-decor marker per fishing spot; rendered as bubbles by
  `FishingDecor3D` (the old static mesh is skipped).
- **Zone / layer** — a level band region / a vertical world level (surface = layer 0, caves below).
- **`suppress`** — flags on `SaveManager`/`GameSettings`/`WorldGen.store` that stop tools/tests from
  writing real save files.
- **validate.tscn** — `tools/validate.gd`, the headless test suite; the gate (`ALL TESTS PASSED`).
