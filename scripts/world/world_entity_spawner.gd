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
	var tile: Dictionary = WorldGen.reg.tile_def(chunk.tile_id(tx, ty))
	var tname: String = WorldGen.reg.tile_order[chunk.tile_id(tx, ty)]
	if chunk.elev.size() > 0 and chunk.elev[ty * WG.CHUNK_TILES + tx] > 0:
		return
	if bool(tile.get("water", false)) or not bool(tile.get("walkable", true)):
		return
	if tname in ["sand", "sand_dune", "shallow", "rock", "cobble", "snow", "gravel", "savanna_grass", "jungle_loam", "boreal_moss", "badland_clay"]:
		return
	var r := WG.r01(seed, chunk.cx * 251 + tx, chunk.cy * 263 + ty, 201)
	var biome_id := _tile_biome_id(chunk, tx, ty)
	var b_idx: int = chunk.biome_at(tx, ty)
	var parent_id: String = WorldGen.reg.parent_biome_id(b_idx) if b_idx != 255 else biome_id
	var near_water := _tile_near_water(chunk, tx, ty)
	var chance := _decor_chance(biome_id, parent_id, near_water)
	if r > chance:
		return
	var d: Node2D = WorldDecor.new()
	d.variant = int(WG.hash_i(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 202) % 1000)
	var kroll := WG.r01(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 205)
	d.kind = _pick_decor_kind(biome_id, near_water, kroll)
	var jitter := Vector2(
		(WG.r01(seed, tx, ty, 203) - 0.5) * WG.TILE * 0.28,
		(WG.r01(seed, tx, ty, 204) - 0.5) * WG.TILE * 0.14)
	d.position = chunk.tile_world(tx, ty) + jitter
	d.visible = false
	container.add_child(d)
	world._decor_nodes.append(d)


func _spawn_water_decor(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0:
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
	e.variant = absi(hash(str(s["node"]) + chunk.key())) % 1000
	if e.kind == "tree":
		e.display_size = TreeArt.tree_size(int(s["level"]), e.label)
		e.click_radius = maxf(e.display_size * 0.5, 30.0)
	else:
		e.display_size = IsoSprites.node_size(e.kind)
		e.click_radius = maxf(e.display_size * 0.8, 26.0)
	e.position = chunk.tile_world(int(s["tx"]), int(s["ty"]))
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
	e.display_size = 54.0 if kind == "tent" else 40.0
	e.click_radius = 38.0
	if part.has("color"):
		e.tent_color = Color.from_string("#" + str(part["color"]), e.tent_color)
		e.glow_color = e.tent_color
	match kind:
		"enemy":
			var boss_name := str(part.get("boss_name", ""))
			var enemy: Dictionary = DataRegistry.get_enemy(boss_name)
			if enemy.is_empty():
				e.queue_free()
				return
			e.enemy_shape = IsoSprites.enemy_shape(boss_name)
			e.is_boss = true
			e.display_size = 50.0
			e.tier_color = tier_color(int(enemy["level"]))
			e.label = boss_name
			e.sub_label = "Lvl %d BOSS" % int(enemy["level"])
			e.action = {"type": "enemy", "name": boss_name, "aggressive": false, "level": int(enemy["level"])}
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
		"bridge":
			pass  # purely decorative deck over the canal
		"fountain":
			e.display_size = 40.0
			e.click_radius = 30.0
			e.action = {"type": "landmark", "label": e.label if not e.label.is_empty() else "Fountain"}
		_:
			if part.has("station"):
				e.action = {"type": "station", "station": str(part["station"]), "label": e.label}
			elif part.has("hook"):
				e.action = {"type": "hook", "message": str(part.get("hookMessage", "Coming soon."))}
			else:
				e.action = {"type": "landmark", "label": e.label}
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
