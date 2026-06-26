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

## Validation

Run the normal headless suite and its 3D smoke path after changes here:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/validate.tscn
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/validate.tscn -- --force3d
```

For live QA, hold a low pitch, rotate through all yaw directions, walk across a
chunk boundary, and zoom out. The screen must remain terrain-filled without a
coverage-driven change to pitch or zoom.
