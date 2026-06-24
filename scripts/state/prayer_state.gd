extends RefCounted
class_name PrayerState
## Prayer / Devotion domain, extracted from GameState.
##
## Devotion max = Prayer level; drained while prayers are active (PrayerSim), regenerates toward max
## when none are active, and snaps to full at an altar / on respawn. State lives here; GameState
## exposes the public API via forwarding methods and serializes active_prayers + devotion.

const DEVOTION_REGEN_PER_SEC := 2.0

var active_prayers: Array = []   # names of prayers toggled on (combat hooks)
var devotion: float = -1.0       # current Devotion (-1 = uninit -> lazily filled to full on first read)


func is_active(prayer_name: String) -> bool:
	return active_prayers.has(prayer_name)


func devotion_max() -> int:
	return maxi(1, GameState.level("prayer"))


## Lazily fill on first read so a fresh/legacy save starts with full Devotion.
func devotion_points() -> float:
	if devotion < 0.0:
		devotion = float(devotion_max())
	return devotion


## Toggle a prayer on/off. Off->on requires the level + some Devotion left, and turns off any
## already-active prayer in the same exclusivity group. Returns the new state.
func toggle(prayer_name: String) -> bool:
	var def: Dictionary = DataRegistry.prayers.get(prayer_name, {})
	if def.is_empty():
		return false
	if active_prayers.has(prayer_name):
		active_prayers.erase(prayer_name)
		EventBus.prayer_changed.emit()
		return false
	if GameState.level("prayer") < int(def.get("levelReq", 1)):
		EventBus.combat_log.emit("[color=#a01010]Prayer level %d required for %s.[/color]" % [int(def.get("levelReq", 1)), prayer_name])
		return false
	if devotion_points() <= 0.0:
		EventBus.combat_log.emit("[color=#a01010]You have no prayer points left — recharge at an altar.[/color]")
		return false
	var group := str(def.get("group", ""))
	if group != "":
		for other: String in active_prayers.duplicate():
			if str(DataRegistry.prayers.get(other, {}).get("group", "")) == group:
				active_prayers.erase(other)
	active_prayers.append(prayer_name)
	EventBus.prayer_changed.emit()
	EventBus.prayer_activated.emit(prayer_name)   # world activation FX
	return true


## Drain Devotion by the active prayers' total per-second cost; deactivate all at empty.
func drain(delta: float) -> void:
	if active_prayers.is_empty():
		return
	var rate := 0.0
	for n: String in active_prayers:
		rate += float(DataRegistry.prayers.get(n, {}).get("drain", 0.2))
	devotion = maxf(devotion_points() - rate * delta, 0.0)
	if devotion <= 0.0 and not active_prayers.is_empty():
		active_prayers.clear()
		EventBus.combat_log.emit("[color=#a01010]Your prayer points run out; your prayers fade.[/color]")
		EventBus.prayer_changed.emit()


## Passive regen toward max while no prayer is active (altars still snap to full instantly).
func regen(delta: float) -> void:
	var mx := float(devotion_max())
	if devotion_points() < mx:
		devotion = minf(devotion + DEVOTION_REGEN_PER_SEC * delta, mx)


func recharge() -> void:
	devotion = float(devotion_max())
	EventBus.prayer_changed.emit()


## Combined multiplier/bonus from active prayers for a given combat style.
func _field(field: String, style: String, base: float) -> float:
	var v := base
	for n: String in active_prayers:
		var def: Dictionary = DataRegistry.prayers.get(n, {})
		var ps := str(def.get("style", "any"))
		if ps != "any" and ps != style:
			continue
		if field == "dr":
			v += float(def.get("dr", 0.0))
		elif def.has(field):
			v *= float(def[field])
	return v


func accuracy_mult(style: String) -> float: return _field("accuracy", style, 1.0)
func damage_mult(style: String) -> float: return _field("damage", style, 1.0)
func dr_bonus() -> float: return _field("dr", "any", 0.0)
func melee_protect() -> float:
	for n: String in active_prayers:
		var m := float(DataRegistry.prayers.get(n, {}).get("meleeProtect", 0.0))
		if m > 0.0:
			return m
	return 1.0
