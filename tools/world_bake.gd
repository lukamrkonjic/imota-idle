extends Node
## world_bake — OFFLINE world compiler. Generates the finite authored world via
## the shared FiniteWorldGenerator service and writes the fixed result to:
##   res://data/world/baked/<id>.world   (var_to_str; tiles base64-packed + spawn)
##   res://data/world/baked/<id>_map.png (1px/tile overview for the M map)
##
## Regions flagged fixed:false (procedural zones, e.g. the Tanglewild) are drawn
## into the map but NOT baked — they keep generating at runtime.
##
## Run (headless is fine, tiles are CPU-only):
##   godot --headless --path . res://tools/world_bake.tscn

const WG := preload("res://scripts/worldgen/wg.gd")
const BakedWorldStore := preload("res://scripts/worldgen/baked_world_store.gd")
const FiniteWorldGenerator := preload("res://scripts/worldgen/finite_world_generator.gd")
const TerrainStyle := preload("res://scripts/render/terrain_style.gd")

const OUT_DIR := "res://data/world/baked/"


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true

	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("world_bake: active spec is not a finite world (set bounds in worldspec).")
		get_tree().quit(1)
		return

	var b: Rect2i = spec.bounds
	print("Baking '%s' — %d chunks x[%d..%d] y[%d..%d]" % [
		spec.id, b.get_area(), b.position.x, b.end.x - 1, b.position.y, b.end.y - 1])

	var gen: RefCounted = FiniteWorldGenerator.new()
	gen.setup(reg, WorldGen.store.world_seed)
	var t0 := Time.get_ticks_msec()
	var chunks: Dictionary = await gen.generate_region(self,
		func(done: int, total: int) -> void:
			if done % 256 == 0 or done == total:
				print("  %d/%d chunks" % [done, total]))

	# Preserve hand-authored placements (structures / decor / fences / settlement buildings) + cut
	# trees from the PREVIOUS bake through this regeneration, and write them to <id>_overlay.json so
	# the authored layer survives generation changes, world expansion, and model swaps.
	var world_path: String = OUT_DIR + str(spec.id) + ".world"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var overlay := AuthoredOverlay.merge_existing(world_path, chunks)
	var ofile := FileAccess.open(OUT_DIR + str(spec.id) + "_overlay.json", FileAccess.WRITE)
	if ofile != null:
		ofile.store_string(JSON.stringify(overlay, "  "))
		ofile.close()
	print("  preserved %d structures, %d enemy spawns, %d chunks-with-cuts, %d chunks-with-elev-edits" % [
		(overlay["structures"] as Array).size(), (overlay["monsters"] as Array).size(),
		(overlay["cuts"] as Dictionary).size(), (overlay["elev"] as Dictionary).size()])

	# Assemble: encode the fixed chunks, render the overview map.
	var tile_w: int = b.size.x * WG.CHUNK_TILES
	var tile_h: int = b.size.y * WG.CHUNK_TILES
	var img := Image.create_empty(tile_w, tile_h, false, Image.FORMAT_RGB8)
	var min_tx: int = b.position.x * WG.CHUNK_TILES
	var min_ty: int = b.position.y * WG.CHUNK_TILES
	var baked := 0
	var chunks_doc: Dictionary = {}
	for key: String in chunks:
		var chunk: RefCounted = chunks[key]
		_paint_map(img, chunk, reg, min_tx, min_ty)
		if spec.should_bake(chunk.cx, chunk.cy):
			chunks_doc[key] = _encode_chunk(chunk)
			baked += 1

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var spawn: Vector2i = gen.default_spawn_tile()
	# Permanent index->id tables so the byte-indexed chunk data survives any future
	# reorder/removal in biomes.json: BakedWorldStore remaps baked indices back to
	# current indices by ID (with deprecatedBiomes/Tiles fallbacks) on load.
	var biome_ids: Array = []
	for bd: Dictionary in reg.biomes:
		biome_ids.append(str(bd["id"]))
	var doc := {
		"version": 2,
		"id": spec.id,
		"bounds": {"min": [b.position.x, b.position.y], "max": [b.end.x - 1, b.end.y - 1]},
		"spawn": [spawn.x, spawn.y],
		"biomeIds": biome_ids,
		"tileIds": Array(reg.tile_order),
		"chunks": chunks_doc,
	}
	var f := FileAccess.open(world_path, FileAccess.WRITE)
	f.store_string(var_to_str(doc))
	f.close()
	img.save_png(OUT_DIR + str(spec.id) + "_map.png")

	print("\n=== BAKE RESULT ===")
	print(JSON.stringify({
		"world": ProjectSettings.globalize_path(world_path),
		"baked_chunks": baked,
		"procedural_chunks_skipped": chunks.size() - baked,
		"map_px": [tile_w, tile_h],
		"took_s": float(Time.get_ticks_msec() - t0) / 1000.0,
	}))
	get_tree().quit(0)


func _paint_map(img: Image, chunk: RefCounted, reg: RefCounted, min_tx: int, min_ty: int) -> void:
	var bx: int = chunk.cx * WG.CHUNK_TILES - min_tx
	var by: int = chunk.cy * WG.CHUNK_TILES - min_ty
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			var tid: int = chunk.tile_id(lx, ly)
			var tdef: Dictionary = reg.tile_def(tid)
			var col: Color = tdef["colors"][0]
			if not bool(tdef.get("water", false)):
				col = TerrainStyle.biome_tinted(col, str(reg.tile_order[tid]), reg.biome_tint(chunk.biome_at(lx, ly)), 0.55)
			img.set_pixel(bx + lx, by + ly, col)


func _encode_chunk(chunk: RefCounted) -> Dictionary:
	return {
		"t": BakedWorldStore.encode(chunk.tiles),
		"b": BakedWorldStore.encode(chunk.biomes_t),
		"p": BakedWorldStore.encode(chunk.parent_biomes_t),
		"s": BakedWorldStore.encode(chunk.sub_biomes_t),
		"k": BakedWorldStore.encode(chunk.collision),
		"e": BakedWorldStore.encode(chunk.elev),
		"zone": chunk.zone.duplicate(true),
		"safe": chunk.safe,
		"sites": chunk.sites.duplicate(true),
		"pois": chunk.pois.duplicate(true),
		"monsters": chunk.monsters.duplicate(true),
		"structures": chunk.structures.duplicate(true),
		"cuts": chunk.tree_cuts.keys(),
	}
