# Save / load / persistence

Two independent JSON saves + a read-only baked world. **The contract: no change may break a player
save; removed/renamed content degrades gracefully.** `tools/validate.gd` enforces it.

## Files
- `user://save.json` — player state (`autoload/save_manager.gd`).
- `user://world.json` — world deltas: explored-chunk snapshots, depletions, obelisks
  (`scripts/worldgen/world_store.gd`).
- `res://data/world/baked/<id>.world` — the authored finite continent, read-only
  (`scripts/worldgen/baked_world_store.gd`, built by `tools/world_bake.gd`).

## Player save (`SaveManager` + `GameState`)
- `SaveManager.save_game()` writes `{ schemaVersion, gameVersion, savedAt, <GameState.to_save_dict>,
  activity, farming }`; autosaves every 30s and on quit; honors `SaveManager.suppress`.
- `GameState.to_save_dict()` persists: `skills` (xp+level per skill), `inventory` (`[{id,qty}]`),
  `bank` (id→qty), `equipment` (slot→id), `coins`, `current_hp`, `combat_style`, `run_energy`,
  `run_enabled`, `active_prayers`, `devotion`, `slayer_task`, `slayer_points`, `player_pos` (`[x,y]`
  or null = spawn).
- `GameState.from_save_dict()` is defensive: malformed skill entries → default 1/0; unknown item ids
  → dropped with a warning; invalid `combat_style` → "attack"; slayer task for a missing monster →
  dropped; missing fields → sane defaults. It never crashes on bad data.

## Migration (`autoload/save_migration.gd`)
- `CURRENT_SCHEMA` (currently **7**) / `CURRENT_GAME_VERSION` ("0.7.0"). `migrate_game_save(data)`
  chains v1→…→current. Steps include: v2 inventory `name`→`id`; v3 slug→opaque numeric ids via
  `content_aliases.json`; v4 `gold`→`coins`; v5 skill roster remap (`SkillRemap`, folds merged
  skills' XP); v6 add `combat_style`; v7 add `run_energy` + `farming`.
- `migrate_world_save(data)` additively upgrades `user://world.json`.
- Renames resolve through `data/content_aliases.json` + `DataRegistry.resolve_item_id`.

## World save (`WorldStore`)
- `user://world.json`: `seed`, `obelisks`, `visitedZones`, `depleted` (chunk→{site_index:respawn_at}),
  `chunkSnapshots`, `explored`, `schemaVersion`, `generatorVersion`.
- `GENERATOR_VERSION` (in `world_store.gd`): bump it when generation logic changes — stale snapshots
  with a mismatched version are discarded and regenerated. Baked finite surface chunks are never
  snapshotted (authored data wins).

## Save-safety contract & validation (`tools/validate.gd`)
Run `godot --headless --path . res://tools/validate.tscn`. Relevant phases:
- Phase 0/0b/0c — content schema, stable ids, every recipe/drop/node resolves to a real item.
- Phase 2 — skill roster (22 skills, no legacy keys).
- Phase 3 — **save round-trip** (to_save→JSON→from_save preserves everything),
  **migration** (legacy v1/v2 load), **fallbacks (3e)** (malformed/removed content degrades, nothing
  crashes), and **rename/alias** resolution (3d).
- Phase 6 — chunk-snapshot persistence + farming/run-energy save.

## Adding a new persisted field — pattern
1. Add the var + initialize in `GameState.reset_state()`.
2. Add it to `GameState.to_save_dict()`.
3. Read it with a default in `GameState.from_save_dict()`:
   `my_field = int(d.get("my_field", DEFAULT))` — old saves without it must not break.
4. Only bump `SaveMigration.CURRENT_SCHEMA` + add a `_migrate_vN_to_vN+1` if old saves need
   re-derivation (a plain defaulted read usually suffices).
5. Add a round-trip + missing-field check to `tools/validate.gd` (mirror Phase 3) and run validate.

## Don'ts
- Never store a node/scene/model reference in a save — only data.
- Never change a `data/*.json` `id`/`name`, a skill key, or a save key without a migration.
- Honor `suppress` flags in any new persistence path (tools/tests must not write real saves).
- Background doc `docs/SAVE_FORMAT.md` is maintained at schema v7 (matches the code); keep it in sync
  with this page if you change the format.
