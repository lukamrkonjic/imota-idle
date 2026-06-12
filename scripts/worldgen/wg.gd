extends RefCounted
## Shared world-generation constants and deterministic hashing.
## Everything in worldgen derives randomness from WG.hash_i/r01 so a given
## world seed always produces the identical world, on every machine.

const TILE := 48.0                       # px per tile (12 art px at PX=4)
const CHUNK_TILES := 16                  # tiles per chunk side
const CHUNK_SIZE := TILE * float(CHUNK_TILES)
const ZONE_CELL := 6                     # zone Voronoi cell size, in chunks
const VIEW_RADIUS := 2                   # chunks kept loaded around the player
const SITE_SEARCH_RADIUS := 14           # chunks scanned for auto-path targets


static func key(layer: int, cx: int, cy: int) -> String:
	return "%d:%d:%d" % [layer, cx, cy]


## Deterministic avalanche hash (splitmix-style). Constants stay below 2^31 so
## literals parse everywhere; intermediate overflow wraps, which is fine.
static func hash_i(p_seed: int, a: int, b: int = 0, c: int = 0) -> int:
	var h: int = p_seed + a * 0x9E3779B9 + b * 0x6C8E9CF5 + c * 0x5851F42D
	h = (h ^ (h >> 30)) * 0x45D9F3B
	h = (h ^ (h >> 27)) * 0x119DE1F3
	h = h ^ (h >> 31)
	return h & 0x7FFFFFFFFFFFFFFF


## Deterministic float in [0, 1).
static func r01(p_seed: int, a: int, b: int = 0, c: int = 0) -> float:
	return float(hash_i(p_seed, a, b, c) % 1000003) / 1000003.0


## Deterministic pick from a weighted dict {key: weight}. Returns "" if empty.
static func pick_weighted(weights: Dictionary, roll: float) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	if total <= 0.0:
		return ""
	var target := roll * total
	for k: String in weights:
		target -= float(weights[k])
		if target <= 0.0:
			return k
	return weights.keys().back()


static func tile_to_world(tx: int, ty: int) -> Vector2:
	return Vector2((float(tx) + 0.5) * TILE, (float(ty) + 0.5) * TILE)


static func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


static func tile_to_chunk(t: Vector2i) -> Vector2i:
	return Vector2i(floori(float(t.x) / CHUNK_TILES), floori(float(t.y) / CHUNK_TILES))


static func world_to_chunk(pos: Vector2) -> Vector2i:
	return tile_to_chunk(world_to_tile(pos))
