extends RefCounted
class_name DecorPlacement
## Pure, deterministic ground-decor placement for the FIXED baked map. Produces the
## list of static decor sprites for a chunk as {key, pos} — NO nodes. The
## ChunkRenderer draws them as batched atlas regions, so the per-chunk decor cost
## is one scan (off-thread) + a few batched draws instead of a 512-tile scan plus
## hundreds of Node2D instantiations every time the chunk streams in.
##
## Thread-safe: reads only the immutable chunk and registry; writes nothing shared.
## (Extracted verbatim from world_entity_spawner's old _spawn_ground_decor_tile so
## placement is identical — same seed, hashes and weights.)

const WG := preload("res://scripts/worldgen/wg.gd")

## Must match tools/bake_sprites.gd DECOR_VARIANTS and world_decor.gd ATLAS_VARIANTS.
const ATLAS_VARIANTS := 24

# Tiles that never grow ground clutter (bare/hard ground, water-adjacent sand…).
const SKIP_TILES := ["sand", "sand_dune", "shallow", "rock", "cobble", "snow",
	"gravel", "savanna_grass", "jungle_loam", "boreal_moss", "badland_clay"]


## Returns Array of {"key":String, "pos":Vector2(world)} for a surface chunk.
static func compute(chunk: RefCounted, reg: RefCounted, seed: int) -> Array:
	var out: Array = []
	if chunk.layer != 0:
		return out
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			var item := _tile(chunk, reg, seed, tx, ty)
			if not item.is_empty():
				out.append(item)
	return out


static func _tile(chunk: RefCounted, reg: RefCounted, seed: int, tx: int, ty: int) -> Dictionary:
	var tid: int = chunk.tile_id(tx, ty)
	if tid < 0 or tid >= reg.tile_order.size():
		return {}
	var tile: Dictionary = reg.tile_def(tid)
	var tname: String = reg.tile_order[tid]
	if chunk.elev.size() > 0 and chunk.elev[ty * WG.CHUNK_TILES + tx] > 0:
		return {}
	if bool(tile.get("water", false)) or not bool(tile.get("walkable", true)):
		return {}
	if tname in SKIP_TILES:
		return {}
	var r := WG.r01(seed, chunk.cx * 251 + tx, chunk.cy * 263 + ty, 201)
	var biome_id := _biome_id(chunk, reg, tx, ty)
	var near_water := _near_water(chunk, reg, tx, ty)
	if r > _chance(reg, biome_id, near_water):
		return {}
	var variant := int(WG.hash_i(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 202) % 1000)
	var kroll := WG.r01(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 205)
	var kind := _pick_kind(reg, biome_id, near_water, kroll)
	var jitter := Vector2(
		(WG.r01(seed, tx, ty, 203) - 0.5) * WG.TILE * 0.28,
		(WG.r01(seed, tx, ty, 204) - 0.5) * WG.TILE * 0.14)
	var pos: Vector2 = chunk.tile_world(tx, ty) + jitter
	return {"key": "decor|%s|%d" % [kind, variant % ATLAS_VARIANTS], "pos": pos}


static func _biome_id(chunk: RefCounted, reg: RefCounted, tx: int, ty: int) -> String:
	var b_idx: int = chunk.biome_at(tx, ty)
	return "" if b_idx == 255 else str(reg.biomes[b_idx]["id"])


static func _near_water(chunk: RefCounted, reg: RefCounted, tx: int, ty: int) -> bool:
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx := tx + ox
			var ny := ty + oy
			if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
				continue
			if bool(reg.tile_def(chunk.tile_id(nx, ny)).get("water", false)):
				return true
	return false


static func _chance(reg: RefCounted, biome_id: String, near_water: bool) -> float:
	var cfg: Dictionary = reg.ground_decor(biome_id)
	if cfg.is_empty():
		return 0.025
	if near_water:
		return float(cfg.get("waterDensity", cfg.get("density", 0.03)))
	return float(cfg.get("density", 0.03))


static func _pick_kind(reg: RefCounted, biome_id: String, near_water: bool, roll: float) -> String:
	var cfg: Dictionary = reg.ground_decor(biome_id)
	var kinds: Array = cfg.get("kinds", [])
	if near_water and biome_id in ["swamp", "marsh_pool", "beach", "oasis", "jungle", "tide_flats", "bog"]:
		for entry: Dictionary in kinds:
			if str(entry.get("kind", "")) in ["reed", "fern", "mushroom"]:
				if roll < 0.55:
					return str(entry["kind"])
	if not kinds.is_empty():
		var total := 0.0
		for entry: Dictionary in kinds:
			total += float(entry.get("weight", 1.0))
		var target := roll * total
		for entry: Dictionary in kinds:
			target -= float(entry.get("weight", 1.0))
			if target <= 0.0:
				return str(entry.get("kind", "grass"))
		return str(kinds.back().get("kind", "grass"))
	return "grass"
