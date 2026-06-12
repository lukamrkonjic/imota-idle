extends RefCounted
## Cellular-automata cave chunks for the negative layers, configured by
## data/world/cave_layers.json. The CA runs on an apron larger than the chunk
## and is seeded per-tile from the world seed, so neighbouring chunks always
## agree at their borders and the same seed yields the same caverns.
##
## Vertical wiring: every cave_entrance POI on the surface chunk above becomes
## a ladder_up here at the same tile; ladders down to the next layer are
## seeded per chunk while that layer exists in the registry.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const APRON := 6  # > CA iterations, so the chunk core is border-independent
const LADDER_DOWN_CHANCE := 0.22

var reg: RefCounted
var zone_map: RefCounted
var site_spawner: RefCounted
var monster_spawner: RefCounted
var world_seed: int = 0


func setup(p_reg: RefCounted, p_zone_map: RefCounted, p_sites: RefCounted, p_monsters: RefCounted, p_seed: int) -> void:
	reg = p_reg
	zone_map = p_zone_map
	site_spawner = p_sites
	monster_spawner = p_monsters
	world_seed = p_seed


## above_chunk: the already-generated chunk one layer up (surface for -1),
## used to align ladder positions.
func generate(layer: int, cx: int, cy: int, above_chunk: RefCounted) -> RefCounted:
	var cfg: Dictionary = reg.cave_layers.get(layer, {})
	var chunk: RefCounted = Chunk.new()
	chunk.setup(layer, cx, cy)
	chunk.zone = zone_map.zone_for_chunk(cx, cy)

	var grid := _automata(layer, cx, cy, cfg)

	var wall_id := int(reg.tile_index[str(cfg.get("wallTile", "cave_wall"))])
	var floor_id := int(reg.tile_index[str(cfg.get("floorTile", "cave_floor"))])
	var fungal_id := int(reg.tile_index.get(str(cfg.get("fungalTile", "cave_floor")), floor_id))
	var fungal_chance := float(cfg.get("fungalChance", 0.0))
	var n := WG.CHUNK_TILES
	for ty: int in n:
		for tx: int in n:
			var solid: bool = grid[(ty + APRON) * (n + APRON * 2) + tx + APRON]
			var id := wall_id
			if not solid:
				id = floor_id
				if fungal_chance > 0.0 and WG.r01(world_seed, cx * n + tx, cy * n + ty, 130 + layer) < fungal_chance:
					id = fungal_id
			chunk.tiles[Chunk.idx(tx, ty)] = id

	var occupied: Dictionary = {}
	_place_ladders(chunk, cfg, above_chunk, occupied, floor_id)
	site_spawner.populate(chunk, occupied)
	monster_spawner.populate(chunk, occupied)
	return chunk


## Standard 4-5 rule CA on an apron grid; initial state is pure per-tile hash.
func _automata(layer: int, cx: int, cy: int, cfg: Dictionary) -> PackedByteArray:
	var fill := float(cfg.get("fill", 0.45))
	var iterations := int(cfg.get("iterations", 4))
	var size := WG.CHUNK_TILES + APRON * 2
	var grid := PackedByteArray()
	grid.resize(size * size)
	for y: int in size:
		for x: int in size:
			var gx := cx * WG.CHUNK_TILES + x - APRON
			var gy := cy * WG.CHUNK_TILES + y - APRON
			grid[y * size + x] = 1 if WG.r01(world_seed, gx, gy, 140 + layer * 9) < fill else 0
	var next := PackedByteArray()
	next.resize(size * size)
	for pass_i: int in iterations:
		for y: int in size:
			for x: int in size:
				var walls := 0
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx := x + dx
						var ny := y + dy
						if nx < 0 or ny < 0 or nx >= size or ny >= size:
							walls += 1  # outside the apron counts as wall
						elif grid[ny * size + nx] == 1:
							walls += 1
				next[y * size + x] = 1 if walls >= 5 else 0
		var tmp := grid
		grid = next
		next = tmp
	return grid


func _place_ladders(chunk: RefCounted, cfg: Dictionary, above_chunk: RefCounted, occupied: Dictionary, floor_id: int) -> void:
	# Ladders up, mirrored from the layer above.
	var up_tiles: Array = []
	if above_chunk != null:
		for poi: Dictionary in above_chunk.pois:
			for part: Dictionary in poi["parts"]:
				var kind := str(part["kind"])
				if (chunk.layer == -1 and kind == "cave") or kind == "ladder_down":
					up_tiles.append(Vector2i(int(part["tx"]), int(part["ty"])))
	for t: Vector2i in up_tiles:
		_carve_room(chunk, t, floor_id)
		_carve_corridor(chunk, t, Vector2i(WG.CHUNK_TILES / 2, WG.CHUNK_TILES / 2), floor_id)
		occupied[Chunk.idx(t.x, t.y)] = true
		chunk.pois.append({
			"type": "ladder_up", "label": "Ladder Up", "anchor": t,
			"safe": false, "respawn": false, "minimap": "e0e0e0",
			"cluster_sites": 0, "cluster_skill": "",
			"parts": [{"kind": "ladder_up", "label": "Climb up", "tx": t.x, "ty": t.y, "target_layer": chunk.layer + 1}],
		})

	# Ladder down, if a deeper layer is registered.
	var below: int = chunk.layer - 1
	if reg.cave_layers.has(below) \
			and WG.r01(world_seed, chunk.cx, chunk.cy, 150 + chunk.layer) < LADDER_DOWN_CHANCE:
		var t := Vector2i(
			3 + WG.hash_i(world_seed, chunk.cx, chunk.cy, 151) % (WG.CHUNK_TILES - 6),
			3 + WG.hash_i(world_seed, chunk.cx, chunk.cy, 152) % (WG.CHUNK_TILES - 6))
		_carve_room(chunk, t, floor_id)
		_carve_corridor(chunk, t, Vector2i(WG.CHUNK_TILES / 2, WG.CHUNK_TILES / 2), floor_id)
		occupied[Chunk.idx(t.x, t.y)] = true
		chunk.pois.append({
			"type": "ladder_down", "label": "Ladder Down", "anchor": t,
			"safe": false, "respawn": false, "minimap": "a0a0a0",
			"cluster_sites": 0, "cluster_skill": "",
			"parts": [{"kind": "ladder_down", "label": "Climb down", "tx": t.x, "ty": t.y, "target_layer": below}],
		})


func _carve_room(chunk: RefCounted, center: Vector2i, floor_id: int) -> void:
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if absi(dx) + absi(dy) > 3:
				continue
			var x := clampi(center.x + dx, 0, WG.CHUNK_TILES - 1)
			var y := clampi(center.y + dy, 0, WG.CHUNK_TILES - 1)
			chunk.tiles[Chunk.idx(x, y)] = floor_id


## L-shaped 2-wide corridor so ladders always join the chunk's cavern body.
func _carve_corridor(chunk: RefCounted, from: Vector2i, to: Vector2i, floor_id: int) -> void:
	var x := from.x
	while x != to.x:
		x += signi(to.x - x)
		chunk.tiles[Chunk.idx(x, from.y)] = floor_id
		chunk.tiles[Chunk.idx(x, clampi(from.y + 1, 0, WG.CHUNK_TILES - 1))] = floor_id
	var y := from.y
	while y != to.y:
		y += signi(to.y - y)
		chunk.tiles[Chunk.idx(to.x, y)] = floor_id
		chunk.tiles[Chunk.idx(clampi(to.x + 1, 0, WG.CHUNK_TILES - 1), y)] = floor_id
