extends RefCounted
class_name RunEnergyState
## Run-energy / Agility-stamina domain, extracted from GameState (spec §16).
##
## Energy drains while running, regenerates while still (faster when resting). State lives here;
## GameState forwards the public API and serializes run_energy + run_enabled (resting is transient,
## always false on load). Reads GameState.level("agility") and GameState.is_moving each tick.

const REST_REGEN_MULT := 2.6     # sitting (rest) recharges this much faster than walking

var energy: float = 100.0
var enabled := false             # OSRS run toggle (minimap run orb, left-click)
var resting := false             # sitting to recharge faster (run orb, right-click)


func spend(amount: float) -> void:
	energy = clampf(energy - amount, 0.0, 100.0)
	EventBus.run_energy_changed.emit(energy)


## Per-frame running cost. OSRS: units/tick = ⌊60 + 67·clamp(weight,0,64)/64⌋·(1 − Agility/300),
## of 10000 units = 100%. No weight system yet → weight 0 → 60 units/tick = 0.6%/tick.
## Ticks are 0.6s, so 0.6%/tick ÷ 0.6 = 1.0%/sec before the Agility factor.
func drain(delta: float) -> void:
	var rate: float = 1.0 - float(GameState.level("agility")) / 300.0   # % per second (weight 0)
	spend(rate * delta)
	if energy <= 0.0:
		set_running(false)


## OSRS regen: units/tick = ⌊Agility/10⌋ + 15 (of 10000). ÷100 → %/tick, ÷0.6 → %/sec.
func regen(delta: float) -> void:
	if enabled and GameState.is_moving:
		return                      # spending energy while running; no regen
	if energy >= 100.0:
		return
	var rate: float = (floor(float(GameState.level("agility")) / 10.0) + 15.0) / 60.0   # % per second
	if resting:
		rate *= REST_REGEN_MULT
	energy = clampf(energy + rate * delta, 0.0, 100.0)
	EventBus.run_energy_changed.emit(energy)


## Minimap run orb — left-click toggles running.
func toggle() -> void:
	set_running(not enabled)


func set_running(on: bool) -> void:
	if on and energy <= 0.0:
		on = false
	if on:
		resting = false             # running cancels rest
	enabled = on
	EventBus.run_toggled.emit(enabled, resting)


## Right-click the run orb — sit down to recharge faster.
func set_resting(on: bool) -> void:
	if on:
		enabled = false             # can't run while resting
	resting = on
	EventBus.run_toggled.emit(enabled, resting)
