extends RefCounted
class_name PixelAnim
## Tiny shared helpers for the procedural, code-driven animation everywhere in the render
## layer (no AnimationPlayer). Centralises the `base + amp*sin(t*freq)` pulse that fire/glow/
## breathing effects each used to roll by hand.

## A smooth oscillation: base ± amp at frequency `freq` (rad/s), optionally phase-shifted.
static func pulse(t: float, freq: float, amp: float = 1.0, base: float = 0.0, phase: float = 0.0) -> float:
	return base + amp * sin(t * freq + phase)


## Two summed octaves — a livelier flicker (fire, torches) than a single sine.
static func flicker(t: float, f1: float, a1: float, f2: float, a2: float, base: float = 1.0) -> float:
	return base + a1 * sin(t * f1) + a2 * sin(t * f2)
