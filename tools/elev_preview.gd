extends Node
## elev_preview — FAST top-down topographic preview of the mountain elevation field,
## for iterating on terrain generation WITHOUT a full world bake. Samples
## BiomeClassifier.elevation_steps() directly (noise only, no chunk assembly) over a few
## regions and writes color-ramped PNGs with cliff edges (|Δelev| > MAX_CLIMB_STEP) marked
## red, so contour readability and cliff placement are visible in seconds.
##
## Run:  godot --headless --path . res://tools/elev_preview.tscn -- --out=/tmp/elevprev/

const WG := preload("res://scripts/worldgen/wg.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")

const REGION := 360   # tiles per side sampled per preview


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	var out_dir := "/tmp/elevprev/"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var clf: RefCounted = BiomeClassifier.new()
	clf.setup(WorldGen.reg, WorldGen.store.world_seed)

	# Centre tiles of the showcase mountain shots (chunk * 16 + 8).
	var spots := {
		"north_peaks": Vector2i(-3 * 16 + 8, -24 * 16 + 8),
		"north_peaks2": Vector2i(6 * 16 + 8, -22 * 16 + 8),
		"grand_north": Vector2i(0 * 16 + 8, -32 * 16 + 8),
		"grand_north2": Vector2i(-10 * 16 + 8, -30 * 16 + 8),
	}
	var t0 := Time.get_ticks_msec()
	for name: String in spots:
		_render(clf, name, spots[name], out_dir)
	print("=== ELEV PREVIEW ===")
	print(JSON.stringify({"out": ProjectSettings.globalize_path(out_dir),
		"regions": spots.keys(), "took_s": float(Time.get_ticks_msec() - t0) / 1000.0}))
	get_tree().quit(0)


func _render(clf: RefCounted, name: String, center: Vector2i, out_dir: String) -> void:
	var n := REGION
	var ox := center.x - n / 2
	var oy := center.y - n / 2
	var elev := PackedInt32Array()
	elev.resize(n * n)
	var emax := 1
	for j: int in n:
		for i: int in n:
			var e: int = clf.elevation_steps(float(ox + i), float(oy + j))
			elev[j * n + i] = e
			emax = maxi(emax, e)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var low := Color(0.30, 0.55, 0.32)    # foothill green
	var high := Color(0.86, 0.82, 0.74)   # bare rock
	for j: int in n:
		for i: int in n:
			var e: int = elev[j * n + i]
			var col: Color
			if e <= 0:
				col = Color(0.20, 0.40, 0.46)   # lowland / sea-ish
			else:
				col = low.lerp(high, clampf(float(e) / float(emax), 0.0, 1.0))
				# Contour banding: darken every 4th step boundary for a topographic read.
				if e % 4 == 0:
					col = col.darkened(0.12)
			# Cliff edge (unwalkable step) to the right/below neighbour -> red.
			var cliff := false
			if i + 1 < n and absi(elev[j * n + i + 1] - e) > WG.MAX_CLIMB_STEP:
				cliff = true
			if j + 1 < n and absi(elev[(j + 1) * n + i] - e) > WG.MAX_CLIMB_STEP:
				cliff = true
			if cliff:
				col = Color(0.85, 0.12, 0.10)
			img.set_pixel(i, j, col)
	img.save_png(out_dir.path_join(name + ".png"))
