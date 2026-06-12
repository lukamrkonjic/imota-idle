# World Generation Guide

## Determinism

All randomness flows from `WG.hash_i()` / `WG.r01()` (or `FastNoiseLite` seeded
from the world seed). Same seed + same `generatorVersion` → identical chunk.

## Pipeline

A chunk is produced by `world_generator.gd` in fixed pass order. World-layout
passes run conceptually *before* any chunk exists (cached, lazy, seeded);
chunk passes consult them — never the other way around.

| Pass | Module | Scope |
|------|--------|-------|
| Zone layout | `zone_map.gd` | Voronoi level zones over chunk cells (progression rings) |
| Anchor layout | `anchor_planner.gd` | Hub anchors per zone cell + road corridors (see below) |
| Terrain fields | `biome_classifier.gd` | Height / moisture / temperature noise, rivers, lakes |
| Elevation | `elevation_map.gd` | Terraced levels 0..7 from height + ruggedness jitter |
| Tiles + biomes | `biome_classifier.gd` | Per-tile biome classify + weighted ground palette |
| Roads | `anchor_planner.road_byte_at()` | Paints corridor tiles over walkable land only |
| POIs | `poi_placement.gd` | Campsite, villages, hub POIs (anchor mode), caves, shrines… |
| Skill sites | `skill_site_spawner.gd` | Gather nodes by biome skillWeights × elevation density |
| Monsters | `monster_spawner.gd` | Bestiary placement by biome/zone band |
| Caves | `cave_generator.gd` | Negative layers (delegated whole-chunk) |

Rendering (`chunk_renderer.gd`) resamples the classifier per subtile for
blended biome borders and adds cliff shading + road tiles at bake time.

## Elevation

`elevation_map.gd` quantizes the height field into discrete levels:

```
0 deep water, 1 shallow water, 2 lowland, 3 normal land,
4 hill, 5 high hill, 6 mountain, 7 peak
```

- Thresholds and a ruggedness jitter live in
  `data/world/generation_rules.json` → `elevation`.
- Levels are stored per tile on chunks (`chunk.elev_t`, snapshot-persisted)
  and queryable via `WorldGen.elevation_at(world_pos)`.
- Resource placement multiplies biome skillWeights by
  `resources.elevationDensity[skill][level]` — mining climbs with altitude,
  trees thin out toward peaks, fishing stays low. A factor of 0 bans the
  skill at that level.
- The renderer darkens tiles below an elevation rise (cliff shadow), adds a
  thin highlight on top edges, and lightens ground above level 4.

Elevation is currently visual + placement only; it does not block movement.

## Anchors and roads (hub layer)

`anchor_planner.gd` + `data/world/anchors.json` decide which zone Voronoi
cells host hub anchors (mining camp, fishing dock, logger camp, outposts).
Selection is deterministic per cell from ring distance (Chebyshev, in cells,
from home), the cell's site biome, and a seeded chance roll. The home cell
always hosts the starting town (the existing campsite).

- Each anchor's placeholder POI (`pois.json`, `placement.mode: "anchor"`) is
  placed by `poi_placement.gd` in the cell's site chunk; hubs claim the
  chunk's major-POI slot, displacing the generic village there.
- Hub POIs include a bank chest, so auto-banking works from distant regions.
- Road corridors connect home to its nearest hubs
  (`generation_rules.json` → `roads`): sine-wobbled bands of walkable path
  tiles, painted by both the tile pass and the renderer, never over water.
- Future static cities: add an anchor type with a richer POI template — the
  planner already reserves the cell and the site chunk.

## Generator versioning

`WorldStore.GENERATOR_VERSION` is stored in `user://world.json`. Bump it when
you change anything that alters generated output (modules above or the
placement-relevant `data/world/*.json`). Explored-chunk snapshots from older
versions are ignored and regenerate. v2 = elevation + anchors + roads.

## Chunk snapshots (explored land)

When the player first loads a chunk, `WorldGen.snapshot_chunk_if_needed()`
serializes it into `world.json` → `chunkSnapshots`. `WorldGen.get_chunk()`
order: memory cache → snapshot → fresh generation. Unvisited chunks always
use the latest generator; explored chunks stay frozen.

Snapshots round-trip through JSON: keep every value JSON-safe and normalize
typed fields (Vector2i, etc.) at the `world_store.gd` serialize/deserialize
boundary. See "Serialization invariant" in TECH_DEBT.md.

### Invalidating snapshots (developers only)

```gdscript
WorldGen.store.invalidate_snapshots()
WorldGen.chunks.clear()
```

## Tuning

- Biome ranges/palettes/densities: `data/world/biomes.json`
- Elevation bands, cliff shading, per-skill elevation density, roads:
  `data/world/generation_rules.json`
- Anchor types, rings, biome whitelists, chances: `data/world/anchors.json`
- Site/node rules per skill: `data/world/skill_sites.json`

## Debugging

- **In game:** press **F3** to cycle the worldgen overlay:
  biome → elevation → climate (temp/moisture) → anchors (markers, rings,
  road centerlines, zone-cell grid). Header shows seed, chunk, elevation,
  zone name/req/biome. (`scripts/world/worldgen_debug_overlay.gd`)
- **Headless:** `tools/world_debug.tscn` ASCII scanner.
- **Tests:** `tools/validate.gd` Phase 6 (worldgen), 6b (snapshots),
  6c (elevation/anchors/roads), Phase 5 (scene + overlay draw paths).

## Testing

Run after any worldgen change:

```powershell
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\Dev\imota-idle res://tools/validate.tscn
```
