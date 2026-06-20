extends RefCounted
## Central arbiter for the mutually-exclusive activity sims (gather / combat / craft).
## Each sim registers itself once, then calls stop_others(self) when it starts — so no
## sim hardcodes the names of the others (the old TickSim->CombatSim/RecipeSim.stop()
## coupling). Passive sims (e.g. farming) simply don't register.
##
## Referenced via preload const in each sim; the static registry is shared because
## preloading the same script returns the same GDScript resource.

static var _sims: Array = []


static func register(sim: Object) -> void:
	if sim not in _sims:
		_sims.append(sim)


## Stop every registered activity except the one starting up.
static func stop_others(active_sim: Object, reason: String = "switching") -> void:
	for s: Object in _sims:
		if s != active_sim and is_instance_valid(s) and bool(s.active):
			s.stop(reason)


## The currently-active sim's save dict (or {} if everything's idle). One active at a time.
static func save_active() -> Dictionary:
	for s: Object in _sims:
		if is_instance_valid(s) and bool(s.active):
			return s.save_activity()
	return {}


## Offer a saved activity dict to every sim; the one whose "kind" matches re-starts it.
static func restore_active(data: Dictionary) -> void:
	if data.is_empty():
		return
	for s: Object in _sims:
		if is_instance_valid(s):
			s.restore_activity(data)
