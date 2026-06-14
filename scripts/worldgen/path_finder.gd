extends RefCounted
## Tile pathfinding over the currently loaded chunks via AStar2D.
##
## A general graph (not AStarGrid2D) is used so movement obeys a per-EDGE climb
## limit: two adjacent walkable tiles are only linked when their elevation differs
## by at most WG.MAX_CLIMB_STEP. The player therefore cannot step straight off a
## tall peak onto low ground — he must descend the terraced slope or walk around,
## like hills in a proper isometric game. Water, cave walls, hazards, blocked
## structure footprints and tiles above WG.MAX_REACHABLE_ELEV carry no node at
## all; whole chunks in zones above the player's entry level are skipped so locked
## zones act as hard barriers.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const ORTHO: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var astar := AStar2D.new()
var region := Rect2i()  # in tile coords
var locked_chunks: Dictionary = {}  # "cx:cy" -> level requirement

var _ids: Dictionary = {}   # Vector2i tile -> AStar point id
var _elev: Dictionary = {}  # Vector2i tile -> elevation step
var _next_id := 0


## chunks: Array of Chunk (one layer). entry_level: zone_map.player_entry_level().
func rebuild(chunks: Array, reg: RefCounted, entry_level: int) -> void:
	astar.clear()
	_ids.clear()
	_elev.clear()
	locked_chunks.clear()
	_next_id = 0
	if chunks.is_empty():
		region = Rect2i()
		return
	var mn := Vector2i(99999, 99999)
	var mx := Vector2i(-99999, -99999)
	var present: Dictionary = {}
	for c: RefCounted in chunks:
		mn = Vector2i(mini(mn.x, c.cx), mini(mn.y, c.cy))
		mx = Vector2i(maxi(mx.x, c.cx), maxi(mx.y, c.cy))
		present["%d:%d" % [c.cx, c.cy]] = c
	region = Rect2i(mn * WG.CHUNK_TILES, (mx - mn + Vector2i.ONE) * WG.CHUNK_TILES)

	# 1) Create a node for every reachable walkable tile.
	for key: String in present:
		var c: RefCounted = present[key]
		var req := int(c.zone.get("req", 1))
		if req > entry_level:
			locked_chunks[key] = req
			continue
		var base := Vector2i(c.cx, c.cy) * WG.CHUNK_TILES
		var has_elev: bool = c.elev.size() > 0
		for ty: int in WG.CHUNK_TILES:
			for tx: int in WG.CHUNK_TILES:
				var td: Dictionary = reg.tile_def(c.tile_id(tx, ty))
				if not bool(td.get("walkable", false)) or bool(td.get("water", false)) \
						or bool(td.get("hazard", false)) or c.is_blocked(tx, ty):
					continue
				var e: int = c.elev[ty * WG.CHUNK_TILES + tx] if has_elev else 0
				if e > WG.MAX_REACHABLE_ELEV:
					continue
				var gt := base + Vector2i(tx, ty)
				_ids[gt] = _next_id
				_elev[gt] = e
				astar.add_point(_next_id, Vector2(gt))
				_next_id += 1

	# 2) Link neighbours only where the elevation step is climbable. Diagonals also
	#    require both orthogonal corners open and climbable (no cutting cliff corners).
	for gt: Vector2i in _ids:
		var id: int = _ids[gt]
		var e: int = _elev[gt]
		for off: Vector2i in ORTHO:
			_try_link(id, e, gt + off)
		for d: Vector2i in DIAG:
			var n := gt + d
			if not _ids.has(n) or absi(_elev[n] - e) > WG.MAX_CLIMB_STEP:
				continue
			var a := gt + Vector2i(d.x, 0)
			var b := gt + Vector2i(0, d.y)
			if not (_ids.has(a) and _ids.has(b)):
				continue
			if absi(_elev[a] - e) > WG.MAX_CLIMB_STEP or absi(_elev[b] - e) > WG.MAX_CLIMB_STEP:
				continue
			if not astar.are_points_connected(id, _ids[n]):
				astar.connect_points(id, _ids[n])


func _try_link(id: int, e: int, n: Vector2i) -> void:
	if not _ids.has(n) or absi(_elev[n] - e) > WG.MAX_CLIMB_STEP:
		return
	if not astar.are_points_connected(id, _ids[n]):
		astar.connect_points(id, _ids[n])


func in_region(tile: Vector2i) -> bool:
	return not _ids.is_empty() and region.has_point(tile)


func has_reachable_tile(tile: Vector2i) -> bool:
	return _ids.has(tile)


## Why is this tile unreachable? Returns the lock level req, or 0.
func lock_req_at(tile: Vector2i) -> int:
	var c := WG.tile_to_chunk(tile)
	return int(locked_chunks.get("%d:%d" % [c.x, c.y], 0))


## Path between world positions. The start always snaps defensively to the
## player's current tile; callers can require the target to be exact for plain
## ground clicks, or allow snapping for entity interactions.
## Returns world-space waypoints (tile centers), empty if unreachable.
func find_path(from_world: Vector2, to_world: Vector2, snap_target: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _ids.is_empty():
		return out
	var from_id := _nearest_id(WG.world_to_tile(from_world))
	var to_tile := WG.world_to_tile(to_world)
	var to_id := _nearest_id(to_tile) if snap_target else int(_ids.get(to_tile, -1))
	if from_id < 0 or to_id < 0:
		return out
	for id: int in astar.get_id_path(from_id, to_id):
		var t := astar.get_point_position(id)
		out.append(WG.tile_to_world(int(t.x), int(t.y)))
	return out


## Nearest tile that has a node, spiralling out from the target. -1 if none close.
func _nearest_id(tile: Vector2i) -> int:
	if _ids.has(tile):
		return _ids[tile]
	for ring: int in range(1, 7):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var n := tile + Vector2i(dx, dy)
				if _ids.has(n):
					return _ids[n]
	return -1
