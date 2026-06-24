extends Node
## Day/night cycle (autoload "DayNight").
##
## `time01` runs 0..1 over DAY_LENGTH:  0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
## WorldAtmosphere reads it each frame to drive the sun (arc / colour / energy), ambient light and
## sky tint; weather then washes over the top of that.
##
## Pace: ~20 real minutes per full day — the cozy/idle sweet spot (Minecraft is 20 min; Stardew a
## day ~14; Don't Starve ~8). Long enough that the light shifts gently, short enough to actually see
## dawn and dusk in a session. Tunable via DAY_LENGTH; admin can scrub/scale it live.

signal phase_changed(phase: String)

const DAY_LENGTH := 1200.0   # seconds for one full cycle

var time01 := 0.32           # start mid-morning so a fresh game opens in daylight
var scale := 1.0             # admin speed multiplier (0 = frozen)

var _phase := ""


func _process(delta: float) -> void:
	if scale == 0.0:
		return
	time01 = fposmod(time01 + delta / DAY_LENGTH * scale, 1.0)
	var p := phase()
	if p != _phase:
		_phase = p
		phase_changed.emit(p)


func set_time(t: float) -> void:
	time01 = fposmod(t, 1.0)


## 0 at midnight .. 1 at noon, with flat-ish nights and a bright plateau at midday.
func daylight() -> float:
	var c := -cos(time01 * TAU) * 0.5 + 0.5   # smooth sinusoid, 0 midnight .. 1 noon
	return clampf(c * 1.35 - 0.18, 0.0, 1.0)


## Sun elevation in degrees above the horizon (negative = below, i.e. night).
func sun_elevation() -> float:
	return sin((time01 - 0.25) * TAU) * 66.0


## 0 high sun .. 1 sun near/below the horizon — drives warm dawn/dusk colour + bloom of the sky.
func horizon_glow() -> float:
	return clampf(1.0 - clampf(sun_elevation() / 16.0, 0.0, 1.0), 0.0, 1.0)


## 0..1, peaks at sunrise — drives the misty-morning shader. Morning half only (never dusk).
func dawn() -> float:
	var morning := 1.0 - smoothstep(0.40, 0.54, time01)   # 1 before sunrise-ish .. 0 by mid-morning
	return horizon_glow() * morning


## 0..1, peaks at sunset — drives the extra colour saturation at dusk. Evening half only (never dawn).
func dusk() -> float:
	var evening := smoothstep(0.50, 0.66, time01)          # 0 midday .. 1 toward sunset
	return horizon_glow() * evening


func is_night() -> bool:
	return daylight() < 0.05


func phase() -> String:
	var t := time01
	if t < 0.22 or t >= 0.80: return "Night"
	if t < 0.30: return "Dawn"
	if t < 0.70: return "Day"
	return "Dusk"


func label() -> String:
	var mins := int(time01 * 24.0 * 60.0)
	return "%02d:%02d (%s)" % [mins / 60, mins % 60, phase()]
