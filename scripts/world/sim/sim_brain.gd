extends RefCounted
class_name SimBrain
## The sim-player "brain": a budgeted, day-in-the-life state machine (2009scape's intent-queue idea
## without its coupling). It only DECIDES — picks the next destination/activity and lays a path; the
## SimDirector owns the roster and steps the actual movement. Decisions are personality-weighted and
## use the sim's own deterministic rolls, so a homebody skiller and a restless wanderer behave
## differently yet reproducibly. Gather/combat never touch the real player economy (theatre only).

const SimPlayer := preload("res://scripts/world/sim/sim_player.gd")

var director: RefCounted   # SimDirector — world queries (paths, entities, nearby sims, chatter)


func setup(d: RefCounted) -> void:
	director = d


## Called when a non-walking state's timer expires: choose what to do next.
func think(sim: SimPlayer) -> void:
	decide_next(sim)


## Called by the director when a WALK path finishes — resolve the pending intent.
func on_arrived(sim: SimPlayer) -> void:
	match sim.state:
		SimPlayer.WALK:
			if sim.gather_skill != "" and is_instance_valid(sim.target) and not sim.target.dimmed:
				_begin_gather(sim)
			else:
				_begin_idle(sim, sim.roll() * 1.5 + 0.6)
		SimPlayer.FOLLOW:
			# Reached the buddy — loiter a beat, then re-evaluate (maybe keep following).
			_begin_idle(sim, sim.roll() * 1.2 + 0.4)
		_:
			_begin_idle(sim, 1.0)


func decide_next(sim: SimPlayer) -> void:
	var r := sim.roll()
	# Wanderers (high personality) favour roaming + socialising; homebodies favour skilling near home.
	var p := sim.personality
	var skill_w := lerpf(0.62, 0.22, p)
	var follow_w := lerpf(0.04, 0.20, p) if director.has_follow_target(sim) else 0.0
	var idle_w := 0.16
	# Normalised thresholds: [gather | follow | idle | wander].
	var total := skill_w + follow_w + idle_w + 1.0   # wander gets weight 1.0 baseline
	var t := r * total
	if t < skill_w and _try_gather(sim):
		return
	t -= skill_w
	if t < follow_w and _try_follow(sim):
		return
	t -= follow_w
	if t < idle_w:
		_begin_idle(sim, sim.roll() * 2.5 + 0.8)
		return
	_begin_wander(sim)


# ---------------------------------------------------------------- intents ----

func _try_gather(sim: SimPlayer) -> bool:
	var node: Node2D = director.nearest_gather_site(sim, 9.0)
	if node == null:
		return false
	sim.target = node
	sim.gather_skill = str(node.action.get("skill", "woodcutting"))
	var stand: Vector2 = director.stand_point_for(sim, node)
	if not director.lay_path(sim, stand):
		sim.target = null
		sim.gather_skill = ""
		return false
	sim.state = SimPlayer.WALK
	return true


func _try_follow(sim: SimPlayer) -> bool:
	var buddy: Node2D = director.follow_target(sim)
	if buddy == null:
		return false
	sim.target = buddy
	sim.gather_skill = ""
	if not director.lay_path(sim, buddy.position):
		sim.target = null
		return false
	sim.state = SimPlayer.FOLLOW
	sim.state_t = 6.0 + sim.roll() * 8.0   # follow for a while, then drift off
	director.maybe_say_group(sim, buddy)
	return true


func _begin_wander(sim: SimPlayer) -> void:
	sim.target = null
	sim.gather_skill = ""
	var dest: Vector2 = director.wander_destination(sim)
	if dest == Vector2.INF or not director.lay_path(sim, dest):
		_begin_idle(sim, sim.roll() * 2.0 + 0.6)
		return
	sim.state = SimPlayer.WALK


func _begin_gather(sim: SimPlayer) -> void:
	sim.state = SimPlayer.GATHER
	sim.state_t = 4.0 + sim.roll() * 7.0
	sim.fake_xp = 0.0
	director.set_gather_pose(sim, true)


func _begin_idle(sim: SimPlayer, dur: float) -> void:
	sim.state = SimPlayer.IDLE
	sim.state_t = dur
	sim.target = null
	sim.gather_skill = ""
	director.set_gather_pose(sim, false)
