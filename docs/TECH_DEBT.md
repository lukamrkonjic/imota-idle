# Technical Debt — Prioritized

Risks and concrete files. Ordered by impact on long-term playability.

> **Active plan:** the prioritized, tiered cleanup for the current **3D pixel-art `main`**
> lives in `docs/REFACTOR_ROADMAP.md`. This file is the longer-standing risk register;
> some line counts below predate the 3D render layer (which is now the largest debt —
> `world_render_3d.gd` ~2200, `prop_meshes.gd` ~1855, `osrs_hud.gd` ~1953).

## P0 — Breaks player worlds

| Risk | Files | Notes |
|------|-------|-------|
| Explored chunks regenerate when generator code changes | `autoload/world_gen.gd`, `scripts/worldgen/world_store.gd`, `scripts/worldgen/world_generator.gd` | Only depletions/obelisks persisted; terrain/sites re-derived from current code. **Mitigation:** chunk snapshots (Phase 5). |
| Display names used as save/inventory keys | `autoload/game_state.gd`, `autoload/save_manager.gd`, `data/items.json` | Renaming "Logs" breaks saves. **Mitigation:** stable ids + aliases (Phase 2). |

## P1 — Blocks scaling content

| Risk | Files | Notes |
|------|-------|-------|
| ~~God object world controller~~ | `scripts/world/world.gd` (~160 lines) + 7 controllers | **Split done (Phase 6).** HUD still calls `open_bank` etc. directly — migrate to EventBus when convenient. |
| World-gen rule pile | `scripts/worldgen/skill_site_spawner.gd` (~441 lines) | Tree/water/biome special cases accumulate. Needs pass pipeline + `data/world/generation_rules.json` (Phase 8). |
| Biome classifier owns too much | `scripts/worldgen/biome_classifier.gd` | Classification + rivers + lakes + shore decoration intertwined. |
| Chunk renderer + biome shading tangled | `scripts/worldgen/chunk_renderer.gd` | Visual baking mixed with biome-specific logic. |
| HUD coupled to world internals | `scripts/ui/osrs_hud.gd` (~950 lines) | Four remaining `world.call()` sites (auto_bank, auto_gather, auto_station, teleport_to); migrate to EventBus. |
| ~~No content schema validation~~ | `tools/validate_content.gd` | **Done (Phase 3).** 202 dangling Bloobs-export refs remain as warnings. |
| ~~No save migration layer~~ | `autoload/save_migration.gd` | **Done (Phase 4).** v1→v2 migration, `schemaVersion` on all saves. |
| Equipment slot inferred from display name | `autoload/game_state.gd` (`slot_for_item`) | Renaming an item can change its inferred slot. Saves are unaffected (store slot→id), but slots should be explicit item data (Phase 9). |

## P2 — Maintainability / modding

| Risk | Files | Notes |
|------|-------|-------|
| Dictionary string keys everywhere | All autoloads, world scripts | Typo-prone; no static typing on content shape. **Started (Tier C):** typed `ItemDef` (`scripts/content/item_def.gd`) + `DataRegistry.item_def()` now back the equipment/combat paths; slot + combat-style are data-driven (no name inference). Remaining incremental: typed Recipe/Enemy/GatherNode + the broader Item dict sites. |
| Procedural art dumps | `scripts/world/iso_sprites.gd` (~433), `scripts/world/tree_art.gd` (~207) | Will grow with every new node type; consider data-driven sprite defs. |
| Activity sims not unified | `tick_sim.gd`, `combat_sim.gd`, `recipe_sim.gd` | Each skill type needs bespoke loop code (Phase 7). |
| ~~Legacy Melvor UI still in tree~~ | ~~`scenes/main.tscn`, `scripts/ui/main_ui.gd`~~ | **Done (Tier 0).** Deleted; validate phase 3 retargeted to the TickSim gather loop. Preserved on `archive/main-2d`. |
| Import-only content ids | `tools/import_bloobs_data.gd` | Items lack explicit `id` field in JSON; runtime assignment only. |

## P3 — Cleanup

| Risk | Files | Notes |
|------|-------|-------|
| ~~Unused exploration fog~~ | ~~`scripts/worldgen/exploration_edge_fog.gd`~~ | **Done (Tier 0).** Deleted (was `@deprecated`, superseded by `unexplored_backdrop.gd`). |
| Missing contributor docs | `docs/` | Only `DATA_GAPS.md` existed before architecture pass. |

## Render-monolith decomposition (Tier D — in progress)

`world_render_3d.gd` (~2.7k) is being carved into modules so the art/animation can be
reworked without touching the render pipeline.

- **Done:** terrain colour + tile classification → `scripts/render/terrain_style.gd`
  (`TerrainStyle`) — the swappable art module (render-verified: terrain shows every frame).
- **Next (scoped, needs per-body-type / per-FX visual verification, NOT a blind cut):**
  - `MoverRig` — the pure rig functions: `_pivot`/`_set_pivot`, `_sway_hair`/`_flow_cloth`/
    `_flow_cape`(+`CAPE_DRAPE`), `_shadow_footprint`, and the 5 `_pose_*` (humanoid/goblin/
    gnoll/quadruped/bird). All parameterized/pure; the orchestrator `_animate_mover` stays and
    calls `MoverRig.pose_*`. ~470 lines, interleaved with `_shadow_push`/`_apply_hurt`/
    `_attack_progress` (which stay), so extract per-function. Verify each body type renders.
  - `WorldFx3D` — campfire/firemaking/prayer-burst FX (`_light_fire`/`_build_campfire`/
    `_on_firemaking_burned`/`_on_prayer_activated`/`_update_fx` + `_fire*`/`_fx_bursts`/
    `_kneel_t` state). Holds a render-ctx ref for `iso_to_3d`/`height_at`/`props_root`/`cam`.
    Verify by triggering firemaking + a prayer (not visible in a spawn screenshot).
  - `FXDirector` + a shared `PixelAnim.pulse(t,freq,amp)` helper (dedupe the per-structure
    `0.5+sin(t*f)*a` glows in campfire/anvil/altar/fountain/obelisk art).

## File size watch list (current, 3D `main`)

| File | Lines | Category |
|------|------:|----------|
| `scripts/render/world_render_3d.gd` | ~2700 | 3D render — TerrainStyle split out; MoverRig/WorldFx3D next |
| `scripts/ui/osrs_hud.gd` | ~1953 | UI — split into per-tab components |
| `scripts/render/prop_meshes.gd` | ~1855 | 3D render — data-drive equip/rig |
| `scripts/worldgen/skill_site_spawner.gd` | ~626 | World generation — rule pile |
| `scripts/worldgen/chunk_renderer.gd` | ~581 | Rendering — split biome colour out |
| `scripts/worldgen/biome_classifier.gd` | ~530 | World generation — split water passes |

`iso_sprites.gd` / `tree_art.gd` monoliths were split under `scripts/world/art/`;
the files at `scripts/world/` are one-line back-compat re-exports.

## Serialization invariant

Chunk snapshots round-trip through JSON (`user://world.json`). JSON has no
Vector2/Vector2i — typed fields must be normalized at the `world_store.gd`
serialize/deserialize boundary (`_vec2i_to_json` / `_json_to_vec2i`). Never
store a Vector2i (or Color, etc.) in a snapshotted dict without adding it
there, and keep the disk round-trip test in `validate.gd` Phase 6b green.

## Recommended work order

1. ~~Stable IDs + aliases~~ — done (Phase 2)
2. ~~Save schema versioning + migrations~~ — done (Phase 4)
3. ~~Chunk snapshots~~ — done (Phase 5)
4. ~~Split `world.gd` into controllers~~ — done (Phase 6)
5. Unified activity model (Phase 7)
6. World-gen pass pipeline (Phase 8)
7. `data/skills.json` + explicit item slots/tags (Phase 9)
8. Test split + STYLE_GUIDE (Phases 10–11)
9. Migrate remaining HUD `world.call()` sites to EventBus
10. Persist player world position in save (currently respawns at `spawn_position()` each launch)
11. ~~Delete legacy `scenes/main.tscn` / `main_ui.gd`~~ — done (Tier 0)
