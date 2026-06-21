extends Node
## Fast end-to-end check of the authored-mask pipeline: samples the LIVE runtime
## classifier (biomes + rivers + elevation) across the whole world and writes a
## colour map — no chunk bake. Run:
##   godot --headless --path . res://tools/mask_check.tscn

const WG := preload("res://scripts/worldgen/wg.gd")

const BIOME_COL := {
	"ocean": Color8(103,120,151), "beach": Color8(205,194,158),
	"plains": Color8(140,150,90), "wheatfield": Color8(196,168,78),
	"flower_meadow": Color8(150,120,150), "forest": Color8(49,81,53),
	"dense_forest": Color8(32,66,36), "grove": Color8(96,150,80),
	"boreal_forest": Color8(40,70,55), "rocky_hills": Color8(150,146,140),
	"heather_moor": Color8(150,96,160), "tundra": Color8(180,188,180),
	"snowdrift": Color8(236,240,246), "alpine": Color8(232,236,237),
	"lichen_field": Color8(170,180,170),
	"desert": Color8(195,150,90), "cactus_plain": Color8(196,174,112),
	"oasis": Color8(80,180,120), "salt_pan": Color8(212,210,196),
	"savanna": Color8(175,160,95), "savanna_scrub": Color8(150,140,80),
	"badlands": Color8(150,95,60), "thorn_waste": Color8(130,90,70),
	"swamp": Color8(86,104,70), "marsh_pool": Color8(70,110,90),
	"bog": Color8(70,80,55), "corrupted_bog": Color8(60,55,70),
	"jungle": Color8(60,96,46), "bamboo_thicket": Color8(110,150,70),
	"volcanic": Color8(60,45,42), "scorched": Color8(80,55,45),
	"obsidian_ridge": Color8(40,35,40), "geyser_field": Color8(120,120,110),
	"rocky_clearing": Color8(140,135,120), "dead_forest": Color8(90,85,70),
}


func _ready() -> void:
	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	var cls: RefCounted = WorldGen.generator.classifier
	print("[mask_check] biome_mask=%s elev_mask=%s river_mask=%s" % [
		cls.has_biome_mask(), cls.has_elev_mask(), cls.has_river_mask()])
	var b: Rect2i = spec.bounds
	var min_tx := float(b.position.x) * WG.CHUNK_TILES
	var min_ty := float(b.position.y) * WG.CHUNK_TILES
	var tw := float(b.size.x) * WG.CHUNK_TILES
	var th := float(b.size.y) * WG.CHUNK_TILES
	var OW := 836
	var OH := int(round(836.0 * th / tw))
	var img := Image.create(OW, OH, false, Image.FORMAT_RGB8)
	var unknown := {}
	for oy: int in OH:
		for ox: int in OW:
			var tx := min_tx + (float(ox) + 0.5) / float(OW) * tw
			var ty := min_ty + (float(oy) + 0.5) / float(OH) * th
			var bi: int = cls.biome_idx(tx, ty)
			var id := str(reg.biomes[bi]["id"])
			if id == "ocean":
				img.set_pixel(ox, oy, Color8(103,120,151)); continue
			if cls.river_at(tx, ty, 0.5) == 2:
				img.set_pixel(ox, oy, Color8(70,120,190)); continue
			var col: Color = BIOME_COL.get(id, Color8(255,0,255))
			if not BIOME_COL.has(id):
				unknown[id] = true
			var lvl: int = cls.mountain_level(tx, ty)
			if lvl >= 3:
				col = Color8(245,245,248)            # snow peak
			elif lvl >= 2:
				col = col.darkened(0.45)             # rock peak
			elif lvl >= 1:
				col = col.darkened(0.22)             # foothill (renders rocky) — flag it
			img.set_pixel(ox, oy, col)
	var out := "res://data/world/masks/aldreth_runtime_preview.png"
	img.save_png(out)
	print("[mask_check] wrote ", ProjectSettings.globalize_path(out), " size ", OW, "x", OH)
	if not unknown.is_empty():
		print("[mask_check] biomes without preview colour: ", unknown.keys())
	get_tree().quit()
