# Porting Imota to real-time 3D pixel-art — inventory, profiling, staged plan

> Companion to the style spike (`scripts/render/pixel3d_preview.gd`, `shaders/
> toon_world.gdshader`, `shaders/palette_snap.gdshader`). Goal: render the EXISTING
> game world as real-time 3D pixel-art (low-res SubViewport → exact 4× nearest,
> full-res UI, toon bands, our palette, **iso angle preserved**), and bake the
> chunk/prop architecture so chunk entry never hitches. **Begin with profiling +
> inventory only — no rendering rewrite until the spike cause is confirmed.**

## 1. Profiling baseline (current 2D game, RTX 3090, forward+)

Captured via the existing `PerfLogger` (`user://perf_log.txt`) on a fresh launch
of `scenes/world.tscn`:

| Phase | Frame time | Notes |
|---|---|---|
| **Initial load** (t≈2.2 s, first chunk fill) | **worst 150 ms** (fps→2) | one-time: worldgen init + first-fill + terrain mesh bake + first-use shader compile |
| Terrain mesh bake (chunk-manager `mesh` stage) | **9.6 ms** first frame, ~1.7 ms/chunk while streaming | the per-chunk vertex-mesh rebuild in `chunk_renderer._rebuild_mesh()` |
| Steady state (t>5 s) | **~12 ms / 144 fps**, worst ~6.9 ms, `cm total` ~2 µs | smooth; no per-frame chunk cost |

**Identified spike causes (measured, not assumed):**
1. One-time worldgen + first chunk fill (~150 ms, first frame only).
2. Per-chunk **terrain mesh baking** (~1.7 ms/chunk; 9.6 ms on the first frame).
3. **First-use shader compilation** (forward+ pipeline warm-up).

It is **NOT** a per-prop material/mesh explosion — props currently share the 2D
canvas; there are **no per-instance materials and no collision objects** today.

## 2. Architecture inventory (what generates visuals at chunk activation)

| Concern | Today (2D) | File(s) |
|---|---|---|
| Terrain | ~300 per-tile polygons **baked once per chunk** into a single vertex-colored 2D triangle mesh, one `draw_mesh` call; has coarse/full LOD | `scripts/worldgen/chunk_renderer.gd` |
| Props / nodes / monsters / structures | one `WorldEntity` (`Node2D`) per item, each `_draw()`s procedural art every redraw; **102 art scripts** | `scripts/world/world_entity_spawner.gd`, `scripts/world/world_entity.gd`, `scripts/world/art/**` |
| Streaming | data-gen + activate/deactivate queues with a per-frame **µs budget** (already!) | `scripts/worldgen/chunk_manager.gd` |
| Collision | **none** — 2D custom pathfinding | `scripts/worldgen/path_finder.gd`, `wg.gd` |
| Materials / shaders | one terrain 2D canvas shader; entities use vertex colors | `shaders/terrain_ground.gdshader` |
| Camera | **`Camera2D`** (iso projection baked into the 2D art) | `scripts/world/world.gd` |
| Perf instrumentation | frame/worst-ms, draw calls, node counts, per-subsystem + chunk-stage µs timings | `scripts/world/perf_logger.gd` |

**Good news for the port:** terrain is *already* a baked per-chunk mesh with
elevation steps + per-tile colors, and streaming already has a commit budget.
Those map almost directly to the 3D target.

## 3. Target 3D architecture (and how the inventory maps)

- **Terrain** → per-chunk 3D `ArrayMesh`: extrude the existing elevation steps to
  heights, carry the existing per-tile colors as vertex color, shade with a
  `toon_ground` material (sharp authored layer transitions, smooth normals).
  *Direct port of the current bake.*
- **Props** → editor-time **baked Mesh + shared Material per prop type** (one per
  art family: each of the 102 `_draw` silhouettes becomes a low-poly mesh that
  keeps its silhouette/palette), rendered via **per-chunk `MultiMeshInstance3D`**
  grouped by mesh/material; variation via `INSTANCE_CUSTOM` (variant/wind/tint),
  never random colors outside the palette.
- **`PropDefinition` resources** (id → mesh, material, simple collision, footprint,
  offset, shadow flags, multimesh-eligible, lod group). Chunk data references
  **stable definition IDs** (preserve all existing content/save IDs).
- **Interaction** → data records + MultiMesh for inactive props; **pooled Node3D
  proxies** only for the prop the player is near (chop/mine/etc.).
- **Camera** → `Camera3D` orthographic at the **current iso angle** (preserve the
  game's identity); pixel-stable quantization later.
- **Animation** → shared GPU vertex shaders (wind via `TIME` + `INSTANCE_CUSTOM`),
  not `_process()` per prop; effects (fire/water) via shared shader/particles.
- **Collision/nav** → simple shapes only where needed (trunk capsule, rock convex),
  merged/chunk-level for static groups, batched nav, built editor-time not runtime.
- **Presentation** → the spike's low-res SubViewport (3×/4× presets) + nearest
  upscale, **full-res UI** layered over it; shared palette-snap post-process.

## 4. Staged migration order (small, reversible, measured)

Each stage: report modified files, before/after worst-frame & chunk-activation
time, node / draw-call / material / collision counts, whether visuals changed, and
a screenshot at the internal pixel resolution. Don't advance without a measurable
benefit or clear architectural purpose.

1. **Profiling + inventory** *(this doc — done).*
2. **3D presentation harness in the real game** (feature-flagged): SubViewport +
   ortho iso `Camera3D` + toon pipeline, render a single 3D terrain chunk from
   existing chunk data; keep the 2D path intact (toggle). *Smallest reversible proof.*
3. **Terrain → per-chunk 3D ArrayMesh** for all loaded chunks (port the existing
   bake), sharp layer transitions, our palette.
4. **`PropDefinition` + baked prop meshes/materials**; build the prop-bake tool
   (editor-time). Start with the highest-count families (trees, rocks, ground decor).
5. **Per-chunk `MultiMeshInstance3D`** for static props (replace `WorldEntity`
   draw for inactive props); `INSTANCE_CUSTOM` variation.
6. **Wind/animation shaders** (canopy/grass) replacing per-prop draw.
7. **Pooled interaction proxies** for near props (chop/mine/fish/fight).
8. **Simplified, batched collision/nav** (only as the 3D world needs it).
9. **Background chunk prep** (worker builds transform/color buffers) + **main-thread
   commit budget** (reuse the existing streaming budget).
10. **Resource background loading + shader warm-up** scene (kills first-use hitch).
11. **LOD / distant impostors** only if profiling still shows a need.

## 5. Save-safety & guardrails (unchanged, non-negotiable)

- No change to save data, content/save IDs, recipes, items, enemies, nodes, drops,
  or serialized content. `PropDefinition.id` maps to existing content IDs.
- Rendering/material/scene-hierarchy/preview/tooling code only.
- Don't flatten close objects to PNG sprites — keep dynamic lighting, depth, cast
  shadows, camera movement, shader animation (impostors only for distant objects).
- Don't bake duplicate meshes/materials per chunk; identical props share resources.
- Preserve iso angle, palette, silhouettes, proportions, atmosphere.
