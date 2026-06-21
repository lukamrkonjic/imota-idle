# World Generation Guide

## Aldreth: authored land mask → biomes → baked chunks

Aldreth's **coastline is hand-authored**, not procedural. The pipeline:

```
data/world/source/aldreth_atlas.png   (illustrated outline map — importer input only)
  └─ tools/world_trace.gd  →  data/world/masks/aldreth_land.png   (clean binary land/water mask)
                              data/world/masks/aldreth_rivers.png  (inland water)
                              aldreth_trace_preview.png (approve) + aldreth_mask.json (mapping)
data/world/worldspec/aldreth.json   (bounds, regions=biome influence, roads, anchors)
  └─ BiomeClassifier samples the mask → coast → climate/region biomes → subBiome stamps
  └─ FiniteWorldGenerator rasterizes roads/rivers + structures
       └─ tools/world_bake.gd  →  data/world/baked/aldreth.world (+ id table) + aldreth_map.png
```

- **The mask is the single source of the continent SHAPE.** `BiomeClassifier._landmass()`
  precomputes a signed-distance field from `aldreth_land.png` and samples it (positive = tiles
  inland, negative = offshore); `_MASK_SHORE`/`_MASK_SLOPE` set the beach width. No mask → the
  old ellipse-continent fallback runs (other specs still work). The runtime/baker read the clean
  **mask**, never the illustrated atlas.
- **Regions don't carve land** — they're ellipse *biome-influence* masks that steer the climate
  model (see `biome_map_generator.gd`). Author them in `aldreth.json` (canonical) or regenerate
  the initial layout from `tools/gen_regions.py`.
- **Coordinate frame:** `bounds` (chunk space) map 1:1 onto the mask. Keep `bounds` aspect equal
  to the mask aspect (both 3:2 here) so sampling isn't distorted. Origin ≈ map centre.

### Authoring tools
| Tool | Use |
|---|---|
| `tools/world_trace.tscn` | atlas → clean land/river masks + approval preview (`-- --from-mask` re-emits from a hand-edited mask) |
| `tools/region_preview.tscn` | draw regions+roads on the mask with a chunk grid; reports `centers_in_sea` (+ nearest land) and `roads_crossing_sea` |
| `tools/coast_preview.tscn` | ~3s biome/coast render through the real classifier (mask active) |
| `tools/gen_regions.py` | expand the compact region/road table → worldspec JSON (run once; JSON is canonical after) |

### Stable IDs / removing biomes safely
Baked chunks store biomes/tiles as **byte indices**. The bake writes permanent `biomeIds`/`tileIds`
(index→id) tables into `aldreth.world`; `BakedWorldStore` remaps baked indices back to current
indices **by id** on load. A removed id resolves through `deprecatedBiomes`/`deprecatedTiles` in
`biomes.json` (`{"old":{"fallbacks":["new"]}}`). So reordering or removing a biome never rerolls or
corrupts a baked world. Older (v1) bakes with no id table load via identity (unchanged).

### Expanding the world
Add an island: paint it into `aldreth_land.png` (or extend `bounds`) and add region/road/anchor
data → re-bake. Existing world coordinates and other baked chunks are unaffected.

## Determinism

All randomness flows from `WG.hash_i()` / `WG.r01()` with the world seed. Same seed + same `generatorVersion` → identical chunk.

## Generator versioning

`WorldStore.GENERATOR_VERSION` is stored in `user://world.json`. Bump it when you change:

- `BiomeClassifier`, `SkillSiteSpawner`, `PoiPlacement`, `MonsterSpawner`, `CaveGenerator`
- Rules in `data/world/*.json` that affect placement (if you want unvisited areas to pick up changes)

## Chunk snapshots (explored land)

**Problem:** Without snapshots, only depletions/obelisks persist; terrain and sites are regenerated from current code on every load.

**Solution:** When the player first loads a chunk (`ChunkManager._load`), `WorldGen.snapshot_chunk_if_needed()` serializes the chunk into `world.json` → `chunkSnapshots`.

On `WorldGen.get_chunk()`:

1. Return cached chunk if in memory.
2. Else restore from snapshot if present.
3. Else generate fresh with current generator.

Unvisited chunks always use the latest generator. Explored chunks stay frozen until you explicitly invalidate snapshots.

### Invalidating snapshots (developers only)

```gdscript
WorldGen.store.invalidate_snapshots()
WorldGen.chunks.clear()
```

Use when you intentionally want explored land to regenerate (e.g. major world reset).

## Testing

`phase6_chunk_snapshots` in `tools/validate.gd`:

- Snapshot survives generator seed change for explored chunk.
- Unvisited chunk picks up new generation.

## Future: pass pipeline (Phase 8)

Target order: TerrainFields → Biome → Water → Shoreline → Zone → POI → SkillSite → Monster → Decor → SnapshotFinalize. Each pass should be deterministic, config-driven, and testable in isolation.
