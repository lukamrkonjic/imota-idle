# File ownership map

Which file OWNS which responsibility. Before adding code, find the owner and extend it — don't create
a parallel system. "Owner" = the single place that responsibility lives.

## State & data
| Responsibility | Owner |
|---|---|
| All player state + the save dict | `autoload/game_state.gd` (`GameState`) |
| Prayer / run-energy / slayer sub-state | `scripts/state/{prayer_state,run_energy_state,slayer_state}.gd` |
| Content load + id/name/alias resolution | `autoload/data_registry.gd` (`DataRegistry`) |
| Item/node/recipe/enemy typed views | `scripts/content/{item_def,gather_node_def,recipe_def,enemy_def}.gd` |
| Stable ids / renames | `scripts/content/{content_id,id_registry}.gd` + `data/{id_registry,rename_map,content_aliases}.json` |
| Skill metadata | `autoload/skill_registry.gd` + `data/skills.json` |
| Settings (pixelation, UI scale, volumes, keybinds, auto-eat) | `autoload/game_settings.gd` |

## Simulations (one foreground at a time)
| Responsibility | Owner |
|---|---|
| Gathering loop | `autoload/tick_sim.gd` (`TickSim`) |
| Combat loop + drops | `autoload/combat_sim.gd` + `scripts/combat/{combat_calc,drop_roller,…}.gd` |
| Crafting/production loop | `autoload/recipe_sim.gd` (`RecipeSim`) |
| Prayer drain/regen | `autoload/prayer_sim.gd` |
| Farming growth | `autoload/farming_sim.gd` |

## World
| Responsibility | Owner |
|---|---|
| World source of truth / chunk access | `autoload/world_gen.gd` (`WorldGen`) |
| Chunk gen / streaming | `scripts/worldgen/{chunk,chunk_manager,finite_world_generator,biome_classifier}.gd` |
| Gather-site placement | `scripts/worldgen/skill_site_spawner.gd` + `data/world/skill_sites.json` |
| World persistence (snapshots/depletions) | `scripts/worldgen/world_store.gd` |
| Baked authored world | `scripts/worldgen/baked_world_store.gd` + `data/world/baked/` |
| Pathfinding | `scripts/worldgen/path_finder.gd` (via `scripts/world/world_path_controller.gd`) |
| World authoring (editor) | `tools/world_editor.gd` |

## The world scene & gameplay loop
| Responsibility | Owner |
|---|---|
| Scene composition + node graph + per-frame loop | `scripts/world/world.gd` (`World`) |
| Entities (clickable world objects) | `scripts/world/world_entity.gd` (`WorldEntity`) + `world_entity_spawner.gd` |
| Input (mouse/zoom/hover/context menu) | `scripts/world/world_input_controller.gd` |
| Action routing (click→walk→act) | `scripts/world/world_activity_controller.gd` |
| Movement/pathing | `scripts/world/{player_avatar,world_path_controller}.gd` |
| Auto-tasks (idle loops) | `scripts/world/world_auto_task_controller.gd` |
| Layer/cave/obelisk transitions | `scripts/world/world_layer_controller.gd` |
| XP floats / visual feedback (2D) | `scripts/world/world_visual_controller.gd` |
| Entity collision/depth | `scripts/world/world_collision_controller.gd` |
| Ambient sim players (NPC crowd) | `scripts/world/sim/{sim_director,sim_player,sim_identity}.gd` + `data/sim_players/` |

## UI
| Responsibility | Owner |
|---|---|
| HUD shell + signal wiring | `scripts/ui/osrs_hud.gd` |
| Tabs (combat/skills/inventory/equipment/prayer/magic) | `scripts/ui/tabs/*.gd` |
| Widgets (orbs/minimap/buttons/tab icons) | `scripts/ui/widgets/*.gd` |
| Popups (bank/shop/slayer/npc/farming/obelisks/recipes/skill-guide) | `scripts/ui/hud_popups.gd` |
| Item icons | `scripts/ui/item_icon.gd` |

## 3D render (cosmetic)
| Responsibility | Owner |
|---|---|
| Render coordinator | `scripts/render/world_render_3d.gd` |
| Low-res viewport / pixelation | `scripts/render/render_viewport_presenter.gd` + `shaders/palette_snap.gdshader` |
| Camera | `scripts/render/world_camera_rig_3d.gd` |
| Sun / fog / sky | `scripts/render/world_atmosphere.gd` |
| Terrain mesh + colour | `scripts/render/terrain/terrain_chunk_mesher.gd` + `terrain_style.gd` + `shaders/toon_*.gdshader` |
| Terrain mesh GEOMETRY (geometry only) | `terrain_chunk_mesher.gd` — `build_chunk_terrain` (runtime/editor) + `build_region_terrain` (offline bake, indexed) |
| Static play-mode terrain (load once) | `scripts/render/terrain/static_terrain_regions.gd` (`StaticTerrainRegions`) + baked `data/world/baked/<id>_terrain.res` (`BakedTerrainSet`) |
| Dynamic terrain (EDITOR / fallback only) | `terrain/terrain_mesh_manager.gd` + `terrain_stream_view.gd` + `terrain/far_terrain_backdrop.gd` — driven only when NOT in static play mode |
| Static props (batched) | `scripts/render/static_prop_batcher.gd` + `prop_meshes.gd` |
| Player/enemy rigs + gather/combat poses | `scripts/render/{mover_renderer_3d,mover_rig,mover_meshes,equip_loadout}.gd` |
| Fishing-spot bubbles | `scripts/render/fishing_decor_3d.gd` |
| World FX (puffs/topple) | `scripts/render/world_fx_3d.gd` |
| `.glb` model loaders | `scripts/render/*_prop.gd` (e.g. `smithy_prop.gd`) |

## Cross-cutting
| Responsibility | Owner |
|---|---|
| Events / signals | `autoload/event_bus.gd` (the only hub) |
| Save I/O + migration | `autoload/{save_manager,save_migration}.gd` |
| Weather / day-night / audio | `autoload/{weather,day_night,audio}.gd` |
| Tests / validation | `tools/validate.gd` (+ `validate_content.gd`) |
