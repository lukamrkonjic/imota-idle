extends RefCounted
class_name FishingHelper
## Fishing spot stand positions and cast range (OSRS-style shore casting).

const WG := preload("res://scripts/worldgen/wg.gd")

const CAST_TILES := 3


static func water_tile(chunk: RefCounted, site: Dictionary) -> Vector2i:
	if site.has("fish_tx") and site.has("fish_ty"):
		return Vector2i(int(site["fish_tx"]), int(site["fish_ty"]))
	return adjacent_water_tile(chunk, Vector2i(int(site["tx"]), int(site["ty"])))


static func adjacent_water_tile(chunk: RefCounted, shore: Vector2i) -> Vector2i:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var w := Vector2i(shore.x + off.x, shore.y + off.y)
		if _is_water(chunk, w):
			return w
	return Vector2i(-1, -1)


static func water_world_pos(chunk: RefCounted, site: Dictionary) -> Vector2:
	var w := water_tile(chunk, site)
	if w.x < 0:
		return chunk.tile_world(int(site["tx"]), int(site["ty"]))
	return chunk.tile_world(w.x, w.y)


static func can_cast_from(player_pos: Vector2, chunk: RefCounted, site: Dictionary) -> bool:
	if not WorldGen.is_walkable_world(player_pos):
		return false
	var water := water_tile_global(chunk, site)
	if water.x < 0:
		return false
	var pt := WG.world_to_tile(player_pos)
	var dist := maxi(absi(pt.x - water.x), absi(pt.y - water.y))
	return dist >= 1 and dist <= CAST_TILES


## GLOBAL tile coords of the spot's water tile (water_tile is chunk-LOCAL). can_cast_from and
## best_stand work in global tile space, so they must convert — mixing the two was why casting
## always failed ("stand on the shore") even stood right next to the water.
static func water_tile_global(chunk: RefCounted, site: Dictionary) -> Vector2i:
	var w := water_tile(chunk, site)
	if w.x < 0:
		return Vector2i(-1, -1)
	return Vector2i(chunk.cx * WG.CHUNK_TILES + w.x, chunk.cy * WG.CHUNK_TILES + w.y)


static func best_stand(player_pos: Vector2, chunk: RefCounted, site: Dictionary) -> Vector2:
	var water := water_tile_global(chunk, site)
	if water.x < 0:
		return chunk.tile_world(int(site["tx"]), int(site["ty"]))
	var best: Vector2 = chunk.tile_world(int(site["tx"]), int(site["ty"]))
	var best_d := player_pos.distance_squared_to(best)
	for dy: int in range(-CAST_TILES, CAST_TILES + 1):
		for dx: int in range(-CAST_TILES, CAST_TILES + 1):
			if maxi(absi(dx), absi(dy)) > CAST_TILES or (dx == 0 and dy == 0):
				continue
			var stand := Vector2i(water.x + dx, water.y + dy)
			var world := WG.tile_to_world(stand.x, stand.y)
			if not WorldGen.is_walkable_world(world):
				continue
			var d := player_pos.distance_squared_to(world)
			if d < best_d:
				best_d = d
				best = world
	return best


static func _is_water(chunk: RefCounted, local: Vector2i) -> bool:
	if local.x < 0 or local.y < 0 or local.x >= WG.CHUNK_TILES or local.y >= WG.CHUNK_TILES:
		return false
	return bool(WorldGen.reg.tile_def(chunk.tile_id(local.x, local.y)).get("water", false))
