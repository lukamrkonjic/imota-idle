extends RefCounted
## Layered-noise terrain fields (height / moisture / temperature) plus rivers
## and lakes, and data-driven biome classification against the biome registry.
## All sampling is in TILE coordinates and fully determined by the world seed.

const WG := preload("res://scripts/worldgen/wg.gd")

## Tiles within this many chunks of the origin are blended toward gentle
## plains values so the home camp always sits on open, walkable ground.
const SPAWN_SHAPE_CHUNKS := 2.2

var reg: RefCounted
var world_seed: int = 0

var _height: FastNoiseLite
var _moist: FastNoiseLite
var _temp: FastNoiseLite
var _river: FastNoiseLite
var _river_mask: FastNoiseLite
var _lake: FastNoiseLite
var _palette: FastNoiseLite  # clustered ground-variant patches, not per-tile salt

# Water sizing from generation_rules.json (rivers widen toward lowlands).
var _river_w_base := 0.042
var _river_w_extra := 0.070
var _lake_water := 0.735
var _lake_shore := 0.695

# Cached tile byte ids for the carving hot path.
var _t_deep: int
var _t_water: int
var _t_shallow: int
var _t_cobble: int


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed
	var wr: Dictionary = reg.gen_rules.get("water", {})
	_river_w_base = float(wr.get("riverWidthBase", 0.042))
	_river_w_extra = float(wr.get("riverWidthExtra", 0.070))
	_lake_water = float(wr.get("lakeWater", 0.735))
	_lake_shore = float(wr.get("lakeShore", 0.695))
	_height = _noise(p_seed, 0.011, 4)
	_moist = _noise(p_seed + 101, 0.016, 3)
	_temp = _noise(p_seed + 202, 0.006, 2)
	_river = _noise(p_seed + 303, 0.0050, 1)
	_river_mask = _noise(p_seed + 304, 0.0028, 2)
	_lake = _noise(p_seed + 404, float(wr.get("lakeFreq", 0.012)), 2)
	_palette = _noise(p_seed + 606, 0.050, 2)
	_t_deep = int(reg.tile_index["deep_water"])
	_t_water = int(reg.tile_index["water"])
	_t_shallow = int(reg.tile_index["shallow"])
	_t_cobble = int(reg.tile_index["cobble"])


static func _noise(p_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


## Height / moisture / temperature at a tile position, each in [0, 1].
func fields(tx: float, ty: float) -> Vector3:
	var h := _height.get_noise_2d(tx, ty) * 0.5 + 0.5
	var m := _moist.get_noise_2d(tx, ty) * 0.5 + 0.5
	var t := _temp.get_noise_2d(tx, ty) * 0.5 + 0.5
	# Home-area shaping: solid temperate land near the origin.
	var dist_chunks := Vector2(tx, ty).length() / float(WG.CHUNK_TILES)
	if dist_chunks < SPAWN_SHAPE_CHUNKS:
		var s := 1.0 - smoothstep(0.0, SPAWN_SHAPE_CHUNKS, dist_chunks)
		h = lerpf(h, clampf(h, 0.46, 0.62), s)
		m = lerpf(m, clampf(m, 0.30, 0.50), s)
		t = lerpf(t, clampf(t, 0.35, 0.65), s)
	return Vector3(h, m, t)


## Index into reg.biomes for the biome at a tile position. Authored regions
## (WorldSpec) force their biome here; everywhere else falls back to the noise
## classifier, so the procedural world is unchanged.
func biome_idx(tx: float, ty: float) -> int:
	var forced := region_biome_idx(tx, ty)
	return forced if forced >= 0 else classify(fields(tx, ty))


## Authored biome index forced by a WorldSpec region at this tile, or -1.
func region_biome_idx(tx: float, ty: float) -> int:
	if reg.spec == null or not reg.spec.active:
		return -1
	var bid := str(reg.spec.biome_for_tile(tx, ty))
	if bid.is_empty():
		return -1
	return int(reg.biome_index.get(bid, -1))


## Data-driven classification: highest-priority biome whose ranges all match.
func classify(f: Vector3) -> int:
	for i: int in reg.biomes.size():
		var w: Dictionary = reg.biomes[i].get("when", {})
		if f.x < float(w.get("heightMin", -1.0)) or f.x > float(w.get("heightMax", 2.0)):
			continue
		if f.y < float(w.get("moistureMin", -1.0)) or f.y > float(w.get("moistureMax", 2.0)):
			continue
		if f.z < float(w.get("tempMin", -1.0)) or f.z > float(w.get("tempMax", 2.0)):
			continue
		return i
	return reg.biomes.size() - 1  # priority-0 fallback always matches


## Lakes and rivers fade to nothing right at the origin so the home camp
## footprint can never flood, whatever the water tuning says.
## 1.0 at the campfire -> 0.0 beyond ~1.8 chunks.
func _home_water_suppress(tx: float, ty: float) -> float:
	var dist_chunks := Vector2(tx, ty).length() / float(WG.CHUNK_TILES)
	return 1.0 - smoothstep(0.8, 1.8, dist_chunks)


## River channel test: ridged band of the river noise, tapering with height
## so streams widen toward the lowlands. Returns 0 none, 1 shallow, 2 deep.
func river_at(tx: float, ty: float, h: float) -> int:
	if h < 0.34 or h > 0.74:
		return 0
	var mask := _river_mask.get_noise_2d(tx, ty) * 0.5 + 0.5
	if mask < 0.46:
		return 0
	var rv: float = absf(_river.get_noise_2d(tx, ty))
	var w := _river_w_base + _river_w_extra * (1.0 - smoothstep(0.34, 0.74, h))
	w *= 1.0 - _home_water_suppress(tx, ty)
	if w <= 0.001:
		return 0
	if rv < w * 0.62:
		return 2
	if rv < w:
		return 1
	return 0


## Lake test for inland depressions. Returns 0 none, 1 shore, 2 water.
func lake_at(tx: float, ty: float, h: float) -> int:
	if h < 0.345 or h > 0.62:
		return 0
	var lv := _lake.get_noise_2d(tx, ty) * 0.5 + 0.5
	var bump := _home_water_suppress(tx, ty) * 0.4
	if lv > _lake_water + bump:
		return 2
	if lv > _lake_shore + bump:
		return 1
	return 0


## Final ground tile (byte id) at a tile position for the given biome index.
## Order: ocean depth -> lakes -> rivers -> weighted biome palette.
func tile_at(tx: float, ty: float, f: Vector3, b_idx: int) -> int:
	var h := f.x
	var biome_id := str(reg.biomes[b_idx]["id"])
	if biome_id == "ocean":
		return _t_deep if h < 0.24 else _t_water
	match lake_at(tx, ty, h):
		2: return _t_water
		1: return _t_shallow
	match river_at(tx, ty, h):
		2: return _t_water
		1: return _t_shallow
	if biome_id != "beach" and biome_id != "desert" and biome_id != "tundra":
		var near_river := false
		for off: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var nf := fields(tx + off.x, ty + off.y)
			if river_at(tx + off.x, ty + off.y, nf.x) > 0:
				near_river = true
				break
		if near_river:
			# Clustered pebbly banks (noise patches), never lone bright tiles.
			var bank := _palette.get_noise_2d(tx * 1.7 + 50.0, ty * 1.7 - 50.0) * 0.5 + 0.5
			if bank > 0.64:
				return _t_cobble
	# Ground variants come in coherent patches: a low-frequency noise picks the
	# palette entry, with a whisper of per-tile dither so patch edges stay soft.
	# (Pure per-tile randomness made tundra/forest floors look like checkers.)
	var weights: Array = reg.biomes[b_idx]["_tile_weights"]
	var patch := _palette.get_noise_2d(tx, ty) * 0.5 + 0.5
	var roll := clampf(patch * 0.90 + WG.r01(world_seed, floori(tx), floori(ty), 7) * 0.10, 0.0, 0.999)
	var total := 0.0
	for entry: Array in weights:
		total += float(entry[1])
	var target := roll * total
	for entry: Array in weights:
		target -= float(entry[1])
		if target <= 0.0:
			return int(entry[0])
	return int(weights.back()[0])


## Biome index sampled with positional jitter — used by the renderer so biome
## borders dissolve into each other instead of forming straight seams.
func biome_idx_jittered(tx: float, ty: float, jitter: float) -> int:
	var jx := (WG.r01(world_seed, floori(tx * 4.0), floori(ty * 4.0), 11) - 0.5) * jitter
	var jy := (WG.r01(world_seed, floori(tx * 4.0), floori(ty * 4.0), 13) - 0.5) * jitter
	return classify(fields(tx + jx, ty + jy))
