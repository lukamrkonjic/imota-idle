# Save Format

## Game save — `user://save.json`

Managed by `SaveManager` + `GameState`. Autosaves every 30s and on quit.

### Schema version 7 (current)

`SaveMigration.CURRENT_SCHEMA = 7`, `CURRENT_GAME_VERSION = "0.7.0"`. The full shape written by
`GameState.to_save_dict()` (plus `SaveManager` metadata + `activity` + `farming`):

```json
{
  "schemaVersion": 7,
  "gameVersion": "0.7.0",
  "savedAt": 1710000000.0,
  "skills": { "<skill_id>": { "xp": 0.0, "level": 1 } },
  "inventory": [{ "id": "item.1042", "qty": 5 }],
  "bank": { "item.1042": 20 },
  "equipment": { "Axe": "item.1311", "Weapon": "item.1327" },
  "coins": 0,
  "current_hp": 10,
  "combat_style": "attack",
  "run_energy": 100.0,
  "run_enabled": false,
  "active_prayers": [],
  "devotion": -1,
  "slayer_task": {},
  "slayer_points": 0,
  "player_pos": [384.0, 384.0],

  "activity": { "kind": "gather", "skill": "woodcutting", "node_id": "node.1023" },
  "farming": { "plotCount": 3, "plots": [] }
}
```

Notes: `player_pos` is `[x, y]` or `null` (= use spawn). `devotion` of `-1` lazily fills to full on
first read. `slayer_task` is `{}` (none) or `{ monster, required, done }`. `combat_style` is the
trained combat skill. `from_save_dict` reads every field with a default, so older/partial saves load
without crashing (unknown item ids are dropped with a warning; a slayer task for a removed monster is
dropped; an invalid `combat_style` falls back to `"attack"`).

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

### Schema version 6 → 7 (skill loops, Phase 6)

`_migrate_v6_to_v7` adds `run_energy` (the Agility meta-stat, default 100) and a `farming`
block (`{ plotCount, plots[] }`, default 3 empty plots). The `farming` block is written by
`FarmingSim.to_save()` and restored in `SaveManager.load_game`; each plot stores its seed,
crop, xp, yield, grow-ticks and current age, so an in-progress crop survives save/load.
Farming growth advances on the global tick **only while the game is open** (no offline).
Prayer (bury bones) and High Alchemy are pure actions — nothing new is persisted for them.

### Schema version 5 → 6 (combat depth, Phase 5)

`_migrate_v5_to_v6` adds the persisted `combat_style` (the trained combat skill); older saves
default to `"attack"`. Everything else in Phase 5 is stats/behaviour re-read from data and is
not stored: per-hit XP routing (`CombatStyles`), per-weapon `attackSpeed`, the combat-level
derivation, `DropRoller` loot, and on-death random-equipped-slot loss (Protect Item negates).

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
  "schemaVersion": 7,
  "generatorVersion": 20,
  "seed": 7,
  "obelisks": { "0:0:0": { "name": "Obelisk (Zone)", "x": 384.0, "y": 384.0 } },
  "visitedZones": { "zone_id": true },
  "depleted": { "0:0:0": { "0": 1710000025.0 } },
  "explored": { "0:0": true },
  "chunkSnapshots": {
    "0:0:0": {
      "layer": 0, "cx": 0, "cy": 0,
      "generatorVersion": 20,
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
- **depleted** — gather site respawn timers (absolute unix time), per chunk → `{site_index: respawn_at}`.
- **explored** — `"cx:cy" → true` surface reveal (fog-of-war).
- **chunkSnapshots** — frozen chunk data for explored areas. A snapshot whose `generatorVersion`
  doesn't match `WorldStore.GENERATOR_VERSION` is discarded and regenerated. Baked finite-world
  surface chunks are never snapshotted (authored data wins). See `docs/WORLDGEN_GUIDE.md`.
- **generatorVersion** — `WorldStore.GENERATOR_VERSION` (currently 20); bump when generation logic
  changes so stale snapshots regenerate. The world-save `schemaVersion` tracks `SaveMigration.CURRENT_SCHEMA`.

## Renaming content safely (Phase 3 IP rename)

Display names are presentation-only; the `id` (frozen numeric) and the legacy `name` field are
the permanent contract. The IP rename pass (spec §7) therefore touches **`displayName` only**:

1. `data/rename_map.json` holds `tokens` (whole-word substitutions that cascade across every
   item/node/enemy sharing a Bloobs-coined material word, e.g. `Cerulium` → `Azurite`) and
   `exact` full-name overrides (bosses, malformed names).
2. `scripts/content/content_rename.gd` applies the map; `tools/apply_renames.gd` stamps a
   `displayName` onto every entry, and the importer does the same so re-imports stay consistent.
3. The `name` field stays the original Bloobs name, so recipe/drop/node cross-references and old
   saves keep resolving. `DataRegistry` indexes both `name` and `displayName` → the same id.
4. **All UI/log display must render `displayName`** (via `DataRegistry.item_display_name()` /
   `enemy_display_name()` or the entry's `displayName`), never the raw `name`.

`tools/validate.tscn` audits that no Bloobs token leaks into any display name and that legacy
names still resolve to their frozen ids.
