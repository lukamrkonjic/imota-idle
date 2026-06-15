# World Generation Guide

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

## Runtime streaming

**Decision:** terrain, entities, and navigation stream at separate radii. Terrain
loads in the widest ring, entity containers load one ring inside that but still
beyond the camera footprint, and `ChunkManager.loaded_chunks()` exposes only the
small nav ring to A*.

**Why:** the baked world can show a large area, especially at low zoom, but trees,
nodes, enemies and POIs must already exist before their chunk reaches the screen.
Navigation does not need that full visible area, so keeping nav small avoids
large A* rebuilds while the visual world preloads ahead of the player.

**Consequence:** do not reduce entity streaming to `NAV_RADIUS` as a far-zoom
optimization. If node counts become an issue, optimize the visible entity subset,
sprite atlas coverage, or static imposters first; otherwise players will see
trees and enemies appear on-camera.

## Future: pass pipeline (Phase 8)

Target order: TerrainFields → Biome → Water → Shoreline → Zone → POI → SkillSite → Monster → Decor → SnapshotFinalize. Each pass should be deterministic, config-driven, and testable in isolation.
