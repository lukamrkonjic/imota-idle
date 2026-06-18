# Imota — Refactor Roadmap (3D pixel-art `main`)

Captured after `main` was overwritten with the 3D pixel-art build (the old 2D build is
preserved on branch `archive/main-2d` and tag `2d-classic`). This is the plan to pay
down debt and reach a clean, modular, scalable base before piling on more content.

The single biggest theme: **the project grew fast as a graphics spike, so the newest
code (render + HUD) is monolithic, and content rules are hardcoded in GDScript instead
of data.** Nothing here is broken — it works and performs well — but adding features
currently means editing god-objects and copy-pasting.

Severity: **P0** architecture-breaking · **P1** blocks scaling · **P2** maintainability · **P3** cleanup.

---

## Progress — first cleanup pass (validate green throughout; render-layer changes render-checked)

**Done & verified:**
- **Tier 0:** deleted legacy 2D UI (`main_ui.gd`/`scenes/main.tscn`, validate retargeted), deleted deprecated `exploration_edge_fog.gd`; wrote `STYLE_GUIDE.md`; refreshed `ARCHITECTURE.md` + `TECH_DEBT.md`.
- **Tier 2 (safe subset):** combat balance magic numbers → named constants (`combat_sim.gd`); `slot_for_item` and `weapon_combat_style` now prefer explicit `slot`/`combatStyle` item data, inference is fallback only.
- **Tier 1 (safe extractions):** HUD inner widgets → `scripts/ui/widgets/` (tab_icon, status_orb, icon_button, minimap) + dead `HpOrb` removed (`osrs_hud.gd` 1958→1661); spawn-dressing data → `scripts/render/spawn_dressing_specs.gd` (`world_render_3d.gd` 2202→2093).
- **Tier 3 (decoupling):** all UI `world.call("...")` sites (HUD + AdminMenu) replaced with EventBus intents (`bank_requested`/`gather_requested`/`station_requested`/`teleport_requested`); world subscribes.
- **Tier 4:** player world position now persists across launches (`GameState.player_pos`, saved/restored, validated).

**Deliberately deferred (too large/risky for one unsupervised pass — need incremental review):**
- Tier 1: the *logic* split of `world_render_3d.gd` (camera/terrain/animation controllers), per-tab HUD components, and `prop_meshes.gd` per-category + data-driven equip/rig. The render loop is stateful and `validate` doesn't cover it, so feel-regressions can't be caught automatically — split these one at a time with live play-testing.
- Tier 2: typed `ItemStack`/`ActionData` (touches the save format), authoring explicit slots across 1803 items, moving all tuning maps to JSON.
- Tier 3: `ActivitySim` base unifying the four sims (touches save serialization); world-gen pass pipeline (touches generation determinism).
- Tier 4/5: chunk-snapshot generator-hash invalidation; remaining magic-number/naming sweeps; ASCII icon maps → data.

---

## Worst-offender files (refactor targets)

| File | Lines | Core problem |
|------|------:|--------------|
| `scripts/render/world_render_3d.gd` | 2202 | God-object: camera + pixelation + terrain build + mover animation + batching + spawn dressing + picking in one file |
| `scripts/ui/osrs_hud.gd` | 1953 | God-object: every tab, popup, minimap, chat, settings, fps overlay + 6 inner UI classes; couples to world via `.call()` |
| `scripts/render/prop_meshes.gd` | 1855 | Giant hand-written geometry; `equip_parts()` and `enemy_rig()` are huge match towers, no data-driving |
| `tools/world_editor.gd` | 1261 | Dev tool; large but lower priority (not shipped game code) |
| `scripts/worldgen/skill_site_spawner.gd` | 626 | Rule pile: `skill == "woodcutting"/...` special-cases scattered across the file |
| `autoload/world_gen.gd` | 636 | Chunk cache/persistence OK, but snapshots don't invalidate when generator code changes |
| `scripts/worldgen/biome_classifier.gd` | 530 | Owns classification + rivers + lakes + shore + elevation all tangled in `tile_at()` |
| `scripts/worldgen/chunk_renderer.gd` | 581 | Visual baking entangled with biome logic; full-detail and LOD draw paths duplicated |
| `autoload/game_state.gd` | 623 | `slot_for_item()` infers equipment slot from display name; untyped inventory dicts; doubles as a regen clock |
| `scripts/world/world_entity_spawner.gd` | 565 | `_spawn_poi_part()` 129-line match; untyped `action` dict built in 13 places |
| `scripts/ui/main_ui.gd` | 679 | Legacy 2D Melvor UI, only kept alive by the validation smoke test |

Cross-cutting smells (everywhere): **untyped string-key dictionaries** at content/save
boundaries, **hardcoded maps and tuning constants** that should be JSON, and **magic
numbers** without provenance comments.

---

## Tier 0 — Foundations & quick wins (do first; cheap, high leverage)

These set the rules of the road and clear noise before the big surgery.

- [ ] **Delete legacy 2D UI.** Remove `scripts/ui/main_ui.gd` + `scenes/main.tscn`; retarget the `validate` smoke test off them. (Preserved on `archive/main-2d` if ever needed.)
- [ ] **Delete confirmed-dead code.** `scripts/worldgen/exploration_edge_fog.gd` (`@deprecated`, superseded by `unexplored_backdrop.gd`); audit `tools/` for one-shot scripts that can go.
- [ ] **Write `docs/STYLE_GUIDE.md`** codifying the target conventions: typed structs over string-key dicts, EventBus-first (no new `world.call()`), data-driven content (no new hardcoded maps), a soft **~600-line file budget**, and "every magic number gets a name + a why-comment."
- [ ] **Refresh `docs/TECH_DEBT.md` + `docs/ARCHITECTURE.md`** — both predate the 3D layer and cite stale line counts (e.g. HUD "~950" is now 1953). Make them describe the 3D `main`.

## Tier 1 — Break up the god-objects (the dominant debt)

Do these as you next touch each area; each unblocks all future work in that area.

- [ ] **Split `world_render_3d.gd`** into a thin orchestrator + focused units: `CameraController3D`, `TerrainMeshBuilder` (split `_build_chunk_terrain` into ground/water/shore emitters, unify the per-vertex emit helper), `MoverAnimator` (collapse the 4 near-identical `_pose_*` functions into one data-driven `_pose_from_spec`), `StaticBatcher` + `PropTransformCache`, `SpawnDressingComposer`, `PickingSystem`. Replace the 10 parallel `_mover_*` dicts with a `MoverState` class.
- [ ] **Split `osrs_hud.gd`** into per-tab components (`InventoryTab`, `EquipmentTab`, `SkillsTab`, `PrayerTab`, `MagicTab`) and standalone popups (bank/shop/slayer/obelisk); move the 6 inner classes (`_TabIcon`, `_Orb`, `_IconButton`, `MinimapPanel/Control`, `HpOrb`) to their own files; keep the HUD as a signal-wiring coordinator. Make tab registration a data list, not 6 `_build_*_tab()` calls.
- [ ] **Split `prop_meshes.gd`** into per-category builders (trees, structures, enemies, equipment) and make `equip_parts()` / `enemy_rig()` **data-driven** from specs (a `RigFactory.build(spec)` and equip-spec table) instead of match towers. Extract the repeated `get_or_compute` cache pattern into one helper.

## Tier 2 — Data-driven content & typed structures (scalability foundation)

This is the work that most directly enables "scale content without touching code."

- [ ] **Introduce typed structures** for the hot dictionaries: `ItemStack {id, qty}`, `ItemDef`, `Plot`, and a discriminated `ActionData` (gather / enemy / station / cave …). Replace `action.get("type")` string-matching in `world_entity.gd` / spawner with typed dispatch.
- [ ] **Explicit item metadata in `data/items.json`** — add `slot`, `tags`, `combatStyle` fields; delete `game_state.slot_for_item()` name-inference and the weapon-style-from-name substring rules in `combat_sim.gd`.
- [ ] **Finish the display-name → stable-id migration.** `game_state` sell/buy/bank still pass display names; make inventory/bank ID-only, resolving names once at the public boundary.
- [ ] **Move hardcoded maps & tuning to `data/`:** skill verbs + station labels (`world_entity.gd`), forest/biome lists + densities (`skill_site_spawner.gd`), combat balance coefficients + damage variance (`combat_sim.gd`), combat-AI speeds/leash/gap (`world_activity_controller.gd`), noise seed offsets + coast thresholds (`biome_classifier.gd`), and the 100-line hike dressing specs (`world_render_3d.gd`).

## Tier 3 — Unify systems & finish decoupling

- [ ] **`ActivitySim` base + `ActivityManager`.** `tick_sim`, `combat_sim`, `recipe_sim`, `farming_sim` reimplement the same `_process → advance / start → stop-others → emit` lifecycle and hardcode cross-`.stop()` calls. Extract a base lifecycle; centralize start/stop arbitration; give each a `to_save_dict()/from_save_dict()` so `save_manager` stops inspecting raw sim fields.
- [ ] **World-gen pass pipeline.** Turn generation into ordered, data-driven passes (continent → water placement → biome → elevation → sites), pulling rivers/lakes/shore out of `biome_classifier.tile_at()` and the skill special-cases out of `skill_site_spawner`. Move biome→color resolution out of `chunk_renderer` into a `BiomeColorizer` so rendering consumes data, not biome logic. Unify the full-detail/LOD draw paths.
- [ ] **Finish EventBus migration.** Replace remaining `world.call(...)` sites in `osrs_hud.gd` (auto_bank/gather/station/teleport) and `admin_menu.gd` with EventBus signals; AdminMenu should emit, not call the HUD back.

## Tier 4 — Robustness

- [ ] **Chunk snapshot invalidation.** Embed a generator-code hash in chunk snapshots so explored chunks auto-regenerate cleanly when generation logic changes (today they can silently go stale — flagged P0 in old TECH_DEBT).
- [ ] **Persist player world position** in the save (currently respawns at `spawn_position()` each launch).
- [ ] **Split the monolithic `tools/validate.gd`** (923 lines) into per-system test files; add focused tests as systems get extracted above.

## Tier 5 — Polish (ongoing, low-risk)

- [ ] Sweep magic numbers → named constants with provenance comments (camera tuning, capture frames, shore field params, crit/variance, preview dims).
- [ ] Consistent member naming (`_` prefix discipline) and shader uniform naming.
- [ ] Move large inline ASCII-art icon maps (`item_icon.gd`, `node_icon.gd`) to data files.

---

## Keep as-is (don't "refactor" these — they're good)

- The pixel-snapped camera + stable-motion algorithm in `world_render_3d.gd`.
- Terrain corner-based height sampling + per-frame memoization (the caching pattern is correct).
- The toon shader set (`shaders/*`) — small, focused, one job each.
- `save_migration.gd` — clean linear v1→vN pipeline; the model to follow.
- `event_bus.gd` and the `world.gd` controller split — the decoupling already done well.
- `content_id.gd` / `id_registry.gd` — solid stable-ID layer.
- The chunk streaming/LOD architecture in `chunk_manager.gd` (just needs clearer naming).

---

## Suggested order

1. Tier 0 (a day or two): delete dead code, write the style guide, fix the docs — sets the bar.
2. Tier 2 typed-structures + item metadata next — cheapest while content is still small; everything downstream benefits.
3. Tier 1 god-object splits opportunistically, area-by-area, as you build features there.
4. Tier 3 unification once the splits give you seams to plug into.
5. Tier 4/5 continuously.
