extends RefCounted
## Discrete terraced elevation for the 2D top-down world. Quantizes the
## classifier's continuous height field into levels 0..7 (deep water ..
## mountain peak) with a small ruggedness jitter so terrace contours break up
## instead of tracing smooth noise isolines. Levels drive resource density
## (generation_rules.json), cliff shading in chunk_renderer.gd, and are stored
## per tile on chunks so gameplay systems can query them without resampling.
##
## Levels: 0 deep water, 1 shallow water, 2 lowland, 3 normal land,
##         4 hill, 5 high hill, 6 mountain, 7 peak.

const WG := preload("res://scripts/worldgen/wg.gd")

const LEVEL_COUNT := 8

var classifier: RefCounted
var world_seed: int = 0
var _bounds: Array = []          # upper height bound per level 0..6
var _rugged: FastNoiseLite
var _rugged_amp := 0.030


func setup(reg: RefCounted, p_classifier: RefCounted, p_seed: int) -> void:
	classifier = p_classifier
	world_seed = p_seed
	var rules: Dictionary = reg.gen_rules.get("elevation", {})
	_bounds = rules.get("bounds", [0.24, 0.345, 0.46, 0.62, 0.72, 0.80, 0.88])
	_rugged = FastNoiseLite.new()
	_rugged.seed = p_seed + 505
	_rugged.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_rugged.frequency = float(rules.get("ruggedFreq", 0.045))
	_rugged.fractal_type = FastNoiseLite.FRACTAL_NONE
	_rugged_amp = float(rules.get("ruggedAmp", 0.030))


## Elevation level from an already-sampled height value at a tile position.
## The jitter only kicks in above water so shorelines stay exactly where the
## classifier carved them.
func level_from_height(h: float, tx: float, ty: float) -> int:
	var v := h
	if h > float(_bounds[1]):
		v += _rugged.get_noise_2d(tx, ty) * _rugged_amp
	for lvl: int in _bounds.size():
		if v < float(_bounds[lvl]):
			return lvl
	return LEVEL_COUNT - 1


func level_at(tx: float, ty: float) -> int:
	var f: Vector3 = classifier.fields(tx, ty)
	return level_from_height(f.x, tx, ty)
