# Signals & events

All cross-system communication goes through **`EventBus`** (`autoload/event_bus.gd`), a stateless
signal hub. Emitters are GameState/sims/world; the main listener is the HUD (`scripts/ui/osrs_hud.gd`)
plus `Audio` and the 3D FX layer. **To wire feedback, connect an EventBus signal — don't poll.**

> Always open `autoload/event_bus.gd` to confirm exact names/arguments before connecting; the list
> below is grounded but the file is the source of truth.

## Progression
- `xp_gained(skill: String, amount: float)` — emitted by `GameState.add_xp`. HUD updates that skill's
  cell; floating XP via `world_visual_controller`.
- `level_up(skill: String, new_level: int)` — `GameState.add_xp` on threshold. HUD chat + skills tab;
  `world_path_controller.on_level_up` (paths may unlock).

## Inventory / economy
- `inventory_changed` — `GameState.add_item/remove_item`. HUD inventory tab.
- `bank_changed` — `GameState.deposit/withdraw`.
- `equipment_changed` — `GameState.equip/unequip`. HUD equipment + combat tabs; 3D rig re-dresses
  (`MoverRenderer3D._apply_player_equipment` connects this).
- `coins_changed(amount)` — `GameState.add_coins`. HUD coins label.
- `loot_gained(item, qty)` — sims on reward. HUD chat splat.
- `hp_changed(current, max)` — `GameState.set_hp`/food. HUD HP orb.

## Activity
- `activity_started(kind, label)` / `activity_stopped(reason)` — sims start/stop ("gather"/"combat"/
  "craft"). HUD chat / state.
- `action_progress(fraction)` — `RecipeSim` craft progress bar.

## Combat
- `combat_log(text)` — colored log lines (many emitters). HUD chatbox.
- `combat_hit_splat(amount, miss, on_player)` — per hit. 3D/2D hitsplat.
- `combat_ranged_shot(amount, miss)` — arrow projectile (ranged). `MoverRenderer3D` marks an attack.
- `enemy_hp_changed(current, max)`, `enemy_killed(name)`, `enemy_respawning(seconds)`,
  `player_died(enemy)`.

## Skills feedback / world FX
- `wc_log_chopped(pos, species)` — woodcutting per-log leaves puff (`WorldFx3D._on_wc_log`, `Audio`).
- `wc_tree_felled(entity, species)` / `wc_tree_grew(entity, species)` — tree topple / regrow.
- `mining_struck(pos)` — per-ore rock-chip puff (`WorldFx3D._on_mining_struck`). Emitted in
  `world_activity_controller.on_xp_gained` for mining.
- `firemaking_log_burned()`, `prayer_changed()`, `prayer_activated(name)`, `farming_changed`,
  `run_energy_changed(value)`, `slayer_changed`.

## World / zones
- `zone_changed(zone_name, level_req)` — HUD zone banner.
- `world_layer_changed(layer)` — cave/underground banner.
- `site_depleted(chunk_key, index)` / `site_respawned(chunk_key, index)`.
- `teleport_requested(pos)` — obelisk/menu → `world_layer_controller`.

## Intents (UI → world)
- `bank_requested` → `world._auto_task_ctrl.auto_bank()`.
- `gather_requested(skill, node)` → `auto_gather`.
- `station_requested(skill, recipe)` → `auto_station`.
- `navigate_requested(pos)` → minimap click → walk.
- `rest_requested` → run orb right-click → halt player.

## Lifecycle
- `game_loaded` — `SaveManager` after load. HUD `_refresh_all()`.
- `GameSettings.changed(prop)` — settings; e.g. render presenter reacts to `pixelation`.
- `Weather.changed(mode)`, `DayNight.phase_changed(phase)`.

## Debugging a broken signal
1. Confirm the signal exists in `event_bus.gd` (name + arg count/types).
2. Confirm the **emitter** actually emits it (grep `EventBus.<signal>.emit`).
3. Confirm the **listener** connects it (grep `<signal>.connect`) and the handler signature matches.
4. Mismatched arg counts silently fail to connect at runtime — check the editor/CLI errors.
See `TROUBLESHOOTING.md`.
