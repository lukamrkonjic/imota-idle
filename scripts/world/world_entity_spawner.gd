extends RefCounted
class_name WorldEntitySpawner
## Converts chunk data into WorldEntity nodes and ground decor.

const WG := preload("res://scripts/worldgen/wg.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")
const WorldDecor := preload("res://scripts/world/world_decor.gd")
const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func on_chunk_loaded(chunk: RefCounted) -> void:
	var container := Node2D.new()
	container.name = "E_" + chunk.key().replace(":", "_").replace("-", "m")
	container.y_sort_enabled = true
	world._entities_layer.add_child(container)
	world._chunk_containers[chunk.key()] = container

	_spawn_ground_decor(chunk, container)
	for i: int in chunk.sites.size():
		_spawn_site(chunk, i, container)
	for poi: Dictionary in chunk.pois:
		for part: Dictionary in poi["parts"]:
			_spawn_poi_part(chunk, poi, part, container)
	for m: Dictionary in chunk.monsters:
		_spawn_monster(chunk, m, container)
	world.entities.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var la := _entity_locked_for_sort(a)
		var lb := _entity_locked_for_sort(b)
		if la != lb:
			return not la
		return a.position.distance_squared_to(world.player.position) < b.position.distance_squared_to(world.player.position))
	world._path_ctrl.mark_path_dirty()


func on_chunk_unloaded(chunk: RefCounted) -> void:
	var key: String = chunk.key()
	var container: Node2D = world._chunk_containers.get(key)
	if container != null:
		for e: Node2D in container.get_children():
			world.entities.erase(e)
			world._decor_nodes.erase(e)
			if e == world.hovered_entity:
				world.hovered_entity = null
			if e == world.combat_target_entity:
				world.combat_target_entity = null
		container.queue_free()
	world._chunk_containers.erase(key)
	for sk: String in world._site_entities.keys():
		if sk.begins_with(key + "#"):
			world._site_entities.erase(sk)
	world._path_ctrl.mark_path_dirty()


func _entity_locked_for_sort(e: Node2D) -> bool:
	var action: Dictionary = e.get("action")
	if action.has("chunk_key") and WorldGen.chunks.has(str(action["chunk_key"])):
		var chunk: RefCounted = WorldGen.chunks[str(action["chunk_key"])]
		return int(chunk.zone.get("req", 1)) > WorldGen.player_entry_level()
	var zone: Dictionary = WorldGen.zone_at(e.position)
	return int(zone.get("req", 1)) > WorldGen.player_entry_level()


func _spawn_ground_decor(chunk: RefCounted, container: Node2D) -> void:
	if chunk.layer != 0:
		return
	var seed: int = WorldGen.store.world_seed
	for ty: int in range(WG.CHUNK_TILES):
		for tx: int in range(WG.CHUNK_TILES):
			var tile: Dictionary = WorldGen.reg.tile_def(chunk.tile_id(tx, ty))
			if bool(tile.get("water", false)) or not bool(tile.get("walkable", true)):
				continue
			var r := WG.r01(seed, chunk.cx * 251 + tx, chunk.cy * 263 + ty, 201)
			var biome_id := _tile_biome_id(chunk, tx, ty)
			var near_water := _tile_near_water(chunk, tx, ty)
			var chance := _decor_chance(biome_id, near_water)
			if r > chance:
				continue
			var d: Node2D = WorldDecor.new()
			d.variant = int(WG.hash_i(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 202) % 1000)
			var kroll := WG.r01(seed, chunk.cx * 97 + tx, chunk.cy * 101 + ty, 205)
			d.kind = _pick_decor_kind(biome_id, near_water, kroll)
			var jitter := Vector2(
				(WG.r01(seed, tx, ty, 203) - 0.5) * WG.TILE * 0.42,
				(WG.r01(seed, tx, ty, 204) - 0.5) * WG.TILE * 0.32)
			d.position = chunk.tile_world(tx, ty) + jitter
			container.add_child(d)
			world._decor_nodes.append(d)


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


func _decor_chance(biome_id: String, near_water: bool) -> float:
	if near_water:
		return 0.16
	match biome_id:
		"dense_forest": return 0.14
		"forest": return 0.105
		"swamp": return 0.13
		"rocky_hills": return 0.055
		"plains": return 0.045
		"beach", "desert": return 0.035
		_: return 0.035


func _pick_decor_kind(biome_id: String, near_water: bool, roll: float) -> String:
	if near_water:
		if roll < 0.45: return "reed"
		if roll < 0.66: return "stick"
		if roll < 0.82: return "grass"
		return "pebble"
	match biome_id:
		"dense_forest":
			if roll < 0.28: return "shrub"
			if roll < 0.50: return "fern"
			if roll < 0.70: return "stick"
			if roll < 0.84: return "mushroom"
			return "grass"
		"forest":
			if roll < 0.26: return "shrub"
			if roll < 0.48: return "fern"
			if roll < 0.66: return "stick"
			if roll < 0.76: return "mushroom"
			if roll < 0.88: return "flower"
			return "grass"
		"swamp":
			if roll < 0.34: return "reed"
			if roll < 0.58: return "fern"
			if roll < 0.74: return "mushroom"
			if roll < 0.88: return "stick"
			return "shrub"
		"rocky_hills":
			return "pebble" if roll < 0.72 else "grass"
		"beach", "desert":
			return "pebble" if roll < 0.62 else "stick"
		_:
			if roll < 0.34: return "grass"
			if roll < 0.54: return "flower"
			if roll < 0.72: return "stick"
			return "shrub"


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
		_:
			if part.has("station"):
				e.action = {"type": "station", "station": str(part["station"]), "label": e.label}
			elif part.has("hook"):
				e.action = {"type": "hook", "message": str(part.get("hookMessage", "Coming soon."))}
			else:
				e.action = {"type": "landmark", "label": e.label}
	container.add_child(e)
	world.entities.append(e)


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
	return colors[idx]
