# Open questions & unverified areas

Things NOT fully verified while writing this wiki. Confirm against source before relying on them, and
update this file (and the relevant page) when you learn the truth. Do not guess in other docs — put
uncertainty here.

## Resolved (verified against source)
- **Terrain = baked static regions in play mode** (Option A, render-layer only). Standalone game loads
  `data/world/baked/<id>_terrain.res` once; no runtime terrain meshing/streaming/eviction. Editor keeps
  the dynamic mesher. See `ANIMATION_AND_SPRITES.md` → TERRAIN MODE + `FILE_OWNERSHIP_MAP.md`.
  - **Perf baseline (pre-change, M5 Pro, `tools/perf_probe.tscn`):** STANDSTILL was already healthy —
    120 FPS, 7–10 ms proc at all zooms (the reported "14 FPS standing still" did NOT reproduce here;
    likely weaker hardware). The real problem was WALK JANK from per-frame terrain meshing: zoom 0.45 =
    **211/400 frames > 33 ms, worst 142 ms**; zoom 0.95 = 39/400, worst 70 ms. `chunk_manager` DATA
    streaming was ~0.3 ms even on worst frames (cheap → kept). Baking removes the walk hitches; it does
    NOT by itself lift a steady-state FPS floor (none here). Re-run the probe after a render change.
  - **LOD decision:** NOT implemented (no LOD / `visibility_range`). 943 regions, ~7.5M tris, indexed
    → `<id>_terrain.res` ≈ 533 MB on disk (~300–400 MB VRAM). Acceptable for the fixed map; revisit a
    half-res far mesh only if min-spec VRAM/draw-calls prove tight.
- **Combat formulas** — transcribed exactly from `scripts/combat/combat_calc.gd` +
  `combat_constants.gd` into `FEATURE_MAP.md` → "Combat formulas". `CombatSim` delegates to
  `CombatCalc` (confirmed: `combat_sim.gd` preloads it and calls `player_max_hit`/`player_hit_chance`/
  `max_attack_roll`/`effective_level`). Tune constants in `combat_constants.gd`.
- **Player movement keys** — confirmed: **no in-game WASD**. The only `KEY_W` is
  `tools/world_editor.gd:3225` (editor aerial-camera fly-over). In-game the player is click-to-walk;
  arrow keys drive the in-game CAMERA (`world_camera_rig_3d.gd:update_input`: Left/Right yaw,
  Up overview, Down cinematic). Documented in `INPUT_ACTIONS.md`.
- **Editor uses the full game renderer** — confirmed: the editor's "🧊 3D View" embeds the REAL
  `world.tscn` (`tools/world_editor.gd`: `_GAME_SCENE := preload("res://scenes/world.tscn")`,
  `_v3d_world` "its render_3d does the 3D"). So `FishingDecor3D`, the `fish_school` static-skip, and
  all render fixes apply in the editor preview too — there is no separate render path.
- **`docs/SAVE_FORMAT.md`** — updated to schema **v7** (current example + world-save example +
  `explored` field). It now matches `SaveMigration.CURRENT_SCHEMA`/`GameState.to_save_dict`.

## Adding a brand-new SKILL
`data/skills.json` defines the roster, but a new skill needs sim wiring (gather/production), tool slot
(if any), UI tab/grid entries, XP table coverage, and `SkillRemap` awareness for saves. This is a
multi-file change — scope it carefully; prefer adding nodes/recipes to existing skills.

## `explored` field in `user://world.json`
Populated by `WorldStore` (fog-of-war reveal) but the exact consumer (world map vs minimap) wasn't
pinned down. Verify in `scripts/ui/widgets/minimap.gd` / the world-map code before depending on it.

## Baked-world file format
`data/world/baked/<id>.world` is `var_to_str`/`str_to_var` with base64 byte arrays + remap LUTs
(`baked_world_store.gd`). Treat as opaque; only `tools/world_bake.gd` should write it. Re-bake after
content/index changes.

## Fishing-spot visibility on pale shoreline water
The bubble spheres are translucent pale-cyan; against very pale shallow/foam water they're subtle.
Tunable via constants at the top of `scripts/render/fishing_decor_3d.gd` (count/size/alpha/spread) if
a future task wants them more prominent. (Billboard-quad bubbles did NOT render in this pipeline —
spheres are the working approach.)

## Possible duplication / risk to watch
- Two fish "school" representations historically existed (static `water_decor_parts("fish_school")`
  and `FishingDecor3D`). The static one is skipped in `static_prop_batcher.gd`; if you re-enable
  water decor, don't re-introduce the pebbles.
- There is a 2D `water_surface_art._draw_fish_school` that is hidden in 3D mode — don't confuse it
  with the 3D bubbles.
