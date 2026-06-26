# Inventory, items & resources

## Item definitions
- **Data:** `data/items.json`, keyed by the item's frozen `name`. Fields: `id` (stable, e.g.
  `item.acadia_logs` or `item.1042`), `name` (frozen legacy key), `displayName` (presentation; may be
  rewritten by `data/rename_map.json`), `category` (material/equipment/tool/consumable), `value`,
  `slot`, `tier`, combat stats (`accuracy`,`damage`,`damageReduction`,`critChance`,`attackSpeed`,…),
  `bonusXp`, `reqs`, render hints (`renderKind`/`renderMaterial`/`renderTint`), `stackable`.
- **Typed wrapper:** `scripts/content/item_def.gd` (`ItemDef`). `ItemDef.from_dict(d)`;
  `is_equippable()`, `weapon_style()`, `weapon_category()`, `attack_bonuses()`,
  `strength_bonuses()`, `defence_bonuses()`, `attack_ticks()`.
- **Lookup:** `DataRegistry.get_item(name_or_id)` (raw dict), `item_def(name_or_id)` (typed),
  `item_display_name(name_or_id)`, `resolve_item_id(value)` → stable id ("" if unknown).

## IDs, renames, aliases (why saves survive content edits)
- `scripts/content/content_id.gd` (`ContentId`): id prefixes `item.`/`node.`/`enemy.`/`recipe.`;
  `slug()`, `item_id()`, etc. `DataRegistry` auto-assigns ids on load if missing.
- `data/id_registry.json` — semantic id ↔ stable slug id mapping (+ `next` counter).
- `data/rename_map.json` — `tokens` (word substitutions) + `exact` overrides applied to
  **`displayName` only**. The `name`/`id` stay frozen, so saves/cross-refs survive a rename.
- `data/content_aliases.json` — old names → stable ids, used by save migration + `resolve_item_id`.
- **Rule:** to rename what the player sees, edit `displayName`/`rename_map.json`. NEVER change
  `id`/`name` (breaks saves + every reference).

## Inventory / bank / equipment state (`autoload/game_state.gd`)
- `inventory: Array` of `{id, qty}` (stable id), 28 slots (`BASE_INVENTORY_SLOTS`). Stackable items
  share a slot; others take one each.
- `bank: Dictionary` id→qty (unlimited). `equipment: Dictionary` slot→id (slots incl Weapon, Helm,
  Body, Boots, Shield, Ring, Gloves, Cape, Amulet, Ammunition, **Axe, Pickaxe, Rod, Lens**).
- `coins: int`.
- Methods: `add_item(name_or_id, qty)` (returns qty added; 0 if full; emits `inventory_changed`),
  `remove_item`, `count_item`, `deposit/withdraw/deposit_all`, `equip` (level-gated via
  `meets_requirements` + `ItemDef.is_equippable`; emits `equipment_changed`), `unequip`, `add_coins`,
  `calculate_equipment_bonuses`, `best_food_id`, `auto_eat`.
- Persisted in `to_save_dict`/`from_save_dict` (graceful: unknown ids dropped with a warning).

## Tools (gate gathering)
- **Data:** `data/tools.json` (entry per tool: `skill`, `level`, `progress`, `value`) + the matching
  equippable item in `data/items.json` (`category:"tool"`, `slot:"Axe"|"Pickaxe"|"Rod"|"Lens"`).
- **Slot mapping:** `SkillRegistry.tool_slot(skill)` → "Axe"/"Pickaxe"/"Rod"/"Lens" (or "" for
  toolless hunter/thieving, which use `SkillRegistry.base_progress`).
- **Check:** `GameState.tool_progress(skill)` reads the equipped tool's `progress`; `TickSim.start_gather`
  refuses to start if it's ≤ 0 ("No suitable tool equipped"). Higher progress = faster gathering.
- The 3D rig swaps the matching tool into hand while gathering (`MoverRenderer3D._refresh_gather_tool`).

## Recipes / production
- **Data:** `data/recipes.json`, keyed `"skill/Name"`. Fields: `id`, `skill`, `name`, `displayName`,
  `levelReq`, `time`, `xp`, `inputs` (`[{item, qty}]`), `output` (`{item, qty}`), `hpValue` (food),
  `unburnable`. Typed: `scripts/content/recipe_def.gd` (`RecipeDef`). Indexed `DataRegistry.recipes_by_skill`.
- **Run:** `RecipeSim.start_craft(skill, name)` checks level + `_has_inputs`; `_complete_craft`
  consumes inputs, produces output, awards xp, emits `loot_gained` (+`firemaking_log_burned`),
  auto-stops when out of inputs. Food `hpValue` feeds `GameState.best_food_id`/`auto_eat`.

## Gather nodes
- **Data:** `data/gather_nodes.json` keyed by skill; node fields `id`, `name`, `displayName`,
  `level`, `xp`, `items` (Array of item names — multiple = multi-yield). Typed:
  `scripts/content/gather_node_def.gd` (`GatherNodeDef`). DataRegistry resolves `items`→`itemIds`.
- Where they spawn: `scripts/worldgen/skill_site_spawner.gd` + `data/world/skill_sites.json` (per-skill
  `kind`, biomes, cave layers, `resources`, `respawnSec`, `waterEdge`). See `WORLD_MAP_AND_NODES.md`.

## Add a new item / tool / node — see `COMMON_TASK_RECIPES.md`
Short version: add the JSON entry (frozen `name`, let `DataRegistry` assign `id`), add any referenced
output item, run `validate.tscn`. No code needed for content. `tools/validate_content.gd` checks that
every recipe/drop/node references a real item.
