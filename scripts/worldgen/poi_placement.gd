extends RefCounted
## Places points of interest into freshly generated surface chunks, driven
## entirely by data/world/pois.json. Placement modes:
##   cell    one POI per NxN-chunk cell at a seed-jittered member chunk
##   zone    one POI per level zone, in the zone's site chunk
##   chance  independent per-chunk roll
## The home chunk (0,0) always receives a campsite so a bank, fire, and
## respawn point are guaranteed at spawn.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

var reg: RefCounted
var classifier: RefCounted
var zone_map: RefCounted
var world_seed: int = 0


func setup(p_reg: RefCounted, p_classifier: RefCounted, p_zone_map: RefCounted, p_seed: int) -> void:
	reg = p_reg
	classifier = p_classifier
	zone_map = p_zone_map
	world_seed = p_seed


func place(chunk: RefCounted, occupied: Dictionary, placement_grid: RefCounted) -> void:
	if chunk.layer != 0:
		return  # cave POIs (ladders) are produced by cave_generator.gd
	var majors := 0
	var minors := 0
	if chunk.cx == 0 and chunk.cy == 0:
		if _try_place(chunk, "campsite", reg.pois.get("campsite", {}), occupied, placement_grid):
			majors += 1
	# Authored anchor (WorldSpec): pin a settlement / landmark / dungeon to this
	# exact chunk, with its authored label and (optionally) a pinned boss.
	if majors == 0 and reg.spec.active:
		var anc: Dictionary = reg.spec.anchor_for_chunk(chunk.cx, chunk.cy)
		if not anc.is_empty():
			var adef: Dictionary = reg.pois.get(str(anc["poi"]), {}).duplicate(true)
			if not adef.is_empty():
				if not str(anc.get("label", "")).is_empty():
					adef["label"] = str(anc["label"])
				if not str(anc.get("boss", "")).is_empty():
					adef["_pinnedBoss"] = str(anc["boss"])
				if _try_place(chunk, str(anc["poi"]), adef, occupied, placement_grid):
					majors += 1
	for type: String in reg.pois:
		# Authored-anchor POIs are placed only by the injection above.
		if reg.spec.active and _authored_anchor_type(chunk.cx, chunk.cy, type):
			continue
		var def: Dictionary = reg.pois[type]
		# Multi-chunk megastructures (cities/ruin fields) are produced by the
		# StructurePlanner across many chunks, not as a single-chunk POI here.
		if def.has("mega"):
			continue
		var placement: Dictionary = def.get("placement", {})
		var mode := str(placement.get("mode", "chance"))
		var is_major := mode != "chance"
		if is_major and majors >= 1:
			continue
		if not is_major and minors >= 2:
			continue
		if not wants_chunk(chunk.cx, chunk.cy, chunk.zone, type):
			continue
		if int(chunk.zone.get("req", 1)) < int(def.get("minTier", 0)):
			continue
		if _try_place(chunk, type, def, occupied, placement_grid):
			if is_major:
				majors += 1
			else:
				minors += 1


## CURATED-ONLY placement for blank-canvas worlds: the home camp + hand-authored
## WorldSpec anchors (settlements / landmarks / dungeons), but NONE of the
## procedural POIs. Anchors ignore the POI's biome whitelist (their tile was
## already validated as flat walkable land) and keep their authored label.
func place_authored_only(_chunk: RefCounted, _occupied: Dictionary, _placement_grid: RefCounted) -> int:
	# CLEAN SLATE: the authored world ships with NO structures — no spawn camp, no anchor POIs —
	# so it can be built up entirely from the world editor. (Re-enable the campsite/anchor block
	# from git history if a default starter camp is ever wanted again.)
	return 0


## Cheap predicate (no chunk generation needed): would this POI type want to
## live in chunk (cx, cy)? Used by WorldGen ring searches to skip chunks.
func wants_chunk(cx: int, cy: int, zone: Dictionary, type: String) -> bool:
	# Authored anchors always claim their chunk (so ring searches find them).
	if reg.spec.active and _authored_anchor_type(cx, cy, type):
		return true
	var placement: Dictionary = reg.pois.get(type, {}).get("placement", {})
	var salt: int = type.hash() & 0xFFFFFF
	match str(placement.get("mode", "chance")):
		"cell":
			var cell := int(placement.get("cellChunks", 5))
			var zx := floori(float(cx) / cell)
			var zy := floori(float(cy) / cell)
			var span := maxi(cell - 2, 1)
			var jx := 1 + WG.hash_i(world_seed, zx, zy, salt) % span if cell > 2 else 0
			var jy := 1 + WG.hash_i(world_seed, zx, zy, salt + 1) % span if cell > 2 else 0
			if cx != zx * cell + jx or cy != zy * cell + jy:
				return false
			var chance := float(placement.get("chance", 1.0))
			return WG.r01(world_seed, zx, zy, salt + 2) < chance
		"zone":
			var site: Vector2i = zone.get("site_chunk", Vector2i(99999, 99999))
			return site.x == cx and site.y == cy
		_:
			var chance := float(placement.get("chance", 0.0))
			return WG.r01(world_seed, cx, cy, salt + 3) < chance


## All POI types that would roll for this chunk (home campsite included).
func candidate_types(cx: int, cy: int, zone: Dictionary) -> Array:
	var out: Array = []
	if cx == 0 and cy == 0:
		out.append("campsite")
	for type: String in reg.pois:
		if wants_chunk(cx, cy, zone, type) and not out.has(type):
			out.append(type)
	return out


func _try_place(chunk: RefCounted, type: String, def: Dictionary, occupied: Dictionary, placement_grid: RefCounted) -> bool:
	if def.is_empty():
		return false
	var parts: Array = def.get("parts", [])
	var needs_water := bool(def.get("needsWater", false))
	var anchor := _find_anchor(chunk, parts, occupied, needs_water, placement_grid)
	if anchor.x < 0:
		return false
	# Biome whitelist is checked at the actual anchor tile.
	var allowed: Array = def.get("biomes", [])
	if not allowed.is_empty():
		var b_idx: int = chunk.biome_at(anchor.x, anchor.y)
		if b_idx == 255 or not allowed.has(str(reg.biomes[b_idx]["id"])):
			return false

	var poi := {
		"type": type, "label": str(def.get("label", type)),
		"anchor": anchor, "safe": bool(def.get("safe", false)),
		"respawn": bool(def.get("respawn", false)),
		"minimap": str(def.get("minimapColor", "ffffff")),
		"cluster_sites": int(def.get("clusterSites", 0)),
		"cluster_skill": str(def.get("clusterSkill", "")),
		"parts": [],
	}

	var variants: Array = def.get("variants", [])
	if not variants.is_empty():
		var v := _pick_variant(chunk, anchor, variants)
		if v.is_empty():
			return false
		if not bool(def.get("_keepLabel", false)):
			poi["label"] = str(v.get("label", poi["label"]))
		parts = [{"kind": str(v.get("kind", "sign")), "label": poi["label"], "dx": 0, "dy": 0}]

	for raw: Dictionary in parts:
		var tx: int = anchor.x + int(raw.get("dx", 0))
		var ty: int = anchor.y + int(raw.get("dy", 0))
		var part := {
			"kind": str(raw.get("kind", "sign")),
			"label": str(raw.get("label", "")),
			"tx": tx, "ty": ty,
		}
		if raw.has("station"):
			part["station"] = str(raw["station"])
		if raw.has("npc"):
			part["npc"] = str(raw["npc"])
		if raw.has("hook"):
			part["hook"] = str(raw["hook"])
			part["hookMessage"] = str(raw.get("hookMessage", "Coming soon."))
		if raw.has("color"):
			part["color"] = str(raw["color"])
		if bool(raw.get("boss", false)):
			var boss := _pick_boss_for(chunk, str(def.get("_pinnedBoss", "")))
			if boss.is_empty():
				continue
			part["boss_name"] = str(boss["name"])
			part["label"] = str(boss["name"])
		elif raw.has("enemy"):
			# A specific named GUARDIAN (not a boss) — themed mobs that hold a set-piece
			# (e.g. ghosts in a ruin). The bestiary name carries its own level/drops, so
			# the POI's minTier just gates it into a zone where that level fits.
			part["enemy_name"] = str(raw["enemy"])
			part["label"] = str(raw["enemy"])
			part["aggressive"] = bool(raw.get("aggressive", true))
		occupied[Chunk.idx(tx, ty)] = true
		poi["parts"].append(part)

	if bool(def.get("safe", false)):
		chunk.safe = true
	placement_grid.place_footprint(chunk, anchor, parts)
	chunk.pois.append(poi)
	return true


## Spiral-scan for an anchor tile where the whole footprint is walkable land.
func _find_anchor(chunk: RefCounted, parts: Array, occupied: Dictionary, needs_water: bool, placement_grid: RefCounted) -> Vector2i:
	var center := WG.CHUNK_TILES / 2
	for ring: int in range(0, WG.CHUNK_TILES):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var ax := center + dx
				var ay := center + dy
				if _footprint_ok(chunk, ax, ay, parts, occupied, placement_grid) \
						and (not needs_water or _adjacent_water(chunk, ax, ay)):
					return Vector2i(ax, ay)
	return Vector2i(-1, -1)


func _footprint_ok(chunk: RefCounted, ax: int, ay: int, parts: Array, occupied: Dictionary, placement_grid: RefCounted) -> bool:
	if not placement_grid.can_place_footprint(chunk, Vector2i(ax, ay), parts):
		return false
	var offsets: Array = [[0, 0]]
	for raw: Dictionary in parts:
		offsets.append([int(raw.get("dx", 0)), int(raw.get("dy", 0))])
	for off: Array in offsets:
		var tx: int = ax + int(off[0])
		var ty: int = ay + int(off[1])
		if tx < 1 or ty < 1 or tx >= WG.CHUNK_TILES - 1 or ty >= WG.CHUNK_TILES - 1:
			return false
		if occupied.has(Chunk.idx(tx, ty)):
			return false
		if chunk.elev.size() > 0 and chunk.elev[Chunk.idx(tx, ty)] > 0:
			return false   # never anchor a settlement on raised (unreachable) rock
		var t: Dictionary = reg.tile_def(chunk.tile_id(tx, ty))
		if not t["walkable"] or t["water"] or t["hazard"]:
			return false
	return true


func _adjacent_water(chunk: RefCounted, tx: int, ty: int) -> bool:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := tx + off.x
		var ny := ty + off.y
		if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
			continue
		if reg.tile_def(chunk.tile_id(nx, ny))["water"]:
			return true
	return false


func _pick_variant(chunk: RefCounted, anchor: Vector2i, variants: Array) -> Dictionary:
	var b_idx: int = chunk.biome_at(anchor.x, anchor.y)
	var biome_id := "" if b_idx == 255 else str(reg.biomes[b_idx]["id"])
	var fitting: Array = []
	for v: Dictionary in variants:
		if Array(v.get("biomes", [])).has(biome_id):
			fitting.append(v)
	if fitting.is_empty():
		# Authored anchors may sit in any biome (their placement is already validated),
		# so fall back to the first variant rather than failing to resolve a look.
		if variants.is_empty():
			return {}
		fitting = [variants[0]]
	var roll := WG.hash_i(world_seed, chunk.cx, chunk.cy, 53) % fitting.size()
	return fitting[roll]


## True when an authored anchor of `type` is pinned to chunk (cx, cy).
func _authored_anchor_type(cx: int, cy: int, type: String) -> bool:
	var anc: Dictionary = reg.spec.anchor_for_chunk(cx, cy)
	return not anc.is_empty() and str(anc["poi"]) == type


## Boss for this anchor: a named bestiary boss when pinned, else best-fit.
func _pick_boss_for(chunk: RefCounted, pinned: String) -> Dictionary:
	if not pinned.is_empty():
		for b: Dictionary in reg.boss_list:
			if str(b["name"]) == pinned:
				return b
	return _pick_boss(chunk)


## Boss whose level best fits this zone (prefer biome natives).
func _pick_boss(chunk: RefCounted) -> Dictionary:
	var req := float(chunk.zone.get("req", 1))
	var biome_id := str(chunk.zone.get("biome", ""))
	var best: Dictionary = {}
	var best_score := INF
	for b: Dictionary in reg.boss_list:
		var score: float = absf(float(b["level"]) - req * 1.15)
		if not Array(b["biomes"]).has(biome_id):
			score += 40.0
		if score < best_score:
			best_score = score
			best = b
	return best
