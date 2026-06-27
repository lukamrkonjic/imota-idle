extends Node
## coord_stability — proves the authored world is IDENTICAL at every absolute tile coordinate.
## Hashes biome/elevation/water/coast sampled on a dense grid over a FIXED ABSOLUTE-tile window
## (the original continent), via the live classifier. Run before and after a canvas expansion: the
## hashes + counts MUST match, proving no existing coordinate shifted.
##   godot --headless --path . res://tools/coord_stability.tscn

const WG := preload("res://scripts/worldgen/wg.gd")

# Original continent in ABSOLUTE tiles (bounds.min(-82,-43)..max(78,47)), fixed forever.
const TX0 := -1312
const TY0 := -688
const TX1 := 1263
const TY1 := 767
const STEP := 7


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	WorldGen.reset(4242)
	var cl: RefCounted = WorldGen.generator.classifier
	var h_biome := 0
	var h_elev := 0
	var h_coast := 0
	var n := 0
	var land := 0
	var water := 0
	var elev_sum := 0
	var tx := TX0
	while tx <= TX1:
		var ty := TY0
		while ty <= TY1:
			var bi: int = cl.mask_biome_idx(float(tx), float(ty))
			var el: int = cl.mask_elev_steps(float(tx), float(ty))
			var wt: bool = cl.mask_is_water(float(tx), float(ty))
			var cs: int = int(round(cl.coast_sink(float(tx), float(ty)) * 1000.0))
			h_biome = hash([h_biome, bi])
			h_elev = hash([h_elev, el])
			h_coast = hash([h_coast, cs])
			elev_sum += el
			if wt:
				water += 1
			else:
				land += 1
			n += 1
			ty += STEP
		tx += STEP
	var out := {
		"samples": n, "land": land, "water": water, "elev_sum": elev_sum,
		"h_biome": h_biome, "h_elev": h_elev, "h_coast": h_coast
	}
	print("=== COORD STABILITY ===")
	print(JSON.stringify(out))
	get_tree().quit()
