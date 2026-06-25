extends Node
## Diagnostic: ASCII-dump the actual generated tile types over a coastal window so we
## can SEE what the "coastal ponds" really are. Symbols:
##   '#' deep_water   '~' water   '.' shallow   ':' sand/beach   ' ' land   '+' other
## Run: Godot --headless --path . res://tools/coast_diag.tscn

const WG := preload("res://scripts/worldgen/wg.gd")


func _sym(name: String) -> String:
	match name:
		"deep_water": return "#"
		"water": return "~"
		"shallow": return "."
		"sand", "sand_dune", "desert_sand", "desert_dune": return ":"
		_: return " "


func _ready() -> void:
	var gen: RefCounted = WorldGen.generator
	# Window in tile space straddling the west coast near spawn.
	var x0 := -46
	var x1 := 10
	var y0 := -8
	var y1 := 30
	# Generate the chunks we need into a lookup.
	var chunks := {}
	var c0 := WG.tile_to_chunk(Vector2i(x0, y0))
	var c1 := WG.tile_to_chunk(Vector2i(x1, y1))
	for cy: int in range(c0.y, c1.y + 1):
		for cx: int in range(c0.x, c1.x + 1):
			chunks[Vector2i(cx, cy)] = gen.generate(0, cx, cy)
	var counts := {}
	var lines: Array = []
	for ty: int in range(y0, y1 + 1):
		var row := ""
		for tx: int in range(x0, x1 + 1):
			var ck := WG.tile_to_chunk(Vector2i(tx, ty))
			var chunk: RefCounted = chunks.get(ck)
			if chunk == null:
				row += "?"
				continue
			var lx := tx - ck.x * WG.CHUNK_TILES
			var ly := ty - ck.y * WG.CHUNK_TILES
			var tid: int = chunk.tile_id(lx, ly)
			var nm := str(WorldGen.reg.tile_order[tid])
			counts[nm] = int(counts.get(nm, 0)) + 1
			row += _sym(nm)
		lines.append(row)
	print("[coast_diag] window tx[%d..%d] ty[%d..%d]  ('#'deep '~'water '.'shallow ':'sand ' 'land)" % [x0, x1, y0, y1])
	for l: String in lines:
		print("  " + l)
	print("[coast_diag] tile counts: ", counts)

	# Profile one transition row: coast_sink, parent biome, tile — to see what drives each tile.
	var cls: RefCounted = WorldGen.generator.classifier
	var py := -7
	print("[coast_diag] profile row ty=%d  (tx: coast_sink parent/tile)" % py)
	var s := ""
	for tx: int in range(-14, 8):
		var cs: float = cls.coast_sink(float(tx), float(py))
		var pidx: int = cls.parent_biome_idx(float(tx), float(py))
		var pid := str(WorldGen.reg.biomes[pidx]["id"]) if pidx >= 0 and pidx < WorldGen.reg.biomes.size() else "?"
		var ck := WG.tile_to_chunk(Vector2i(tx, py))
		var chunk: RefCounted = chunks.get(ck)
		var nm := "?"
		if chunk != null:
			nm = str(WorldGen.reg.tile_order[chunk.tile_id(tx - ck.x * WG.CHUNK_TILES, py - ck.y * WG.CHUNK_TILES)])
		s += "%d:%.2f/%s/%s  " % [tx, cs, pid.substr(0, 4), nm.substr(0, 4)]
	print("  " + s)
	get_tree().quit(0)
