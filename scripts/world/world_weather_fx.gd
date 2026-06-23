extends Node2D
class_name WorldWeatherFx
## Screen-space weather overlay: snow flakes, rain streaks and A-Short-Hike wind lines. Lives on its
## own CanvasLayer ABOVE the 3D present (set up in world.gd) so it always composites over the rendered
## world and draws in viewport space (ignores the 2D camera). Intensity is read live from the Weather
## autoload — this node only renders; all the logic/scheduling/gating is in Weather.

const SNOW_MAX := 72
const RAIN_MAX := 95
const WIND_MAX := 26

var _t := 0.0


func _process(delta: float) -> void:
	# Time runs faster in wind so rain and streaks sweep harder.
	_t += delta * (0.55 + Weather.wind * 1.8)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x < 4.0:
		return
	if Weather.snow > 0.01:
		_draw_snow(size, Weather.snow, Weather.wind)
	if Weather.rain > 0.01:
		_draw_rain(size, Weather.rain, Weather.wind)
	if Weather.wind > 0.30:
		_draw_wind(size, Weather.wind)


func _draw_snow(size: Vector2, amt: float, wind: float) -> void:
	for i: int in int(round(amt * SNOW_MAX)):
		var rx := _r(i, 11.0)
		var rp := _r(i, 22.0)
		var life := _frac(_t * (0.05 + rx * 0.05) + rp)
		var y := life * (size.y + 20.0) - 10.0
		var x := _wrap(rx * size.x + sin(_t * 0.9 + rp * 31.0) * (5.0 + wind * 22.0) + life * wind * 90.0, size.x)
		var s := 2.0 + rx * 2.0
		var col := Color(0.93, 0.96, 1.0, (0.45 + 0.4 * amt) * (0.6 + 0.4 * sin(life * PI)))
		draw_rect(Rect2(x, y, s, s), col)


func _draw_rain(size: Vector2, amt: float, wind: float) -> void:
	var dir := Vector2(0.18 + wind * 0.5, 1.0).normalized()
	for i: int in int(round(amt * RAIN_MAX)):
		var rx := _r(i, 33.0)
		var rp := _r(i, 44.0)
		var life := _frac(_t * (0.6 + rx * 0.5) + rp)
		var p := Vector2(_wrap(rx * size.x + life * wind * 160.0, size.x), life * (size.y + 40.0) - 20.0)
		var col := Color(0.62, 0.72, 0.92, 0.26 + 0.22 * amt)
		draw_line(p, p - dir * (10.0 + rx * 10.0), col, 1.0 + rx)


func _draw_wind(size: Vector2, wind: float) -> void:
	var dir := Vector2(1.0, -0.16).normalized()
	for i: int in int(round(clampf(wind - 0.3, 0.0, 1.0) * WIND_MAX)):
		var ry := _r(i, 55.0)
		var rp := _r(i, 66.0)
		var rl := _r(i, 77.0)
		var life := _frac(_t * (0.18 + rl * 0.22 + wind * 0.2) + rp)
		var p := Vector2(-size.x * 0.2 + life * size.x * 1.4, ry * size.y + sin(life * TAU + rp * 9.0) * 10.0)
		var col := Color(1.0, 1.0, 1.0, (0.05 + 0.10 * wind) * sin(life * PI))
		draw_line(p, p + dir * (50.0 + rl * 130.0), col, 1.0 + rl)


# Deterministic per-particle 0..1 so each flake/streak keeps a stable lane + phase frame to frame.
static func _r(i: int, salt: float) -> float:
	return _frac(sin(float(i) * 12.9898 + salt) * 43758.5453)


static func _frac(v: float) -> float:
	return v - floorf(v)


static func _wrap(v: float, m: float) -> float:
	return fposmod(v, m)
