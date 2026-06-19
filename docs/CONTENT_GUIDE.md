# Content Guide

## Rules

- Every entity has a **stable id** (`item.logs`, `node.woodcutting.regular_tree`, `enemy.chickens`, `recipe.cooking.shrimp`).
- **Display names** are presentation only. Never use them as save keys or primary references.
- Renames go through `data/content_aliases.json`.

## Adding an item

`data/*.json` is the canonical, hand-authored source of truth — see [content/SCHEMA.md](content/SCHEMA.md)
for the field reference. (The old `tools/import_bloobs_data.gd` is **retired**; the data has
diverged from any export and re-importing would discard enrichment fields.)

1. Add an entry to `data/items.json` keyed by `name`, with `value` + a `category`, mirroring a
   sibling item of the same kind (material / equipment / tool / consumable).
2. Stamp an explicit opaque `id` (`item.<N>`, next id from `data/id_registry.json`) and record
   its slug→id in `data/id_registry.json` and `data/content_aliases.json` — never name-derived.
3. Run validation: `godot --headless --path <project> res://tools/validate.tscn`. Recipe/node/
   drop references to items are now **hard errors** if they don't resolve.

## Renaming an item safely

1. Do **not** change the stable id.
2. Add alias: `"Old Name": "item.existing_id"` in `content_aliases.json` → `items`.
3. Change `name` / `displayName` in the item dict.
4. Validation tests alias resolution in `phase3_rename_alias`.

## Adding a gather node

1. Add entry to `data/gather_nodes.json` under the skill array.
2. Id is assigned as `node.<skill>.<slug>` from the node `name` field.
3. Ensure `items[]` references exist in `items.json`.

## Adding a recipe

1. Add to `data/recipes.json` with key `skill/RecipeName`.
2. Id: `recipe.<skill>.<slug>`.
3. `inputs[].item` and `output.item` must resolve via `DataRegistry.resolve_item_id()`.

## Adding an enemy drop

1. Edit `data/enemies.json` drop table.
2. `drops[].item` must be a valid item display name or id.

## Adding a biome / skill site / POI

World content lives in `data/world/`:

| File | Purpose |
|------|---------|
| `biomes.json` | Tiles + biome classification rules |
| `skill_sites.json` | Site spawn weights and station defs |
| `monsters.json` | Monster placement rules |
| `pois.json` | Campsites, obelisks, caves |
| `cave_layers.json` | Underground layers |

After edits, run the validation suite.

## API quick reference

```gdscript
DataRegistry.resolve_item_id("Logs")           # -> "item.logs"
DataRegistry.resolve_node_id("woodcutting", "Regular Tree")
DataRegistry.get_item("item.logs")             # works with id or name
DataRegistry.item_display_name("item.logs")    # -> "Logs"
```
