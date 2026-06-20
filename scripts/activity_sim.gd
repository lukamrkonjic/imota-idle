extends Node
class_name ActivitySim
## Shared base for the mutually-exclusive activity sims (gather / combat / craft). It owns the
## common lifecycle — registration with ActivityManager, the active flag, and the per-frame
## advance — and the save contract, so each sim only implements its own behaviour + (de)
## serialization. Passive sims (farming/prayer) do NOT extend this; they tick independently.

const _AM := preload("res://scripts/activity_manager.gd")

var active := false


func _ready() -> void:
	_AM.register(self)


func _process(delta: float) -> void:
	if active:
		advance(delta)


## Stop every OTHER registered activity (call from a sim's start_*). One active at a time.
func _stop_others(reason: String = "switching") -> void:
	_AM.stop_others(self, reason)


# --- overridden by each sim --------------------------------------------------

func advance(_delta: float) -> void:
	pass


func stop(_reason: String = "stopped") -> void:
	pass


## When active, the dict to persist (with a "kind" tag); {} when idle. Owned by the sim so
## SaveManager no longer special-cases each one.
func save_activity() -> Dictionary:
	return {}


## Re-start this sim's activity from a saved dict IF its "kind" matches; otherwise a no-op
## (ActivityManager offers the dict to every sim and the right one claims it).
func restore_activity(_data: Dictionary) -> void:
	pass
