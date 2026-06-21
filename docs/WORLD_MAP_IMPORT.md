# Import a hand-drawn map as a game world

Turn an **illustrated outline map** into a finite, baked game world: trace it to a
clean land/water mask, lay biomes on top, and bake it to chunks. The same pipeline
works for **any** world id — Aldreth is just the first one. You can also **shuffle
the biomes** on a fixed coastline to explore different dispositions.

Runtime/baker only ever read the generated *masks*, never the illustration.

> Godot on this machine: `/Applications/Godot.app/Contents/MacOS/Godot`
> (substitute your own path; `--headless` is fine for every tool here).

## The pipeline

```
data/world/source/<id>_atlas.png      illustrated outline map  (importer input only)
   │  tools/world_trace.gd
   ▼
data/world/masks/<id>_land.png         clean binary land/water mask  (EDITABLE source of the coast)
data/world/masks/<id>_rivers.png       inland water (rivers/lakes)
data/world/masks/<id>_trace_preview.png  review overlay  (APPROVE this)
data/world/masks/<id>_mask.json        mask ↔ world-chunk mapping + recommended bounds
   │
data/world/worldspec/<id>.json         bounds, regions (biome influence), roads, anchors
   │  BiomeClassifier samples the mask → coast → climate/region biomes → micro-biome stamps
   │  FiniteWorldGenerator rasterizes roads/rivers + plants structures
   ▼
data/world/baked/<id>.world            shipped chunk data (+ permanent id table)
data/world/baked/<id>_map.png          overview map
```

## Step by step (any world)

### 1. Provide the map
Draw or generate an outline map and save it as `data/world/source/<id>_atlas.png`.
What traces cleanly:
- **Land = a light/warm colour, ocean = a dark/blue colour** (the refined-outline
  style: cream land on navy sea). High contrast is all that matters.
- Rivers as thin dark lines inside land are detected as inland water.
- A legend / compass / scale bar / frame is fine — the importer strips decoration
  that sits in the open-sea margins; large title text in a corner is removed by the
  `IGNORE_ZONES` in `tools/world_trace.gd` (tune the rects if your map differs).

### 2. Trace it to masks
```
Godot --headless --path . res://tools/world_trace.tscn -- --world=<id>
```
(`--world` defaults to `worldspec/index.json`'s `active`, so for the active world you
can omit it.) Then **open `data/world/masks/<id>_trace_preview.png` and check it**:
land = cream, sea = navy, rivers = cyan, stripped decoration = magenta.

- Misreads? Adjust the classification constants at the top of `world_trace.gd`
  (`LAND_MIN_LUMA`, `OCEAN_MAX_LUMA`, …) and re-run.
- Or hand-fix `<id>_land.png` in any image editor (white = land, black = sea) and
  refresh the preview/meta without re-tracing:
  ```
  Godot --headless --path . res://tools/world_trace.tscn -- --world=<id> --from-mask
  ```

### 3. Set up the worldspec
- Copy `data/world/masks/<id>_mask.json` → `recommendedBounds` into your
  `data/world/worldspec/<id>.json` `bounds` (keep the bounds aspect equal to the mask
  aspect so sampling isn't distorted; origin ≈ map centre).
- Point `data/world/worldspec/index.json` `active` at `<id>` (and `enabled: true`).
- The mask auto-activates: `BiomeClassifier` loads `data/world/masks/<id>_land.png`
  (path from the active spec id) and the coastline follows it. No mask → the old
  procedural ellipse continent is used instead.

### 4. Lay out regions (biomes)
Regions are **ellipse biome-influence masks** that steer the climate model; they don't
carve land. For Aldreth they're generated from a compact table in `tools/gen_regions.py`
(run once, then the JSON is canonical), but you can also hand-edit
`worldspec/<id>.json` `regions` directly.

Verify placement against the real coastline:
```
Godot --headless --path . res://tools/region_preview.tscn
# -> data/world/masks/<id>_region_preview.png  (regions + roads on a chunk grid)
# stdout reports centers_in_sea (with nearest-land suggestions) and roads_crossing_sea
```
Then see the biomes the climate model actually produces:
```
Godot --headless --path . res://tools/coast_preview.tscn   # ~30s -> <id>_preview.png
```

### 5. Bake
```
Godot --headless --path . res://tools/world_bake.tscn      # minutes -> <id>.world + <id>_map.png
```
Bump `WorldStore.GENERATOR_VERSION` when generation logic changes so stale explored
snapshots regenerate. See [WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md) for the determinism
guard (`tools/validate.gd` `WORLDGEN_TILES_HASH`).

## Shuffle the biomes — explore dispositions

Keep the coastline + region positions fixed and reassign **which biome each region
holds**, rendered through the real climate model so you see what would bake.

**See many at once** (contact sheet; cells are seeds, default 6):
```
Godot --headless --path . res://tools/biome_shuffle.tscn
# -> data/world/masks/<id>_shuffle_sheet.png   (3 across; stdout maps cell -> seed)
Godot --headless --path . res://tools/biome_shuffle.tscn -- --variants=9 --mode=random
```
- `--mode=permute` (default): shuffle the *existing* biomes among regions — same
  variety, new layout.
- `--mode=random`: draw each region from a biome pool — wilder (desert in the north…).
- The spawn region (`greenhollow`) stays its authored biome so home is always safe.

**Look closer at one** (no changes written):
```
Godot --headless --path . res://tools/biome_shuffle.tscn -- --seed=4
# -> data/world/masks/<id>_shuffle_preview.png
```

**Commit one you like** to the worldspec, then preview + bake it:
```
Godot --headless --path . res://tools/biome_shuffle.tscn -- --apply --seed=4
Godot --headless --path . res://tools/coast_preview.tscn   # confirm
Godot --headless --path . res://tools/world_bake.tscn      # bake it for real
```
(For Aldreth, re-running `python3 tools/gen_regions.py` restores the canonical biome
layout if you want to undo an `--apply`.)

## Synthesize a world without a map (experimental)

If you don't have an illustration, `tools/gen_world.gd` makes a candidate world by
generating a fractal land mask procedurally and snapping the authored biome layout
onto it:

```
Godot --headless --path . res://tools/gen_world.tscn -- --world=<id> --seed=<n>
# writes masks/<id>_land.png + worldspec/<id>.json; then set index active=<id> + coast_preview
```

It writes a normal mask + worldspec, so it flows through the same coast_preview / bake
pipeline. **Caveat:** the current coastline knobs tend to produce one broad continent
rather than the multi-island, deep-bay character of a hand-traced map — tune
`SEA_LEVEL` / the falloff / `WARP_AMP` / island params in `gen_world.gd`, or trace an
illustration with `world_trace` for the best results.

## Tools at a glance

| Tool | Input → output |
|---|---|
| `tools/world_trace.tscn` | `source/<id>_atlas.png` → `masks/<id>_{land,rivers,trace_preview}.png` + `<id>_mask.json` (`--from-mask` re-emits from an edited mask) |
| `tools/region_preview.tscn` | mask + worldspec → `<id>_region_preview.png`; reports `centers_in_sea`, `roads_crossing_sea` |
| `tools/coast_preview.tscn` | classifier → `<id>_preview.png` (biomes/coast through the real model, ~30s) |
| `tools/biome_shuffle.tscn` | mask + regions → `<id>_shuffle_sheet.png` / `_shuffle_preview.png`; `--apply` writes the worldspec |
| `tools/gen_regions.py` | compact region/road table → worldspec JSON (Aldreth authoring) |
| `tools/gen_world.tscn` | **experimental** — synthesize a mask + worldspec procedurally (no illustration) |
| `tools/world_bake.tscn` | worldspec + masks → `<id>.world` (+ id table) + `<id>_map.png` |

## Notes & safety

- **Removing/reordering biomes is safe.** The bake stores permanent `biomeIds`/`tileIds`
  tables; `BakedWorldStore` remaps baked indices back to current ones by id, with
  `deprecatedBiomes`/`deprecatedTiles` fallbacks in `biomes.json`. A baked world never
  rerolls when `biomes.json` changes.
- **Expanding** a world: paint new land into `<id>_land.png` (or extend `bounds`) and add
  regions/roads — existing coordinates and other baked chunks are unaffected.
- See [WORLDGEN_GUIDE.md](WORLDGEN_GUIDE.md) for generator internals and
  [WORLD_DESIGN.md](WORLD_DESIGN.md) for the geography decisions.
