extends RefCounted
class_name WorldEntitySpawner
## Converts chunk data into WorldEntity nodes and ground decor.

const WG := preload("res://scripts/worldgen/wg.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")
const WorldDecor := preload("res://scripts/world/world_decor.gd")
const WorldWaterDecor := preload("res://scripts/world/world_water_decor.gd")
const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const TerrainStyle := preload("res://scripts/render/terrain_style.gd")
const FishingHelper := preload("res://scripts/world/fishing_helper.gd")

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


# Per-coroutine slice and shared frame budget for streaming a chunk's contents
# in. Several chunk spawn coroutines can overlap while walking, so each one is
# kept tiny and they all share a soft per-frame cap.
const SPAWN_BUDGET_USEC := 450
const STREAM_FRAME_BUDGET_USEC := 1200
var _stream_budget_frame := -1
var _stream_budget_used_usec := 0


func on_chunk_loaded(chunk: RefCounted, immediate: bool = false) -> void:
	var container := Node2D.new()
	container.name = "E_" + chunk.key().replace(":", "_").replace("-", "m")
	container.y_sort_enabled = true
	container.modulate.a = 0.0
	world._entities_layer.add_child(container)
	world._chunk_containers[chunk.key()] = container

	# Initial fill (and anything that must be ready this frame) spawns
	# synchronously; chunks streamed in as the player walks are spread across a
	# few frames so a chunk crossing never spikes the frame. The container stays
	# invisible until finalize, then is shown instantly (no fade) — and it loads
	# off camera (ACTIVE_RADIUS), so it is never seen popping in half-built.
	if immediate:
		_spawn_chunk_contents(chunk, container)
		_finalize_chunk(chunk, container)
	else:
		_spawn_chunk_streamed(chunk, container)


func _spawn_chunk_contents(chunk: RefCounted, container: Node2D) -> void:
	_spawn_ground_decor(chunk, container)
	_spawn_canopy(chunk, container)
	_spawn_water_decor(chunk, container)
	for i: int in chunk.sites.size():
		_spawn_site(chunk, i, container)
	_spawn_fishing_schools(chunk, container)
	for poi: Dictionary in chunk.pois:
		for part: Dictionary in poi["parts"]:
			_spawn_poi_part(chunk, poi, part, container)
	for part: Dictionary in chunk.structures:
		_spawn_poi_part(chunk, {}, part, container)
	for m: Dictionary in chunk.monsters:
		_spawn_monster(chunk, m, container)


# Time-sliced version of _spawn_chunk_contents: yields a frame whenever the
# per-frame budget is exhausted, and bails out cleanly if the chunk gets
# unloaded mid-spawn (player walked back out of range).
func _spawn_chunk_streamed(chunk: RefCounted, container: Node2D) -> void:
	var key: String = chunk.key()
	var started := _begin_stream_slice()

	if chunk.layer == 0:
		var seed: int = WorldGen.store.world_seed
		for ty: int in range(WG.CHUNK_TILES):
			for tx: int in range(WG.CHUNK_TILES):
				_spawn_ground_decor_tile(chunk, container, seed, tx, ty)
			if _stream_budget_exhausted(started):
				_finish_stream_slice(started)
				await world.get_tree().process_frame
				if not _still_loading(key, container):
					return
				started = _begin_stream_slice()

		# Canopy -> choppable woodcutting sites (cheap dict appends, guarded once-per-chunk); the
		# site loop below spawns the actual tree entities under the streaming budget.
		_spawn_canopy(chunk, container)

		var reg: RefCounted = WorldGen.reg
		for ty: int in range(WG.CHUNK_TILES):
			for tx: int in range(WG.CHUNK_TILES):
				_spawn_water_decor_tile(chunk, container, seed, reg, tx, ty)
			if _stream_budget_exhausted(started):
				_finish_stream_slice(started)
				await world.get_tree().process_frame
				if not _still_loading(key, container):
					return
				started = _begin_stream_slice()

		for s: Dictionary in chunk.sites:
			_spawn_fishing_school(chunk, s, container)
			if _stream_budget_exhausted(started):
				_finish_stream_slice(started)
				await world.get_tree().process_frame
				if not _still_loading(key, container):
					return
				started = _begin_stream_slice()

	for i: int in chunk.sites.size():
		_spawn_site(chunk, i, container)
		if _stream_budget_exhausted(started):
			_finish_stream_slice(started)
			await world.get_tree().process_frame
			if not _still_loading(key, container):
				return
			started = _begin_stream_slice()
	for poi: Dictionary in chunk.pois:
		for part: Dictionary in poi["parts"]:
			_spawn_poi_part(chunk, poi, part, container)
			if _stream_budget_exhausted(started):
				_finish_stream_slice(started)
				await world.get_tree().process_frame
				if not _still_loading(key, container):
					return
				started = _begin_stream_slice()
	for part: Dictionary in chunk.structures:
		_spawn_poi_part(chunk, {}, part, container)
		if _stream_budget_exhausted(started):
			_finish_stream_slice(started)
			await world.get_tree().process_frame
			if not _still_loading(key, container):
				return
			started = _begin_stream_slice()
	for m: Dictionary in chunk.monsters:
		_spawn_monster(chunk, m, container)
		if _stream_budget_exhausted(started):
			_finish_stream_slice(started)
			await world.get_tree().process_frame
			if not _still_loading(key, container):
				return
			started = _begin_stream_slice()

	if not _still_loading(key, container):
		_finish_stream_slice(started)
		return
	_finish_stream_slice(started)
	_finalize_chunk(chunk, container)


## The chunk is still the live container for its key (not unloaded/replaced
## while we were yielding). Guards every resume point in the streamed spawn.
func _still_loading(key: String, container: Variant) -> bool:
	return is_instance_valid(container) and world._chunk_containers.get(key) == container


func _begin_stream_slice() -> int:
	_reset_stream_budget_if_needed()
	return Time.get_ticks_usec()


func _stream_budget_exhausted(started: int) -> bool:
	_reset_stream_budget_if_needed()
	var elapsed := maxi(0, Time.get_ticks_usec() - started)
	return elapsed >= SPAWN_BUDGET_USEC or _stream_budget_used_usec + elapsed >= STREAM_FRAME_BUDGET_USEC


func _finish_stream_slice(started: int) -> void:
	_reset_stream_budget_if_needed()
	_stream_budget_used_usec += maxi(0, Time.get_ticks_usec() - started)


func _reset_stream_budget_if_needed() -> void:
	var frame := Engine.get_process_frames()
	if frame == _stream_budget_frame:
		return
	_stream_budget_frame = frame
	_stream_budget_used_usec = 0


func _finalize_chunk(_chunk: RefCounted, container: Node2D) -> void:
	# Entity lookups choose by distance at click/hover time, so finalization does
	# not need to re-sort the whole world list for every streamed chunk.
	world._path_ctrl.mark_path_dirty()
	# Reveal the chunk only once it is fully built (it was kept invisible during
	# the streamed spawn) — no fade, so props simply appear, never pop in one by
	# one. It is loaded outside the view, so the reveal happens off screen.
	container.modulate.a = 1.0


func sort_entities_for_targeting() -> void:
	var pp: Vector2 = world.player.position
	var keyed: Array = []
	keyed.resize(world.entities.size())
	for i: int in world.entities.size():
		var e: Node2D = world.entities[i]
		keyed[i] = [e, _entity_locked_for_sort(e), e.position.distance_squared_to(pp)]
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return not a[1]
		return a[2] < b[2])
	for i: int in keyed.size():
		world.entities[i] = keyed[i][0]


func _entity_locked_for_sort(e: Node2D) -> bool:
	var action: Dictionary = e.get("action")
	if action.has("chunk_key") and WorldGen.chunks.has(str(action["chunk_key"])):
		var chunk: RefCounted = WorldGen.chunks[str(action["chunk_key"])]
		return int(chunk.zone.get("req", 1)) > WorldGen.player_entry_level()
	var zone: Dictionary = WorldGen.zone_at(e.position)
	return int(zone.get("req", 1)) > WorldGen.player_entry_level()


func on_chunk_unloaded(chunk: RefCounted) -> void:
	var key: String = chunk.key()
	var container: Node2D = world._chunk_containers.get(key)
	if container != null:
		# Collect this chunk's children once, then filter each tracking array in a
		# single pass — far cheaper than a linear Array.erase() per child per array.
		var kids: Dictionary = {}
		for e: Node2D in container.get_children():
			kids[e] = true
			if e == world.hovered_entity:
				world.hovered_entity = null
			if e == world.combat_target_entity:
				world.combat_target_entity = null
		if not kids.is_empty():
			var keep := func(e: Node2D) -> bool: return not kids.has(e)
			world.entities = world.entities.filter(keep)
			world._decor_nodes = world._decor_nodes.filter(keep)
			world._water_decor_nodes = world._water_decor_nodes.filter(keep)
			world._roofed_entities = world._roofed_entities.filter(keep)
			world._activity_ctrl.forget_entities(kids)  # drop despawned mobs from AI state
		container.queue_free()
	world._chunk_containers.erase(key)
	for sk: String in world._site_entities.keys():
		if sk.begins_with(key + "#"):
			world._site_entities.erase(sk)
	world._path_ctrl.mark_path_dirty()


func _spawn_ground_decor(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0:
		return
	var seed: int = WorldGen.store.world_seed
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			_spawn_ground_decor_tile(chunk, container, seed, tx, ty)


func _spawn_ground_decor_tile(chunk: RefCounted, container: Node2D, seed: int, tx: int, ty: int) -> void:
	# Decorative ground flora scatters even on "blank" authored worlds — only harvestable
	# nodes (gather sites/ores) are hand-placed; the cosmetic clutter stays procedural.
	var tile: Dictionary = WorldGen.reg.tile_def(chunk.tile_id(tx, ty))
	var tname: String = WorldGen.reg.tile_order[chunk.tile_id(tx, ty)]
	var elev := int(chunk.elev[ty * WG.CHUNK_TILES + tx]) if chunk.elev.size() > 0 else 0
	if bool(tile.get("water", false)) or (elev <= 0 and not bool(tile.get("walkable", true))):
		return
	# Roads + paved/bridge tiles stay clear of ground clutter so a drawn road reads clean.
	# Erasing a road reverts the tile, so the procedural clutter returns automatically.
	if elev <= 0 and (TerrainStyle.is_path(tname) or tname in ["sand", "sand_dune", "shallow", "rock", "snow", "plank_floor", "plaza", "savanna_grass", "jungle_loam", "boreal_moss"]):
		return
	var r := WG.r01(seed, chunk.cx * 251 + tx, chunk.cy * 263 + ty, 201)
	var biome_id := _tile_biome_id(chunk, tx, ty)
	var b_idx: int = chunk.biome_at(tx, ty)
	var parent_id: String = WorldGen.reg.parent_biome_id(b_idx) if b_idx != 255 else biome_id
	var near_water := _tile_near_water(chunk, tx, ty)
	var chance := _decor_chance(biome_id, parent_id, near_water)
	var gx: int = int(chunk.cx) * WG.CHUNK_TILES + tx
	var gy: int = int(chunk.cy) * WG.CHUNK_TILES + ty
	var flowery := elev <= 0 and _biome_flower_weight(biome_id) >= 0.4
	if elev > 0:
		# Medium-scale alpine clusters: sparse open slopes alternating with denser
		# ledges/outcrop pockets. The low-frequency cell gate prevents even scatter.
		var cluster := WG.r01(seed, floori(float(gx) / 5.0), floori(float(gy) / 5.0), 231)
		chance = (0.08 if cluster > 0.5 else 0.018)
	if r > chance:
		return
	var d: Node2D = WorldDecor.new()
	d.variant = int(WG.hash_i(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 202) % 1000)
	var kroll := WG.r01(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 205)
	d.kind = _pick_alpine_decor(elev, kroll, d.variant) if elev > 0 else _pick_decor_kind(biome_id, near_water, kroll)
	if flowery and d.kind.begins_with("flower"):
		# Flowers bloom only inside clump patches; between patches the tile falls back to wild
		# grass, so the meadow floor stays full instead of bare around the flower clusters. The
		# colour leans one hue per patch, and a per-instance shape suffix varies the silhouette.
		var patch := WG.flower_clump(seed, gx, gy)   # ~0 in gaps .. ~1.9 in patch centres
		if WG.r01(seed, gx * 13 + 5, gy * 13 + 9, 273) > patch:
			d.kind = "wild_grass"
		else:
			d.kind = WG.flower_color(seed, gx, gy) + _flower_shape(seed, gx, gy, d.variant)
	var jitter := Vector2(
		(WG.r01(seed, tx, ty, 203) - 0.5) * WG.TILE * 0.28,
		(WG.r01(seed, tx, ty, 204) - 0.5) * WG.TILE * 0.14)
	d.position = chunk.tile_world(tx, ty) + jitter
	d.visible = false
	container.add_child(d)
	world._decor_nodes.append(d)


## Ambient forest layer: scatter a biome's signature trees (firs in boreal, palms in
## jungle, saguaros in desert, …) as batched canopy decor. Density + species come from
## the biome's `canopy` block. Runtime + deterministic like ground decor, so tuning it
## needs no rebake. Trees skip water/raised rock/path and self-space on a coarse grid so
## a forest reads as clumps and clearings rather than one tree per tile.
## Turn the biome's ambient canopy into choppable woodcutting SITES (once per chunk — the chunk
## is cached, so guard against re-appending). The site loop then renders + makes them choppable.
func _spawn_canopy(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0 or chunk.canopy_sites_built:
		return
	chunk.canopy_sites_built = true
	_load_tree_species()
	var seed: int = WorldGen.store.world_seed
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			_spawn_canopy_tile(chunk, container, seed, tx, ty)


## Editor hook: drop this chunk's PROCEDURAL canopy (ambient trees) and reset the build flag, so a
## biome repaint regrows the NEW biome's trees on the next load. Authored/hand-placed gather sites
## (which have no "ambient" tag) are left untouched.
func clear_ambient_canopy(chunk: RefCounted) -> void:
	for i: int in range(chunk.sites.size() - 1, -1, -1):
		if bool((chunk.sites[i] as Dictionary).get("ambient", false)):
			chunk.sites.remove_at(i)
	chunk.canopy_sites_built = false


## species (canopy_* render kind) -> woodcutting node name -> level, from tree_species.json +
## the woodcutting node table. Loaded once.
var _species_node: Dictionary = {}
var _wc_level: Dictionary = {}
func _load_tree_species() -> void:
	if not _species_node.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/tree_species.json"))
	if parsed is Dictionary:
		_species_node = (parsed as Dictionary).get("speciesToNode", {})
	for e: Dictionary in WorldGen.reg.node_table.get("woodcutting", []):
		_wc_level[str(e.get("node", ""))] = int(e.get("level", 1))


func _spawn_canopy_tile(chunk: RefCounted, container: Node2D, seed: int, tx: int, ty: int) -> void:
	# Decorative trees scatter even on "blank" authored worlds (cosmetic clutter is
	# procedural; only harvestable rare trees/ores are placed by hand, with care).
	if chunk.tree_cuts.has(ty * WG.CHUNK_TILES + tx):
		return  # the world editor's eraser cleared the ambient tree on this tile
	var elev := int(chunk.elev[ty * WG.CHUNK_TILES + tx]) if chunk.elev.size() > 0 else 0
	if elev > 0:
		return  # no ambient forest on raised/impassable rock (alpine has its own pass)
	var tile: Dictionary = WorldGen.reg.tile_def(chunk.tile_id(tx, ty))
	if bool(tile.get("water", false)) or not bool(tile.get("walkable", true)) or bool(tile.get("hazard", false)):
		return
	var tname: String = WorldGen.reg.tile_order[chunk.tile_id(tx, ty)]
	if TerrainStyle.is_path(tname) or tname in ["plaza", "plank_floor", "building_wall"]:
		return  # keep roads / paths / settlement floors / bridges clear of trees
	var biome_id := _tile_biome_id(chunk, tx, ty)
	var cfg: Dictionary = WorldGen.reg.canopy(biome_id)
	var density := float(cfg.get("density", 0.0))
	if density <= 0.0:
		return
	# OSRS-style clumping: a smooth low-frequency cluster field carves the even per-tile
	# scatter into dense stands separated by open clearings; CANOPY_THIN keeps the woods
	# sparse overall (clearings -> ~0 trees, stand centres -> the biome's density).
	var gx: int = chunk.cx * WG.CHUNK_TILES + tx
	var gy: int = chunk.cy * WG.CHUNK_TILES + ty
	var eff := density * WG.canopy_density_mul(seed, gx, gy)
	var r := WG.r01(seed, chunk.cx * 271 + tx, chunk.cy * 283 + ty, 211)
	if r > eff:
		return
	var kinds: Array = cfg.get("kinds", [])
	if kinds.is_empty():
		return
	var kroll := WG.r01(seed, chunk.cx * 131 + tx, chunk.cy * 137 + ty, 213)
	var total := 0.0
	for entry: Dictionary in kinds:
		total += float(entry.get("weight", 1.0))
	var target := kroll * total
	var picked := str(kinds.back().get("kind", "canopy_broadleaf"))
	for entry: Dictionary in kinds:
		target -= float(entry.get("weight", 1.0))
		if target <= 0.0:
			picked = str(entry.get("kind", "canopy_broadleaf"))
			break
	# Register this canopy tree as a CHOPPABLE woodcutting site, its species mapped to the OSRS
	# table (data/world/tree_species.json). The site loop renders it (keeping the visual species)
	# and makes it interactable; no separate decor node, so there's exactly one tree per tile.
	var node_name := str(_species_node.get(picked, "Regular Tree"))
	var lvl := int(_wc_level.get(node_name, 1))
	# Depletion mapped from OSRS: a regular tree always falls after 1 log; higher tiers give more
	# (they last longer), respawning a touch slower the rarer they are.
	var logs := 1 if node_name == "Regular Tree" else clampi(2 + lvl / 15, 2, 12)
	chunk.sites.append({
		"skill": "woodcutting", "node": node_name, "level": lvl,
		"kind": "tree", "tree_species": picked, "tx": tx, "ty": ty,
		"resources": logs, "remaining": logs, "respawn_sec": _wc_respawn(node_name),
		"available": true, "respawn_at": 0.0, "ambient": true,
	})


## Stump respawn time (seconds) per tree, mapped from OSRS Forestry depletion timers. Higher-tier
## trees take much longer to regrow; tweak here to rebalance the woodcutting economy.
func _wc_respawn(node: String) -> float:
	match node:
		"Regular Tree": return 8.0
		"Oak Tree": return 27.0
		"Willow Tree", "Teak Tree": return 30.0
		"Maple Tree", "Acadia Tree": return 60.0
		"Eucalyptus Tree": return 84.0
		"Yew Tree": return 114.0
		"Elven Tree": return 180.0
		"Red Maple Tree": return 200.0
		"Magic Tree": return 234.0
		"Rubra Tree": return 264.0
		"Lunarwood Tree": return 300.0
	return 30.0


func _pick_alpine_decor(elev: int, roll: float, variant: int) -> String:
	# Mostly hardy grass + lichen with the OCCASIONAL boulder. Alpine shelves already read as
	# rock through the terrain itself, so decor stays sparse — not a field of boulders.
	if elev < 28 and roll < 0.08 and variant % 3 != 0:
		return "alpine_pine"
	if roll < 0.08:
		return "alpine_boulder" + str(variant % 3)   # ~8% boulders (was 42%)
	if roll < 0.13:
		return "pebble"
	if roll < 0.66 and elev < 32:
		return "grass"
	return "lichen"


func _spawn_water_decor(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0 or WorldGen.reg.spec.is_blank():
		return
	var seed: int = WorldGen.store.world_seed
	var reg: RefCounted = WorldGen.reg
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			_spawn_water_decor_tile(chunk, container, seed, reg, tx, ty)


func _spawn_water_decor_tile(chunk: RefCounted, container: Node2D, seed: int, reg: RefCounted, tx: int, ty: int) -> void:
	var tid: int = chunk.tile_id(tx, ty)
	if tid < 0 or tid >= reg.tile_order.size():
		return
	var tname: String = reg.tile_order[tid]
	var td: Dictionary = reg.tile_def(tid)
	if not bool(td.get("water", false)):
		return
	if tname == "deep_water":
		return
	var water_n := _water_neighbors(chunk, tx, ty)
	if water_n < 1:
		return
	var r := WG.r01(seed, chunk.cx * 311 + tx, chunk.cy * 317 + ty, 401)
	if tname in ["shallow", "water"] and r < 0.075:
		var d: Node2D = WorldWaterDecor.new()
		d.kind = "lily"
		d.variant = int(WG.hash_i(seed, chunk.cx * 113 + tx, chunk.cy * 127 + ty, 402) % 10000)
		d.position = chunk.tile_world(tx, ty)
		d.visible = false
		container.add_child(d)
		world._water_decor_nodes.append(d)


func _spawn_fishing_schools(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0:
		return
	for s: Dictionary in chunk.sites:
		_spawn_fishing_school(chunk, s, container)


func _spawn_fishing_school(chunk: RefCounted, s: Dictionary, container: Node2D) -> void:
	if str(s.get("skill", "")) != "fishing":
		return
	var water := FishingHelper.water_tile(chunk, s)
	if water.x < 0:
		return
	var seed: int = WorldGen.store.world_seed
	var d: Node2D = WorldWaterDecor.new()
	d.kind = "fish_school"
	d.variant = int(WG.hash_i(seed, water.x, water.y, chunk.cx * 401 + chunk.cy) % 10000)
	d.position = chunk.tile_world(water.x, water.y)
	d.visible = false
	container.add_child(d)
	world._water_decor_nodes.append(d)


func _water_neighbors(chunk: RefCounted, tx: int, ty: int) -> int:
	var count := 0
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if _is_water_tile(chunk, tx + ox, ty + oy):
				count += 1
	return count


func _is_water_tile(chunk: RefCounted, tx: int, ty: int) -> bool:
	if tx >= 0 and ty >= 0 and tx < WG.CHUNK_TILES and ty < WG.CHUNK_TILES:
		return bool(WorldGen.reg.tile_def(chunk.tile_id(tx, ty)).get("water", false))
	var gtx: int = chunk.cx * WG.CHUNK_TILES + tx
	var gty: int = chunk.cy * WG.CHUNK_TILES + ty
	var tid: int = WorldGen.surface_tile_id(gtx, gty)
	if tid < 0 or tid >= WorldGen.reg.tile_order.size():
		return false
	return bool(WorldGen.reg.tile_def(tid).get("water", false))


func _tile_biome_id(chunk: RefCounted, tx: int, ty: int) -> String:
	var b_idx: int = chunk.biome_at(tx, ty)
	return "" if b_idx == 255 else str(WorldGen.reg.biomes[b_idx]["id"])


func _tile_near_water(chunk: RefCounted, tx: int, ty: int) -> bool:
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx := tx + ox
			var ny := ty + oy
			if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
				continue
			if bool(WorldGen.reg.tile_def(chunk.tile_id(nx, ny)).get("water", false)):
				return true
	return false


func _decor_chance(biome_id: String, _parent_id: String, near_water: bool) -> float:
	var cfg: Dictionary = WorldGen.reg.ground_decor(biome_id)
	if cfg.is_empty():
		return 0.025
	if near_water:
		return float(cfg.get("waterDensity", cfg.get("density", 0.03)))
	return float(cfg.get("density", 0.03))


## Total weight of flower kinds in a biome's ground decor, cached per biome. Used to
## decide whether a tile is in a "flowery" biome (>= 0.4) and so gets meadow clumping.
var _flower_w_cache: Dictionary = {}
func _biome_flower_weight(biome_id: String) -> float:
	if _flower_w_cache.has(biome_id):
		return _flower_w_cache[biome_id]
	var w := 0.0
	for entry: Dictionary in WorldGen.reg.ground_decor(biome_id).get("kinds", []):
		if str(entry.get("kind", "")).begins_with("flower"):
			w += float(entry.get("weight", 0.0))
	_flower_w_cache[biome_id] = w
	return w


## Flower silhouette suffix. The shape is driven mostly by a coarse spatial ZONE (so tall spikes
## cluster tightly together rather than scattering), with a little per-instance variation inside
## each zone so a cluster isn't perfectly uniform.
func _flower_shape(seed: int, gx: int, gy: int, variant: int) -> String:
	var zone := WG.flower_shape_zone(seed, gx, gy)
	var v := variant % 6
	if zone < 0.46:
		return "_daisy" if v == 0 else "_spike"      # tall-spike clusters (the signature)
	elif zone < 0.72:
		return "_bell" if v == 0 else "_cluster"     # low rounded bunches
	elif zone < 0.88:
		return "_cluster" if v >= 4 else "_daisy"    # flat daisies
	return "_spike" if v >= 4 else "_bell"           # nodding bells


func _pick_decor_kind(biome_id: String, near_water: bool, roll: float) -> String:
	var cfg: Dictionary = WorldGen.reg.ground_decor(biome_id)
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


func _spawn_site(chunk: RefCounted, i: int, container: Node2D) -> void:
	var s: Dictionary = chunk.sites[i]
	var e: Node2D = WorldEntity.new()
	e.kind = str(s["kind"])
	e.label = str(s["node"])
	e.sub_label = "Lvl %d" % int(s["level"])
	e.tier_color = tier_color(int(s["level"]))
	e.variant = absi(hash(str(s["node"]) + chunk.key() + str(s.get("tx")) + ":" + str(s.get("ty")))) % 1000
	if e.kind == "tree":
		e.display_size = TreeArt.tree_size(int(s["level"]), e.label)
		# Hover/click area tight to the CANOPY (its big visible mass) — the screen pick also lifts
		# onto the canopy (world_input_controller), so the area hugs the tree, not a wide ground ring.
		e.click_radius = maxf(e.display_size * 0.5, 30.0)
		if s.has("tree_species"):
			e.prop_kind = str(s["tree_species"])   # keep its ambient canopy look (fir/oak/…)
	else:
		e.display_size = IsoSprites.node_size(e.kind)
		e.click_radius = maxf(e.display_size * 0.8, 26.0)
	e.position = chunk.tile_world(int(s["tx"]), int(s["ty"]))
	if e.kind == "tree" and s.has("tree_species"):
		# A little off-grid jitter so the converted canopy reads as a natural forest, not rows.
		var jx := WG.r01(WorldGen.store.world_seed, int(s["tx"]), int(s["ty"]), 215) - 0.5
		var jy := WG.r01(WorldGen.store.world_seed, int(s["tx"]), int(s["ty"]), 216) - 0.5
		e.position += Vector2(jx * WG.TILE * 0.5, jy * WG.TILE * 0.3)
	e.dimmed = not bool(s["available"])
	e.action = {
		"type": "gather", "skill": str(s["skill"]), "node": str(s["node"]),
		"chunk_key": chunk.key(), "site_index": i,
	}
	container.add_child(e)
	world.entities.append(e)
	world._site_entities["%s#%d" % [chunk.key(), i]] = e


func _spawn_poi_part(chunk: RefCounted, poi: Dictionary, part: Dictionary, container: Node2D) -> void:
	var kind := str(part["kind"])
	if kind == "stall" and str(part.get("label", "")).to_lower().contains("burrow"):
		kind = "burrow"
	var e: Node2D = WorldEntity.new()
	e.kind = kind
	e.label = str(part.get("label", ""))
	e.position = chunk.tile_world(int(part["tx"]), int(part["ty"]))
	if part.has("ox"):
		e.position += Vector2(float(part["ox"]), float(part["oy"]))   # free (non-grid) placement offset
	e.display_size = 54.0 if kind == "tent" else 40.0
	e.click_radius = 38.0
	if part.has("yaw"):
		e.yaw = float(part["yaw"])   # editor-placed structures keep their chosen facing
	if part.has("color"):
		e.tent_color = Color.from_string("#" + str(part["color"]), e.tent_color)
		e.glow_color = e.tent_color
	match kind:
		"enemy":
			# A boss (boss_name, pinned/zone-fit) or a named GUARDIAN (enemy_name) that
			# holds a set-piece. Both pull their level/shape from the bestiary.
			var is_boss := not str(part.get("boss_name", "")).is_empty()
			var enemy_name := str(part.get("boss_name", "")) if is_boss else str(part.get("enemy_name", ""))
			var enemy: Dictionary = DataRegistry.get_enemy(enemy_name)
			if enemy.is_empty():
				e.queue_free()
				return
			e.enemy_shape = IsoSprites.enemy_shape(enemy_name)
			e.tier_color = tier_color(int(enemy["level"]))
			e.label = enemy_name
			if is_boss:
				e.is_boss = true
				e.display_size = 50.0
				e.sub_label = "Lvl %d BOSS" % int(enemy["level"])
				e.action = {"type": "enemy", "name": enemy_name, "aggressive": false, "level": int(enemy["level"])}
			else:
				e.display_size = 34.0
				e.click_radius = 26.0
				e.sub_label = "Lvl %d" % int(enemy["level"])
				e.variant = absi(hash(enemy_name + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
				e.action = {"type": "enemy", "name": enemy_name, "aggressive": bool(part.get("aggressive", true)), "level": int(enemy["level"])}
		"cave":
			e.action = {"type": "descend", "target_layer": world.current_layer - 1 if world.current_layer < 0 else -1}
		"ladder_down":
			e.action = {"type": "descend", "target_layer": int(part.get("target_layer", world.current_layer - 1))}
		"ladder_up":
			e.action = {"type": "ascend", "target_layer": int(part.get("target_layer", world.current_layer + 1))}
		"obelisk":
			e.attuned = WorldGen.store.obelisks.has(chunk.key())
			e.action = {"type": "obelisk", "chunk_key": chunk.key()}
		"landmark_tree", "meteor", "mammoth":
			e.display_size = 110.0 if kind == "landmark_tree" else 60.0
			e.click_radius = 48.0
			e.action = {"type": "landmark", "label": e.label}
		"ruin_arch":
			e.variant = absi(hash(kind + chunk.key())) % 1000
			e.display_size = 64.0
			e.click_radius = 44.0
			e.action = {"type": "landmark", "label": e.label}
		"ruin_pillar", "broken_wall", "rubble_pile", "broken_statue":
			# Decorative ruin masonry — seed a per-tile variant for variety and
			# leave the action empty so they aren't clickable interactables.
			e.variant = absi(hash(kind + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
		"house":
			# Decorative townhouse with a fade-on-approach roof (driven by the
			# visual controller); the station entity in front is what's clickable.
			e.variant = absi(hash("house" + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
			if part.has("color"):
				e.roof_color = Color.from_string("#" + str(part["color"]), e.roof_color)
		"building":
			# Large multi-tile hall — display_size carries its footprint in tiles.
			e.display_size = float(part.get("foot", 6))
			e.variant = absi(hash("bld" + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
			if part.has("color"):
				e.roof_color = Color.from_string("#" + str(part["color"]), e.roof_color)
		"mountain":
			# display_size carries the footprint in tiles; impassable (handled by
			# the chunk collision layer) and non-interactable (empty action).
			e.display_size = float(part.get("foot", 2))
			e.mountain_snow = float(part.get("snow", 0.0))
			e.variant = absi(hash("mtn" + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
			# Sit the massif on top of its raised ground so its base meets the
			# terraced terrain instead of floating below it.
			var gtx: int = chunk.cx * WG.CHUNK_TILES + int(part["tx"])
			var gty: int = chunk.cy * WG.CHUNK_TILES + int(part["ty"])
			e.position.y -= float(WorldGen.generator.classifier.elevation_steps(float(gtx), float(gty))) * WG.ELEV_STEP_PX
		"city_wall":
			e.variant = int(part.get("piece", 0))
		"city_prop":
			e.prop_kind = str(part.get("prop", "crate"))
			e.variant = absi(hash(e.prop_kind + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
		"decor":
			# A standalone ground-clutter model (editor-placed). prop carries the decor
			# kind (mushroom/fern/reed/flower/shrub/grass/pebble/…). Not interactable.
			e.prop_kind = str(part.get("prop", "grass"))
			e.display_size = 22.0
			e.click_radius = 0.0
			e.variant = absi(hash("decor" + e.prop_kind + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
		"tree", "rock", "bush", "node":
			# Editor-placed decorative nature (label picks the tree species); varied per
			# tile, not a gather node, so it just stands there as scenery.
			e.variant = absi(hash(kind + str(e.label) + chunk.key() + str(part["tx"]) + ":" + str(part["ty"]))) % 1000
			if kind == "tree":
				e.display_size = 90.0
		"bridge", "bridge_pole":
			# Plank-bridge meshes: an oriented deck segment (deck + planks + side rails) or a support
			# pillar. yaw lays the deck ALONG the path; gx/gy place it at the exact smooth centerline.
			# The span endpoints + t let the renderer keep the deck LEVEL, floating over the water/gap.
			e.yaw = float(part.get("yaw", 0.0))
			e.height_offset = float(part.get("h", 0.0))
			if part.has("gx"):
				e.position = WG.grid_to_iso(Vector2(float(part["gx"]) + 0.5, float(part["gy"]) + 0.5))
			if part.has("t"):
				e.bridge_a = WG.grid_to_iso(Vector2(float(part["ax"]) + 0.5, float(part["ay"]) + 0.5))
				e.bridge_b = WG.grid_to_iso(Vector2(float(part["bx"]) + 0.5, float(part["by"]) + 0.5))
				e.bridge_t = float(part["t"])
		"fence":
			# A dragged fence segment: yaw orients its rails along the path; gx/gy place it on the
			# exact smooth centerline; it rides the terrain height so the run climbs hills.
			e.yaw = float(part.get("yaw", 0.0))
			if part.has("gx"):
				e.position = WG.grid_to_iso(Vector2(float(part["gx"]) + 0.5, float(part["gy"]) + 0.5))
			e.display_size = 30.0
			e.click_radius = 0.0
		"fountain":
			e.display_size = 40.0
			e.click_radius = 30.0
			e.action = {"type": "landmark", "label": e.label if not e.label.is_empty() else "Fountain"}
		"npc":
			var npc_id := str(part.get("npc", ""))
			var npc_def: Dictionary = DataRegistry.npcs.get(npc_id, {})
			e.label = str(npc_def.get("name", e.label))
			e.sub_label = "NPC"
			e.display_size = 44.0
			e.click_radius = 32.0
			e.variant = absi(hash(npc_id)) % 1000
			e.action = {"type": "npc", "npc": npc_id, "label": e.label}
		_:
			if part.has("station"):
				e.action = {"type": "station", "station": str(part["station"]), "label": e.label}
			elif part.has("hook"):
				e.action = {"type": "hook", "message": str(part.get("hookMessage", "Coming soon."))}
			else:
				e.action = {"type": "landmark", "label": e.label}
	# Editor-placed structures pin an explicit variant so the spawned model matches the look
	# previewed by the hover ghost (otherwise the per-tile hash above would pick a different one).
	if part.has("variant"):
		e.variant = int(part["variant"])
	container.add_child(e)
	world.entities.append(e)
	if kind == "house" or kind == "building":
		world._roofed_entities.append(e)


func _spawn_monster(chunk: RefCounted, m: Dictionary, container: Node2D) -> void:
	var name := str(m["name"])
	var e: Node2D = WorldEntity.new()
	e.kind = "enemy"
	e.enemy_shape = IsoSprites.enemy_shape(name)
	e.display_size = 34.0
	e.tier_color = tier_color(int(m["level"]))
	e.label = name
	e.sub_label = "Lvl %d" % int(m["level"])
	e.variant = absi(hash(name + chunk.key())) % 1000
	e.click_radius = 26.0
	e.position = chunk.tile_world(int(m["tx"]), int(m["ty"]))
	e.action = {"type": "enemy", "name": name, "aggressive": bool(m["aggressive"]), "level": int(m["level"])}
	container.add_child(e)
	world.entities.append(e)


static func tier_color(level: int) -> Color:
	var colors: Array[Color] = [
		PixelPalette.pal("dirt_a"), PixelPalette.pal("stone_a"), PixelPalette.pal("grass_b"),
		PixelPalette.pal("water_a"), PixelPalette.pal("outfit_a"), PixelPalette.pal("gold"),
		PixelPalette.pal("dirt_b"), PixelPalette.pal("snow_a"),
	]
	var idx := 0
	for threshold: int in [10, 20, 40, 60, 80, 100, 150]:
		if level >= threshold:
			idx += 1
	return PixelPalette.enrich_entity(colors[idx])
