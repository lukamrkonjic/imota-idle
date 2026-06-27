# Animation, sprites & 3D rendering

There are **no 2D sprites/AnimationPlayers for gameplay**. The world is drawn by a 3D pixel-art
renderer that reads the 2D gameplay state each frame. It is COSMETIC — never put game logic here.

## Render coordinator
`scripts/render/world_render_3d.gd` (`WorldRender3D`, the `WorldRender3D` node, `world.render_3d`).
`_build()` creates the subsystems; `_process(delta)` ticks them. Runs only when 3D is active
(headless tests use the 2D substrate unless `-- --force3d`). Exposes `iso_to_3d(pos, y)`,
`height_at(pos)`, `props_root`, `invalidate_static_batches`, `fx_layer`.

Subsystems (all in `scripts/render/`):
- `render_viewport_presenter.gd` — the low-res `SubViewport` + nearest-neighbour upscale +
  `palette_snap`/posterize. This IS the pixelation. (`GameSettings.pixelation` drives it.)
- `world_camera_rig_3d.gd` — the 3D camera; zoom mirrored from the 2D `Camera2D`
  (`size = CAM_SIZE_BASE/zoom`, zoom 0.55..4.5), pitch budget vs zoom. Note: it READS `world._camera.zoom`.
- `world_atmosphere.gd` — `WorldEnvironment` + the directional sun. **Sun direction is pinned**
  (`SUN_DIR_DEG`, `set_sun_direction` for the admin slider); DayNight only changes sun colour/energy,
  so shadows don't slide. The colour-grade post pass (`Environment.adjustment_*`) is kept **neutral
  at dusk** (saturation ≤ 1.0, contrast = 1.0): it's a GLOBAL screen pass that also grades the
  unshaded terrain, and pumping saturation amplified the ground's baked painterly value-variation
  into shadow-like dark-green blotches that "animated in" at sunset (looked like cast cloud shadows,
  but nothing casts them). Dusk warmth comes from the sun colour/fog/ambient only — the unshaded
  ground ignores those, so it stays flat at every time of day. Weather may only DESATURATE.
- `terrain/terrain_chunk_mesher.gd` + `terrain_mesh_manager` — builds terrain meshes; `TILE_S=1.0`
  (1 tile = 1 unit). `terrain_style.gd` colours terrain. **ONE FLAT COLOUR PER BIOME** (clean,
  distinct regions): `TerrainStyle.flat_ground` paints each tile its biome's single curated colour
  (`biomes.json` `ground` field → `WorldRegistry.biome_ground`), with sand/snow as single flat tones
  and a rock/snow read BY ELEVATION ONLY (peaks still read). NO per-tile noise, broad bands, painterly
  `terrain_patch`, or wide `biome_tinted` blend — borders soften only ~1 tile via the shared corner
  colour. (The old `grade`/`biome_tinted`/`terrain_patch` remain in `terrain_style.gd` but are no
  longer used by the 3D ground.) Beaches are one flat sand tone (`toon_ground` `beach_color`). Biome
  REGIONS are crisp because `biome_map_generator._blend_offset` is now zero (the authored mask is
  sampled at the exact tile — no domain-warp/jitter). Ground/water shaders:
  `shaders/toon_ground.gdshader`, `toon_water.gdshader`. Ground is flat-lit; only object cast-shadows
  darken it. **Re-bake after any terrain-colour or biome-assignment change.**
- **TERRAIN MODE (play vs editor).** In the **standalone game** terrain is a fixed BAKED static-region
  world: `tools/world_bake.gd` meshes the continent offline in 64×64 regions
  (`terrain_chunk_mesher.build_region_terrain`, indexed) into `data/world/baked/<id>_terrain.res`
  (`BakedTerrainSet`); `static_terrain_regions.gd` (`StaticTerrainRegions`) instances them once at
  startup and there is **no runtime terrain meshing, chunk streaming, eviction, seam reconcile, or
  far-backdrop** — Godot frustum-culls. `WorldRender3D._init_terrain_mode` picks this on frame 1 when
  `world.gameplay_active` and the resource exists; the per-frame `mesh_manager.update` is replaced by
  `mesh_manager.refresh_data_index()` (keeps the height field's data apron current — camera/props/
  picking still sample it). The **world editor** (embeds the world with `gameplay_active=false`) keeps
  the FULL dynamic `terrain_mesh_manager` + `terrain_stream_view` + `far_terrain_backdrop` so live
  brushing re-meshes (`rebuild_chunk`/`rebuild_chunk_instant`). `stream_view` + the chunk DATA demand
  stay live in BOTH modes (they also stream gameplay data for distant-but-visible props/entities).
  **Re-bake (`imota bake` / `tools/world_bake.tscn`) to see terrain edits in the shipped game.**
- `static_prop_batcher.gd` — batches static props + decor into MultiMeshes (mirrors `world.entities`,
  `world._decor_nodes`, `world._water_decor_nodes`). Skips `fish_school` (handled by FishingDecor3D).
- `mover_renderer_3d.gd` — animated rigs for the player + enemies (gait, turn spring, squash, combat
  lunges, gather poses, blob shadows, equipment). Reads `TickSim`/`CombatSim`/`world.gather_ref`.
- `mover_meshes.gd` — builds the humanoid rig + held weapon/tool meshes (`weapon_profile`,
  `equip_parts`: sword/axe/pickaxe/fishing_rod/…). `equip_loadout.gd` maps equipped items → visuals.
- `mover_rig.gd` — per-frame poses: `_pose_humanoid(...)` (walk/idle, gait phase) and
  `_pose_gather_work(work, ...)` for "chop"/"mine"/"fish_rod"/"fish_kneel"/"forage"/"trap"/"steal".
- `prop_meshes.gd` — procedural meshes for trees/rocks/buildings/decor + `blob_shadow`,
  `water_decor_parts`. `smithy_prop.gd` — example `.glb` loader (see repo `docs/GLB_IMPORT_GUIDE.md`).
- `fishing_decor_3d.gd` — animated bubble clusters on fishing-spot water (translucent cyan spheres,
  rise/grow/pop, staggered loop).
- `world_fx_3d.gd` — leaf puffs (woodcutting), rock-chip puffs (`mining_struck`), tree fall/grow.

## How gather/combat animation works (the player)
Each frame `MoverRenderer3D._animate_mover`:
1. Computes walk amount + an accumulated **gait phase** scaled by ground speed (legs match walk/run
   speed — no slow-mo run).
2. Decides facing: while gathering, faces the `gather_ref` node (or fishing water); a `face_ready`
   gate (turned + stopped) must pass before the work pose starts ("walk → square up → animate").
3. Picks the work motion from `TickSim.skill` (woodcutting→chop, mining→mine, fishing→fish_rod/
   fish_kneel by node name, foraging→forage, hunter→trap, thieving→steal) and the right tool in hand
   via `_refresh_gather_tool`.
4. Calls `MoverRig._pose_humanoid(..., chop, work, work_amt, gait)` which dispatches to the motion.
Combat uses attack lunges driven by `combat_hit_splat`/`combat_ranged_shot`.

## Tuning / extending
- New gather motion: add a case in `MoverRig._pose_gather_work` + map the skill in
  `MoverRenderer3D._animate_mover` + (if it needs a tool) a `weapon_profile`/`equip_parts` entry and
  a `_refresh_gather_tool` branch.
- New held tool/weapon look: `mover_meshes.gd` `weapon_profile` (grip) + `equip_parts` (mesh) + map
  the equipped item kind in `equip_loadout.gd`.
- New prop look: `prop_meshes.gd` (procedural) or a `.glb` via a `*_prop.gd` loader (repo
  `docs/GLB_IMPORT_GUIDE.md`). Keep models isolated; gameplay refers to entity `kind`, not files.
- Shaders live in `shaders/`; the pixelation/posterize is in `render_viewport_presenter.gd` +
  `palette_snap.gdshader`. Don't pre-pixelate art — the viewport does it.
- Verify visuals with `tools/world_shoot.tscn` / `tools/fish_shot.tscn` (windowed, save PNGs).
  Note: those tools' camera framing can fight the rig's zoom — frame loosely.
