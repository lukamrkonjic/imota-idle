extends Node
## gen_world — synthesize a NEW world WITHOUT an illustrated map: generate a
## fractal land/water mask procedurally, then drop the authored biome layout onto
## it by snapping each region to the nearest land. Output is a normal mask +
## worldspec, so it flows through the exact same coast_preview / bake pipeline as
## an imported world.
##
## EXPERIMENTAL — the coastline knobs below still tend to produce one broad
## continent rather than the multi-island, deep-bay look of a hand-traced map
## (tools/world_trace.gd). Treat this as a starting point: tune SEA_LEVEL / the
## falloff / WARP_AMP / island params, or trace an illustration for best results.
##
##   godot --headless --path . res://tools/gen_world.tscn -- --world=alpha --seed=101
##
## Writes data/world/masks/<id>_land.png (+ _mask.json) and
##        data/world/worldspec/<id>.json   (regions snapped onto the new land)
## Then set worldspec/index.json active=<id> and run coast_preview to see biomes.

const WG := preload("res://scripts/worldgen/wg.gd")

const W := 1536          # mask resolution (matches the Aldreth atlas, 3:2)
const H := 1024
const TEMPLATE := "res://data/world/worldspec/aldreth.json"   # biome layout to reuse
const OUT_MASK := "res://data/world/masks/"
const OUT_SPEC := "res://data/world/worldspec/"

# Coastline shape knobs (tune for more/less land + crinkle).
const SEA_LEVEL := 0.50      # field threshold; higher => less land
const FALL_IN := 0.34        # radius where the central landmass starts fading
const FALL_OUT := 1.02       # radius where it's fully sea
const WARP_AMP := 200.0      # domain-warp strength => bays/capes
const RIDGE_MIX := 0.30      # how much ridged detail frays the coast
const ISLAND_LIFT := 0.34    # offshore island strength
const MIN_ISLAND_FRAC := 0.00006   # drop land specks below this fraction of pixels


func _ready() -> void:
	if _has_autoload("SaveManager"): SaveManager.suppress = true
	if _has_autoload("GameSettings"): GameSettings.suppress = true
	var args := OS.get_cmdline_user_args()
	var id := _arg(args, "--world=", "alpha")
	var seed := int(_arg(args, "--seed=", "101"))
	var t0 := Time.get_ticks_msec()

	# 1. synthesize + clean the land mask
	var land := _gen_land(seed)
	_despeckle(land, maxi(40, int(W * H * MIN_ISLAND_FRAC)))
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	for i: int in W * H:
		img.set_pixel(i % W, i / W, Color8(232, 226, 208) if land[i] == 1 else Color8(20, 38, 64))
	DirAccess.make_dir_recursive_absolute(OUT_MASK)
	img.save_png(OUT_MASK + id + "_land.png")

	# 2. reuse the authored biome layout: snap every region to the new land
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE))
	spec["id"] = id
	spec["name"] = "Candidate world '%s'" % id
	spec["seed"] = seed
	var b: Rect2i = _bounds(spec)
	var snapped := 0
	for r: Dictionary in spec.get("regions", []):
		var c := _snap_to_land(land, b, int(r["shape"]["center"][0]), int(r["shape"]["center"][1]))
		r["shape"]["center"] = [c.x, c.y]
		snapped += 1
	# fresh-world content: keep only a spawn anchor (snapped), clear roads/features
	var spawn := _region_center(spec, "greenhollow", b, land)
	spec["anchors"] = [{"id": "spawn", "poi": "player_spawn", "label": "Home",
		"chunk": [spawn.x, spawn.y], "region": "greenhollow", "teleport": false, "locked": false}]
	spec["roads"] = []
	spec["settlements"] = []
	spec["features"] = []
	spec["routes"] = []
	var f := FileAccess.open(OUT_SPEC + id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(spec, "\t"))
	f.close()

	# mask meta (same mapping as world_trace writes)
	var meta := {"world": id, "source": "(synthesized)", "land": id + "_land.png",
		"atlasSize": [W, H], "maskSize": [W, H],
		"recommendedBounds": {"min": [b.position.x, b.position.y], "max": [b.end.x - 1, b.end.y - 1]}}
	var mf := FileAccess.open(OUT_MASK + id + "_mask.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta, "\t"))
	mf.close()

	print(JSON.stringify({"tool": "gen_world", "world": id, "seed": seed,
		"land_fraction": float(_count(land)) / float(W * H), "regions_snapped": snapped,
		"spawn": [spawn.x, spawn.y], "took_s": float(Time.get_ticks_msec() - t0) / 1000.0,
		"next": "set worldspec/index.json active=%s, run coast_preview" % id}, "\t"))
	get_tree().quit(0)


# --- fractal land field -------------------------------------------------------

func _gen_land(seed: int) -> PackedByteArray:
	var warp := _noise(seed + 10, 0.0018, 2)
	var cont := _noise(seed + 20, 0.0015, 5)
	var detail := _noise(seed + 30, 0.0052, 4)
	var isl := _noise(seed + 40, 0.0034, 3)
	var land := PackedByteArray()
	land.resize(W * H)
	for y: int in H:
		for x: int in W:
			var u := float(x) / float(W) * 2.0 - 1.0
			var v := float(y) / float(H) * 2.0 - 1.0
			var wx := float(x) + warp.get_noise_2d(float(x), float(y)) * WARP_AMP
			var wy := float(y) + warp.get_noise_2d(float(x) + 99.0, float(y) + 33.0) * WARP_AMP
			var base := cont.get_noise_2d(wx, wy) * 0.5 + 0.5
			var ridge := 1.0 - absf(detail.get_noise_2d(wx, wy))   # ridged => fjord/cape fray
			var shape := base * (1.0 - RIDGE_MIX) + ridge * RIDGE_MIX
			var r := sqrt(u * u + v * v)
			var fall := 1.0 - smoothstep(FALL_IN, FALL_OUT, r)
			var field := shape * 0.62 + fall * 0.52
			var island := smoothstep(0.70, 0.96, isl.get_noise_2d(wx, wy) * 0.5 + 0.5) \
				* ISLAND_LIFT * (1.0 - smoothstep(0.45, 1.05, r))
			field += island
			land[y * W + x] = 1 if field > SEA_LEVEL else 0
	return land


static func _noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if oct > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = oct
	return n


## Remove land components below min_area (4-connected), keeping real islands.
func _despeckle(land: PackedByteArray, min_area: int) -> void:
	var seen := PackedByteArray()
	seen.resize(land.size())
	for start: int in land.size():
		if land[start] != 1 or seen[start] == 1:
			continue
		var comp := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			comp.push_back(i)
			var x := i % W
			var y := i / W
			if x > 0 and land[i - 1] == 1 and seen[i - 1] == 0: seen[i - 1] = 1; stack.push_back(i - 1)
			if x < W - 1 and land[i + 1] == 1 and seen[i + 1] == 0: seen[i + 1] = 1; stack.push_back(i + 1)
			if y > 0 and land[i - W] == 1 and seen[i - W] == 0: seen[i - W] = 1; stack.push_back(i - W)
			if y < H - 1 and land[i + W] == 1 and seen[i + W] == 0: seen[i + W] = 1; stack.push_back(i + W)
		if comp.size() < min_area:
			for i: int in comp:
				land[i] = 0


# --- region snapping ----------------------------------------------------------

func _bounds(spec: Dictionary) -> Rect2i:
	var bm: Dictionary = spec.get("bounds", {})
	var mn: Array = bm.get("min", [-67, -45])
	var mx: Array = bm.get("max", [67, 44])
	return Rect2i(int(mn[0]), int(mn[1]), int(mx[0]) - int(mn[0]) + 1, int(mx[1]) - int(mn[1]) + 1)


func _snap_to_land(land: PackedByteArray, b: Rect2i, cx: int, cy: int) -> Vector2i:
	if _is_land(land, b, cx, cy):
		return Vector2i(cx, cy)
	for radius: int in range(1, 60):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if _is_land(land, b, cx + dx, cy + dy):
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(cx, cy)


func _is_land(land: PackedByteArray, b: Rect2i, cx: int, cy: int) -> bool:
	var px := int((float(cx) - float(b.position.x)) / float(b.size.x) * float(W))
	var py := int((float(cy) - float(b.position.y)) / float(b.size.y) * float(H))
	if px < 0 or py < 0 or px >= W or py >= H:
		return false
	return land[py * W + px] == 1


func _region_center(spec: Dictionary, rid: String, b: Rect2i, land: PackedByteArray) -> Vector2i:
	for r: Dictionary in spec.get("regions", []):
		if str(r["id"]) == rid:
			return _snap_to_land(land, b, int(r["shape"]["center"][0]), int(r["shape"]["center"][1]))
	return Vector2i(0, 0)


# --- helpers ------------------------------------------------------------------

static func _count(land: PackedByteArray) -> int:
	var n := 0
	for v: int in land:
		if v == 1:
			n += 1
	return n


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a: String in args:
		if a.begins_with(key):
			return a.substr(key.length())
	return def


func _has_autoload(name: String) -> bool:
	return Engine.has_singleton(name) or get_node_or_null("/root/" + name) != null
