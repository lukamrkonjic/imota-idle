extends Node
## Global weather (autoload "Weather").
##
## Intensity-based, NOT biome-based: `snow`, `rain` and `wind` are eased 0..1 values that every
## renderer samples — the atmosphere colour grade (whiter snow / bluer rain), the screen-space
## particle overlay (flakes / rain streaks / A-Short-Hike wind lines), and the tree-wind rate.
##
## Targets come from one of two sources:
##   • a forced admin MODE (normal / windy / snow / rain) — shown everywhere, for testing/showcase,
##   • the AUTO scheduler — a slow storminess "front" gated by the LOCAL CLIMATE at the player, so the
##     same front falls as SNOW on cold ground (far north / high elevation) and RAIN in the warm
##     south, and never snows in the warm south. That's what makes it map-driven, not biome-driven.

signal changed(mode: String)

const MODES := ["auto", "normal", "windy", "snow", "rain"]

var mode := "auto"

# Eased display intensities — what the renderers read each frame.
var snow := 0.0
var rain := 0.0
var wind := 0.12
# Colour wash for the atmosphere grade: rgb tint + strength in .a.
var tint := Color(0.85, 0.90, 1.0, 0.0)

var _ts := 0.0     # target snow
var _tr := 0.0     # target rain
var _tw := 0.12    # target wind

# AUTO scheduler: a storminess "front" 0..1 that drifts slowly over minutes.
var _front := 0.18
var _front_to := 0.18
var _front_timer := 6.0

const EASE := 0.7  # intensity ease toward target, per second (gentle cross-fades, no snapping)


func set_mode(m: String) -> void:
	if m == mode or not MODES.has(m):
		return
	mode = m
	changed.emit(m)


## Step to the next mode (admin hotkey / button convenience). Returns the new mode.
func cycle() -> String:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])
	return mode


func label() -> String:
	return mode.capitalize()


## Called every frame by the world. `climate01`: 0 = cold (far north / high ground) .. 1 = warm (south).
func update(delta: float, climate01: float) -> void:
	match mode:
		"normal": _ts = 0.0; _tr = 0.0; _tw = 0.10
		"windy":  _ts = 0.0; _tr = 0.0; _tw = 0.95
		"snow":   _ts = 1.0; _tr = 0.0; _tw = 0.40
		"rain":   _ts = 0.0; _tr = 1.0; _tw = 0.48
		_:        _auto(delta, climate01)
	snow = move_toward(snow, _ts, EASE * delta)
	rain = move_toward(rain, _tr, EASE * delta)
	wind = move_toward(wind, _tw, EASE * delta)
	# Whichever precipitation is heavier owns the colour wash; clear weather = no wash.
	if snow >= rain and snow > 0.01:
		tint = Color(0.82, 0.88, 1.0, snow * 0.55)     # cool snowy white
	elif rain > 0.01:
		tint = Color(0.50, 0.58, 0.74, rain * 0.50)    # cool blue-grey
	else:
		tint = Color(0.85, 0.90, 1.0, 0.0)


func _auto(delta: float, climate01: float) -> void:
	_front_timer -= delta
	if _front_timer <= 0.0:
		_front_timer = randf_range(45.0, 130.0)
		_front_to = randf()                            # next front strength
	_front = move_toward(_front, _front_to, 0.05 * delta)   # very slow drift between fronts
	var cold := 1.0 - clampf(climate01, 0.0, 1.0)
	var storm := smoothstep(0.52, 0.9, _front)         # only the upper band of a front is "weather"
	var snowiness := smoothstep(0.42, 0.78, cold)      # cold -> snow, warm -> rain (south never snows)
	_ts = storm * snowiness
	_tr = storm * (1.0 - snowiness)
	_tw = 0.10 + 0.5 * _front
