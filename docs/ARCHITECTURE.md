# Imota Architecture

Godot 4.6 semi-idle incremental RPG. Data-driven content from Bloobs Adventure Idle export; procedural overworld with OSRS-style skills and UI.

## Layer model

| Layer | Role | Location |
|-------|------|----------|
| **Simulation** | Pure game rules, no scene nodes | `autoload/tick_sim.gd`, `combat_sim.gd`, `recipe_sim.gd`, `game_state.gd` |
| **Content** | JSON definitions + indexes | `data/`, `autoload/data_registry.gd`, `scripts/worldgen/world_registry.gd` |
| **World generation** | Deterministic chunk data | `autoload/world_gen.gd`, `scripts/worldgen/*` |
| **Persistence** | Player + world deltas | `autoload/save_manager.gd`, `scripts/worldgen/world_store.gd` |
| **Presentation** | Scene, input, rendering | `scripts/world/world.gd`, `chunk_manager.gd`, `chunk_renderer.gd` |
| **UI** | Displays state, emits intent | `scripts/ui/osrs_hud.gd` |

Communication between layers uses **EventBus** signals. UI and world should not mutate sim state except through autoload APIs.

```
┌─────────────────────────────────────────────────────────────┐
│  scenes/world.tscn                                          │
│    world.gd ──► ChunkManager, PathFinder, WorldEntity       │
│    osrs_hud.gd (CanvasLayer)                                │
└──────────────────────────┬──────────────────────────────────┘
                           │ EventBus / autoload calls
┌──────────────────────────▼──────────────────────────────────┐
│  EventBus │ DataRegistry │ GameState                        │
│  TickSim │ CombatSim │ RecipeSim │ SaveManager              │
│  WorldGen (facade)                                          │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  WorldGenerator → BiomeClassifier, ZoneMap, PoiPlacement,   │
│                   SkillSiteSpawner, MonsterSpawner, CaveGen │
│  WorldRegistry (data/world/*.json)                          │
│  WorldStore (user://world.json)                             │
└─────────────────────────────────────────────────────────────┘
```

## Autoloads

| Name | File | Purpose |
|------|------|---------|
| `EventBus` | `autoload/event_bus.gd` | Global signals: XP, loot, combat log, activity, inventory, world events |
| `DataRegistry` | `autoload/data_registry.gd` | Loads `res://data/*.json`; item/enemy/recipe/node lookup and XP table |
| `GameState` | `autoload/game_state.gd` | Skills, inventory, bank, equipment, gold, HP |
| `TickSim` | `autoload/tick_sim.gd` | Gathering loop (damage-per-action → resources + XP) |
| `CombatSim` | `autoload/combat_sim.gd` | Continuous combat, drops, respawn |
| `RecipeSim` | `autoload/recipe_sim.gd` | Crafting/production loop |
| `WorldGen` | `autoload/world_gen.gd` | Chunk cache, queries, depletion, obelisks |
| `SaveManager` | `autoload/save_manager.gd` | `user://save.json`, offline progress, triggers world save |
| `GameSettings` | `autoload/game_settings.gd` | `user://settings.json`: UI scale, volume, vsync, FPS limit, toggles |

`SaveMigration` (`autoload/save_migration.gd`) is a static helper class, not an autoload.

## System reference

### DataRegistry

Loads Bloobs export JSON on startup. Indexes items (by display name key), enemies, recipes (`skill/name`), gather nodes (per skill array), tools, XP table. Builds `recipes_by_skill` and `food_hp` from cooking outputs.

**Type:** Content / simulation support (read-only at runtime).

**Stable IDs:** Assigns internal ids at load (`item.logs`, `node.woodcutting.regular_tree`, etc.) and resolves aliases for save compatibility.

### GameState

Single source of truth for player state. All inventory/bank/equip mutations emit EventBus signals. Starter kit on reset. HP regen out of combat.

**Type:** Simulation + persistence (serializes via `to_save_dict` / `from_save_dict`).

### TickSim

Gathering: accumulates timer per frame; each action applies tool `progress` as node damage; every 100 damage awards one resource + node XP. Mutually exclusive with CombatSim and RecipeSim.

**Type:** Simulation.

### CombatSim

3s player attack interval; enemy attacks on cooldown. Accuracy, crit, combat triangle, drop rolls. Trains combat skills + beastmastery.

**Type:** Simulation.

### RecipeSim

Validates recipe inputs, waits `recipe.time`, consumes inputs, grants output + XP. Auto-repeats until inputs or inventory space run out.

**Type:** Simulation.

### WorldGen

Facade over world subsystems. Owns `WorldRegistry`, `WorldGenerator`, `WorldStore`, in-memory chunk cache.

- `get_chunk(layer, cx, cy)` — snapshot first, else generate, apply depletions, cache.
- Queries: nearest site/station/POI, zone/biome at position, spawn position.
- Ticks site respawns from WorldStore depletion timers.

**Type:** World generation + persistence facade.

### WorldStore

Persists player-made world changes to `user://world.json`: seed, obelisks, visited zones, depleted sites, **chunk snapshots** (explored terrain).

Static terrain is deterministic from seed; snapshots preserve explored chunks across generator changes.

**Type:** Persistence.

### WorldGenerator

Orchestrates one chunk: terrain fields → elevation → tiles/biomes → roads → POIs → skill sites → monsters. Surface uses BiomeClassifier + ElevationMap + AnchorPlanner + placement passes; negative layers use CaveGenerator. See docs/WORLDGEN_GUIDE.md for the full pass table.

**Type:** World generation (pure data).

### ElevationMap / AnchorPlanner

`elevation_map.gd`: terraced elevation levels 0..7 from the height field (stored per tile, drives resource density and cliff rendering). `anchor_planner.gd`: high-level layout — hub anchors per zone cell (data/world/anchors.json) and road corridors from home to nearby hubs. Both deterministic, both consulted by chunk passes and the renderer. F3 in game opens the worldgen debug overlay.

**Type:** World generation (layout layer).

### BiomeClassifier

Simplex noise → height/moisture/temperature. Picks biome from `data/world/biomes.json` rules. River/lake carving, spawn-area shaping, tile byte assignment.

**Type:** World generation (simulation of terrain fields).

### SkillSiteSpawner

Places gather sites from biome skill weights, zone level band, `skill_sites.json` rules. Special cases: home trees, forest patches, waterline trees, fishing at water edges.

**Type:** World generation.

### ChunkManager

Scene child of `world.gd` (not autoload). Streams 5×5 chunks around player. Bakes ground via ChunkRenderer. Signals `chunk_loaded` / `chunk_unloaded`.

**Type:** Rendering + scene lifecycle.

### World scene (`world.gd` + controllers)

`world.gd` owns scene composition and delegates to focused controllers:

| Controller | File | Responsibility |
|------------|------|----------------|
| Entity spawner | `world_entity_spawner.gd` | Chunk load/unload, sites, POIs, monsters, decor |
| Path | `world_path_controller.gd` | A* rebuild, walk targets, long-distance re-path |
| Input | `world_input_controller.gd` | Mouse clicks, zoom, hover text |
| Activity | `world_activity_controller.gd` | Gather/combat/station actions, aggro, depletion |
| Auto task | `world_auto_task_controller.gd` | Auto-gather, auto-bank, auto-station |
| Layer | `world_layer_controller.gd` | Cave/surface switching, obelisks, teleport, death respawn |
| Visual | `world_visual_controller.gd` | Zone/biome announcements, darkness, label LOD, XP float |

**Type:** Presentation + input + orchestration.

### Procedural art (`scripts/world/art/`)

Pixel art is split into modules (not one monolithic `iso_sprites.gd`):

| Folder | Contents |
|--------|----------|
| `art/core/` | `pixel_palette.gd`, `pixel_draw.gd` — shared drawing primitives |
| `art/characters/` | `player_art.gd`, `enemy_art.gd` |
| `art/trees/` | `tree_art.gd` — all tree species |
| `art/nodes/` | `rock_art.gd`, `bush_art.gd`, `fish_art.gd`, `gather_node_art.gd` |
| `art/structures/` | POI/station sprites (tent, chest, obelisk, cave, etc.) — one file each |
| `art/ground_decor/` | `grass_decor.gd`, `stick_decor.gd`, `shrub_decor.gd`, … + `ground_decor_art.gd` router |
| `art/iso_sprites.gd` | Public facade; `scripts/world/iso_sprites.gd` re-exports for compatibility |

### OSRS HUD (`osrs_hud.gd`)

Procedural OSRS-style UI: hover, minimap, HP orb, inventory/equipment/skills panel, chat, popups. Listens to EventBus; `bind_world(w)` for world actions.

**Type:** UI only.

## Data files

| Path | Keys | Content |
|------|------|---------|
| `data/items.json` | Display name → item dict | Stats, value, reqs, combat fields |
| `data/enemies.json` | Display name → enemy dict | Level, HP, drops, XP |
| `data/recipes.json` | `skill/name` → recipe | Inputs, output, time, XP |
| `data/gather_nodes.json` | skill → node array | Level, XP, output items |
| `data/tools.json` | Tool name → shop entry | Skill, level, progress |
| `data/world/*.json` | Various | Biomes, sites, monsters, POIs, caves |

Import pipeline: `tools/import_bloobs_data.gd` from Unity export.

## Saves

| File | Manager | Contents |
|------|---------|----------|
| `user://save.json` | SaveManager | Player state, activity, schemaVersion |
| `user://world.json` | WorldStore | Seed, obelisks, visited zones, depletions, chunk snapshots |

## Tests

Headless suite: `godot --headless --path <project> res://tools/validate.tscn`

Phases 0–6 cover data, gathering, combat, save roundtrip, recipes, food/shop/offline, world scene, worldgen determinism.

## Scene entry points

| Scene | Script | Use |
|-------|--------|-----|
| `scenes/world.tscn` | `world.gd` | **Playable game** |
| `scenes/main.tscn` | `main_ui.gd` | Legacy Melvor UI (validate smoke only) |
| `tools/validate.tscn` | `validate.gd` | CI / headless tests |
| `tools/world_debug.tscn` | `world_debug.gd` | ASCII world-gen scanner |
