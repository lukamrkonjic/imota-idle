extends Node
## coast_preview — FAST landmass-shape iteration. Renders the parent-biome /
## land-sea map at half resolution using only the BiomeClassifier (no chunk
## assembly, no POIs, no smoothing), so a full continent preview takes a couple
## of seconds instead of a 90s bake. Use it to tune the coastline, then run the
## real bake (tools/world_bake.tscn) once the shape looks right.
##
##   godot --headless --path . res://tools/coast_preview.tscn
## Writes res://data/world/baked/aldreth_preview.png

const WG := preload("res://scripts/worldgen/wg.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")

const STEP := 2   # tiles per pixel (2 => 640x640 for an 80-chunk world)

const PALETTE := {
	"ocean": Color8(40, 58, 92),
	"beach": Color8(214, 196, 142),
	"plains": Color8(96, 140, 64),
	"wheatfield": Color8(196, 168, 78),
	"flower_meadow": Color8(140, 178, 96),
	"forest": Color8(54, 96, 52),
	"dense_forest": Color8(32, 66, 36),
	"grove": Color8(96, 150, 80),
	"boreal_forest": Color8(60, 104, 92),
	"rocky_hills": Color8(126, 124, 120),
	"heather_moor": Color8(132, 96, 140),
	"tundra": Color8(210, 216, 220),
	"snowdrift": Color8(236, 240, 246),
	"alpine": Color8(214, 220, 230),
	"lichen_field": Color8(150, 166, 150),
	"desert": Color8(214, 184, 120),
	"cactus_plain": Color8(196, 174, 112),
	"oasis": Color8(80, 150, 110),
	"salt_pan": Color8(228, 224, 214),
	"savanna": Color8(176, 160, 86),
	"savanna_scrub": Color8(150, 140, 80),
	"badlands": Color8(168, 104, 72),
	"thorn_waste": Color8(140, 100, 70),
	"swamp": Color8(64, 84, 66),
	"bog": Color8(74, 78, 58),
	"jungle": Color8(38, 92, 46),
	"bamboo_thicket": Color8(120, 150, 60),
	"volcanic": Color8(120, 56, 48),
	"scorched": Color8(80, 60, 56),
	"obsidian_ridge": Color8(44, 40, 48),
	"geyser_field": Color8(150, 160, 170),
	"dead_forest": Color8(96, 92, 84),
	"corrupted_bog": Color8(86, 64, 96),
}


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true

	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("coast_preview: active spec is not a finite world.")
		get_tree().quit(1)
		return

	var cls: RefCounted = BiomeClassifier.new()
	cls.setup(reg, WorldGen.store.world_seed)

	var b: Rect2i = spec.bounds
	var min_tx: int = b.position.x * WG.CHUNK_TILES
	var min_ty: int = b.position.y * WG.CHUNK_TILES
	var w: int = b.size.x * WG.CHUNK_TILES / STEP
	var h: int = b.size.y * WG.CHUNK_TILES / STEP
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)

	var t0 := Time.get_ticks_msec()
	for py: int in h:
		for px: int in w:
			var tx: float = float(min_tx + px * STEP)
			var ty: float = float(min_ty + py * STEP)
			var id: String = cls.map_gen.parent_id_at(tx, ty)
			img.set_pixel(px, py, PALETTE.get(id, Color8(255, 0, 255)))

	var out := "res://data/world/baked/" + str(spec.id) + "_preview.png"
	img.save_png(out)
	print(JSON.stringify({
		"tool": "coast_preview",
		"png": ProjectSettings.globalize_path(out),
		"px": [w, h],
		"took_s": float(Time.get_ticks_msec() - t0) / 1000.0,
	}))
	get_tree().quit(0)
