# Autoloads & globals

15 autoload singletons (declared in `project.godot [autoload]`, scripts in `autoload/`). They are the
backbone — reuse them; do not create parallel managers.

| Autoload | Script | Role / key API |
|---|---|---|
| **EventBus** | `event_bus.gd` | Global signal hub, NO state. All cross-system events. See `SIGNALS_AND_EVENTS.md`. |
| **DataRegistry** | `data_registry.gd` | Loads every `data/*.json` in `load_all()`. Exposes `items`, `items_by_id`, `enemies`, `recipes`, `recipes_by_skill`, `gather_nodes`, `nodes_by_id`, `prayers`, `npcs`, `xp_required`. Lookups: `item_def`, `get_item`, `item_display_name`, `resolve_item_id`, `node_def`, `recipe_def`, `enemy_def`, `xp_for_level`, `level_for_xp`. |
| **GameState** | `game_state.gd` | ALL player state: `skills`, `inventory`, `bank`, `equipment`, `coins`, `current_hp`, `combat_style`, `run_energy`, prayer/slayer sub-states, `player_pos`. Methods: `add_xp`, `level`, `add_item/remove_item/count_item`, `equip/unequip`, `deposit/withdraw`, `tool_progress`, `auto_eat`, `to_save_dict`, `from_save_dict`, `reset_state`. THE save model. |
| **SkillRegistry** | `skill_registry.gd` | Skill metadata from `data/skills.json`: `ids`, `meta`, `kind`, `is_gather`, `is_production`, `verb`, `tool_slot`, `base_progress`. |
| **TickSim** | `tick_sim.gd` | Gathering sim (extends ActivitySim). `start_gather(skill, node)`, `advance`, `success_chance`, `_award_resource`. Holds `skill`, `node` (GatherNodeDef), `active`. |
| **CombatSim** | `combat_sim.gd` | Combat sim (extends ActivitySim). `start_combat(enemy, train_style)`, `advance`, `_player_attack`, `_enemy_attack`, `_auto_eat`. Holds `enemy` (EnemyDef), `enemy_hp`, `train_skill`. |
| **RecipeSim** | `recipe_sim.gd` | Crafting sim (extends ActivitySim). `start_craft(skill, recipe)`, `advance`, `_complete_craft`. |
| **FarmingSim** | `farming_sim.gd` | Passive crop growth (`GROW_INTERVAL=30s`); `plant(seed)`; save block `farming`. |
| **PrayerSim** | `prayer_sim.gd` | Drains/regens devotion each `_process` based on active prayers. |
| **WorldGen** | `world_gen.gd` | World source of truth. `get_chunk(layer,cx,cy)`, `spawn_position`, `find_nearest_site/poi/station`, `deplete_site`, `save_world`. Owns `reg` (WorldRegistry), `store` (WorldStore → `user://world.json`), `baked` (BakedWorldStore), `chunks`. |
| **SaveManager** | `save_manager.gd` | `user://save.json` I/O; 30s autosave; save-on-quit; `suppress` flag (tools); `save_game`/`load_game`. |
| **GameSettings** | `game_settings.gd` | Pixelation, UI scale, volumes, **keybinds**, auto-eat threshold. `changed` signal. `suppress` flag. |
| **Weather** | `weather.gd` | `Weather.mode`/`tint`/`snow`/`rain`; `changed` signal; `set_mode`. |
| **DayNight** | `day_night.gd` | `time01` (0..1 day cycle, 20-min day), `daylight()`, `sun_elevation()`, `horizon_glow()`. Drives sky colour/energy (sun DIRECTION is pinned in `world_atmosphere.gd`). |
| **Audio** | `audio.gd` | Music/SFX; connects to gameplay signals (e.g. `wc_log_chopped` → chop sound). |

## Notes
- **`suppress` flags:** `SaveManager.suppress`, `GameSettings.suppress`, `WorldGen.store.suppress` are
  set true by headless tools/tests and the editor sandbox so they don't touch real save files. Honor
  them in any new persistence code.
- **GameState sub-states** live in `scripts/state/`: `prayer_state.gd`, `run_energy_state.gd`,
  `slayer_state.gd` (composed into GameState).
- **ActivitySim base:** the three foreground sims share `active` + `advance`/`stop` +
  `save_activity`/`restore_activity`; starting one stops the others (one foreground activity at a time).
- **Order matters:** DataRegistry loads before everything that reads content; WorldGen sets up after
  its registry. Keep new autoloads after their dependencies if you ever add one (rare — prefer not to).
