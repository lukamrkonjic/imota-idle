# Open questions & unverified areas

Things NOT fully verified while writing this wiki. Confirm against source before relying on them, and
update this file (and the relevant page) when you learn the truth. Do not guess in other docs — put
uncertainty here.

## Combat formulas
`scripts/combat/combat_calc.gd` (`CombatCalc`) and `combat_constants.gd` hold the accuracy/max-hit/
crit/combat-triangle math. The exact formulas were not transcribed here (background in `docs/COMBAT.md`).
Before changing balance, read `combat_calc.gd` directly; `tools/validate.gd` Phase 5 has the worked
examples that must keep passing.

## Movement keys (WASD)
The top-of-screen hint says "WASD / R-drag move". Click-to-walk via `world_path_controller` is the
confirmed path; whether/where continuous WASD movement is handled (which file, and how it interacts
with the path controller) was not fully traced. Check `world_input_controller.gd` /
`world_camera_rig_3d.gd` before relying on WASD.

## Adding a brand-new SKILL
`data/skills.json` defines the roster, but a new skill needs sim wiring (gather/production), tool slot
(if any), UI tab/grid entries, XP table coverage, and `SkillRemap` awareness for saves. This is a
multi-file change — scope it carefully; prefer adding nodes/recipes to existing skills.

## `explored` field in `user://world.json`
Populated by `WorldStore` (fog-of-war reveal) but the exact consumer (world map vs minimap) wasn't
pinned down. Verify in `scripts/ui/widgets/minimap.gd` / the world-map code before depending on it.

## `docs/SAVE_FORMAT.md` is stale
It documents schema **v5**; the code is at **v7** (`SaveMigration.CURRENT_SCHEMA`). Trust the code +
`SAVE_LOAD_AND_PERSISTENCE.md`. If you touch the save format, update both `docs/SAVE_FORMAT.md` and
this wiki.

## Editor vs game render parity
The world editor (`tools/world_editor.gd`) has its own 3D preview path. Whether it runs the full
`WorldRender3D` (so `FishingDecor3D` bubbles / the `fish_school` static-skip apply there too) was not
fully confirmed. If a fix shows in Test Level but not the editor preview (or vice-versa), suspect a
separate render path. Verify in the editor's 3D-view setup.

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
