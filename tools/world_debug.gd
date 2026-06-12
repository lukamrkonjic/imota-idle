extends Node
## Headless world-gen debug renderer + sample-seed scanner. Run:
##   godot --headless --path . res://tools/world_debug.tscn -- --seed=1337 --radius=12
##   godot --headless --path . res://tools/world_debug.tscn -- --seed=1337 --tiles
##   godot --headless --path . res://tools/world_debug.tscn -- --scan=2000
##
## Map legend (chunk view): one char per chunk = dominant biome, overridden by
## POI markers. Biomes: ~ ocean, . beach, " plains, f forest, F deepwood,
## s swamp, d desert, t tundra, v volcanic, h highlands. POIs: C campsite,
## V village, O obelisk, B boss lair, L landmark, E cave entrance, A altar,
## X soul shrine, D depot, # locked zone (req > 30 shown for orientation).

const WG := preload("res://scripts/worldgen/wg.gd")

const BIOME_CHARS := {
	"ocean": "~", "beach": ".", "plains": "\"", "forest": "f",
	"dense_forest": "F", "swamp": "s", "desert": "d", "tundra": "t",
	"volcanic": "v", "rocky_hills": "h",
}
const POI_CHARS := {
	"campsite": "C", "village": "V", "obelisk": "O", "boss_lair": "B",
	"landmark": "L", "cave_entrance": "E", "altar": "A", "soul_shrine": "X",
	"resource_depot": "D", "fishing_hotspot": "D", "trap_site": "n",
}


func _ready() -> void:
	SaveManager.suppress = true
	WorldGen.store.suppress = true
	var seed_v := WorldGen.DEFAULT_SEED
	var radius := 10
	var tiles := false
	var scan := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_v = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--radius="):
			radius = int(arg.trim_prefix("--radius="))
		elif arg == "--tiles":
			tiles = true
		elif arg.begins_with("--scan="):
			scan = int(arg.trim_prefix("--scan="))
	if scan > 0:
		_scan_seeds(scan)
	else:
		WorldGen.reset(seed_v)
		if tiles:
			_print_tiles(seed_v)
		else:
			_print_chunk_map(seed_v, radius)
			_print_zones(seed_v)
	get_tree().quit(0)


# ------------------------------------------------------------- ascii maps ----

func _print_chunk_map(seed_v: int, radius: int) -> void:
	print("World seed %d — chunk map, radius %d (player spawn at center @):" % [seed_v, radius])
	for cy: int in range(-radius, radius + 1):
		var line := ""
		for cx: int in range(-radius, radius + 1):
			line += _chunk_char(cx, cy)
		print(line)


func _chunk_char(cx: int, cy: int) -> String:
	var zone: Dictionary = WorldGen.generator.zone_map.zone_for_chunk(cx, cy)
	# POI markers come from the cheap placement predicate, not full chunk gen.
	for type: String in POI_CHARS:
		if WorldGen.generator.poi_placer.wants_chunk(cx, cy, zone, type):
			return POI_CHARS[type]
	if cx == 0 and cy == 0:
		return "@"
	var center_tile := (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * WG.CHUNK_TILES
	var b: int = WorldGen.generator.classifier.biome_idx(center_tile.x, center_tile.y)
	return str(BIOME_CHARS.get(str(WorldGen.reg.biomes[b]["id"]), "?"))


func _print_tiles(seed_v: int) -> void:
	print("World seed %d — tile map, chunks (-1,-1)..(1,1):" % seed_v)
	print("~ deep, = water, - shallow, ' land by biome char; T/R/F/B sites; C/V... POI anchors; m monster")
	var n := WG.CHUNK_TILES
	for gy: int in range(-n, n * 2):
		var line := ""
		for gx: int in range(-n, n * 2):
			var c := WG.tile_to_chunk(Vector2i(gx, gy))
			var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
			var tx: int = gx - c.x * n
			var ty: int = gy - c.y * n
			line += _tile_char(chunk, tx, ty)
		print(line)


func _tile_char(chunk: RefCounted, tx: int, ty: int) -> String:
	for poi: Dictionary in chunk.pois:
		for part: Dictionary in poi["parts"]:
			if int(part["tx"]) == tx and int(part["ty"]) == ty:
				return str(POI_CHARS.get(str(poi["type"]), "P"))
	for s: Dictionary in chunk.sites:
		if int(s["tx"]) == tx and int(s["ty"]) == ty:
			return {"woodcutting": "T", "mining": "R", "fishing": "F", "foraging": "B"}.get(str(s["skill"]), "S")
	for m: Dictionary in chunk.monsters:
		if int(m["tx"]) == tx and int(m["ty"]) == ty:
			return "m"
	var tile_id := str(WorldGen.reg.tile_order[chunk.tile_id(tx, ty)])
	match tile_id:
		"deep_water": return "~"
		"water": return "="
		"shallow": return "-"
		"lava": return "!"
		"cave_wall", "deep_wall": return "#"
	var b: int = chunk.biome_at(tx, ty)
	if b == 255:
		return "'"
	return str(BIOME_CHARS.get(str(WorldGen.reg.biomes[b]["id"]), "'"))


func _print_zones(seed_v: int) -> void:
	print("\nZones near spawn (seed %d):" % seed_v)
	var seen: Dictionary = {}
	for cy: int in range(-9, 10, 3):
		for cx: int in range(-9, 10, 3):
			var z: Dictionary = WorldGen.generator.zone_map.zone_for_chunk(cx, cy)
			if seen.has(z["id"]):
				continue
			seen[z["id"]] = true
			print("  %-28s req %3d  %-12s biome %-12s site chunk %s" % [
				str(z["name"]), int(z["req"]), str(z["tier"]), str(z["biome"]), str(z["site_chunk"])])


# ------------------------------------------------------------- seed scan ----

## Find seeds matching the sample-seed deliverable: plains at origin, forest
## to the north, a river to the east, and a ~level-10 zone within 3 chunks.
## (A campsite within 2 chunks is guaranteed by the forced home camp.)
func _scan_seeds(count: int) -> void:
	print("Scanning %d seeds for the sample starting area..." % count)
	var found := 0
	for seed_v: int in range(1, count + 1):
		WorldGen.reset(seed_v)
		if _seed_matches():
			print("  seed %d MATCHES" % seed_v)
			found += 1
			if found >= 10:
				break
	if found == 0:
		print("  no matching seed found — relax the criteria or scan more")


func _seed_matches() -> bool:
	var classifier: RefCounted = WorldGen.generator.classifier
	var n := WG.CHUNK_TILES
	# Plains at the origin chunk.
	if _biome_id_at(classifier, 0.5 * n, 0.5 * n) != "plains":
		return false
	# Forest to the north (any chunk in cx -1..1, cy -3..-1).
	var forest := false
	for cy: int in range(-3, 0):
		for cx: int in range(-1, 2):
			var id := _biome_id_at(classifier, (float(cx) + 0.5) * n, (float(cy) + 0.5) * n)
			if id == "forest" or id == "dense_forest":
				forest = true
	if not forest:
		return false
	# River water to the east (chunks cx 1..3, cy -1..1), sampled per tile.
	var river := false
	for cx: int in range(1, 4):
		for ty: int in range(0, n, 2):
			for tx: int in range(0, n, 2):
				var gx := float(cx * n + tx)
				var gy := float(-n / 2.0 + ty)
				var f: Vector3 = classifier.fields(gx, gy)
				if f.x >= 0.30 and classifier.river_at(gx, gy, f.x) == 2:
					river = true
	if not river:
		return false
	# A level ~10 zone within 3 chunks.
	for cy: int in range(-3, 4):
		for cx: int in range(-3, 4):
			var z: Dictionary = WorldGen.generator.zone_map.zone_for_chunk(cx, cy)
			if int(z["req"]) >= 5 and int(z["req"]) <= 15:
				return true
	return false


func _biome_id_at(classifier: RefCounted, tx: float, ty: float) -> String:
	var b: int = classifier.biome_idx(tx, ty)
	return str(WorldGen.reg.biomes[b]["id"])
