extends Node
## Biome census — counts how many tiles of each defined biome actually exist in the
## baked finite world, so we can see which biomes are defined but never placed.
## Run: godot --headless --path . res://tools/biome_census.tscn

const WG := preload("res://scripts/worldgen/wg.gd")


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("biome_census: active spec is not a finite world.")
		get_tree().quit(1)
		return
	var counts: Dictionary = {}
	for b: Dictionary in reg.biomes:
		counts[str(b["id"])] = 0
	var b: Rect2i = spec.bounds
	var total := 0
	# --live: sample the live biome generator over a strided grid (fast, no bake needed,
	# for iterating on placement). Default: census the actual baked tiles (accurate).
	var live := "--live" in OS.get_cmdline_user_args()
	if live:
		var mg: RefCounted = WorldGen.generator.classifier.map_gen
		var stride := 2
		var x0 := b.position.x * WG.CHUNK_TILES
		var y0 := b.position.y * WG.CHUNK_TILES
		var x1 := b.end.x * WG.CHUNK_TILES
		var y1 := b.end.y * WG.CHUNK_TILES
		for ty: int in range(y0, y1, stride):
			for tx: int in range(x0, x1, stride):
				var idx: int = mg.effective_idx_at(float(tx), float(ty))
				if idx == 255 or idx >= reg.biomes.size():
					continue
				var id := str(reg.biomes[idx]["id"])
				counts[id] = int(counts.get(id, 0)) + 1
				total += 1
	else:
		for cy: int in range(b.position.y, b.end.y):
			for cx: int in range(b.position.x, b.end.x):
				var chunk: RefCounted = WorldGen.get_chunk(0, cx, cy)
				if chunk == null:
					continue
				for v: int in chunk.biomes_t:
					if v == 255 or v >= reg.biomes.size():
						continue
					var id := str(reg.biomes[v]["id"])
					counts[id] = int(counts.get(id, 0)) + 1
					total += 1
	# Report sorted by count; flag the zero-tile biomes loudly.
	var ids: Array = counts.keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return counts[x] < counts[y])
	print("=== BIOME CENSUS (%d biomes, %d land tiles) ===" % [reg.biomes.size(), total])
	var missing: Array = []
	for id: String in ids:
		var c: int = counts[id]
		var pct := 100.0 * float(c) / maxf(float(total), 1.0)
		print("  %-16s %9d  %5.2f%%" % [id, c, pct])
		if c == 0:
			missing.append(id)
	print("MISSING (0 tiles): %s" % (", ".join(missing) if not missing.is_empty() else "none — every biome is placed"))
	get_tree().quit()
