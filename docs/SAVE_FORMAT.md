# Save Format

## Game save — `user://save.json`

Managed by `SaveManager` + `GameState`. Autosaves every 30s and on quit.

### Schema version 5 (current)

```json
{
  "schemaVersion": 5,
  "gameVersion": "0.5.0",
  "skills": { "<skill_id>": { "xp": 0.0, "level": 1 } },
  "inventory": [{ "id": "item.1042", "qty": 5 }],
  "bank": { "item.1042": 20 },
  "equipment": { "Axe": "item.1311", "Weapon": "item.1327" },
  "coins": 0,
  "current_hp": 10,
  "savedAt": 1710000000.0,
  "activity": {
    "kind": "gather",
    "skill": "woodcutting",
    "node_id": "node.1023"
  }
}
```

### Opaque numeric ids + the id registry (Phase 0)

**Decision:** content ids are opaque, frozen, OSRS-style numbers behind a type prefix
(`item.1042`, `enemy.1009`, `node.1023`, `recipe.1187`) — **never** derived from the
display name. **Why:** the old scheme slugged the name (`item.suncoil_logs`), so the
IP-rename pass (Phase 3) would have changed every id and broken live saves. **Consequence:**
display names are now pure presentation and rename freely; the id is the permanent contract.

- `data/id_registry.json` is the record of truth: it maps each content's *legacy slug id*
  (the old name-derived id, what live v2 saves hold) → its frozen numeric id, plus a `next`
  counter per kind. `scripts/content/id_registry.gd` mints through it.
- The importer (`tools/import_bloobs_data.gd`) and the one-shot `tools/stamp_ids.gd` both
  mint via the registry, so **re-imports preserve every existing assignment** and only mint
  ids for genuinely new content. Ids are never reused after a removal.
- Data files (`items.json`, …) carry an explicit `id` per entry; recipes/drops/nodes still
  cross-reference items by **name** and resolve to ids at load, keeping data human-readable.

### Schema version 4 → 5 (skill roster, Phase 2)

`_migrate_v4_to_v5` rewrites Bloobs skill keys in the `skills` dict to the OSRS-style roster
via `SkillRemap` (devotion→prayer, tracking→hunter, dexterity→agility, homesteading→farming,
herbology→alchemy, beastmastery→slayer; imbuing+soulbinding fold into crafting). XP/levels are
preserved and folded skills **sum** their XP, so no progress is lost. `SkillRemap` is the single
source of truth, also used by `tools/remap_skills.gd` (data) and the importer (which mints ids
from the original Bloobs slug, then writes the new skill name — keeping the id registry stable).

### Schema version 3 → 4 (currency rename, Phase 1)

The currency field `gold` was renamed to `coins` (Imota spec §0). `_migrate_v3_to_v4` copies
`gold` → `coins` and drops the old key; `GameState.from_save_dict` also reads `coins` with a
`gold` fallback. Other Phase 1 mechanical changes (inventory 24→28, XP table regenerated from
the OSRS formula × `S=1.25` to a level-99 cap, and **offline progress removed entirely**) do
not change the save shape — stats/curves re-read from `data/*.json` at load.

### Schema version 2 (legacy)

Inventory/bank/equipment held **name-derived slug ids** (`item.logs`). `data/content_aliases.json`
maps every old slug id → its numeric id, and `_migrate_v2_to_v3` re-resolves all id-bearing
save fields. Proven by `tools/validate.tscn` (zero "unknown item" loss).

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
