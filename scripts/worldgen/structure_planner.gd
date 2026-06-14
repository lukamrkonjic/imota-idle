extends RefCounted
class_name StructurePlanner
## Discovers multi-chunk megastructures (sprawling cities from WorldSpec anchors,
## ruined-city fields from a deterministic cell grid), builds a StructurePlan for
## each (cached), and stamps each chunk's slice during generation — tiles painted
## into chunk.tiles and entity parts pushed into chunk.structures. Everything is
## a pure function of (center, seed), so chunks agree no matter the load order.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const StructurePlan := preload("res://scripts/worldgen/structure_plan.gd")

var reg: RefCounted
var classifier: RefCounted
var world_seed: int = 0

var _cities: Array = []
var _ruin_cfg: Dictionary = {}
var _plans: Dictionary = {}
var _is_water: Callable


func setup(p_reg: RefCounted, p_classifier: RefCounted, p_seed: int) -> void:
	reg = p_reg
	classifier = p_classifier
	world_seed = p_seed
	_plans.clear()
	_is_water = func(gtx: int, gty: int) -> bool:
		var f: Vector3 = classifier.fields(float(gtx), float(gty))
		var b: int = classifier.biome_idx(float(gtx), float(gty))
		var tid: int = classifier.tile_at(float(gtx), float(gty), f, b)
		return tid >= 0 and tid < reg.tile_order.size() and bool(reg.tile_def(tid).get("water", false))
	_discover_cities()
	_ruin_cfg = reg.pois.get("ancient_ruins", {}).get("mega", {})


func _discover_cities() -> void:
	_cities.clear()
	if not reg.spec.active:
		return
	for a: Dictionary in reg.spec.anchors:
		var def: Dictionary = reg.pois.get(str(a["poi"]), {})
		var mega: Dictionary = def.get("mega", {})
		if str(mega.get("kind", "")) != "city":
			continue
		var ch := Vector2i(a["chunk"])
		_cities.append({
			"kind": "city",
			"center": Vector2i(ch.x * WG.CHUNK_TILES + WG.CHUNK_TILES / 2,
				ch.y * WG.CHUNK_TILES + WG.CHUNK_TILES / 2),
			"radius": int(mega.get("radius", 40)),
			"seed": world_seed ^ (str(a["id"]).hash() & 0x7FFFFFFF),
			"poi": str(a["poi"]),
			"def": mega,
		})


## Megastructure specs whose footprint can reach chunk (cx,cy).
func _specs_near(cx: int, cy: int) -> Array:
	var out: Array = []
	var cc := Vector2(cx * WG.CHUNK_TILES + 8, cy * WG.CHUNK_TILES + 8)
	for c: Dictionary in _cities:
		if cc.distance_to(Vector2(c["center"])) <= float(int(c["radius"]) + WG.CHUNK_TILES * 2):
			out.append(c)
	out.append_array(_ruin_specs_near(cx, cy))
	return out


func _ruin_specs_near(cx: int, cy: int) -> Array:
	var out: Array = []
	if _ruin_cfg.is_empty():
		return out
	var cell: int = int(_ruin_cfg.get("cellChunks", 6))
	var radius: int = int(_ruin_cfg.get("radius", 32))
	var chance: float = float(_ruin_cfg.get("chance", 0.55))
	var min_dist: int = int(_ruin_cfg.get("minDist", 40))
	var biomes: Array = _ruin_cfg.get("biomes", [])
	var salt: int = "ancient_ruins".hash() & 0xFFFFFF
	var reach: int = int(ceil(float(radius) / float(WG.CHUNK_TILES))) + 1
	var span: int = maxi(cell - 2, 1)
	var z0x := floori(float(cx - reach) / float(cell)) - 1
	var z1x := floori(float(cx + reach) / float(cell)) + 1
	var z0y := floori(float(cy - reach) / float(cell)) - 1
	var z1y := floori(float(cy + reach) / float(cell)) + 1
	for zy: int in range(z0y, z1y + 1):
		for zx: int in range(z0x, z1x + 1):
			if WG.r01(world_seed, zx, zy, salt + 2) >= chance:
				continue
			var jx: int = 1 + WG.hash_i(world_seed, zx, zy, salt) % span if cell > 2 else 0
			var jy: int = 1 + WG.hash_i(world_seed, zx, zy, salt + 1) % span if cell > 2 else 0
			var mcx := zx * cell + jx
			var mcy := zy * cell + jy
			var center := Vector2i(mcx * WG.CHUNK_TILES + 8, mcy * WG.CHUNK_TILES + 8)
			if Vector2(center).length() < float(min_dist):
				continue
			if not _biome_ok(center, biomes):
				continue
			out.append({
				"kind": "ruins", "center": center, "radius": radius,
				"seed": world_seed ^ (WG.hash_i(world_seed, mcx, mcy, salt + 5)),
				"poi": "ancient_ruins", "def": _ruin_cfg,
			})
	return out


## Nearest megastructure centre of a kind, computed straight from the
## deterministic plan (no chunk generation needed) — for admin teleport / minimap.
func nearest_center(from_tile: Vector2i, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	if kind == "city":
		for c: Dictionary in _cities:
			var d := Vector2(from_tile).distance_to(Vector2(c["center"]))
			if d < best_d:
				best_d = d
				best = {"center": c["center"], "label": reg.pois.get(str(c["poi"]), {}).get("label", "City")}
		return best
	if kind == "ruins" and not _ruin_cfg.is_empty():
		var cell: int = int(_ruin_cfg.get("cellChunks", 7))
		var chance: float = float(_ruin_cfg.get("chance", 0.55))
		var min_dist: int = int(_ruin_cfg.get("minDist", 40))
		var biomes: Array = _ruin_cfg.get("biomes", [])
		var salt: int = "ancient_ruins".hash() & 0xFFFFFF
		var span: int = maxi(cell - 2, 1)
		var z0 := Vector2i(floori(float(from_tile.x) / float(cell * WG.CHUNK_TILES)),
			floori(float(from_tile.y) / float(cell * WG.CHUNK_TILES)))
		for dzy: int in range(-22, 23):
			for dzx: int in range(-22, 23):
				var zx := z0.x + dzx
				var zy := z0.y + dzy
				if WG.r01(world_seed, zx, zy, salt + 2) >= chance:
					continue
				var jx: int = 1 + WG.hash_i(world_seed, zx, zy, salt) % span if cell > 2 else 0
				var jy: int = 1 + WG.hash_i(world_seed, zx, zy, salt + 1) % span if cell > 2 else 0
				var center := Vector2i((zx * cell + jx) * WG.CHUNK_TILES + 8, (zy * cell + jy) * WG.CHUNK_TILES + 8)
				if Vector2(center).length() < float(min_dist) or not _biome_ok(center, biomes):
					continue
				var d := Vector2(from_tile).distance_to(Vector2(center))
				if d < best_d:
					best_d = d
					best = {"center": center, "label": "Ancient Ruins"}
	return best


func _biome_ok(center: Vector2i, biomes: Array) -> bool:
	var idx: int = classifier.map_gen.parent_idx_at(float(center.x), float(center.y))
	if idx < 0 or idx >= reg.biomes.size():
		return false
	var id := str(reg.biomes[idx]["id"])
	if id in ["ocean", "beach", "volcanic"]:
		return false
	if biomes.is_empty():
		return true
	return biomes.has(id)


func _get_plan(spec: Dictionary) -> StructurePlan:
	var c: Vector2i = spec["center"]
	var key := "%s:%d:%d" % [str(spec["kind"]), c.x, c.y]
	if _plans.has(key):
		return _plans[key]
	var p := StructurePlan.new()
	p.build(str(spec["kind"]), c, int(spec["radius"]), int(spec["seed"]), spec["def"], _is_water)
	_plans[key] = p
	return p


## Stamp every overlapping structure's slice into this chunk (tiles + parts).
func stamp(chunk: RefCounted, occupied: Dictionary) -> void:
	if chunk.layer != 0:
		return
	for spec: Dictionary in _specs_near(chunk.cx, chunk.cy):
		_apply(chunk, _get_plan(spec), spec, occupied)


func _apply(chunk: RefCounted, plan: StructurePlan, spec: Dictionary, occupied: Dictionary) -> void:
	var bx: int = chunk.cx * WG.CHUNK_TILES
	var by: int = chunk.cy * WG.CHUNK_TILES
	var city := plan.is_city()
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			var tid := plan.tile_id_at(bx + lx, by + ly, reg)
			if tid < 0:
				continue
			var cur: Dictionary = reg.tile_def(chunk.tile_id(lx, ly))
			if bool(cur.get("water", false)) or bool(cur.get("hazard", false)):
				continue
			chunk.tiles[Chunk.idx(lx, ly)] = tid
			if city:
				occupied[Chunk.idx(lx, ly)] = true
	for p: Dictionary in plan.parts_in_chunk(chunk.cx, chunk.cy):
		var lx: int = int(p["tx"]) - bx
		var ly: int = int(p["ty"]) - by
		if lx < 0 or ly < 0 or lx >= WG.CHUNK_TILES or ly >= WG.CHUNK_TILES:
			continue
		# Never place a structure on water or hazard — keep buildings on land.
		var under: Dictionary = reg.tile_def(chunk.tile_id(lx, ly))
		if bool(under.get("water", false)) or bool(under.get("hazard", false)):
			continue
		var local := p.duplicate()
		local["tx"] = lx
		local["ty"] = ly
		if str(p.get("kind", "")) == "enemy" and bool(p.get("boss", false)) and not p.has("boss_name"):
			_assign_boss(local, plan)
		occupied[Chunk.idx(lx, ly)] = true
		chunk.structures.append(local)
	# city chunks are safe; centre chunk also carries a findable POI marker
	var cc := Vector2(bx + 8, by + 8)
	var inside: bool = cc.distance_to(Vector2(plan.center)) <= float(plan.radius)
	if city and inside:
		chunk.safe = true
	if _chunk_holds(chunk, plan.center):
		_add_marker_poi(chunk, plan, spec)


func _chunk_holds(chunk: RefCounted, tile: Vector2i) -> bool:
	var bx: int = chunk.cx * WG.CHUNK_TILES
	var by: int = chunk.cy * WG.CHUNK_TILES
	return tile.x >= bx and tile.y >= by and tile.x < bx + WG.CHUNK_TILES and tile.y < by + WG.CHUNK_TILES


## A part-less POI at the centre so find_nearest_poi / minimap / admin still work.
func _add_marker_poi(chunk: RefCounted, plan: StructurePlan, spec: Dictionary) -> void:
	var def: Dictionary = reg.pois.get(str(spec["poi"]), {})
	chunk.pois.append({
		"type": str(spec["poi"]),
		"label": str(def.get("label", "")),
		"anchor": Vector2i(plan.center.x - chunk.cx * WG.CHUNK_TILES, plan.center.y - chunk.cy * WG.CHUNK_TILES),
		"safe": plan.is_city(),
		"respawn": false,
		"minimap": str(def.get("minimapColor", "ffffff")),
		"cluster_sites": 0, "cluster_skill": "",
		"parts": [],
	})


func _assign_boss(part: Dictionary, plan: StructurePlan) -> void:
	if reg.boss_list.is_empty():
		part.erase("boss")
		return
	var idx: int = WG.hash_i(plan.seed, plan.center.x, plan.center.y, 909) % reg.boss_list.size()
	var boss: Dictionary = reg.boss_list[idx]
	part["boss_name"] = str(boss["name"])
	part["label"] = str(boss["name"])
