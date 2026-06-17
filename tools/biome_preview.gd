extends Node
## Fast biome-only overview (~seconds): samples BiomeClassifier across the world
## bounds and writes an approximate-colour PNG to user://biome_preview.png. Use to
## iterate on shape/climate/biome tuning without the ~4-minute full bake.
##   godot --headless --path . tools/biome_preview.tscn -- --seed=1337 --px=360

const WG := preload("res://scripts/worldgen/wg.gd")

const COLORS := {
	"ocean": Color(0.16, 0.22, 0.36), "deep_water": Color(0.11, 0.16, 0.29),
	"beach": Color(0.83, 0.76, 0.53),
	"plains": Color(0.56, 0.66, 0.36), "wheatfield": Color(0.80, 0.74, 0.38),
	"forest": Color(0.25, 0.45, 0.23), "boreal_forest": Color(0.23, 0.40, 0.33),
	"swamp": Color(0.33, 0.42, 0.29), "jungle": Color(0.13, 0.42, 0.19),
	"savanna": Color(0.69, 0.63, 0.33), "desert": Color(0.84, 0.71, 0.43),
	"tundra": Color(0.82, 0.84, 0.83), "rocky_hills": Color(0.52, 0.51, 0.52),
	"volcanic": Color(0.17, 0.12, 0.13), "alpine": Color(0.74, 0.76, 0.80),
	"badlands": Color(0.62, 0.40, 0.30),
	# sub-biomes (tinted near their parent so they read as pockets, not noise)
	"dense_forest": Color(0.18, 0.36, 0.18), "flower_meadow": Color(0.62, 0.62, 0.40),
	"marsh_pool": Color(0.30, 0.44, 0.40), "rocky_clearing": Color(0.58, 0.56, 0.50),
	"oasis": Color(0.30, 0.55, 0.30), "grove": Color(0.30, 0.48, 0.26),
	"bamboo_thicket": Color(0.40, 0.52, 0.24), "snowdrift": Color(0.90, 0.92, 0.93),
	"cactus_plain": Color(0.62, 0.60, 0.34), "salt_pan": Color(0.86, 0.85, 0.80),
	"heather_moor": Color(0.46, 0.40, 0.46), "bog": Color(0.30, 0.34, 0.26),
	"tide_flats": Color(0.66, 0.66, 0.58), "geyser_field": Color(0.60, 0.74, 0.78),
	"savanna_scrub": Color(0.66, 0.60, 0.36), "thorn_waste": Color(0.50, 0.36, 0.30),
	"lichen_field": Color(0.56, 0.60, 0.54),
}


func _ready() -> void:
	SaveManager.suppress = true
	WorldGen.store.suppress = true
	var seed_v := WorldGen.DEFAULT_SEED
	var px := 360
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_v = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--px="):
			px = int(arg.trim_prefix("--px="))
	WorldGen.reset(seed_v)
	var cls: RefCounted = WorldGen.generator.classifier
	var reg: RefCounted = WorldGen.reg
	var b: Rect2i = reg.spec.bounds
	var t0x := float(b.position.x * WG.CHUNK_TILES)
	var t0y := float(b.position.y * WG.CHUNK_TILES)
	var wt := float(b.size.x * WG.CHUNK_TILES)
	var ht := float(b.size.y * WG.CHUNK_TILES)
	var py := int(round(float(px) * ht / wt))
	var img := Image.create(px, py, false, Image.FORMAT_RGB8)
	for yy: int in py:
		for xx: int in px:
			var tx := t0x + float(xx) / float(px) * wt
			var ty := t0y + float(yy) / float(py) * ht
			var idx: int = cls.biome_idx(tx, ty)
			var id := str(reg.biomes[idx]["id"])
			img.set_pixel(xx, yy, COLORS.get(id, Color(1.0, 0.0, 1.0)))
	img.save_png("user://biome_preview.png")
	print("biome_preview saved %dx%d seed=%d" % [px, py, seed_v])
	get_tree().quit(0)
