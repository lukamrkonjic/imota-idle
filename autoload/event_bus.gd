extends Node
## Global signal hub so the UI stays dumb. Sims and GameState emit; UI listens.

signal xp_gained(skill: String, amount: float)
signal level_up(skill: String, new_level: int)
signal inventory_changed
signal bank_changed
signal equipment_changed
signal coins_changed(new_amount: int)
signal hp_changed(current: int, max_hp: int)
signal farming_changed
signal run_energy_changed(value: float)

signal activity_started(kind: String, label: String)
signal activity_stopped(reason: String)
signal action_progress(fraction: float)
signal loot_gained(item_name: String, qty: int)

signal combat_log(text: String)
## A damage splat to show in the world: amount (0 on a miss/block), miss flag for
## the blue splat, and on_player to place it on the player vs the combat target.
signal combat_hit_splat(amount: int, miss: bool, on_player: bool)
signal enemy_hp_changed(current: float, max_hp: float)
signal enemy_killed(enemy_name: String)
signal enemy_respawning(seconds: float)
signal player_died(enemy_name: String)

signal game_loaded

signal zone_changed(zone_name: String, level_req: int)
signal biome_changed(biome_id: String, music_tag: String)
signal world_layer_changed(layer: int)
signal site_depleted(chunk_key: String, site_index: int)
signal site_respawned(chunk_key: String, site_index: int)
signal obelisk_unlocked(obelisk_name: String)
