extends RefCounted
class_name UiScale
## Global UI scale factor — bump fonts and panel metrics together.

const SCALE := 1.2


static func f(base: float) -> float:
	return base * SCALE


static func i(base: int) -> int:
	return maxi(1, int(roundf(float(base) * SCALE)))


static func v2(base: Vector2) -> Vector2:
	return base * SCALE
