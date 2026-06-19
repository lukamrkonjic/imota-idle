# Content Data Schema

`data/*.json` is the **canonical, hand-authored** source of truth (the old
`tools/import_bloobs_data.gd` is retired). This documents the field set of each entity.
See [../CONTENT_GUIDE.md](../CONTENT_GUIDE.md) for the add/rename workflow.

## Identity & references — the contract

- **`id`** is an opaque, frozen, numeric stable id (`item.1042`, `enemy.1107`, `node.1168`,
  `recipe.1776`). Assigned exactly once via `data/id_registry.json` (`next` counters),
  **never reused, never derived from a name**. This is the permanent on-disk + save contract.
- **`name`** is the top-level JSON key and the frozen legacy string. **`displayName`** is the
  presentation name and is the *only* thing a rename may change.
- **Cross-references** (recipe `inputs`/`output`, enemy `drops`, node `items`) reference items
  by **`name`** string. They resolve through `DataRegistry.resolve_item_id()`:
  `content_aliases.json` slug → `name` → `displayName` → id. A reference that resolves to
  nothing is a **hard validation error** (`tools/validate_content.gd`), except the currency
  token (below).
- **Currency token:** a drop/recipe ref of `"Gold"` (legacy) or `"Coins"` is a pseudo-item the
  drop system converts to Coins — it is *not* a real item and is whitelisted from ref checks.
  Real currency-drop wiring is Phase 7.

## Item (`data/items.json`) — keyed by `name`

Required on every item:

| Field | Type | Notes |
|---|---|---|
| `id` | string | opaque stable id `item.<N>` |
| `name` | string | frozen legacy key (== the JSON key) |
| `displayName` | string | presentation name; the only rename-mutable field |
| `value` | float | base shop/alch value (Coins) |
| `category` | string | `material` \| `equipment` \| `tool` \| `consumable` |
| `tier` | int | progression tier (0 = none) |
| `levelBand` | string | e.g. `"40-49"`, `"none"` |
| `stackable` | bool | inventory stacking |
| `info` | string | one-line flavour/usage hint |
| `reqs` | object | `{skill: level}` to equip/use (e.g. `{"woodcutting": 50}`) |
| `bonusXp` | object | `{skill: mult}` passive XP bonuses (usually `{}`) |
| stat block | float | `accuracy`, `damage`, `critChance`, `damageReduction`, `magicAccuracy`, `magicDamage`, `rangeAccuracy`, `rangeDamage`, `runSpeed`, `progress` (tool action power) — 0.0 when N/A |

Conditional:

| Field | When | Notes |
|---|---|---|
| `slot` | equipment + tools | `Weapon`/`Head`/`Body`/`Ring`/`Axe`/`Pickaxe`/`Rod`/`Lens`/… — **explicit**, never inferred from the name |
| `combatStyle` | weapons | drives XP routing |

## Recipe (`data/recipes.json`) — keyed by `"skill/name"`

`id`, `name`, `displayName`, `skill`, `levelReq` (int), `xp` (float), `time` (s),
`inputs` (array of `{item, qty}`), `output` (`{item, qty}`), `hpValue` (food HP, 0 if none),
`unburnable` (bool). Optional: `balanceStatus` (authoring note).

## Enemy (`data/enemies.json`) — keyed by `name`

`id`, `name`, `displayName`, `level`, `maxHealth`, `style`, `accuracy`, `damage`,
`damageReduction`, `critChance`, `critMultiplier`, `cooldown`, `combatXp`, `hitpointsXp`,
`isBoss` (bool), `drops` (array of `{item, chance (0<c≤1), min, max}`). `beastMasteryReq`/
`beastMasteryXp` are the per-enemy slayer gate (Beastmastery is folded into Slayer, per the
build plan — not its own skill).

## Gather node (`data/gather_nodes.json`) — `skill → [node, …]`

`id`, `name`, `displayName`, `level` (int), `xp` (float), `items` (array of item `name`s the
node yields). `skill` is added at load from the top-level key.

## Reserved (removed) item fields

`tags`, `rarity`, `deprecated` were enrichment-pass leftovers — declared but never populated
(all `[]` / `"common"` / `false`) and read by no code. **Removed** for a clean schema;
reintroduce per-need if a system actually consumes them (e.g. `tags` for tradeable/quest
flags, `deprecated` to tombstone a removed item whose id must stay reserved).
