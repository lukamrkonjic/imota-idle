extends RefCounted
## Tile pathfinding over the currently loaded chunks via AStarGrid2D.
## Water, cave walls, and hazards are solid; whole chunks in zones above the
## player's entry level are solid too, so locked zones act as hard barriers
## the pathfinder simply routes around (or refuses to enter).

const WG := preload("res://scripts/worldgen/wg.gd")

var grid: AStarGrid2D = null
var region := Rect2i()  # in tile coords
var locked_chunks: Dictionary = {}  # "cx:cy" -> level requirement


## chunks: Array of Chunk (one layer). entry_level: zone_map.player_entry_level().
func rebuild(chunks: Array, reg: RefCounted, entry_level: int) -> void:
	locked_chunks.clear()
	if chunks.is_empty():
		grid = null
		return
	var mn := Vector2i(99999, 99999)
	var mx := Vector2i(-99999, -99999)
	for c: RefCounted in chunks:
		mn = Vector2i(mini(mn.x, c.cx), mini(mn.y, c.cy))
		mx = Vector2i(maxi(mx.x, c.cx), maxi(mx.y, c.cy))
	region = Rect2i(mn * WG.CHUNK_TILES, (mx - mn + Vector2i.ONE) * WG.CHUNK_TILES)
	grid = AStarGrid2D.new()
	grid.region = region
	grid.cell_size = Vector2(WG.TILE, WG.TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	# Everything defaults open; close missing chunks, locked zones, bad tiles.
	var present: Dictionary = {}
	for c: RefCounted in chunks:
		present["%d:%d" % [c.cx, c.cy]] = c
	for cy: int in range(mn.y, mx.y + 1):
		for cx: int in range(mn.x, mx.x + 1):
			var key := "%d:%d" % [cx, cy]
			var base := Vector2i(cx, cy) * WG.CHUNK_TILES
			if not present.has(key):
				_fill_solid(base)
				continue
			var c: RefCounted = present[key]
			var req := int(c.zone.get("req", 1))
			if req > entry_level:
				locked_chunks[key] = req
				_fill_solid(base)
				continue
			for ty: int in WG.CHUNK_TILES:
				for tx: int in WG.CHUNK_TILES:
					var td: Dictionary = reg.tile_def(c.tile_id(tx, ty))
					if not td["walkable"] or td["hazard"] or c.is_blocked(tx, ty):
						grid.set_point_solid(base + Vector2i(tx, ty), true)


func _fill_solid(base: Vector2i) -> void:
	for ty: int in WG.CHUNK_TILES:
		for tx: int in WG.CHUNK_TILES:
			grid.set_point_solid(base + Vector2i(tx, ty), true)


func in_region(tile: Vector2i) -> bool:
	return grid != null and region.has_point(tile)


## Why is this tile unreachable? Returns the lock level req, or 0.
func lock_req_at(tile: Vector2i) -> int:
	var c := WG.tile_to_chunk(tile)
	return int(locked_chunks.get("%d:%d" % [c.x, c.y], 0))


## Path between world positions; both ends snap to the nearest open tile.
## Returns world-space waypoints (tile centers), empty if unreachable.
func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if grid == null:
		return out
	var from_t := _nearest_open(WG.world_to_tile(from_world))
	var to_t := _nearest_open(WG.world_to_tile(to_world))
	if from_t.x == -99999 or to_t.x == -99999:
		return out
	var cells := grid.get_id_path(from_t, to_t)
	for cell: Vector2i in cells:
		out.append(WG.tile_to_world(cell.x, cell.y))
	return out


func _nearest_open(tile: Vector2i) -> Vector2i:
	var t := Vector2i(
		clampi(tile.x, region.position.x, region.end.x - 1),
		clampi(tile.y, region.position.y, region.end.y - 1))
	if not grid.is_point_solid(t):
		return t
	for ring: int in range(1, 6):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var n := t + Vector2i(dx, dy)
				if region.has_point(n) and not grid.is_point_solid(n):
					return n
	return Vector2i(-99999, -99999)
