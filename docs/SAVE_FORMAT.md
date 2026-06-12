# Save Format

## Game save — `user://save.json`

Managed by `SaveManager` + `GameState`. Autosaves every 30s and on quit.

### Schema version 2 (current)

```json
{
  "schemaVersion": 2,
  "gameVersion": "0.2.0",
  "skills": { "<skill_id>": { "xp": 0.0, "level": 1 } },
  "inventory": [{ "id": "item.logs", "qty": 5 }],
  "bank": { "item.logs": 20 },
  "equipment": { "Axe": "item.bronze_axe", "Weapon": "item.bronze_sword" },
  "gold": 0,
  "current_hp": 10,
  "savedAt": 1710000000.0,
  "activity": {
    "kind": "gather",
    "skill": "woodcutting",
    "node_id": "node.woodcutting.regular_tree"
  }
}
```

Activity kinds:

| kind | fields |
|------|--------|
| `gather` | `skill`, `node_id` |
| `combat` | `enemy_id`, `train` |
| `craft` | `skill`, `recipe_id` |

### Schema version 1 (legacy)

Inventory used `"name"` instead of `"id"`. Bank keys and equipment values were display names. `SaveMigration.migrate_game_save()` upgrades v1 → v2 on load.

Unknown items during migration produce a warning and are skipped (no crash).

## World save — `user://world.json`

Managed by `WorldStore`. Written alongside the game save.

```json
{
  "schemaVersion": 2,
  "generatorVersion": 1,
  "seed": 7,
  "obelisks": { "0:0:0": { "name": "Obelisk (Zone)", "x": 384.0, "y": 384.0 } },
  "visitedZones": { "zone_id": true },
  "depleted": { "0:0:0": { "0": 1710000025.0 } },
  "chunkSnapshots": {
    "0:0:0": {
      "layer": 0, "cx": 0, "cy": 0,
      "generatorVersion": 1,
      "tiles": [0, 1, 2],
      "biomes": [0, 0, 1],
      "zone": { "req": 1, "name": "Green Timberland" },
      "safe": true,
      "sites": [],
      "pois": [],
      "monsters": []
    }
  }
}
```

- **seed** — world RNG seed (unchanged across sessions).
- **depleted** — gather site respawn timers (absolute unix time).
- **chunkSnapshots** — frozen chunk data for explored areas. See `docs/WORLDGEN_GUIDE.md`.
- **generatorVersion** — bump in `WorldStore.GENERATOR_VERSION` when generation logic changes.

## Renaming content safely

1. Keep the stable `id` unchanged in data (or in runtime index).
2. Add an entry to `data/content_aliases.json`:
   ```json
   { "items": { "Old Display Name": "item.logs" } }
   ```
3. Update `displayName` in data if desired.
4. Old saves and references resolve through `DataRegistry.resolve_*_id()`.
