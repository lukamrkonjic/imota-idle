# Data flow

How a player action becomes XP/items/feedback, and how the HUD stays in sync.

## 1. Click → action → walk → execute
```
InputEventMouseButton (left)              scripts/world/world_input_controller.gd: handle_input()
  → _over_ui()? if HUD, ignore
  → click_pos = world.mouse_world_pos()   (3D camera projection when render_3d active)
  → target = entity_at(click_pos)          (nearest WorldEntity within click_radius)
  → world.show_click_fx(...)
  → if target: world.begin_action(target)  scripts/world/world.gd
        → world_activity_controller.begin_action(entity)   scripts/world/world_activity_controller.gd
              world.pending_action = entity.action.duplicate(); ["entity_path"]=entity path
              choose stand tile by action.type:
                 enemy+ranged → in-range tile; enemy+melee → fighting gap;
                 gather+fishing → FishingHelper.best_stand (water's edge, exact_stand);
                 gather → _adjacent_stand (tile beside the node, exact_stand)
              world.walk_to_pos(target)     scripts/world/world_path_controller.gd: walk_to_pos()
     else: walk to ground (stop sims/combat first)
```
`exact_stand=true` (set in pending_action) tells `walk_to_pos` NOT to trim the last waypoint, so the
player ends exactly on the chosen adjacent/edge tile.

## 2. Arrival → execute_action
```
player.arrived (signal)  →  _path_ctrl.on_waypoint_reached() → _advance_waypoint / _on_path_finished()
  → if world.pending_action not empty: world_activity_controller.execute_action(action)
        match action.type:
          "gather"  → _start_gather(action) → TickSim.start_gather(skill, node)
                       (fishing also: FishingHelper.can_cast_from check + player.set_fish_cast)
                       world.gather_ref = {chunk, site_index, entity}
          "enemy"   → CombatSim.start_combat(name, hud.train_style()); world.combat_target_entity = entity
          "station" → STATION_OPEN[station] → open bank/shop UI, or RecipeSim.start_craft, or open recipes
          "npc"     → hud.open_npc_dialog(npc)
          "descend"/"ascend"/"obelisk"/"landmark" → world layer/teleport controller
```

## 3. Sim tick → rewards → signals
```
TickSim.advance(delta)      every ~2.4s (4 ticks): _roll_action() → success? _award_resource():
   GameState.add_item(item) → EventBus.loot_gained ; GameState.add_xp(skill, node.xp)
GameState.add_xp():
   skills[skill].xp += amount (+ equipment XP bonus) → EventBus.xp_gained(skill, total)
   while xp ≥ DataRegistry.xp_for_level(level+1): level++ → EventBus.level_up(skill, level)
GameState.add_item(): inventory mutate → EventBus.inventory_changed (returns 0 if full → sim stops)
```
Combat (`CombatSim`) and craft (`RecipeSim`) follow the same shape: tick → mutate `GameState` →
emit `EventBus` signals (`combat_hit_splat`, `enemy_killed`, `loot_gained`, `xp_gained`, …).

## 4. State → UI
The HUD (`scripts/ui/osrs_hud.gd`) connects to `EventBus` signals and refreshes the matching panel —
it does NOT poll (except live-redraw widgets like the HP/run orbs in `_process`). Examples:
`xp_gained → skills tab cell`, `inventory_changed → inventory tab`, `equipment_changed → equipment +
combat tabs`, `coins_changed → coins label`, `combat_log/loot_gained/level_up → chatbox`,
`game_loaded → refresh all`. See `SIGNALS_AND_EVENTS.md` + `UI_AND_HUD.md`.

## 5. Render mirror (cosmetic)
`World._process` ticks `render_3d._process` (when active). `MoverRenderer3D` reads `world.player` +
enemy entities and `TickSim`/`CombatSim` state to drive rig poses (walk/chop/mine/cast/attack);
`StaticPropBatcher` mirrors `world.entities` + decor; `FishingDecor3D` mirrors `world._water_decor_nodes`.
The render layer never changes gameplay state — it only reads it.

## 6. Auto-tasks (idle loops)
`EventBus.gather_requested/bank_requested/station_requested` → `world._auto_task_ctrl` sets
`world.auto_task` and calls `WorldGen.find_nearest_site/station` → `walk_to_pos` → on arrival
`execute_action`; when a site depletes, `find_next()` repeats. (`world_auto_task_controller.gd`.)

## 7. Save/Load
`SaveManager.save_game()` → `GameState.to_save_dict()` + active sim (`ActivityManager.save_active`) +
`FarmingSim.to_save()` → `user://save.json`; `WorldGen.save_world()` → `user://world.json`. Load runs
`SaveMigration.migrate_game_save` then `GameState.from_save_dict` (graceful defaults) and emits
`game_loaded`. See `SAVE_LOAD_AND_PERSISTENCE.md`.
