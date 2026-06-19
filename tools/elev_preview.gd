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


# Alpine elevation colour ramp (mirrors world_render_3d._alpine_ramp) for a top-down
# preview that approximates the smooth 3D look.
const MEADOW := Color(0.42, 0.55, 0.31)
const OLIVE := Color(0.53, 0.55, 0.33)
const DIRT := Color(0.60, 0.47, 0.30)
const ROCK := Color(0.60, 0.53, 0.47)
const ROCK_HI := Color(0.74, 0.73, 0.76)
const SNOW := Color(0.93, 0.95, 0.99)


func _ramp(e: float) -> Color:
	if e < 6.0:
		return MEADOW
	elif e < 12.0:
		return MEADOW.lerp(OLIVE, smoothstep(6.0, 12.0, e))
	elif e < 19.0:
		return OLIVE.lerp(DIRT, smoothstep(12.0, 19.0, e))
	elif e < 28.0:
		return DIRT.lerp(ROCK, smoothstep(19.0, 28.0, e))
	return ROCK.lerp(ROCK_HI, smoothstep(28.0, 42.0, e))


func _render(clf: RefCounted, name: String, center: Vector2i, out_dir: String) -> void:
	var n := REGION
	var ox := center.x - n / 2
	var oy := center.y - n / 2
	var elev := PackedFloat32Array()
	elev.resize(n * n)
	var snow := PackedFloat32Array()
	snow.resize(n * n)
	for j: int in n:
		for i: int in n:
			var e: int = clf.elevation_steps(float(ox + i), float(oy + j))
			elev[j * n + i] = float(e)
			snow[j * n + i] = clf.snow01(float(ox + i), float(oy + j), e)
	# Hillshade: light from the NW, exaggerated so steep slopes read as relief.
	var light := Vector3(-0.5, 1.4, -0.5).normalized()
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for j: int in n:
		for i: int in n:
			var e: float = elev[j * n + i]
			if e <= 0.0:
				img.set_pixel(i, j, Color(0.20, 0.40, 0.46))   # lowland / sea
				continue
			var col := _ramp(e) if snow[j * n + i] < 0.5 else SNOW
			# Slope shading from elevation gradient (in step units, ~ELEV_H world height).
			var el: float = elev[j * n + maxi(i - 1, 0)]
			var er: float = elev[j * n + mini(i + 1, n - 1)]
			var eu: float = elev[maxi(j - 1, 0) * n + i]
			var ed: float = elev[mini(j + 1, n - 1) * n + i]
			var nrm := Vector3(-(er - el) * 0.25, 2.0, -(ed - eu) * 0.25).normalized()
			var sh := clampf(nrm.dot(light), 0.0, 1.0)
			sh = 0.55 + 0.55 * sh
			img.set_pixel(i, j, Color(col.r * sh, col.g * sh, col.b * sh).clamp())
	img.save_png(out_dir.path_join(name + ".png"))
