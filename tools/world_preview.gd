extends Node
## Fast macro world-map preview — samples the LIVE biome generator over the whole
## finite bounds and writes a coloured PNG, WITHOUT baking chunks (seconds, not minutes).
## Use it to iterate on the continent shape + biome layout, then bake once at the end.
##   godot --headless --path . res://tools/world_preview.tscn
## Output: user://world_preview.png  (and copy noted in stdout)

const WG := preload("res://scripts/worldgen/wg.gd")

const STRIDE := 2   # tiles per pixel (smaller = sharper + slower)


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("world_preview: active spec is not a finite world.")
		get_tree().quit(1)
		return
	var mg: RefCounted = WorldGen.generator.classifier.map_gen
	var cl: RefCounted = WorldGen.generator.classifier

	# Per-biome colour = its primary ground tile's lit colour; ocean/sea = blue.
	var biome_col: Array = []
	for b: Dictionary in reg.biomes:
		var tiles: Dictionary = b.get("tiles", {})
		var c := Color(0.4, 0.45, 0.4)
		if not tiles.is_empty():
			var first: String = tiles.keys()[0]
			var td: Dictionary = reg.tile_def(int(reg.tile_index.get(first, 0)))
			var cols: Array = td.get("colors", [])
			if not cols.is_empty():
				c = cols[0]
		biome_col.append(c)
	var sea := Color(0.36, 0.42, 0.55)

	var b: Rect2i = spec.bounds
	var x0 := b.position.x * WG.CHUNK_TILES
	var y0 := b.position.y * WG.CHUNK_TILES
	var w_tiles := b.size.x * WG.CHUNK_TILES
	var h_tiles := b.size.y * WG.CHUNK_TILES
	var pw := int(w_tiles / STRIDE)
	var ph := int(h_tiles / STRIDE)
	var img := Image.create_empty(pw, ph, false, Image.FORMAT_RGB8)

	for py: int in ph:
		for px: int in pw:
			var tx := x0 + px * STRIDE
			var ty := y0 + py * STRIDE
			# Sea first (signed landmass < shore band) so coasts read clearly.
			if cl.coast_sink(float(tx), float(ty)) > 0.72:
				img.set_pixel(px, py, sea)
				continue
			var idx: int = mg.effective_idx_at(float(tx), float(ty))
			if idx == 255 or idx >= biome_col.size():
				img.set_pixel(px, py, sea)
			else:
				img.set_pixel(px, py, biome_col[idx])
	img.save_png("user://world_preview.png")
	print("[world-preview] %dx%d px (stride %d) -> user://world_preview.png" % [pw, ph, STRIDE])
	get_tree().quit()
