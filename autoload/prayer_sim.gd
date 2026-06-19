extends Node
## Drains Devotion while any prayer is active (GameState.drain_devotion). Mirrors the other
## passive sims (FarmingSim) — a tiny always-on _process. Prayers fade automatically when
## Devotion empties; recharge at an altar (or on respawn).


func _process(delta: float) -> void:
	if not GameState.active_prayers.is_empty():
		GameState.drain_devotion(delta)
