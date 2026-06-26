# Feature map

For each system: purpose, primary files, key classes/methods/signals, data, dependents, and how to
extend safely. Paths are repo-relative. **Read the primary files before editing.**

---

## Inventory / Items / Equipment
- **Purpose:** player items, bank, equipment, coins; item definitions + stable ids.
- **Primary files:** `autoload/game_state.gd` (state), `autoload/data_registry.gd` (lookup),
  `scripts/content/item_def.gd` (`ItemDef`), `scripts/content/content_id.gd`,
  `scripts/content/id_registry.gd`, `data/items.json`, `data/tools.json`, `data/id_registry.json`,
  `data/rename_map.json`, `data/content_aliases.json`.
- **State:** `GameState.inventory` (Array of `{id, qty}`, 28 slots), `GameState.bank` (Dict id→qty),
  `GameState.equipment` (Dict slot→id; slots incl Weapon/Helm/Body/…/Axe/Pickaxe/Rod/Lens),
  `GameState.coins`.
- **Key methods:** `GameState.add_item/remove_item/count_item/deposit/withdraw/deposit_all/equip/
  unequip/add_coins`; `DataRegistry.item_def/get_item/item_display_name/resolve_item_id`.
- **Signals:** `inventory_changed`, `bank_changed`, `equipment_changed`, `coins_changed`,
  `loot_gained`.
- **Depends on:** DataRegistry, EventBus. **Dependents:** HUD inventory/equipment tabs, sims, save.
- **Extend:** add to `data/items.json` (frozen `name`, stable `id`, `displayName`); never rename
  `id`/`name`. See `INVENTORY_ITEMS_AND_RESOURCES.md` + recipe in `COMMON_TASK_RECIPES.md`.

## Skills / XP / Progression
- **Purpose:** 22 skills, levels, XP curve, level-ups.
- **Primary files:** `autoload/skill_registry.gd` (`SkillRegistry`), `autoload/game_state.gd`
  (skills dict + `add_xp`), `data/skills.json`, `data/xp_table.json`,
  `scripts/content/skill_remap.gd` (legacy skill renames).
- **Key methods:** `GameState.add_xp(skill, amount)` / `level(skill)` / `xp(skill)`;
  `DataRegistry.xp_for_level/level_for_xp`; `SkillRegistry.ids/meta/kind/is_gather/is_production/
  verb/tool_slot/base_progress`.
- **Signals:** `xp_gained(skill, amount)`, `level_up(skill, level)`.
- **Extend:** new skill = add to `data/skills.json` (kind/icon/color/order) — but a new skill needs
  UI/sim wiring; prefer adding nodes/recipes to existing skills. See `OPEN_QUESTIONS.md`.

## Gathering (woodcutting / mining / fishing / foraging / hunter / thieving)
- **Purpose:** harvest resources from world sites.
- **Primary files:** `autoload/tick_sim.gd` (`TickSim`), `data/gather_nodes.json`,
  `scripts/content/gather_node_def.gd`, `scripts/worldgen/skill_site_spawner.gd` (places sites),
  `data/world/skill_sites.json` (per-skill kind/biome/respawn), `scripts/world/fishing_helper.gd`.
- **Key methods:** `TickSim.start_gather(skill, node_name)`, `advance`, `_roll_action`,
  `_award_resource`; site dict fields `{skill,node,level,kind,tx,ty,resources,respawn_sec,available,
  respawn_at, fish_tx/fish_ty}`; `SkillSiteSpawner.populate(chunk, occupied)`.
- **Signals:** `loot_gained`, `xp_gained`, `level_up`, `site_depleted/site_respawned`,
  `wc_log_chopped`, `wc_tree_felled`, `wc_tree_grew`, `mining_struck`.
- **Depends on:** GameState (tool/level/inventory), DataRegistry, WorldGen. **Dependents:** activity
  controller, world editor Skills tool, 3D render (gather poses, bubbles).
- **Extend:** add node to `data/gather_nodes.json` (+ item to `items.json`); optional biome rule in
  `data/world/skill_sites.json`. Recipe in `COMMON_TASK_RECIPES.md`.

## Combat
- **Purpose:** melee/ranged/magic combat vs monsters; drops, slayer.
- **Primary files:** `autoload/combat_sim.gd` (`CombatSim`), `scripts/combat/combat_calc.gd`
  (`CombatCalc`), `scripts/combat/drop_roller.gd` (`DropRoller`), `scripts/combat/attack_styles.gd`,
  `scripts/combat/combat_styles.gd`, `scripts/combat/combat_constants.gd`, `data/enemies.json`,
  `data/world/monsters.json`, `data/rare_drop_table.json`, `scripts/content/enemy_def.gd`.
  Background: `docs/COMBAT.md`.
- **Key methods:** `CombatSim.start_combat(enemy_name, train_style, player_initiated)`, `advance`,
  `_player_attack`, `_enemy_attack`, `_auto_eat`; `GameState.combat_style`,
  `GameState.calculate_equipment_bonuses`.
- **Signals:** `combat_log`, `combat_hit_splat(amount, miss, on_player)`, `combat_ranged_shot`,
  `enemy_hp_changed`, `enemy_killed`, `enemy_respawning`, `player_died`, `level_up`.
- **Spawning:** monsters as `WorldEntity kind="enemy"` via `scripts/world/world_entity_spawner.gd`;
  NPC/sim crowd via `scripts/world/sim/sim_director.gd`.
- **Extend:** add to `data/enemies.json` + items; place via monsters/POI data or the editor Creatures
  tool. Tune formulas in `combat_calc.gd` carefully (validate Phase 5 covers them).

### Combat formulas (exact — `scripts/combat/combat_calc.gd` + `combat_constants.gd`)
`CombatSim` delegates ALL math to the pure static `CombatCalc` (verified: `combat_sim.gd` preloads it
and calls `player_max_hit`/`player_hit_chance`/etc. through it). **Tune the constants in
`combat_constants.gd`, never hardcode numbers in `combat_sim.gd`.** OSRS-inspired; values are ours.

Constants (`CombatConstants`): `EFFECTIVE_PLAYER_LEVEL_BASE=8`, `EFFECTIVE_NPC_DEFENCE_BASE=9`,
`EQUIPMENT_ROLL_BASE=64`, `MAX_HIT_DIVISOR=640.0`, `MAX_HIT_ROUNDING_OFFSET=0.5`,
`TICK_DURATION_MS=600`, `GLOBAL_DAMAGE_CAP=9999`, `DEFAULT_CRIT_CHANCE=0.05`,
`DEFAULT_CRIT_MULTIPLIER=1.5`, `MAX_CRIT_CHANCE=0.50`, `MAX_CRIT_MULTIPLIER=3.0`.

Formulas:
- **Effective level** (for accuracy AND max hit): `floor(level × prayer_mult) + temp_bonus +
  style_bonus + 8`.
- **Player max attack roll**: `effective_attack × (relevant_attack_bonus + 64)`.
- **Enemy max defence roll**: `(defence_level + 9) × (relevant_defence_bonus + 64)`.
- **Hit chance** (clamped [0,1]): if `attack_roll > defence_roll`:
  `1 − (defence_roll + 2) / (2 × (attack_roll + 1))`; else `attack_roll / (2 × (defence_roll + 1))`.
- **Max hit**: `floor(0.5 + effective_strength × (strength_bonus + 64) / 640)`.
- **Base damage roll**: uniform integer in `[0, max_hit]` (a landed hit can still roll 0).
- **Damage pipeline** (`finalize_damage`): `floor(base × crit × special × player_mult ×
  enemy_taken_mult)` then **subtract flat reduction** then clamp `[0, 9999]` (flat reduction is
  applied AFTER flooring the multiplied damage).
- **Crit** (`roll_crit`): if `rng < clamp(crit_chance, 0, 0.50)` → multiplier `clamp(crit_mult, 1, 3)`.
- **Avg crit multiplier**: `1 + crit_chance × (crit_mult − 1)`.
- **Expected damage/attack**: `hit_chance × (max_hit / 2) × avg_crit_mult`; **DPS** = that ÷
  `attack_ticks × 0.6s`.
- **Combat level** (`combat_level(att,str,def,hp,ranged,magic,prayer)`):
  `floor(0.25·(def + hp + floor(prayer/2)) + max(meleeM, rangedM, magicM))` where
  `meleeM = 0.325·(att + str)`, `rangedM = 0.325·(floor(ranged/2) + ranged)`,
  `magicM = 0.325·(floor(magic/2) + magic)`.
Weak weapons stay weak via a low **strength bonus**, never a per-weapon damage cap. Enemy stats from
`data/enemies.json` (`EnemyDef`); drops resolved by `scripts/combat/drop_roller.gd`.

## Stations / Production (cooking, smithing, firemaking, fletching, crafting, alchemy)
- **Purpose:** craft items at stations.
- **Primary files:** `autoload/recipe_sim.gd` (`RecipeSim`), `data/recipes.json`,
  `scripts/content/recipe_def.gd`, station mapping in `scripts/world/world_activity_controller.gd`
  (`STATION_OPEN` dict), HUD recipe popup (`scripts/ui/hud_popups.gd`).
- **Key methods:** `RecipeSim.start_craft(skill, recipe_name)`, `advance`, `_complete_craft`,
  `_has_inputs`; recipe keyed `"skill/Name"`.
- **Signals:** `activity_started`, `action_progress`, `loot_gained`, `firemaking_log_burned`,
  `xp_gained`, `level_up`.
- **Extend:** add to `data/recipes.json` (+ output item). Stations are entities with
  `action.type="station"`, `action.station=<key>`.

## Prayer
- `autoload/prayer_sim.gd` (drains/regens devotion), `scripts/state/prayer_state.gd`,
  `data/prayers.json`. Toggled via the HUD prayer tab; recharged at altars
  (`GameState.recharge_devotion`). Signals `prayer_changed`, `prayer_activated`.

## Farming
- `autoload/farming_sim.gd` (passive growth, `GROW_INTERVAL=30s`), `data/farming.json`. Plots in the
  save (`farming` block). HUD farming popup. Signal `farming_changed`.

## Run energy / Slayer (GameState sub-states)
- `scripts/state/run_energy_state.gd` (run drain/regen; `run_energy_changed`),
  `scripts/state/slayer_state.gd` (task assign/kill/cancel; `slayer_changed`; `slayer_points`).

## Movement / Camera
- **Primary files:** `scripts/world/player_avatar.gd` (`PlayerAvatar`: `WALK_SPEED`, `RUN_SPEED`,
  `walk_to`, `arrived`, `is_running`, fishing-cast state), `scripts/world/world_path_controller.gd`
  (`WorldPathController`: A* `walk_to_pos`, waypoints, follow-entity, `exact_stand`), the `Camera2D`
  on Player (2D), `scripts/render/world_camera_rig_3d.gd` (`WorldCameraRig3D`: the 3D camera, zoom
  mirrored from the 2D camera, pitch budget). Run pace gated by `GameState` run energy.
- **Extend:** tweak speeds in `player_avatar.gd`; stand distance in `world_activity_controller.gd`
  (`_adjacent_stand`) + `fishing_helper.gd` (`best_stand`); cadence in `mover_rig.gd` gait.

## World generation / Chunks / Sites / POIs
- **Primary files:** `autoload/world_gen.gd` (`WorldGen`), `scripts/worldgen/` (chunk, chunk_manager,
  finite_world_generator, biome_classifier, skill_site_spawner, world_store, baked_world_store,
  path_finder, road_brush, zone_map, …), `data/world/*` (biomes, pois, skill_sites, monsters,
  stamps, tree_species, settlement_templates, cave_layers, zone_names, road_styles).
  Background: `docs/WORLDGEN_GUIDE.md`. See `WORLD_MAP_AND_NODES.md`.
- **Key:** chunks hold `tiles/biomes/elev/sites/pois/monsters/zone`; `WorldGen.get_chunk(layer,cx,cy)`
  (baked → snapshot → generated); `WorldStore` persists snapshots/depletions to `user://world.json`.
  **World is baked** — terrain/spawn changes need `imota bake` to take effect.

## World editor (authoring)
- `tools/world_editor.gd` + `tools/world_editor.tscn`. Tools: Paint/Sculpt/Nature/Build/**Skills**/
  Live/Edit. The **Skills** group places functional gather sites + monsters per skill
  (`_build_skill_tool_group`, `_place_skill`, `_place_skill_site`). Saves to the worldspec.

## UI / HUD
- `scripts/ui/osrs_hud.gd` (`$HUD`), `scripts/ui/tabs/*` (combat/skills/inventory/equipment/prayer/
  magic), `scripts/ui/widgets/*` (status_orb, minimap, icon_button, tab_icon), `scripts/ui/item_icon.gd`,
  `scripts/ui/hud_popups.gd` (bank/shop/slayer/npc/farming/obelisks/recipes/skill-guide). HUD updates
  from `EventBus` signals. See `UI_AND_HUD.md`.

## Input
- `scripts/world/world_input_controller.gd` (`WorldInputController`: clicks, wheel/pinch zoom, hover,
  right-click context menu) + `osrs_hud.gd` keyboard (M map, Esc) + `GameSettings` keybinds. No
  Godot InputMap. See `INPUT_ACTIONS.md`.

## Save / Load
- `autoload/save_manager.gd`, `autoload/save_migration.gd`, `GameState.to_save_dict/from_save_dict`,
  `scripts/worldgen/world_store.gd`. Background: `docs/SAVE_FORMAT.md`. See
  `SAVE_LOAD_AND_PERSISTENCE.md`.

## 3D render / Animation
- `scripts/render/world_render_3d.gd` (coordinator) + subsystems (`mover_renderer_3d`, `mover_rig`,
  `mover_meshes`, `static_prop_batcher`, `prop_meshes`, `fishing_decor_3d`, `world_atmosphere`,
  `world_camera_rig_3d`, `render_viewport_presenter`, `terrain_style`, `terrain/terrain_chunk_mesher`,
  `world_fx_3d`, `equip_loadout`, `smithy_prop`). Shaders in `shaders/`. See `ANIMATION_AND_SPRITES.md`.

## Sim players (ambient NPCs)
- `scripts/world/sim/sim_director.gd`, `sim_player.gd`, `sim_identity.gd`, `sim_nameplates.gd`,
  `data/sim_players/{names,looks,dialogue}.json`. Right-click → follow/ask-to-follow/examine.

## Weather / Day-night / Audio
- `autoload/weather.gd`, `autoload/day_night.gd` (`DayNight.time01`, sun colour/energy; sun direction
  is pinned — see `world_atmosphere.gd`), `autoload/audio.gd`. `autoload/game_settings.gd` holds
  pixelation, UI scale, volumes, keybinds, auto-eat.
