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
signal prayer_changed   # active prayers or Devotion changed (HUD prayer tab + orb refresh)
signal prayer_activated(prayer_name: String)   # a prayer was just toggled ON (world FX)
signal firemaking_log_burned   # one log consumed by the firemaking fire (world FX)
signal slayer_changed   # slayer task assigned/progressed/completed (HUD refresh)
signal run_energy_changed(value: float)
signal run_toggled(enabled: bool, resting: bool)

signal activity_started(kind: String, label: String)
signal activity_stopped(reason: String)
signal action_progress(fraction: float)
signal loot_gained(item_name: String, qty: int)

signal combat_log(text: String)
## A damage splat to show in the world: amount (0 on a miss/block), miss flag for
## the blue splat, and on_player to place it on the player vs the combat target.
signal combat_hit_splat(amount: int, miss: bool, on_player: bool)
## A ranged shot left the player's bow — the world flies an arrow to the target,
## which triggers the damage splat on arrival (so it syncs with the attack tick).
signal combat_ranged_shot(amount: int, miss: bool)
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

# --- UI → world intents (decoupled from the world's method surface) -----------
# The HUD / admin menu emit these; world.gd connects them to its handlers, so the
# UI never calls into the world node directly (no more world.call("...")).
signal bank_requested
signal gather_requested(skill: String, node_name: String)
signal station_requested(skill: String, recipe_name: String)
signal teleport_requested(pos: Vector2)
signal navigate_requested(pos: Vector2)   # minimap click → walk-route to a world position

# --- woodcutting feedback (render FX: shake/leaves on a log, fall+pop on depletion) -----
signal wc_log_chopped(pos: Vector2, species: String)   # one log obtained — small leaves puff
signal wc_tree_felled(entity: Node, species: String)   # tree depleted — fall over + pop + leaves
signal wc_tree_grew(entity: Node, species: String)     # tree respawned — grow back up from the stump
