# Common task recipes

Step-by-step for frequent tasks. Each lists the files to inspect FIRST. Always finish with
`godot --headless --path . res://tools/validate.tscn`.

## Add a new inventory item
Inspect: `data/items.json`, `scripts/content/item_def.gd`, `autoload/data_registry.gd`.
1. Add an entry to `data/items.json` keyed by a frozen `name`; set `displayName`, `category`,
   `value`, `slot`/`tier`/stats as needed. Omit `id` (DataRegistry assigns a stable one) or set one.
2. (Optional) Add a `rename_map.json` entry if the shown name should differ from `name`.
3. Validate. Use it via `GameState.add_item("Name")` or by referencing it from a node/recipe/drop.

## Add a new mineable rock / gather node
Inspect: `data/gather_nodes.json`, `data/world/skill_sites.json`, `scripts/worldgen/skill_site_spawner.gd`.
1. Add a node under the skill in `data/gather_nodes.json`: `{name, displayName, level, xp, items:[...]}`.
2. Ensure each item in `items` exists in `data/items.json` (add if new).
3. (Optional) Add a regex rule in `data/world/skill_sites.json` to bias its biomes/cave layers.
4. Re-bake the world (`tools/world_bake.tscn` / `imota bake`) or place it via the editor Skills tool.
5. Validate (Phase 1 gather + Phase 0b content resolve).

## Add a new tool
Inspect: `data/tools.json`, `data/items.json`, `autoload/skill_registry.gd` (`tool_slot`),
`autoload/game_state.gd` (`tool_progress`).
1. Add to `data/tools.json`: `{name, skill, level, progress, value}` (higher `progress` = faster).
2. Add the equippable item to `data/items.json` (`category:"tool"`, correct `slot`).
3. Validate; equip with `GameState.equip(name)`.

## Add / adjust a player gather animation
Inspect: `scripts/render/mover_rig.gd` (`_pose_gather_work`), `scripts/render/mover_renderer_3d.gd`
(`_animate_mover` skill→work mapping, `_refresh_gather_tool`), `scripts/render/mover_meshes.gd`
(`weapon_profile`/`equip_parts` if a held tool).
1. Add/modify the `match work:` case in `_pose_gather_work` (use `_set_pivot` on arm/elbow/spine; the
   gather skills already follow this).
2. If a new skill needs it, map `TickSim.skill → work` in `_animate_mover` and add a tool branch in
   `_refresh_gather_tool` (+ a `weapon_profile`/`equip_parts` entry for the tool mesh).
3. Verify with `tools/fish_shot.tscn` (it forces each skill's pose and saves PNGs). Validate.

## Add a new fishing spot
Inspect: `scripts/world/fishing_helper.gd`, `tools/world_editor.gd` (`_place_skill_site`),
`scripts/render/fishing_decor_3d.gd`.
- Easiest: world editor → Skills → Fishing → pick the fish → click a SHORE tile next to water
  (auto-binds `fish_tx/fish_ty`). Save (Ctrl+S). The spot becomes a `fish` site + a `fish_school`
  decor node (rendered as bubbles).
- In data: add a `fishing` node to `data/gather_nodes.json`; sites then spawn near water per
  `skill_sites.json` (`waterEdge:true`) on bake.

## Add a new UI panel / tab
Inspect: `scripts/ui/osrs_hud.gd` (`_build_side_panel`), an existing `scripts/ui/tabs/*.gd`.
1. New `scripts/ui/tabs/<x>_tab.gd` (RefCounted, `class_name Hud<X>Tab`, `build()`+`refresh()`).
2. Preload + `tabs.add_child(_x_tab.build())` in `_build_side_panel`; add a tab-icon `defs` entry.
3. Connect the EventBus signals it needs in `osrs_hud._ready()`. Validate / launch the game.

## Add a new map/world node (station/landmark/interactable)
Inspect: `scripts/world/world_entity.gd`, `scripts/world/world_entity_spawner.gd`,
`data/world/pois.json`, `scripts/render/prop_meshes.gd`.
1. Define the entity `kind` + `action` (e.g. `{type:"station", station:"forge", skill:"smithing"}`).
2. Spawn it from POI/chunk data (handle the part in `world_entity_spawner._spawn_poi_part`).
3. Handle its action in `world_activity_controller.execute_action` (or reuse a station key in
   `STATION_OPEN`). Give it a 3D mesh (`prop_meshes.gd` or `.glb`). Re-bake. Validate.

## Add a new NPC / interactable
Inspect: `data/npcs.json`, `scripts/ui/hud_popups.gd` (`open_npc_dialog`).
1. Add the NPC to `data/npcs.json`. 2. Spawn a `WorldEntity kind="npc"` with `action={type:"npc",
   npc:<id>}`. 3. Dialog opens via `hud.open_npc_dialog`. Validate.

## Add a new skill/progression reward
Inspect: `data/skills.json`, `autoload/game_state.gd` (`add_xp`), `data/xp_table.json`.
- A new gatherable/craftable reward → add the node/recipe (above). A whole new SKILL needs UI + sim
  wiring and is non-trivial — coordinate via `OPEN_QUESTIONS.md` first.

## Add a new save field
Inspect: `autoload/game_state.gd` (`to_save_dict`/`from_save_dict`/`reset_state`),
`autoload/save_migration.gd`, `tools/validate.gd` (Phase 3).
1. Add var + reset default. 2. Add to `to_save_dict`. 3. Read with default in `from_save_dict`.
4. Migration only if old saves need re-derivation. 5. Add a round-trip + missing-field check to
   `validate.gd`. Validate.

## Debug a broken signal
Inspect: `autoload/event_bus.gd`. Confirm the signal name + args; grep `.emit(` and `.connect(`;
check the handler signature matches the arg count. See `TROUBLESHOOTING.md`.

## Debug a scene/node reference issue
Inspect: `scripts/world/world.gd` (`_build_scene`). Confirm the node name exists and is created;
remember most nodes are code-built, not in `world.tscn`. `get_node`/`$Name` must match `world.gd`.

## Debug animation orientation / tool-holding
Inspect: `scripts/render/mover_meshes.gd` (`weapon_profile` rot/`equip_parts` geometry),
`scripts/render/mover_rig.gd` (the pose). Tool sideways/upside-down = profile rotation; tool not in
hand = `_refresh_gather_tool` branch / `equip_loadout` mapping. Verify with `tools/fish_shot.tscn` /
`tools/weapon_pose_preview.tscn`.
