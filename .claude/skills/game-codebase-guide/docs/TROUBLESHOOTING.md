# Troubleshooting

Common breakages and how to diagnose them. Always run `godot --headless --path . res://tools/validate.tscn`
first — it surfaces parse errors and save/content regressions.

## "Identifier <Class> not declared in the current scope"
A new `class_name` isn't in Godot's global-class cache yet. Run once:
`godot --headless --path . --import`. (Seen this session when adding `FishingDecor3D`.) Same for a new
`.glb` (regenerates its `.import`).

## Parse error after an edit
- Variable shadowing: re-declaring a name that already exists in the function (e.g. a local `bob`
  when the pose already has `bob`). Rename your local.
- Type inference on an untyped value (`world.player.position.distance_to(...)`): annotate explicitly
  (`var d: float = ...`).
- Tabs vs spaces: the codebase uses TABS. Mixed indentation fails to parse.

## A signal does nothing
1. Confirm it exists in `autoload/event_bus.gd` with the exact name + arg list.
2. `grep -rn "EventBus.<sig>.emit"` — is it actually emitted where you expect?
3. `grep -rn "<sig>.connect"` — is a listener connected, and does the handler's parameter count match
   the signal? A mismatch fails the connection (watch the console).
4. HUD not updating: the HUD connects in `osrs_hud._ready()`; make sure your new emit happens AFTER
   the HUD is built (it is, for normal gameplay).

## A node reference is null / "node not found"
Most nodes are built in code in `scripts/world/world.gd` (`_build_scene`), NOT in `world.tscn`. Check
the name there. `world.render_3d` is null in pure-2D/headless (guard with `if world.render_3d != null`).
`gather_ref`/`combat_target_entity` can be empty/invalid — always `is_instance_valid()`.

## Gather/skill won't start
- "No suitable tool equipped": `GameState.tool_progress(skill) <= 0` — equip the matching tool
  (slot from `SkillRegistry.tool_slot`).
- Level too low: node/recipe `level` > `GameState.level(skill)`.
- Fishing "Stand on the shore to cast": `FishingHelper.can_cast_from` failed — the site's water tile
  must be within `CAST_TILES`; `best_stand` should put you at the edge. (Historic bug: local vs
  global tile coords — fixed via `water_tile_global`.)

## Animation: tool sideways / floating / not held
- Sideways/wrong angle = the held-weapon **rotation** in `mover_meshes.gd` `weapon_profile` (roll/yaw)
  — keep the swing in the sagittal plane (roll 0) for overhead tools.
- Floating / not in hand = `_refresh_gather_tool` didn't swap it, or `equip_loadout` doesn't map the
  kind. Wrong striking end = the head geometry in `equip_parts`.
- Player animates mid-turn / before walking = the `face_ready` gate; the work pose only starts once
  the player has stopped and turned (see `mover_renderer_3d.gd`).
Verify poses with `tools/fish_shot.tscn` (forces each skill) or `tools/weapon_pose_preview.tscn`.

## Fishing-spot visual looks like grey pebbles
The old static `water_decor_parts("fish_school")` squashed spheres. `StaticPropBatcher` now SKIPS
`fish_school`; `FishingDecor3D` draws translucent bubble spheres instead. If pebbles reappear, check
that skip in `static_prop_batcher.gd` and that `FishingDecor3D.update` runs (only when 3D active).

## World edit didn't show up in play
The world is **baked** — re-run the bake (`tools/world_bake.tscn` / `imota bake`). Editor placements
saved to the worldspec persist; procedural terrain/spawn changes need a bake. Also bump
`WorldStore.GENERATOR_VERSION` if you changed generation so stale chunk snapshots regenerate.

## Save won't load / data lost
- Check `SaveMigration` chained to `CURRENT_SCHEMA`; add a `_migrate_vN_to_vN+1` if you changed the
  schema. Unknown ids are dropped by design (warnings in console) — resolve via
  `content_aliases.json` instead of renaming ids.
- `from_save_dict` defaults missing fields; if a new field vanishes after load, you forgot to add it
  to `to_save_dict` or to read it back.

## Validate fails
Read the failing phase name — it points at the system (Phase 0/0b content, Phase 1 gather/inventory,
Phase 2 skills, Phase 3/3d/3e save+rename+fallbacks, Phase 5 combat, Phase 6 worldgen/snapshots). The
phase function in `tools/validate.gd` shows the exact assertion.

## Headless render shows nothing
Expected — the 3D layer needs a display. Use `-- --force3d` only to smoke-test wiring (no pixels), or
the windowed `*_shoot`/`*_preview` tools to actually see output.
