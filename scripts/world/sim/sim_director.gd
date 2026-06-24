extends RefCounted
class_name SimDirector
## Owns the sim-player roster: spawns/culls them by the player's active radius (exactly like
## enemies), ticks a budgeted brain over them, steps their movement, drives the gather-pose theatre,
## and plumbs their chatter (speech bubbles + nameplates). Identity is deterministic per home chunk +
## slot, so the cast regenerates for free each session — nothing here touches save.json (the world's
## save-safety contract). See docs/SIM_PLAYERS_PLAN.md.

const WG := preload("res://scripts/worldgen/wg.gd")
const SimPlayer := preload("res://scripts/world/sim/sim_player.gd")
const SimIdentity := preload("res://scripts/world/sim/sim_identity.gd")
const SimBrain := preload("res://scripts/world/sim/sim_brain.gd")
const SpeechBubble := preload("res://scripts/world/sim/speech_bubble.gd")
const SimNameplates := preload("res://scripts/world/sim/sim_nameplates.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")

# Conservative for v1: a couple dozen rigged humanoids stays well inside the draw-call envelope the
# engine already sustains (hundreds of enemy rigs). Tune up once animation-LOD ships (Phase 5).
const SIM_RADIUS_CHUNKS := 2          # spawn ring around the player (<= ACTIVE_RADIUS so chunks are loaded)
const DESPAWN_RADIUS_CHUNKS := 3      # cull once the home chunk drifts past this
const MAX_VISIBLE_SIMS := 18
const MAX_PER_CHUNK := 2
const THINK_BUDGET_PER_FRAME := 3     # cap pathfinding decisions per frame (the only real CPU cost)
const RESCAN_INTERVAL := 1.0
const FEED_CHATTER := true            # also surface some chatter in the chat feed for MMO ambience

var world: Node2D
var brain: SimBrain
var _container: Node2D
var _nameplates: SimNameplates
var _sims: Dictionary = {}            # slot_key -> SimPlayer
var _by_id: Dictionary = {}           # entity instance_id -> SimPlayer
var _seed := 0
var _spawn_cd := 0.4
var _social_acc := 0.0
var _thinks_left := 0


func setup(w: Node2D) -> void:
	world = w
	brain = SimBrain.new()
	brain.setup(self)


## The sims live under a dedicated container (NOT a chunk container), so a chunk unload never
## sweeps them — the director owns their lifecycle. Built lazily: setup() runs before the world's
## entities layer exists.
func _ensure_container() -> void:
	if _container != null:
		return
	_container = Node2D.new()
	_container.name = "SimPlayers"
	world._entities_layer.add_child(_container)


func _ensure_overlay() -> void:
	# Nameplates live on the 3D screen-space overlay (created lazily — render_3d builds its fx_layer
	# during world setup). Headless / 2D runs simply skip the overlay; the sims still simulate.
	if _nameplates != null or world.render_3d == null or not world.render_3d.is_active():
		return
	_nameplates = SimNameplates.new()
	_nameplates.director = self
	_nameplates.render_3d = world.render_3d
	world.render_3d.fx_layer.add_child(_nameplates)


# ----------------------------------------------------------------- main loop ----

func process_tick(delta: float) -> void:
	if world.player == null:
		return
	_ensure_container()
	_ensure_overlay()
	_seed = WorldGen.store.world_seed
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = RESCAN_INTERVAL
		_rescan()
	_thinks_left = THINK_BUDGET_PER_FRAME
	for sim: SimPlayer in _sims.values():
		_step(sim, delta)
	_social_acc += delta
	if _social_acc >= GameState.TICK:
		_social_acc = 0.0
		_social_tick()


## Per-frame movement + state advance for one sim. Pathfinding-triggering decisions are gated by the
## frame think-budget so a crowd of bots can't all repath on the same frame.
func _step(sim: SimPlayer, delta: float) -> void:
	var e: Node2D = sim.entity
	if not is_instance_valid(e):
		return
	# A right-click "Follow" overrides the brain: shadow the player at their own pace until told to stop.
	if sim.commanded:
		_step_commanded_follow(sim, delta)
		return
	match sim.state:
		SimPlayer.WALK:
			if _advance_path(sim, delta):
				brain.on_arrived(sim)
		SimPlayer.FOLLOW:
			sim.state_t -= delta
			if sim.state_t <= 0.0 or not is_instance_valid(sim.target):
				if _thinks_left > 0:
					_thinks_left -= 1
					brain.think(sim)
				return
			_advance_path(sim, delta)
			# Keep heading toward the (moving) buddy: repath when it has wandered off the path end.
			if sim.path_i >= sim.path.size() and _thinks_left > 0:
				_thinks_left -= 1
				lay_path(sim, sim.target.position)
		SimPlayer.IDLE, SimPlayer.GATHER:
			sim.state_t -= delta
			if sim.state_t <= 0.0:
				if _thinks_left > 0:
					_thinks_left -= 1
					brain.think(sim)


## Move the entity toward its current waypoint; returns true when the whole path is consumed.
## speed < 0 uses the sim's own walk pace; a follower passes the player's current pace to keep up.
func _advance_path(sim: SimPlayer, delta: float, speed := -1.0) -> bool:
	var e: Node2D = sim.entity
	if sim.path_i >= sim.path.size():
		return true
	var dest: Vector2 = sim.path[sim.path_i]
	var to := dest - e.position
	var d := to.length()
	var step := (sim.walk_speed if speed < 0.0 else speed) * delta
	if d <= maxf(step, 2.5):
		e.position = dest
		sim.path_i += 1
		return sim.path_i >= sim.path.size()
	e.position += to / d * step
	return false


## RuneScape-style Follow: keep pace a tile behind the player, repathing as they move, matching their
## walk/run speed (sprint when they sprint). Separation keeps the follower from standing on the player.
const FOLLOW_GAP := WG.TILE * 1.15
const FOLLOW_LEASH := WG.TILE * 24.0   # give up if somehow dragged this far from the player

func _step_commanded_follow(sim: SimPlayer, delta: float) -> void:
	if not is_instance_valid(world.player):
		_clear_follow(sim)
		return
	sim.state = SimPlayer.FOLLOW
	var pp: Vector2 = world.player.position
	var dist: float = sim.entity.position.distance_to(pp)
	if dist > FOLLOW_LEASH:
		_clear_follow(sim)
		return
	sim.follow_repath_t -= delta
	if dist > FOLLOW_GAP and (sim.follow_repath_t <= 0.0 or sim.path_i >= sim.path.size()) and _thinks_left > 0:
		_thinks_left -= 1
		sim.follow_repath_t = 0.3
		lay_path(sim, pp)
	if dist > FOLLOW_GAP:
		# Match the player's pace, with a small catch-up boost when lagging so they don't trail off.
		var spd: float = float(world.player.move_speed()) * (1.18 if dist > WG.TILE * 3.0 else 1.0)
		_advance_path(sim, delta, spd)


# ----------------------------------------------------------------- spawn / cull ----

func _rescan() -> void:
	var center := WG.world_to_chunk(world.player.position)
	# Cull sims whose home chunk drifted out of range (or whose entity died).
	for key: String in _sims.keys():
		var sim: SimPlayer = _sims[key]
		if not is_instance_valid(sim.entity):
			_remove(key)
			continue
		if sim.commanded:
			continue   # a follower travels with the player — don't cull it by its (now-distant) home chunk
		var hc := WG.world_to_chunk(sim.home)
		if maxi(absi(hc.x - center.x), absi(hc.y - center.y)) > DESPAWN_RADIUS_CHUNKS:
			_remove(key)
	# Spawn the deterministic roster for each loaded chunk in the active ring.
	for dy: int in range(-SIM_RADIUS_CHUNKS, SIM_RADIUS_CHUNKS + 1):
		for dx: int in range(-SIM_RADIUS_CHUNKS, SIM_RADIUS_CHUNKS + 1):
			if _sims.size() >= MAX_VISIBLE_SIMS:
				return
			var cx := center.x + dx
			var cy := center.y + dy
			if not WorldGen.chunks.has(WG.key(world.current_layer, cx, cy)):
				continue
			var n := _chunk_sim_count(cx, cy)
			for slot: int in n:
				if _sims.size() >= MAX_VISIBLE_SIMS:
					return
				_spawn(cx, cy, slot)


## Deterministic 0..MAX_PER_CHUNK sims for a chunk (most chunks empty, a few busy — a believable
## scatter that clusters where chunks roll high). A density curve by settlement is Phase 5.
func _chunk_sim_count(cx: int, cy: int) -> int:
	var r := WG.r01(_seed, cx * 7 + 13, cy * 9 + 91, 555)
	if r < 0.55:
		return 0
	if r < 0.84:
		return 1
	return MAX_PER_CHUNK


func _spawn(cx: int, cy: int, slot: int) -> void:
	var key := "%d:%d:%d" % [cx, cy, slot]
	if _sims.has(key):
		return
	var home := _home_for(cx, cy, slot)
	if home == Vector2.INF:
		return   # no walkable home tile in this chunk slot (e.g. open water) — skip
	var sim := SimIdentity.build(_seed, cx, cy, slot, home)
	var e := WorldEntity.new()
	e.kind = "sim"
	e.label = sim.pname
	e.sub_label = "Lvl %d" % sim.combat_level
	e.display_size = 40.0
	e.click_radius = 30.0         # picked by the RIGHT-click Follow menu; left-click still ignores it
	e.action = {}                 # empty -> ignored by aggro / targeting / left-click interaction
	e.position = home
	e.set_meta("sim_skin", sim.skin)
	e.set_meta("sim_loadout", sim.loadout)
	e.set_meta("sim_gathering", false)
	sim.entity = e
	sim.state = SimPlayer.IDLE
	sim.state_t = sim.roll() * 1.6
	_container.add_child(e)
	world.entities.append(e)
	_sims[key] = sim
	_by_id[e.get_instance_id()] = sim


func _remove(key: String) -> void:
	var sim: SimPlayer = _sims.get(key)
	if sim == null:
		return
	if is_instance_valid(sim.bubble):
		sim.bubble.queue_free()
	if is_instance_valid(sim.entity):
		_by_id.erase(sim.entity.get_instance_id())
		world.entities.erase(sim.entity)
		sim.entity.queue_free()
	_sims.erase(key)


## A deterministic walkable home tile inside a chunk slot; INF if the slot only hits water/cliffs.
func _home_for(cx: int, cy: int, slot: int) -> Vector2:
	var base := Vector2i(cx, cy) * WG.CHUNK_TILES
	for attempt: int in 6:
		var ox := WG.hash_i(_seed, cx * 101 + slot * 17 + attempt, cy * 103, 201) % WG.CHUNK_TILES
		var oy := WG.hash_i(_seed, cx * 107 + slot * 19 + attempt, cy * 109, 202) % WG.CHUNK_TILES
		var p := WG.tile_to_world(base.x + ox, base.y + oy)
		if WorldGen.is_walkable_world(p, world.current_layer):
			return p
	return Vector2.INF


# ----------------------------------------------------------------- brain API ----

## Lay an A* path for a sim toward a world target. Returns false (and leaves the sim where it is) if
## unreachable / the nav graph isn't ready.
func lay_path(sim: SimPlayer, dest: Vector2) -> bool:
	var pf: RefCounted = world._path_ctrl.path_finder
	var path := PackedVector2Array(pf.find_path(sim.entity.position, dest, true))
	if path.is_empty():
		return false
	sim.path = path
	sim.path_i = 0
	# Drop a leading waypoint that's essentially where we already stand, so the first step reads
	# as forward motion (the renderer derives facing from velocity).
	if path.size() >= 2 and sim.entity.position.distance_to(path[0]) < WG.TILE * 0.4:
		sim.path_i = 1
	return true


## Nearest non-depleted gather node (tree/rock/fish) within `max_tiles` of a sim.
func nearest_gather_site(sim: SimPlayer, max_tiles: float) -> Node2D:
	var pos: Vector2 = sim.entity.position
	var maxd := max_tiles * WG.TILE
	var best: Node2D = null
	var best_d := INF
	for e: Node2D in world.entities:
		if not is_instance_valid(e) or e.dimmed:
			continue
		var a: Dictionary = e.action
		if str(a.get("type", "")) != "gather":
			continue
		if str(a.get("skill", "")) not in ["woodcutting", "mining", "fishing"]:
			continue
		var d := pos.distance_to(e.position)
		if d < best_d and d <= maxd:
			best_d = d
			best = e
	return best


## A walkable spot beside a gather node to stand and "work" (offset per-sim so two bots don't stack).
func stand_point_for(sim: SimPlayer, node: Node2D) -> Vector2:
	var ang := sim.roll() * TAU
	var p: Vector2 = node.position + Vector2(cos(ang), sin(ang)) * WG.TILE * 0.95
	return WorldGen.nearest_walkable_world(p, world.current_layer)


## A random walkable wander target: homebodies stay tight to home, wanderers roam wide.
func wander_destination(sim: SimPlayer) -> Vector2:
	var wr := lerpf(3.0, 8.0, sim.personality) * WG.TILE
	var ang := sim.roll() * TAU
	var rad := sqrt(sim.roll()) * wr
	var p: Vector2 = sim.home + Vector2(cos(ang), sin(ang)) * rad
	return WorldGen.nearest_walkable_world(p, world.current_layer)


## Is there anyone nearby worth following (player or another sim)? Pure proximity — no rolls — so the
## brain's weighting math stays deterministic.
func has_follow_target(sim: SimPlayer) -> bool:
	var pos: Vector2 = sim.entity.position
	if pos.distance_to(world.player.position) <= 5.0 * WG.TILE:
		return true
	for other: SimPlayer in _sims.values():
		if other != sim and is_instance_valid(other.entity) and pos.distance_to(other.entity.position) <= 5.0 * WG.TILE:
			return true
	return false


## Pick a follow buddy: occasionally tag along with the player, else the nearest sim.
func follow_target(sim: SimPlayer) -> Node2D:
	var pos: Vector2 = sim.entity.position
	if pos.distance_to(world.player.position) <= 5.0 * WG.TILE and sim.roll() < 0.5:
		return world.player
	var best: Node2D = null
	var best_d := INF
	for other: SimPlayer in _sims.values():
		if other == sim or not is_instance_valid(other.entity):
			continue
		var d := pos.distance_to(other.entity.position)
		if d < best_d and d <= 5.0 * WG.TILE:
			best_d = d
			best = other.entity
	return best


## Toggle the working pose (woodcutting/mining swing). Fishing just stands and casts.
func set_gather_pose(sim: SimPlayer, on: bool) -> void:
	if is_instance_valid(sim.entity):
		sim.entity.set_meta("sim_gathering", on and sim.gather_skill in ["woodcutting", "mining"])


# ----------------------------------------------------------------- chatter ----

func sims() -> Array:
	return _sims.values()


# ----------------------------------------------------------------- follow command (right-click) ----

func sim_for_entity(e: Node2D) -> SimPlayer:
	return _by_id.get(e.get_instance_id())


func is_following(e: Node2D) -> bool:
	var sim := sim_for_entity(e)
	return sim != null and sim.commanded


## Right-click "Follow": the sim shadows the player (RuneScape-style) until told to stop.
func command_follow(e: Node2D) -> void:
	var sim := sim_for_entity(e)
	if sim == null:
		return
	sim.commanded = true
	sim.state = SimPlayer.FOLLOW
	sim.follow_repath_t = 0.0
	sim.path = PackedVector2Array()
	sim.path_i = 0
	set_gather_pose(sim, false)
	var dia := SimIdentity.dialogue()
	_say_raw(sim, _pick(dia.get("group", ["Lead the way!"]), sim).replace("@name", "traveller"), FEED_CHATTER)


func stop_follow(e: Node2D) -> void:
	var sim := sim_for_entity(e)
	if sim != null:
		_clear_follow(sim)
		_say_raw(sim, "See you around!", false)


func _clear_follow(sim: SimPlayer) -> void:
	sim.commanded = false
	sim.state = SimPlayer.IDLE
	sim.state_t = 0.6
	sim.path = PackedVector2Array()
	sim.path_i = 0


## Right-click "Examine": a flavour line about the sim (its name + what it's up to).
func examine(e: Node2D) -> void:
	var sim := sim_for_entity(e)
	if sim == null:
		return
	var doing := "wandering the world"
	match sim.state:
		SimPlayer.GATHER:
			doing = "training %s" % sim.gather_skill.capitalize()
		SimPlayer.FOLLOW:
			doing = "following you"
	EventBus.combat_log.emit("[color=#7c89a8]%s — combat level %d, %s.[/color]" % [sim.pname, sim.combat_level, doing])


## Periodic social pass (every game tick): smalltalk, skill chatter, level-up flavour, and greeting
## the player when he comes close. All gated by per-sim cooldowns so chatter is contextual, not spam.
func _social_tick() -> void:
	var dia := SimIdentity.dialogue()
	if dia.is_empty():
		return
	var pp: Vector2 = world.player.position
	var now := Time.get_ticks_msec() / 1000.0
	for sim: SimPlayer in _sims.values():
		if not is_instance_valid(sim.entity):
			continue
		sim.chat_cd = maxf(sim.chat_cd - GameState.TICK, 0.0)
		# Theatrical XP while "skilling": occasionally a level-up shout.
		if sim.state == SimPlayer.GATHER:
			sim.fake_xp += 8.0 + sim.roll() * 14.0
			if sim.fake_xp >= 60.0:
				sim.fake_xp = 0.0
				if sim.chat_cd <= 0.0 and sim.roll() < 0.5:
					_say_levelup(sim, dia)
					continue
		if sim.chat_cd > 0.0:
			continue
		# Greet the player on close approach (rate-limited per sim).
		if sim.entity.position.distance_to(pp) <= 3.2 * WG.TILE and now - sim.greeted_player_at > 22.0 and sim.roll() < 0.55:
			sim.greeted_player_at = now
			_say(sim, _pick(dia.get("player_greetings", []), sim), dia, 0.0)
			continue
		# Skill chatter while working.
		if sim.state == SimPlayer.GATHER and sim.roll() < 0.22:
			var by_skill: Dictionary = dia.get("skill", {})
			var lines: Array = by_skill.get(sim.gather_skill, by_skill.get("generic", []))
			_say(sim, _pick(lines, sim), dia)
			continue
		# Idle/walking smalltalk (rare — keeps the world murmuring, not babbling).
		if sim.state in [SimPlayer.IDLE, SimPlayer.WALK] and sim.roll() < 0.06:
			_say(sim, _pick(dia.get("smalltalk", []), sim), dia)


func maybe_say_group(sim: SimPlayer, buddy: Node2D) -> void:
	if sim.chat_cd > 0.0:
		return
	var dia := SimIdentity.dialogue()
	var line := _pick(dia.get("group", []), sim)
	line = line.replace("@name", _name_of(buddy))
	_say_raw(sim, line, false)


func _say_levelup(sim: SimPlayer, dia: Dictionary) -> void:
	var skill := sim.gather_skill if sim.gather_skill != "" else sim.main_skill()
	var lvl := int(sim.levels.get(skill, sim.combat_level)) + 1
	sim.levels[skill] = lvl
	var line := _pick(dia.get("reactions", {}).get("levelup", []), sim)
	line = line.replace("@skill", skill.capitalize()).replace("@level", str(lvl))
	_say_raw(sim, line, FEED_CHATTER)


## Resolve @name templating against the nearest other party, then show the line.
func _say(sim: SimPlayer, line: String, _dia: Dictionary, feed_chance := 0.12) -> void:
	if line.is_empty():
		return
	if line.contains("@name"):
		line = line.replace("@name", _nearest_other_name(sim))
	_say_raw(sim, line, FEED_CHATTER and sim.roll() < feed_chance)


func _say_raw(sim: SimPlayer, line: String, feed: bool) -> void:
	if line.is_empty() or not is_instance_valid(sim.entity):
		return
	sim.chat_cd = 6.0 + sim.roll() * 8.0
	_spawn_bubble(sim, line)
	if feed:
		EventBus.combat_log.emit("[color=#7c89a8]%s: %s[/color]" % [sim.pname, line])


func _spawn_bubble(sim: SimPlayer, line: String) -> void:
	if world.render_3d == null or not world.render_3d.is_active():
		return
	if is_instance_valid(sim.bubble):
		sim.bubble.queue_free()
	var b := SpeechBubble.new()
	b.text = line
	b.anchor = sim.entity
	b.projector = world.render_3d
	b.lift = world.render_3d.mover_top(sim.entity)
	world.render_3d.fx_layer.add_child(b)
	sim.bubble = b


func _pick(lines: Array, sim: SimPlayer) -> String:
	if lines.is_empty():
		return ""
	return str(lines[int(sim.roll() * lines.size()) % lines.size()])


func _nearest_other_name(sim: SimPlayer) -> String:
	var pos: Vector2 = sim.entity.position
	if pos.distance_to(world.player.position) <= 4.0 * WG.TILE:
		return "traveller"
	var best: SimPlayer = null
	var best_d := INF
	for other: SimPlayer in _sims.values():
		if other == sim or not is_instance_valid(other.entity):
			continue
		var d := pos.distance_to(other.entity.position)
		if d < best_d:
			best_d = d
			best = other
	return best.pname if best != null else "friend"


func _name_of(n: Node2D) -> String:
	if n == world.player:
		return "traveller"
	var sim: SimPlayer = _by_id.get(n.get_instance_id())
	return sim.pname if sim != null else "friend"
