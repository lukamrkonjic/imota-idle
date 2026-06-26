# 3D render decisions

This is the decision record for player-camera and terrain-coverage behaviour in
the 3D world view. It complements [ARCHITECTURE.md](ARCHITECTURE.md): that file
describes ownership, while this one records the player-facing rendering choices.

## D1 — Low forward camera is a supported player pose

- **Decision:** The player may hold any pitch in `CAM_PITCH_MIN..CAM_PITCH_MAX`
  and any wheel-selected zoom without automatic tilt or coverage zoom correction.
- **Why:** A low forward-looking view is part of the exploration feel. Auto-zoom
  and forced re-pitch made the camera feel like it was fighting the player.
- **Consequence:** Up/Down only change pitch. Wheel zoom remains independent.
  Coverage must be solved by rendering and streaming, not by altering framing.

## D2 — Keep the orthographic image plane above the terrain

- **Decision:** At low pitch, `WorldCameraRig3D` moves the camera farther back
  along its own view ray and expands its far clip as needed. It keeps the same
  orthographic size, aim point, yaw, and pitch.
- **Why:** The apparent "unloaded terrain" at the bottom of the screen was often
  not a missing chunk. The bottom of a grazing orthographic image plane could
  start below the ground, meaning its rays never intersected terrain at all and
  exposed the renderer clear colour.
- **Consequence:** `SCREEN_GROUND_CLEARANCE` is a geometry safety margin, not a
  visual clamp. Do not reintroduce camera auto-zoom to conceal this condition.

## D3 — Hybrid visual terrain coverage

- **Decision:** Use camera-footprint-prioritised real terrain streaming together
  with a small deterministic low-detail terrain underlay. Full terrain meshes
  depth-occlude the underlay as soon as they are ready.
- **Why:** A player-centred loading queue is wrong for a low, forward-looking
  camera: the terrain ahead can be visible long before it is near the player.
  Prioritising the footprint makes real, authored terrain arrive first. The
  low-detail mesh ensures a fast turn or a cold stream never presents a void
  while that work completes.
- **Consequence:** The active gameplay/entity radius remains player-centred;
  only visual terrain data gets the wider, camera-shaped priority. The fallback
  is intentionally bounded: four-by-four-tile colour cells, one mesh instance,
  no entities, collision, navigation, saves, or simulation state.

### Alternatives evaluated

| Approach | Result | Decision |
|---|---|---|
| Player-centred streaming plus camera auto-zoom | Hides gaps by changing the player's framing. | Rejected. |
| Camera-footprint demand only | Correct, high-fidelity terrain arrives much sooner; a sufficiently abrupt turn can still wait on data/mesh work. | Retained as the primary path. |
| Low-detail underlay only | Prevents voids, but can briefly look flatter than the authored terrain and does not improve detailed-mesh arrival. | Retained only as fallback. |
| Hybrid demand + underlay | Detailed terrain arrives first, with a bounded no-void fallback during handoff. | Adopted. |

## D4 — Rendering changes never alter save data

- **Decision:** Camera coverage, chunk priority, and far-terrain fallback are
  presentation-only.
- **Why:** Imota ships in Early Access and save stability is release-critical.
- **Consequence:** These systems never mint, rename, remove, or serialize
  content IDs. They must not require a save migration.

## D5 — Painterly terrain colour: readable biome families, soft transitions, no "splotches"

- **Target:** An *A Short Hike*-style look — large readable colour regions, soft
  natural biome transitions, subtle brush-like variation that reads as sunlight and
  hand-painted texture. No hard per-tile colour swaps, no high-frequency noise, no
  dark-green islands that look like accidental biomes.
- **Decision (three independent fixes, all cosmetic):**
  1. **Grass stays one light-green family** (`terrain_style.grade`, grass branch). The
     old gradient drifted broad low-frequency bands toward `leaf_green`/`forest_green`
     (up to 45 %), manufacturing dark-green regions inside plain meadow. Removed: grass
     now interpolates only between `mid_foliage` and `sunlit_grass` (a gentle value
     sun/shade sweep) plus a faint moss highlight. **Forest depth no longer comes from
     this band** — it comes from the biome tint, which only darkens where a forest biome
     actually is.
  2. **Painterly patches are value-only** (`terrain_style.terrain_patch`). The old patch
     pass pushed shaded blobs toward a cooler, *more-saturated* green (a hue/sat shift),
     so they read as a second biome. Now it applies a single broad, soft brush field as a
     symmetric brightness swing of at most ±7 % on the *same* colour — never a hue/sat
     change. The rare flower/lichen accent is kept but fainter and sparser. Helpers
     `_patch_dark`/`_patch_light` were deleted.
  3. **Biome tint is weight-blended over a wide, organic edge**
     (`terrain_chunk_mesher._blended_biome_tint`). Instead of a hard per-tile tint, the
     tint is a distance-weighted average of nearby biome tints over two sample rings
     (≈ ±16 tiles), with the sample point domain-warped by low-frequency noise so the
     boundary is an organic painted edge. A biome **interior** stays pure (every tap
     agrees → no neighbour-biome bleed deep inside another biome); only **borders** blend.
     Flat-grass tint strength is `0.30` (raised modestly now that grass carries no false
     forest darkening, so biome families read clearly through the soft blend).
- **Why:** Stacked together, the band-driven grass darkening, the high-contrast hue-shifting
  patch noise, and the hard per-tile biome tint produced dark-green "splotches" that looked
  like stray biomes on uniform meadow.
- **Consequence:** Cosmetic only — same tiles, walkability, and gather sites; no gameplay or
  save impact. The 2D map bakers (`world_bake.gd`, `world_editor.gd`) keep their own
  deliberately stronger `0.55` tint and are unaffected. Per-tile biome tints are cached
  (`_bt_cache`, cleared each frame), so the wider blend adds only a small fixed tap loop per
  vertex on the build path.

## Validation

Run the normal headless suite and its 3D smoke path after changes here:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/validate.tscn
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/validate.tscn -- --force3d
```

For live QA, hold a low pitch, rotate through all yaw directions, walk across a
chunk boundary, and zoom out. The screen must remain terrain-filled without a
coverage-driven change to pitch or zoom.
