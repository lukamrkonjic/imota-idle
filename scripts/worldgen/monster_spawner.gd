extends RefCounted
## Populates chunks with roaming monsters from the bestiary, weighted by biome
## affinity (data/world/monsters.json) and the zone's level requirement, so
## chickens roam the home meadows and frost giants the far tundra. Safe chunks
## (campsites/villages) never spawn monsters. Bosses are placed separately as
## boss_lair POI anchors by poi_placement.gd.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const PLACE_ATTEMPTS := 10

var reg: RefCounted
var world_seed: int = 0


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed


func populate(chunk: RefCounted, occupied: Dictionary) -> void:
	if chunk.safe:
		return
	var density := float(reg.monster_cfg.get("densityPerChunk", 2.2))
	if chunk.layer == 0:
		var c := WG.CHUNK_TILES / 2
		var b_idx: int = chunk.biome_at(c, c)
		if b_idx == 255:
			return
		density *= float(reg.biomes[b_idx].get("monsterDensity", 0.5))
	else:
		density *= float(reg.cave_layers.get(chunk.layer, {}).get("monsterDensity", 0.8))
	var roll := WG.r01(world_seed, chunk.cx, chunk.cy, 100 + chunk.layer)
	var count := int(density) + (1 if roll < density - floorf(density) else 0)
	if count <= 0:
		return
	var req := int(chunk.zone.get("req", 1))
	for i: int in count:
		var tile := _pick_tile(chunk, occupied, i)
		if tile.x < 0:
			continue
		var pick := _pick_monster(chunk, tile, req, i)
		if pick.is_empty():
			continue
		occupied[Chunk.idx(tile.x, tile.y)] = true
		chunk.monsters.append({
			"name": str(pick["name"]),
			"level": int(pick["level"]),
			"tx": tile.x, "ty": tile.y,
			"aggressive": bool(pick["aggressive"]),
		})


func _pick_tile(chunk: RefCounted, occupied: Dictionary, salt: int) -> Vector2i:
	for attempt: int in PLACE_ATTEMPTS:
		var tx := 1 + WG.hash_i(world_seed, chunk.cx * 13 + salt, chunk.cy, 110 + attempt + chunk.layer * 7) % (WG.CHUNK_TILES - 2)
		var ty := 1 + WG.hash_i(world_seed, chunk.cx, chunk.cy * 13 + salt, 111 + attempt + chunk.layer * 7) % (WG.CHUNK_TILES - 2)
		if occupied.has(Chunk.idx(tx, ty)):
			continue
		var td: Dictionary = reg.tile_def(chunk.tile_id(tx, ty))
		if td["walkable"] and not td["water"] and not td["hazard"]:
			return Vector2i(tx, ty)
	return Vector2i(-1, -1)


## Pick a non-boss enemy whose biome affinity matches the tile and whose level
## sits inside the zone's band, weighted toward the zone requirement.
func _pick_monster(chunk: RefCounted, tile: Vector2i, req: int, salt: int) -> Dictionary:
	var band_low := float(reg.monster_cfg.get("levelBandLow", 0.45))
	var band_high := float(reg.monster_cfg.get("levelBandHigh", 2.6))
	var lvl_min := maxf(1.0, float(req) * band_low)
	var lvl_max := maxf(3.0, float(req) * band_high)
	var biome_id := ""
	var parent_id := ""
	if chunk.layer == 0:
		var b_idx: int = chunk.biome_at(tile.x, tile.y)
		if b_idx != 255:
			biome_id = str(reg.biomes[b_idx]["id"])
			parent_id = reg.parent_biome_id(b_idx)
	var fitting: Array = []
	var weights: Array = []
	var total := 0.0
	for name: String in reg.monster_table:
		var m: Dictionary = reg.monster_table[name]
		if bool(m["boss"]):
			continue
		var lvl := float(m["level"])
		if lvl < lvl_min or lvl > lvl_max:
			continue
		if chunk.layer == 0:
			var ok_biome := Array(m["biomes"]).has(biome_id) or Array(m["biomes"]).has(parent_id)
			if not ok_biome:
				continue
			var forbidden: Array = m.get("forbiddenBiomes", [])
			if forbidden.has(biome_id) or forbidden.has(parent_id):
				continue
		elif not Array(m["cave_layers"]).has(chunk.layer):
			continue
		var w := 1.0 / (1.0 + absf(float(req) * 0.85 - lvl) * 0.1)
		fitting.append(m)
		weights.append(w)
		total += w
	if fitting.is_empty():
		return {}
	var target := WG.r01(world_seed, chunk.cx * 19 + tile.x, chunk.cy * 19 + tile.y, 120 + salt) * total
	for i: int in fitting.size():
		target -= float(weights[i])
		if target <= 0.0:
			return fitting[i]
	return fitting.back()
