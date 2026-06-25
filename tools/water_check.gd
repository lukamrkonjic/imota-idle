extends Node
## CI gate for inland-water hygiene. Scans the LIVE runtime classifier across the
## whole authored mask and asserts two invariants that, when violated, cause the
## "random ponds / water on raised rock" bugs:
##   1. NO water tile sits on raised elevation (mask_elev_steps > RAISED_STEPS) —
##      such tiles get rock-fragmented at bake ("foam indented in water").
##   2. NO stray single-tile water island (a water tile with no water neighbour) —
##      these are despeckle escapees that read as random ponds.
## Exits non-zero on any violation so it can run in CI. Run:
##   Godot --headless --path . res://tools/water_check.tscn

const WG := preload("res://scripts/worldgen/wg.gd")

const RAISED_STEPS := 3   # mirrors clean_water_mask.py / _place_mountains shoulder cut


func _ready() -> void:
	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	var cls: RefCounted = WorldGen.generator.classifier
	print("[water_check] river_mask=%s elev_mask=%s" % [cls.has_river_mask(), cls.has_elev_mask()])
	if not cls.has_river_mask():
		print("[water_check] no river mask on active spec — nothing to check.")
		get_tree().quit(0)
		return

	var b: Rect2i = spec.bounds
	var min_tx := b.position.x * WG.CHUNK_TILES
	var min_ty := b.position.y * WG.CHUNK_TILES
	var max_tx := (b.position.x + b.size.x) * WG.CHUNK_TILES
	var max_ty := (b.position.y + b.size.y) * WG.CHUNK_TILES

	var water := 0
	var raised := 0
	var stray := 0
	var first_raised := Vector2i.ZERO
	var first_stray := Vector2i.ZERO
	for ty: int in range(min_ty, max_ty):
		var fty := float(ty)
		for tx: int in range(min_tx, max_tx):
			var ftx := float(tx)
			if not cls.mask_is_water(ftx, fty):
				continue
			water += 1
			if cls.mask_elev_steps(ftx, fty) > RAISED_STEPS:
				if raised == 0:
					first_raised = Vector2i(tx, ty)
				raised += 1
			# Stray = no water in the 8-neighbourhood (one mask pixel ~1.5 tiles, so a
			# genuine body always has neighbours; an island here is a despeckle escapee).
			var has_neighbour := false
			for off: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
					Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]:
				if cls.mask_is_water(ftx + off.x, fty + off.y):
					has_neighbour = true
					break
			if not has_neighbour:
				if stray == 0:
					first_stray = Vector2i(tx, ty)
				stray += 1

	print("[water_check] water tiles=%d  on-raised-elev=%d  stray-islands=%d" % [water, raised, stray])
	var ok := true
	if raised > 0:
		print("  FAIL: %d water tiles on raised elevation (e.g. %s). Run clean_water_mask.py to carve elev flat." % [raised, first_raised])
		ok = false
	if stray > 0:
		print("  FAIL: %d stray single-tile water islands (e.g. %s). Lower clean_water_mask.py --min or re-author." % [stray, first_stray])
		ok = false
	if ok:
		print("[water_check] PASS")
	get_tree().quit(0 if ok else 1)
