extends Node
## biome_shuffle — explore DIFFERENT biome dispositions on the SAME authored
## coastline. Keeps the land mask + region positions fixed and reassigns which
## biome each region anchors, then renders the real climate model so you see what
## would actually bake. Great for "what if the desert were in the north?".
##
## Contact sheet of variants (default 6) — one image, many dispositions:
##   godot --headless --path . res://tools/biome_shuffle.tscn
##   godot --headless --path . res://tools/biome_shuffle.tscn -- --variants=9 --mode=random
##   -> data/world/masks/<id>_shuffle_sheet.png   (cells are seeds base..base+N-1)
##
## One bigger single variant:
##   godot --headless --path . res://tools/biome_shuffle.tscn -- --seed=4
##   -> data/world/masks/<id>_shuffle_preview.png
##
## Commit a disposition you like to the worldspec (then coast_preview + bake):
##   godot --headless --path . res://tools/biome_shuffle.tscn -- --apply --seed=4
##
## Modes:  permute (default) = shuffle the EXISTING biomes among regions (same
##         variety, new layout);  random = draw each region from a biome pool.

const WG := preload("res://scripts/worldgen/wg.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")

const SHEET_STEP := 6     # tiles/px in contact-sheet cells (small + fast)
const SINGLE_STEP := 3    # tiles/px for a single --seed preview
const COLS := 3
const BASE_SEED := 1

# Region ids kept at their authored biome (spawn stays safe plains, etc.).
const LOCKED := ["greenhollow"]
# Pool drawn from in --mode=random (parent biomes only).
const POOL := ["plains", "forest", "dense_forest", "boreal_forest", "wheatfield",
	"flower_meadow", "grove", "savanna", "rocky_hills", "heather_moor", "tundra",
	"desert", "swamp", "bog", "jungle", "volcanic", "badlands"]

const PALETTE := {
	"ocean": Color8(40, 58, 92), "beach": Color8(214, 196, 142),
	"plains": Color8(96, 140, 64), "wheatfield": Color8(196, 168, 78),
	"flower_meadow": Color8(140, 178, 96), "forest": Color8(54, 96, 52),
	"dense_forest": Color8(32, 66, 36), "grove": Color8(96, 150, 80),
	"boreal_forest": Color8(60, 104, 92), "rocky_hills": Color8(126, 124, 120),
	"heather_moor": Color8(150, 96, 160), "tundra": Color8(210, 216, 220),
	"snowdrift": Color8(236, 240, 246), "alpine": Color8(214, 220, 230),
	"desert": Color8(214, 184, 120), "cactus_plain": Color8(196, 174, 112),
	"oasis": Color8(80, 180, 120), "salt_pan": Color8(236, 232, 222),
	"savanna": Color8(190, 168, 80), "savanna_scrub": Color8(150, 140, 80),
	"badlands": Color8(178, 104, 72), "swamp": Color8(64, 96, 66),
	"bog": Color8(84, 84, 56), "jungle": Color8(38, 110, 50),
	"volcanic": Color8(150, 56, 44), "geyser_field": Color8(150, 170, 180),
	"dead_forest": Color8(110, 100, 90), "corrupted_bog": Color8(110, 64, 120),
}


func _ready() -> void:
	if _has_autoload("SaveManager"): SaveManager.suppress = true
	if _has_autoload("GameSettings"): GameSettings.suppress = true

	var args := OS.get_cmdline_user_args()
	var mode := _arg(args, "--mode=", "permute")
	var apply := args.has("--apply")
	var single_seed := int(_arg(args, "--seed=", "-1"))
	var variants := int(_arg(args, "--variants=", "6"))

	var reg: RefCounted = WorldGen.reg
	var spec: RefCounted = reg.spec
	if not spec.active or not spec.finite:
		push_error("biome_shuffle: active spec is not a finite world."); get_tree().quit(1); return

	# snapshot the authored biomes so every variant shuffles from the same base
	var originals := {}
	for r: Dictionary in spec.regions:
		originals[str(r["id"])] = str(r["biome"])

	if apply:
		_apply(spec, originals, single_seed if single_seed >= 0 else BASE_SEED, mode)
		return

	var cls: RefCounted = BiomeClassifier.new()
	cls.setup(reg, WorldGen.store.world_seed)   # builds the land SDF ONCE
	if not cls.has_land_mask():
		push_error("biome_shuffle: no land mask for '%s' — run world_trace first." % spec.id)
		get_tree().quit(1); return

	var t0 := Time.get_ticks_msec()
	if single_seed >= 0:
		_render_single(cls, spec, originals, single_seed, mode)
	else:
		_render_sheet(cls, spec, originals, variants, mode)
	# leave the worldspec untouched (preview only)
	_restore(spec, originals)
	print("  took %.1fs" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit(0)


# --- rendering ----------------------------------------------------------------

func _render_sheet(cls: RefCounted, spec: RefCounted, originals: Dictionary, n: int, mode: String) -> void:
	var b: Rect2i = spec.bounds
	var cw := b.size.x * WG.CHUNK_TILES / SHEET_STEP
	var ch := b.size.y * WG.CHUNK_TILES / SHEET_STEP
	var rows := int(ceil(float(n) / float(COLS)))
	var gap := 4
	var sheet := Image.create_empty(COLS * cw + (COLS + 1) * gap, rows * ch + (rows + 1) * gap, false, Image.FORMAT_RGB8)
	sheet.fill(Color8(12, 20, 34))
	var legend := []
	for i: int in n:
		var seed := BASE_SEED + i
		_apply_shuffle(spec, originals, seed, mode)
		cls.map_gen.reset_region_cache()
		var col := i % COLS
		var row := i / COLS
		var ox := gap + col * (cw + gap)
		var oy := gap + row * (ch + gap)
		_render_cell(sheet, cls, b, ox, oy, cw, ch, SHEET_STEP)
		legend.append("cell[%d,%d] = seed %d" % [row, col, seed])
	var out := "res://data/world/masks/" + str(spec.id) + "_shuffle_sheet.png"
	sheet.save_png(out)
	print(JSON.stringify({"tool": "biome_shuffle", "sheet": ProjectSettings.globalize_path(out),
		"mode": mode, "variants": n, "legend": legend,
		"apply_hint": "pick a seed, then: biome_shuffle.tscn -- --apply --seed=<n>"}, "\t"))


func _render_single(cls: RefCounted, spec: RefCounted, originals: Dictionary, seed: int, mode: String) -> void:
	var b: Rect2i = spec.bounds
	var w := b.size.x * WG.CHUNK_TILES / SINGLE_STEP
	var h := b.size.y * WG.CHUNK_TILES / SINGLE_STEP
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	_apply_shuffle(spec, originals, seed, mode)
	cls.map_gen.reset_region_cache()
	_render_cell(img, cls, b, 0, 0, w, h, SINGLE_STEP)
	var out := "res://data/world/masks/" + str(spec.id) + "_shuffle_preview.png"
	img.save_png(out)
	print(JSON.stringify({"tool": "biome_shuffle", "preview": ProjectSettings.globalize_path(out),
		"mode": mode, "seed": seed}, "\t"))


func _render_cell(img: Image, cls: RefCounted, b: Rect2i, ox: int, oy: int, cw: int, ch: int, step: int) -> void:
	var min_tx := b.position.x * WG.CHUNK_TILES
	var min_ty := b.position.y * WG.CHUNK_TILES
	for py: int in ch:
		for px: int in cw:
			var tx := float(min_tx + px * step)
			var ty := float(min_ty + py * step)
			var id: String = cls.map_gen.parent_id_at(tx, ty)
			img.set_pixel(ox + px, oy + py, PALETTE.get(id, Color8(255, 0, 255)))


# --- shuffle ------------------------------------------------------------------

## Reassign spec.regions[*].biome in place for a seed+mode (from the originals).
func _apply_shuffle(spec: RefCounted, originals: Dictionary, seed: int, mode: String) -> void:
	var assign := _shuffled_assignment(originals, seed, mode)
	for r: Dictionary in spec.regions:
		r["biome"] = assign.get(str(r["id"]), str(r["biome"]))


func _shuffled_assignment(originals: Dictionary, seed: int, mode: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ids: Array = []
	var pool: Array = []
	for rid: String in originals:
		if rid in LOCKED:
			continue
		ids.append(rid)
		pool.append(originals[rid])
	var result := originals.duplicate()
	if mode == "random":
		for rid: String in ids:
			result[rid] = POOL[rng.randi() % POOL.size()]
	else:  # permute: Fisher-Yates over the existing biomes
		for i: int in range(pool.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t: Variant = pool[i]; pool[i] = pool[j]; pool[j] = t
		for k: int in ids.size():
			result[ids[k]] = pool[k]
	return result


func _restore(spec: RefCounted, originals: Dictionary) -> void:
	for r: Dictionary in spec.regions:
		r["biome"] = originals.get(str(r["id"]), str(r["biome"]))


## Write a chosen disposition into the worldspec JSON (regions[*].biome by id).
func _apply(spec: RefCounted, originals: Dictionary, seed: int, mode: String) -> void:
	var assign := _shuffled_assignment(originals, seed, mode)
	var path := "res://data/world/worldspec/" + str(spec.id) + ".json"
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		push_error("biome_shuffle --apply: cannot read %s" % path); get_tree().quit(1); return
	var changed := 0
	for r: Dictionary in (doc as Dictionary).get("regions", []):
		var rid := str(r.get("id", ""))
		if assign.has(rid) and str(r.get("biome", "")) != assign[rid]:
			r["biome"] = assign[rid]
			changed += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print(JSON.stringify({"tool": "biome_shuffle --apply", "world": spec.id, "seed": seed,
		"mode": mode, "regions_changed": changed, "file": path,
		"next": "verify with coast_preview.tscn, then bake with world_bake.tscn"}, "\t"))
	get_tree().quit(0)


# --- helpers ------------------------------------------------------------------

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a: String in args:
		if a.begins_with(key):
			return a.substr(key.length())
	return def


func _has_autoload(name: String) -> bool:
	return Engine.has_singleton(name) or get_node_or_null("/root/" + name) != null
