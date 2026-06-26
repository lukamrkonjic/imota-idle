# World, map & nodes

## WorldGen (`autoload/world_gen.gd`)
The world source of truth. Owns:
- `reg` — `WorldRegistry` (`scripts/worldgen/world_registry.gd`): loads `data/world/*` (biomes, pois,
  skill_sites, monsters, stamps, tree_species, …) and builds `node_table` (skill → node entries),
  `skill_cfg(skill)`, the world `spec` (finite/blank).
- `store` — `WorldStore` (`scripts/worldgen/world_store.gd`): `user://world.json` (snapshots,
  depletions, obelisks, explored).
- `baked` — `BakedWorldStore` (`scripts/worldgen/baked_world_store.gd`): the authored continent in
  `data/world/baked/<id>.world`.
- `chunks` — runtime cache.
Key API: `get_chunk(layer, cx, cy)` (baked → snapshot → generated, then applies depletions),
`spawn_position()`, `find_nearest_site/poi/station(...)`, `deplete_site(chunk, i)`, `save_world()`,
`surface_tile_id(gx, gy)`, `zone_at(pos)`, `is_walkable_world(pos)`.

> **The world is baked.** Terrain/spawn/authored changes require running the bake (`imota bake` /
> `tools/world_bake.tscn`) to take effect in play. See repo `docs/WORLDGEN_GUIDE.md`.

## Chunks (`scripts/worldgen/chunk.gd`, `chunk_manager.gd`)
A chunk holds per-tile arrays (`tiles`, `biomes`, `parent_biomes`, `sub_biomes`, `elev`, collision),
plus `zone`, `safe`, and content arrays: `sites` (gather), `pois`, `monsters`. `tile_world(tx,ty)` →
world pos. `ChunkManager` (the `Chunks` node) streams chunks around the player (`update_center`),
`loaded_chunks()`, `data_chunks()`. Entities are spawned from chunk content by
`scripts/world/world_entity_spawner.gd`.

## Gather sites (`scripts/worldgen/skill_site_spawner.gd` + `data/world/skill_sites.json`)
Each `chunk.sites` entry: `{skill, node, level, kind, tx, ty, resources, remaining, respawn_sec,
available, respawn_at}` (+ `fish_tx/fish_ty` for fishing). `kind` comes from `skill_sites.json` per
skill: woodcutting→`tree`, mining→`rock`, fishing→`fish`, foraging→`bush`, hunter→`burrow`,
thieving→`stall`. `skill_sites.json` also controls biomes, cave layers, `resources`, `respawnSec`,
`waterEdge`. `SkillSiteSpawner.populate(chunk, occupied)` places them (forests, waterlines, POI
rings, general scatter). The spawner keeps authored (non-`ambient`) sites and regrows ambient ones.

## Fishing spots
A fishing site is a `WorldEntity kind="fish"` on the shore; the adjacent water tile is `fish_tx/
fish_ty`. `scripts/world/fishing_helper.gd`: `water_tile`/`water_tile_global`, `can_cast_from`,
`best_stand` (the walkable tile at the water's edge), `water_world_pos`. Each fishing site also gets
an invisible `fish_school` water-decor node (`world_entity_spawner._spawn_fishing_school`) which the
3D layer renders as animated bubbles (`scripts/render/fishing_decor_3d.gd`).

## POIs, settlements, roads, zones
`data/world/pois.json`, `settlement_templates.json`, `road_styles.json`, `zone_names.json`,
`cave_layers.json`. POIs spawn stations/landmarks/obelisks/cave entrances as entities
(`world_entity_spawner._spawn_poi_part`). Zones gate level bands (validate checks site/monster levels
fit their zone). Caves are other `layer`s reached by descend/ascend (`world_layer_controller.gd`).

## Minimap & world map (UI)
`scripts/ui/widgets/minimap.gd` (HUD minimap; click → `navigate_requested`) and the full-screen world
map (toggled with M). They read WorldGen/chunk data + `explored`.

## The world editor (`tools/world_editor.gd`)
Authoring tool (`tools/world_editor.tscn`). Tool groups: Paint (biome/terrain), Sculpt (elevate/
smoothen), Nature (trees/clutter/stamp), Build (structure/settlement/road), **Skills**, Live
(creatures/spawn), Edit (pan/erase). The **Skills** group has one button per skill (Combat +
Woodcutting/Mining/Fishing/Foraging/Hunter/Thieving); selecting one shows that skill's nodes/creatures
in the options panel and clicking a tile places a functional gather site (`_place_skill_site`, sets
fish water for fishing) or monster pack. Saves to the worldspec (Ctrl+S). Placed sites are authored
(non-ambient) so they persist.

## Adding world content
- New gather node / rock / fish: edit `data/gather_nodes.json` (+ item + optional `skill_sites.json`
  biome rule), then re-bake or place via the editor. Recipe in `COMMON_TASK_RECIPES.md`.
- New POI/station/landmark: `data/world/pois.json` + handle its `kind` in the spawner + a 3D mesh
  (procedural in `prop_meshes.gd` or a `.glb`).
- Always run `validate.tscn` (Phase 5/6 cover worldgen, zone bands, fishing-touches-water,
  snapshots).
