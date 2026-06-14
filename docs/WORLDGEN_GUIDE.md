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

## Future: pass pipeline (Phase 8)

Target order: TerrainFields → Biome → Water → Shoreline → Zone → POI → SkillSite → Monster → Decor → SnapshotFinalize. Each pass should be deterministic, config-driven, and testable in isolation.
