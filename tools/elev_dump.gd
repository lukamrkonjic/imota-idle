extends Node
## elev_dump — prints the baked elevation grid for a tile region so we can see the
## mountain shape (data, not the iso render). Digit per tile; '~' = water.
##   godot --path . res://tools/elev_dump.tscn

const WG := preload("res://scripts/worldgen/wg.gd")


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	await get_tree().process_frame
	_dump(-330, -255, 95, 135)
	_verify_pick(-330, -255, 95, 135)
	get_tree().quit(0)


## For every raised tile in the region, compute where its top renders and confirm
## tile_at_screen() resolves to a RAISED tile (the block you point at) instead of
## the flat elevation-0 tile in front of it (the old bug).
func _verify_pick(tx0: int, tx1: int, ty0: int, ty1: int) -> void:
	var raised := 0
	var hit := 0
	var exact := 0
	for ty: int in range(ty0, ty1 + 1):
		for tx: int in range(tx0, tx1 + 1):
			var t := Vector2i(tx, ty)
			var e: int = WorldGen._tile_elev(0, t)
			if e < 1 or e > WG.MAX_REACHABLE_ELEV:
				continue
			raised += 1
			var top := WG.tile_to_world(tx, ty) - Vector2(0.0, float(e) * WG.ELEV_STEP_PX)
			var picked: Vector2i = WorldGen.tile_at_screen(top, 0)
			if WorldGen._tile_elev(0, picked) >= 1:
				hit += 1
			if picked == t:
				exact += 1
	print("\ntile_at_screen: of %d raised tiles, %d resolve to a raised tile (%d exact)" % [
		raised, hit, exact])


func _ch(e: int) -> String:
	# hex 0-15, then X for impassable peaks (> MAX_REACHABLE_ELEV).
	if e > WG.MAX_REACHABLE_ELEV:
		return "X"
	return "%x" % e


func _dump(tx0: int, tx1: int, ty0: int, ty1: int) -> void:
	print("\n=== elevation grid  x[%d..%d]  y[%d..%d]  (digit=elev steps, ~=water, # >9) ===" % [tx0, tx1, ty0, ty1])
	# Column header (tens then ones of x).
	for ty: int in range(ty0, ty1 + 1):
		var row := "%4d  " % ty
		for tx: int in range(tx0, tx1 + 1):
			var wp := WG.tile_to_world(tx, ty)
			var c := WG.tile_to_chunk(Vector2i(tx, ty))
			var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
			var lx: int = tx - c.x * WG.CHUNK_TILES
			var ly: int = ty - c.y * WG.CHUNK_TILES
			var td: Dictionary = WorldGen.reg.tile_def(chunk.tile_id(lx, ly))
			if bool(td.get("water", false)):
				row += "~"
				continue
			var e := 0
			if chunk.elev.size() > 0:
				e = chunk.elev[ly * WG.CHUNK_TILES + lx]
			row += _ch(e)
		print(row)
