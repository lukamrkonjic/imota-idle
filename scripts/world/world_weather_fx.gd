extends Node2D
class_name WorldWeatherFx
## Screen-space weather overlay: a full-screen colour hue (blue rain / white snow) plus snow flakes,
## rain streaks and A-Short-Hike wind lines. Lives on its own CanvasLayer ABOVE the 3D present (set
## up in world.gd) so it always composites over the rendered world and draws in viewport space
## (ignores the 2D camera). Intensity is read live from the Weather autoload — this node only renders.

const SNOW_MAX := 150   # heavier snowfall
const RAIN_MAX := 110
const WIND_MAX := 34

var _t := 0.0


func _process(delta: float) -> void:
	# Time runs faster in wind so rain and streaks sweep harder.
	_t += delta * (0.55 + Weather.wind * 1.8)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x < 4.0:
		return
	# Full-screen colour hue: clearly tint the whole view blue while raining / white while snowing.
	var hue: Color = Weather.tint
	if hue.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(hue.r, hue.g, hue.b, hue.a * 0.5))
	if Weather.snow > 0.01:
		_draw_snow(size, Weather.snow, Weather.wind)
	if Weather.rain > 0.01:
		_draw_rain(size, Weather.rain, Weather.wind)
	if Weather.wind > 0.28:
		_draw_wind(size, Weather.wind)


func _draw_snow(size: Vector2, amt: float, wind: float) -> void:
	for i: int in int(round(amt * SNOW_MAX)):
		var rx := _r(i, 11.0)
		var rp := _r(i, 22.0)
		var life := _frac(_t * (0.05 + rx * 0.05) + rp)
		var y := life * (size.y + 24.0) - 12.0
		var x := _wrap(rx * size.x + sin(_t * 0.9 + rp * 31.0) * (5.0 + wind * 22.0) + life * wind * 90.0, size.x)
		var s := 4.0 + rx * 4.0   # bigger flakes
		var col := Color(0.95, 0.97, 1.0, (0.55 + 0.4 * amt) * (0.65 + 0.35 * sin(life * PI)))
		draw_rect(Rect2(x, y, s, s), col)


func _draw_rain(size: Vector2, amt: float, wind: float) -> void:
	var dir := Vector2(0.18 + wind * 0.5, 1.0).normalized()
	for i: int in int(round(amt * RAIN_MAX)):
		var rx := _r(i, 33.0)
		var rp := _r(i, 44.0)
		var life := _frac(_t * (0.6 + rx * 0.5) + rp)
		var p := Vector2(_wrap(rx * size.x + life * wind * 160.0, size.x), life * (size.y + 40.0) - 20.0)
		var col := Color(0.66, 0.76, 0.96, 0.34 + 0.26 * amt)
		draw_line(p, p - dir * (16.0 + rx * 16.0), col, 2.0 + rx * 1.5)   # longer, thicker streaks


func _draw_wind(size: Vector2, wind: float) -> void:
	var dir := Vector2(1.0, -0.16).normalized()
	for i: int in int(round(clampf(wind - 0.28, 0.0, 1.0) * WIND_MAX)):
		var ry := _r(i, 55.0)
		var rp := _r(i, 66.0)
		var rl := _r(i, 77.0)
		var life := _frac(_t * (0.18 + rl * 0.22 + wind * 0.2) + rp)
		var p := Vector2(-size.x * 0.2 + life * size.x * 1.4, ry * size.y + sin(life * TAU + rp * 9.0) * 10.0)
		var col := Color(1.0, 1.0, 1.0, (0.12 + 0.22 * wind) * sin(life * PI))   # clearer streaks
		draw_line(p, p + dir * (80.0 + rl * 170.0), col, 1.6 + rl * 1.8)         # longer + thicker


# Deterministic per-particle 0..1 so each flake/streak keeps a stable lane + phase frame to frame.
static func _r(i: int, salt: float) -> float:
	return _frac(sin(float(i) * 12.9898 + salt) * 43758.5453)


static func _frac(v: float) -> float:
	return v - floorf(v)


static func _wrap(v: float, m: float) -> float:
	return fposmod(v, m)
