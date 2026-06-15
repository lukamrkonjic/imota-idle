extends Node
## Procedural world service. Owns the data registries, the seeded generator,
## the chunk-data cache, and world persistence; answers world queries for the
## scene and the HUD (nearest site/station/POI, zones, spawn point) and ticks
## gather-site respawns. Chunk data is generated deterministically from the
## seed on first request and cached; only player-made changes are saved
## (see world_store.gd).

const WG := preload("res://scripts/worldgen/wg.gd")
const WorldRegistry := preload("res://scripts/worldgen/world_registry.gd")
const WorldGenerator := preload("res://scripts/worldgen/world_generator.gd")
const WorldStore := preload("res://scripts/worldgen/world_store.gd")
const BakedWorldStore := preload("res://scripts/worldgen/baked_world_store.gd")
const FishingHelper := preload("res://scripts/world/fishing_helper.gd")

## Sample seed: plains at the origin camp ("Green Timberland", level 1),
## forest to the north, a river and lake to the east of camp, and level ~6-11
## zones within 3 chunks (verified by tools/world_debug.gd --scan).
const DEFAULT_SEED := 7

var reg: RefCounted = WorldRegistry.new()
var generator: RefCounted = WorldGenerator.new()
var store: RefCounted = WorldStore.new()
var baked: RefCounted = BakedWorldStore.new()

var chunks: Dictionary = {}  # WG.key(layer,cx,cy) -> Chunk

var _respawn_timer := 0.0
var _station_poi_types: Dictionary = {}  # station id -> [poi type]


func _ready() -> void:
	reg.load_all()
	store.load_file(DEFAULT_SEED)
	generator.setup(reg, store.world_seed)
	baked.setup(reg)
	if reg.spec.active and reg.spec.finite:
		baked.load_world(reg.spec.id)
	_index_station_pois()


## Re-seed and forget all cached chunk data (debug tools and tests).
func reset(new_seed: int) -> void:
	chunks.clear()
	store.world_seed = new_seed
	store.obelisks = {}
	store.depleted = {}
	store.visited_zones = {}
	store.chunk_snapshots = {}
	generator.setup(reg, new_seed)


func save_world() -> void:
	store.save_file()


# ------------------------------------------------------------ chunk cache ----

func get_chunk(layer: int, cx: int, cy: int) -> RefCounted:
	var key := WG.key(layer, cx, cy)
	if chunks.has(key):
		return chunks[key]
	var chunk: RefCounted = null
	# In a finite authored world the BAKED data is authoritative — never let an
	# old explored-chunk snapshot from a previous play session shadow it, or
	# re-baked/editor-saved worlds wouldn't show up. (Player-made changes like
	# depletions/obelisks are applied separately below.) Snapshots still serve
	# caves and the non-finite procedural world.
	var baked_here: bool = layer == 0 and reg.spec.active and reg.spec.finite \
		and reg.spec.in_bounds(cx, cy) and not reg.spec.is_procedural_zone(cx, cy) and baked.has(cx, cy)
	if not baked_here:
		chunk = store.load_chunk_snapshot(layer, cx, cy)
	if chunk == null:
		chunk = _source_chunk(layer, cx, cy)
	store.apply_to_chunk(chunk)
	generator.placement_grid.register_chunk_pois(chunk)
	chunks[key] = chunk
	return chunk


## Where a fresh chunk's data comes from. For the surface of a finite authored
## world: open ocean beyond bounds, the generator for procedural zones, the
## pre-baked fixed data otherwise. Caves and non-finite worlds keep generating.
func _source_chunk(layer: int, cx: int, cy: int) -> RefCounted:
	if layer == 0 and reg.spec.active and reg.spec.finite:
		if not reg.spec.in_bounds(cx, cy):
			return baked.ocean_chunk(cx, cy)
		# The overworld is a FIXED, fully-baked map: NEVER procedurally generate a
		# surface chunk at runtime (that was the walking-stutter source — a single
		# uncached chunk could cost 100ms+). Generation is an editor/bake-time tool
		# only. An in-bounds chunk that isn't baked shows as ocean — a loud "re-bake
		# the world" signal — instead of freezing the frame.
		if baked.has(cx, cy):
			return baked.build_chunk(cx, cy)
		push_warning("world_gen: unbaked in-bounds chunk %d:%d — re-run tools/world_bake.tscn" % [cx, cy])
		return baked.ocean_chunk(cx, cy)
	var above: RefCounted = null
	if layer < 0:
		above = get_chunk(layer + 1, cx, cy)
	return generator.generate(layer, cx, cy, above)


## Persist explored chunk data so generator changes cannot rewrite visited land.
func snapshot_chunk_if_needed(chunk: RefCounted) -> void:
	# Baked finite-world surface chunks are fixed/authored — don't snapshot them
	# (the snapshot would later shadow a re-bake/editor save). Only procedural
	# zones, caves and the non-finite world get explored-chunk snapshots.
	if chunk.layer == 0 and reg.spec.active and reg.spec.finite \
			and reg.spec.in_bounds(chunk.cx, chunk.cy) \
			and not reg.spec.is_procedural_zone(chunk.cx, chunk.cy) and baked.has(chunk.cx, chunk.cy):
		return
	var key: String = chunk.key()
	if store.has_chunk_snapshot(key):
		return
	store.save_chunk_snapshot(chunk)


func chunk_at(layer: int, world_pos: Vector2) -> RefCounted:
	var c := WG.world_to_chunk(world_pos)
	return get_chunk(layer, c.x, c.y)


func zone_at(world_pos: Vector2) -> Dictionary:
	return generator.zone_map.zone_at_world(world_pos)


func biome_id_at(world_pos: Vector2) -> String:
	var t := WG.world_to_tile(world_pos)
	var idx: int = generator.classifier.biome_idx(float(t.x), float(t.y))
	return str(reg.biomes[idx]["id"])


func tile_debug_at(world_pos: Vector2, layer: int = 0) -> Dictionary:
	# Resolve the raised tile actually drawn under the cursor (not the flat tile in
	# front of a mountain), so the overlay reports the block you're pointing at.
	var t: Vector2i = tile_at_screen(world_pos, layer)
	var c: Vector2i = WG.tile_to_chunk(t)
	var chunk: RefCounted = get_chunk(layer, c.x, c.y)
	var lx: int = t.x - c.x * WG.CHUNK_TILES
	var ly: int = t.y - c.y * WG.CHUNK_TILES
	if lx < 0 or ly < 0 or lx >= WG.CHUNK_TILES or ly >= WG.CHUNK_TILES:
		return {}
	var eff_idx: int = chunk.biome_at(lx, ly)
	var parent_idx: int = chunk.parent_biome_at(lx, ly)
	var sub_idx: int = chunk.sub_biome_at(lx, ly)
	var tid: int = chunk.tile_id(lx, ly)
	var td: Dictionary = reg.tile_def(tid) if tid >= 0 and tid < reg.tile_order.size() else {}
	var zone: Dictionary = zone_at(WG.tile_to_world(t.x, t.y))
	var eff_id: String = "" if eff_idx == 255 else str(reg.biomes[eff_idx]["id"])
	var parent_id: String = "" if parent_idx == 255 else str(reg.biomes[parent_idx]["id"])
	var sub_id: String = ""
	if sub_idx != 255:
		sub_id = str(reg.biomes[sub_idx]["id"])
	return {
		"tile": t,
		"tile_name": reg.tile_order[tid] if tid >= 0 and tid < reg.tile_order.size() else "?",
		"parent_biome": parent_id,
		"sub_biome": sub_id,
		"effective_biome": eff_id,
		"walkable": bool(td.get("walkable", false)),
		"water": bool(td.get("water", false)),
		"zone": str(zone.get("name", "")),
		"zone_lvl": int(zone.get("req", 1)),
		"elev": _tile_elev(layer, t),
	}


func player_entry_level() -> int:
	return generator.zone_map.player_entry_level()


func _tile_def_at_world(pos: Vector2, layer: int = 0) -> Dictionary:
	var t := WG.world_to_tile(pos)
	# Infinite (non-finite) surface: keep the cheap noise probe (no chunk gen).
	if layer == 0 and not (reg.spec.active and reg.spec.finite):
		return surface_tile_def_at(t.x, t.y)
	# Finite authored world (and all caves): read the ACTUAL chunk tile, so the
	# baked roads / rivers / coastline drive walkability — not the raw noise.
	var c := WG.tile_to_chunk(t)
	var chunk: RefCounted = get_chunk(layer, c.x, c.y)
	var lx := t.x - c.x * WG.CHUNK_TILES
	var ly := t.y - c.y * WG.CHUNK_TILES
	if lx < 0 or ly < 0 or lx >= WG.CHUNK_TILES or ly >= WG.CHUNK_TILES:
		return {}
	return reg.tile_def(chunk.tile_id(lx, ly))


## Deterministic surface tile without generating a chunk (Minecraft-style probe).
func surface_tile_id(gtx: int, gty: int) -> int:
	var f: Vector3 = generator.classifier.fields(float(gtx), float(gty))
	var b_idx: int = generator.classifier.biome_idx(float(gtx), float(gty))
	return generator.classifier.tile_at(float(gtx), float(gty), f, b_idx)


func surface_tile_def_at(gtx: int, gty: int) -> Dictionary:
	var tid: int = surface_tile_id(gtx, gty)
	if tid < 0 or tid >= reg.tile_order.size():
		return {}
	return reg.tile_def(tid)


func surface_biome_matches(gtx: int, gty: int, biome_id: String) -> bool:
	var idx: int = generator.classifier.biome_idx(float(gtx), float(gty))
	if idx < 0 or idx >= reg.biomes.size():
		return false
	var eff_id: String = str(reg.biomes[idx]["id"])
	var par_id: String = reg.parent_biome_id(idx)
	return eff_id == biome_id or par_id == biome_id


## True when the tile under a world position is land the player can stand on.
func is_walkable_world(pos: Vector2, layer: int = 0) -> bool:
	var td: Dictionary = _tile_def_at_world(pos, layer)
	if td.is_empty():
		return false
	if not bool(td.get("walkable", false)) or bool(td.get("water", false)) or bool(td.get("hazard", false)):
		return false
	# Solid structures block their footprint in the finite authored world.
	if layer == 0 and reg.spec.active and reg.spec.finite:
		var t := WG.world_to_tile(pos)
		var c := WG.tile_to_chunk(t)
		var chunk: RefCounted = get_chunk(0, c.x, c.y)
		var lx: int = t.x - c.x * WG.CHUNK_TILES
		var ly: int = t.y - c.y * WG.CHUNK_TILES
		if chunk.elev.size() > 0 and chunk.elev[ly * WG.CHUNK_TILES + lx] > WG.MAX_REACHABLE_ELEV:
			return false
		if chunk.is_blocked(lx, ly):
			return false
	return true


## Terraced terrain elevation (in steps) under a world position — 0 on flat
## ground/water, rising over mountains. Drives the player's visual height so it
## reads clearly when he is up on a slope versus down in a valley.
func elevation_at(pos: Vector2, layer: int = 0) -> int:
	if layer != 0:
		return 0
	var t := WG.world_to_tile(pos)
	var c := WG.tile_to_chunk(t)
	var chunk: RefCounted = get_chunk(0, c.x, c.y)
	if chunk == null or chunk.elev.size() == 0:
		return 0
	var lx: int = t.x - c.x * WG.CHUNK_TILES
	var ly: int = t.y - c.y * WG.CHUNK_TILES
	return chunk.elev[ly * WG.CHUNK_TILES + lx]


## Elevation (steps) of a specific surface tile.
func _tile_elev(layer: int, t: Vector2i) -> int:
	if layer != 0:
		return 0
	var c := WG.tile_to_chunk(t)
	var chunk: RefCounted = get_chunk(layer, c.x, c.y)
	if chunk == null or chunk.elev.size() == 0:
		return 0
	var lx: int = t.x - c.x * WG.CHUNK_TILES
	var ly: int = t.y - c.y * WG.CHUNK_TILES
	if lx < 0 or ly < 0 or lx >= WG.CHUNK_TILES or ly >= WG.CHUNK_TILES:
		return 0
	return chunk.elev[ly * WG.CHUNK_TILES + lx]


## Tile whose RAISED top is drawn under a world/cursor position. Plain
## world_to_tile() is a flat projection, so hovering or clicking a drawn mountain
## resolves to the low tile in FRONT of it (reading elevation 0). A raised tile's
## top is shifted up by elev*ELEV_STEP_PX, so we add that back and test elevations
## tallest-first, returning the topmost tile actually drawn under the cursor.
const ELEV_PICK_MAX := 42   # generator ELEV_MAX_STEPS — tallest possible peak

func tile_at_screen(world_pos: Vector2, layer: int = 0) -> Vector2i:
	if layer == 0:
		for e: int in range(ELEV_PICK_MAX, 0, -1):
			var t := WG.world_to_tile(world_pos + Vector2(0.0, float(e) * WG.ELEV_STEP_PX))
			if _tile_elev(layer, t) == e:
				return t
	return WG.world_to_tile(world_pos)


func is_water_world(pos: Vector2, layer: int = 0) -> bool:
	var td: Dictionary = _tile_def_at_world(pos, layer)
	return not td.is_empty() and bool(td.get("water", false))


## Safe admin landing: walkable dry ground at elevation 0 on the surface.
func is_admin_teleport_floor(pos: Vector2, layer: int = 0) -> bool:
	if not is_walkable_world(pos, layer):
		return false
	if layer == 0 and elevation_at(pos, layer) != 0:
		return false
	return true


## Dry flat land with no water on the four cardinals. Avoids river/lake shore spawns.
func is_spawn_floor(pos: Vector2, layer: int = 0) -> bool:
	if not is_admin_teleport_floor(pos, layer):
		return false
	var t := WG.world_to_tile(pos)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if is_water_world(WG.tile_to_world(t.x + d.x, t.y + d.y), layer):
			return false
	return true


## Spiral outward from preferred until a walkable tile center is found.
func nearest_walkable_world(preferred: Vector2, layer: int = 0, max_rings: int = 16) -> Vector2:
	var found: Vector2 = _spiral_tile(preferred, layer, max_rings, is_walkable_world)
	return found if found != Vector2.INF else _fallback_home_spawn(layer)


## Admin/world teleports should never land on mountain terraces. Search wider
## than click walking because biome/place jumps can target cliffs or peaks.
func nearest_admin_teleport_world(preferred: Vector2, layer: int = 0, max_rings: int = 128) -> Vector2:
	var found: Vector2 = _spiral_tile(preferred, layer, max_rings, is_admin_teleport_floor)
	return found if found != Vector2.INF else _fallback_home_spawn(layer)


func nearest_spawn_floor(preferred: Vector2, layer: int = 0, max_rings: int = 24) -> Vector2:
	var found: Vector2 = _spiral_tile(preferred, layer, max_rings, is_spawn_floor)
	return found if found != Vector2.INF else _fallback_home_spawn(layer)


func _spiral_tile(preferred: Vector2, layer: int, max_rings: int, ok: Callable) -> Vector2:
	var center := WG.world_to_tile(preferred)
	for ring: int in range(0, max_rings + 1):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if ring > 0 and maxi(absi(dx), absi(dy)) != ring:
					continue
				var pos: Vector2 = WG.tile_to_world(center.x + dx, center.y + dy)
				if ok.call(pos, layer):
					return pos
	return Vector2.INF


func _fallback_home_spawn(layer: int = 0) -> Vector2:
	var home: RefCounted = get_chunk(layer, 0, 0)
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			var pos: Vector2 = home.tile_world(tx, ty)
			if is_spawn_floor(pos, layer):
				return pos
	push_warning("WorldGen: no spawn floor in home chunk — using chunk centre")
	return WG.tile_to_world(WG.CHUNK_TILES / 2, WG.CHUNK_TILES / 2)


## Where a fresh (or dead) player appears. An authored spawn from the baked
## finite world wins (snapped to the nearest walkable tile); otherwise fall back
## to dry flat ground beside the home camp.
func spawn_position() -> Vector2:
	if baked.loaded and baked.has_spawn:
		var pos: Vector2 = WG.tile_to_world(baked.spawn_tile.x, baked.spawn_tile.y)
		if is_spawn_floor(pos):
			return pos
		return nearest_spawn_floor(pos, 0, 32)
	var home: RefCounted = get_chunk(0, 0, 0)
	for poi: Dictionary in home.pois:
		if not bool(poi.get("respawn", false)):
			continue
		var a: Vector2i = poi["anchor"]
		var candidates: Array[Vector2] = [
			home.tile_world(a.x, a.y + 2),
			home.tile_world(a.x, a.y + 1),
			home.tile_world(a.x - 2, a.y + 1),
			home.tile_world(a.x + 2, a.y + 1),
			home.tile_world(a.x, a.y),
		]
		for part: Dictionary in poi.get("parts", []):
			var dx: int = int(part.get("dx", 0))
			var dy: int = int(part.get("dy", 0))
			candidates.append(home.tile_world(a.x + dx, a.y + dy + 1))
		for pref: Vector2 in candidates:
			var pos: Vector2 = nearest_spawn_floor(pref)
			if is_spawn_floor(pos):
				return pos
		return nearest_spawn_floor(home.tile_world(a.x, a.y), 0, 32)
	return _fallback_home_spawn()


# ------------------------------------------------------- site depletion ----

func deplete_site(chunk: RefCounted, site_index: int) -> void:
	var site: Dictionary = chunk.sites[site_index]
	site["available"] = false
	site["respawn_at"] = Time.get_unix_time_from_system() + float(site["respawn_sec"])
	store.record_depletion(chunk.key(), site_index, float(site["respawn_at"]))
	EventBus.site_depleted.emit(chunk.key(), site_index)


func _process(delta: float) -> void:
	_respawn_timer += delta
	if _respawn_timer < 1.0:
		return
	_respawn_timer = 0.0
	var now := Time.get_unix_time_from_system()
	for chunk_key: String in store.depleted.keys():
		for idx_str: String in Dictionary(store.depleted[chunk_key]).keys():
			if float(store.depleted[chunk_key][idx_str]) > now:
				continue
			var idx := int(idx_str)
			store.clear_depletion(chunk_key, idx)
			if chunks.has(chunk_key):
				var chunk: RefCounted = chunks[chunk_key]
				if idx < chunk.sites.size():
					chunk.sites[idx]["available"] = true
					chunk.sites[idx]["remaining"] = int(chunk.sites[idx]["resources"])
			EventBus.site_respawned.emit(chunk_key, idx)


# --------------------------------------------------------------- queries ----

## Nearest available gather site for an exact node, ring-searching outward
## from `from_pos`. Distant rings are prefiltered by zone band and a single
## biome sample per chunk, so misses stay cheap. Returns {} or
## {chunk, site_index, pos}.
func find_nearest_site(layer: int, from_pos: Vector2, skill: String, node_name: String,
		max_rings: int = WG.SITE_SEARCH_RADIUS) -> Dictionary:
	var entry := _node_entry(skill, node_name)
	if entry.is_empty():
		return {}
	var center := WG.world_to_chunk(from_pos)
	var best: Dictionary = {}
	var best_d := INF
	for ring: int in range(0, max_rings + 1):
		if not best.is_empty() and (float(ring) - 1.0) * WG.CHUNK_SIZE > best_d:
			break
		for coords: Vector2i in _ring(center, ring):
			if not _site_prefilter(layer, coords, entry, ring):
				continue
			var chunk: RefCounted = get_chunk(layer, coords.x, coords.y)
			if layer == 0 and int(chunk.zone.get("req", 1)) > player_entry_level():
				continue
			for i: int in chunk.sites.size():
				var s: Dictionary = chunk.sites[i]
				if str(s["skill"]) != skill or str(s["node"]) != node_name or not bool(s["available"]):
					continue
				var pos: Vector2 = chunk.tile_world(int(s["tx"]), int(s["ty"]))
				if skill == "fishing":
					pos = FishingHelper.best_stand(from_pos, chunk, s)
				var d := from_pos.distance_to(pos)
				if d < best_d:
					best_d = d
					best = {"chunk": chunk, "site_index": i, "pos": pos}
	return best


func _node_entry(skill: String, node_name: String) -> Dictionary:
	for e: Dictionary in reg.node_table.get(skill, []):
		if str(e["name"]) == node_name:
			return e
	return {}


func _site_prefilter(layer: int, coords: Vector2i, entry: Dictionary, ring: int) -> bool:
	var key := WG.key(layer, coords.x, coords.y)
	if chunks.has(key) or ring <= 3:
		return true  # cached or close: just look
	# Zone band: the node only spawns where its level fits the zone.
	var zone: Dictionary = generator.zone_map.zone_for_chunk(coords.x, coords.y)
	var req := int(zone["req"]) + (int(reg.cave_layers.get(layer, {}).get("oreLevelBonus", 0)) if layer < 0 else 0)
	var lvl := int(entry["level"])
	if lvl > req + 10 or lvl < roundi(float(req) * 0.3) - 1:
		return false
	if layer != 0:
		return Array(entry["cave_layers"]).has(layer)
	# One biome sample at the chunk center.
	var center_tile := (Vector2(coords) + Vector2(0.5, 0.5)) * WG.CHUNK_TILES
	var b_idx: int = generator.classifier.biome_idx(center_tile.x, center_tile.y)
	return Array(entry["biomes"]).has(str(reg.biomes[b_idx]["id"]))


## Nearest POI part with the given station id (bank, anvil, campfire...).
## Returns {} or {chunk, poi, part, pos}.
func find_nearest_station(layer: int, from_pos: Vector2, station: String,
		max_rings: int = WG.SITE_SEARCH_RADIUS) -> Dictionary:
	return _find_part(layer, from_pos, max_rings,
		_station_poi_types.get(station, []),
		func(part: Dictionary) -> bool: return str(part.get("station", "")) == station)


## Nearest multi-chunk megastructure ("city" or "ruins") centre, resolved from
## the deterministic planner without generating chunks. Returns {pos,name,distance}.
func find_nearest_structure(from_pos: Vector2, kind: String) -> Dictionary:
	var t: Vector2i = WG.world_to_tile(from_pos)
	var hit: Dictionary = generator.structure_planner.nearest_center(t, kind)
	if hit.is_empty():
		return {}
	var c: Vector2i = hit["center"]
	var pos: Vector2 = WG.tile_to_world(c.x, c.y)
	return {"pos": pos, "name": str(hit.get("label", "")), "distance": from_pos.distance_to(pos)}


## Nearest POI of one of the given types (e.g. respawn campsite).
func find_nearest_poi(layer: int, from_pos: Vector2, types: Array,
		max_rings: int = WG.SITE_SEARCH_RADIUS) -> Dictionary:
	return _find_part(layer, from_pos, max_rings, types,
		func(_part: Dictionary) -> bool: return true)


func _find_part(layer: int, from_pos: Vector2, max_rings: int, poi_types: Array,
		part_ok: Callable) -> Dictionary:
	if poi_types.is_empty():
		return {}
	var center := WG.world_to_chunk(from_pos)
	var best: Dictionary = {}
	var best_d := INF
	for ring: int in range(0, max_rings + 1):
		if not best.is_empty() and (float(ring) - 1.0) * WG.CHUNK_SIZE > best_d:
			break
		for coords: Vector2i in _ring(center, ring):
			var key := WG.key(layer, coords.x, coords.y)
			if not chunks.has(key):
				# Cheap predicate: would any wanted POI type even roll here?
				var zone: Dictionary = generator.zone_map.zone_for_chunk(coords.x, coords.y)
				var any := false
				for t: String in poi_types:
					if generator.poi_placer.wants_chunk(coords.x, coords.y, zone, t) \
							or (coords == Vector2i.ZERO and t == "campsite"):
						any = true
						break
				if not any:
					continue
			var chunk: RefCounted = get_chunk(layer, coords.x, coords.y)
			for poi: Dictionary in chunk.pois:
				if not poi_types.has(str(poi["type"])):
					continue
				var hit_parts: Array = poi["parts"]
				if hit_parts.is_empty():
					var anc: Vector2i = poi.get("anchor", Vector2i.ZERO)
					hit_parts = [{"tx": anc.x, "ty": anc.y}]
				for part: Dictionary in hit_parts:
					if not part_ok.call(part):
						continue
					var pos: Vector2 = chunk.tile_world(int(part["tx"]), int(part["ty"]))
					var d := from_pos.distance_to(pos)
					if d < best_d:
						best_d = d
						best = {"chunk": chunk, "poi": poi, "part": part, "pos": pos}
	return best


func _ring(center: Vector2i, ring: int) -> Array:
	var out: Array = []
	if ring == 0:
		out.append(center)
		return out
	for d: int in range(-ring, ring + 1):
		out.append(center + Vector2i(d, -ring))
		out.append(center + Vector2i(d, ring))
		if absi(d) != ring:
			out.append(center + Vector2i(-ring, d))
			out.append(center + Vector2i(ring, d))
	return out


func _index_station_pois() -> void:
	for type: String in reg.pois:
		for part: Dictionary in reg.pois[type].get("parts", []):
			if part.has("station"):
				var st := str(part["station"])
				if not _station_poi_types.has(st):
					_station_poi_types[st] = []
				if not _station_poi_types[st].has(type):
					_station_poi_types[st].append(type)


# -------------------------------------------------------------- obelisks ----

func unlock_obelisk(chunk: RefCounted, poi: Dictionary) -> bool:
	var name := "%s (%s)" % [str(poi["label"]), str(chunk.zone.get("name", "?"))]
	var a: Vector2i = poi["anchor"]
	var pos: Vector2 = chunk.tile_world(a.x, a.y)
	if store.unlock_obelisk(chunk.key(), name, pos):
		EventBus.obelisk_unlocked.emit(name)
		return true
	return false


func unlocked_obelisks() -> Array:
	var out: Array = []
	for key: String in store.obelisks:
		var o: Dictionary = store.obelisks[key]
		out.append({"name": str(o["name"]), "pos": Vector2(float(o["x"]), float(o["y"]))})
	return out


# ----------------------------------------------------------- admin / debug ----

## Every surface biome from data/world/biomes.json (new biomes appear automatically).
func list_surface_biomes() -> Array:
	var out: Array = []
	for b: Dictionary in reg.biomes:
		if bool(b.get("isSubBiome", false)):
			continue
		out.append({
			"id": str(b["id"]),
			"name": str(b.get("name", b["id"])),
			"priority": int(b.get("priority", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))
	return out


## Sub-biome / micro-biome entries from biomes.json.
func list_sub_biomes() -> Array:
	var out: Array = []
	for b: Dictionary in reg.biomes:
		if not bool(b.get("isSubBiome", false)):
			continue
		out.append({
			"id": str(b["id"]),
			"name": str(b.get("name", b["id"])),
			"parent": str(b.get("parentBiome", "")),
			"priority": int(b.get("priority", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))
	return out


## Nearest walkable (or water for ocean) tile in the given biome. Uses lightweight
## biome/tile probes — no chunk generation (safe for long-range admin teleports).
func find_nearest_biome(from_pos: Vector2, biome_id: String, max_chunk_rings: int = 128) -> Dictionary:
	if biome_id.is_empty():
		return {}
	var center := WG.world_to_chunk(from_pos)
	var best_d := INF
	var best_pos := Vector2.INF
	for ring: int in range(0, max_chunk_rings + 1):
		if best_d < INF and (float(ring) - 1.0) * WG.CHUNK_SIZE > best_d:
			break
		for coords: Vector2i in _ring(center, ring):
			var base_tx: int = coords.x * WG.CHUNK_TILES
			var base_ty: int = coords.y * WG.CHUNK_TILES
			var mid_tx: int = base_tx + WG.CHUNK_TILES / 2
			var mid_ty: int = base_ty + WG.CHUNK_TILES / 2
			if not surface_biome_matches(mid_tx, mid_ty, biome_id):
				continue
			for ty: int in range(WG.CHUNK_TILES):
				for tx: int in range(WG.CHUNK_TILES):
					var gtx: int = base_tx + tx
					var gty: int = base_ty + ty
					if not surface_biome_matches(gtx, gty, biome_id):
						continue
					var pos: Vector2 = WG.tile_to_world(gtx, gty)
					if not _admin_biome_tile_ok(biome_id, gtx, gty):
						continue
					var d := from_pos.distance_to(pos)
					if d < best_d:
						best_d = d
						best_pos = pos
	if best_pos == Vector2.INF:
		return {}
	var b: Dictionary = reg.biome_by_id(biome_id)
	return {
		"pos": best_pos,
		"biome_id": biome_id,
		"name": str(b.get("name", biome_id)),
		"distance": best_d,
	}


func _admin_biome_tile_ok(biome_id: String, gtx: int, gty: int) -> bool:
	var td: Dictionary = surface_tile_def_at(gtx, gty)
	if td.is_empty():
		return false
	if biome_id == "ocean" or biome_id == "swamp":
		return bool(td.get("water", false)) or (
			bool(td.get("walkable", false))
			and not bool(td.get("water", false))
			and not bool(td.get("hazard", false))
		)
	return bool(td.get("walkable", false)) and not bool(td.get("water", false)) and not bool(td.get("hazard", false))
