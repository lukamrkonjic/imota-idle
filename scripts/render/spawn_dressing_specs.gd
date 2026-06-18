extends RefCounted
## Data-only layout for the cozy "A Short Hike" spawn camp: every dressing piece
## (paths, cabin/lodge, campfire, benches, autumn trees, conifer backdrop, cliffs,
## fences, flowers, clutter) as {kind, off (tile), angle, scale, lift, variant}.
## Extracted out of world_render_3d.gd so the renderer consumes a flat spec list and
## this stays a pure, designer-tweakable data table.

static func specs() -> Array:
	var specs := []

	# --- Paths: two soft trails meeting at the camp, then out to the trailhead.
	var path := [
		# trailhead coming in from the front-left, curving up to the cabin door
		Vector2i(-2, 5), Vector2i(-2, 4), Vector2i(-3, 3), Vector2i(-3, 2),
		Vector2i(-4, 1), Vector2i(-4, 0), Vector2i(-4, -1),
		# spur across the clearing to the lodge on the right
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(3, -1), Vector2i(4, -2)]
	for i: int in path.size():
		specs.append({"kind": "hike_path", "off": path[i], "angle": -0.55 + float(i % 5) * 0.14, "scale": 0.92 + float(i % 4) * 0.06, "lift": 0.035, "variant": i})

	# --- Hero structures + the open central clearing (campfire & seating).
	specs.append_array([
		{"kind": "hike_cabin", "off": Vector2i(-4, -2), "angle": -0.58, "scale": 1.0, "variant": 0},
		{"kind": "hike_lodge", "off": Vector2i(4, -2), "angle": -0.72, "scale": 0.96, "variant": 1},
		{"kind": "hike_campfire", "off": Vector2i(-1, 0), "angle": 0.2, "scale": 1.3, "lift": 0.04, "variant": 1},
		{"kind": "hike_sign", "off": Vector2i(-2, 4), "angle": -0.35, "scale": 1.08, "variant": 0},
		{"kind": "hike_bench", "off": Vector2i(0, 1), "angle": -0.7, "scale": 1.12, "variant": 0},
		{"kind": "hike_bench", "off": Vector2i(-2, -1), "angle": 0.55, "scale": 1.05, "variant": 1},
		{"kind": "hike_log", "off": Vector2i(1, 1), "angle": 0.5, "scale": 1.3, "variant": 1},
		{"kind": "hike_log", "off": Vector2i(-2, 2), "angle": -0.25, "scale": 1.0, "variant": 2},
		{"kind": "hike_stump", "off": Vector2i(2, 1), "angle": 0.0, "scale": 1.05, "variant": 0},
		{"kind": "hike_stump", "off": Vector2i(-5, 1), "angle": 0.0, "scale": 0.95, "variant": 1},
		# a teal hiking pool tucked into the front-left, foam-edged by the terrain
		{"kind": "hike_pool", "off": Vector2i(-6, 5), "angle": 0.24, "scale": 1.8, "lift": 0.02, "variant": 0},
	])

	# --- Boulders: a few big warm slabs bedding the camp into the slope.
	for b: Dictionary in [
			{"off": Vector2i(3, 2), "angle": 0.4, "scale": 1.2},
			{"off": Vector2i(-6, -1), "angle": -0.2, "scale": 1.05},
			{"off": Vector2i(5, 1), "angle": 0.9, "scale": 0.95},
			{"off": Vector2i(-5, 3), "angle": 0.1, "scale": 0.85}]:
		specs.append({"kind": "hike_boulder", "off": b["off"], "angle": b["angle"], "scale": b["scale"], "variant": int(b["off"].x) & 1})

	# --- Autumn color band: the vivid red/orange/gold canopies ringing the bowl
	#     (mid radius). Kept out of the near-foreground so they frame, not cover.
	var leaves := [
		Vector2i(-7, 2), Vector2i(-7, 0), Vector2i(-6, -3), Vector2i(-4, -4),
		Vector2i(-1, -4), Vector2i(2, -4), Vector2i(5, -4), Vector2i(7, -2),
		Vector2i(7, 0), Vector2i(6, 2), Vector2i(-8, 4), Vector2i(8, 3),
		Vector2i(-3, -3), Vector2i(3, -3)]
	for i: int in leaves.size():
		specs.append({"kind": "hike_deciduous", "off": leaves[i], "angle": float(i) * 0.29, "scale": 0.95 + float(i % 4) * 0.13, "variant": i})

	# --- Conifer backdrop: a dense pine wall behind and along the wings (image 2).
	var conifers := [
		Vector2i(-10, -3), Vector2i(-9, -5), Vector2i(-8, -7), Vector2i(-6, -6),
		Vector2i(-5, -5), Vector2i(-3, -6), Vector2i(-1, -7), Vector2i(1, -7),
		Vector2i(3, -6), Vector2i(5, -6), Vector2i(6, -5), Vector2i(8, -5),
		Vector2i(9, -3), Vector2i(10, -1), Vector2i(9, 1), Vector2i(-9, 1),
		Vector2i(-10, 3), Vector2i(10, 2), Vector2i(-7, -8), Vector2i(7, -7)]
	for i: int in conifers.size():
		specs.append({"kind": "hike_conifer", "off": conifers[i], "angle": float(i) * 0.37, "scale": 1.12 + float(i % 4) * 0.12, "variant": i})

	# --- Layered cliff back-wall: warm stone slabs across the deep background.
	var cliffs := [
		Vector2i(-10, -8), Vector2i(-8, -9), Vector2i(-6, -9), Vector2i(-4, -9),
		Vector2i(-2, -10), Vector2i(0, -10), Vector2i(2, -9), Vector2i(4, -9),
		Vector2i(6, -8), Vector2i(8, -8), Vector2i(9, -6), Vector2i(-10, -6),
		Vector2i(-11, -3), Vector2i(10, -4)]
	for i: int in cliffs.size():
		specs.append({"kind": "hike_cliff", "off": cliffs[i], "angle": 0.08 + float(i) * 0.14, "scale": 1.3 - float(i % 3) * 0.08, "variant": i})

	# --- Split-rail fence arcing around the front edge of the clearing.
	var fences := [
		{"off": Vector2i(-4, 4), "angle": 0.55}, {"off": Vector2i(-2, 5), "angle": -0.12},
		{"off": Vector2i(0, 5), "angle": 0.0}, {"off": Vector2i(2, 4), "angle": 0.2},
		{"off": Vector2i(4, 3), "angle": 0.7}, {"off": Vector2i(5, 2), "angle": 0.88},
		{"off": Vector2i(-6, 2), "angle": 0.78}, {"off": Vector2i(-6, 0), "angle": 0.88}]
	for i: int in fences.size():
		var f: Dictionary = fences[i]
		specs.append({"kind": "hike_fence", "off": f["off"], "angle": f["angle"], "scale": 1.08, "variant": i})

	# --- Flower beds and mushrooms freshening the clearing edges.
	var flowers := [
		Vector2i(-3, 1), Vector2i(-1, 2), Vector2i(0, 3), Vector2i(2, 2),
		Vector2i(-4, 3), Vector2i(1, 3), Vector2i(3, 1), Vector2i(-5, 0),
		Vector2i(-3, 3), Vector2i(2, 3), Vector2i(-2, 3), Vector2i(4, 2)]
	for i: int in flowers.size():
		specs.append({"kind": "hike_flower", "off": flowers[i], "angle": float(i) * 0.2, "scale": 1.0 + float(i % 2) * 0.2, "lift": 0.02, "variant": i})
	specs.append_array([
		{"kind": "hike_mushroom", "off": Vector2i(-5, 4), "angle": 0.2, "scale": 1.05, "variant": 0},
		{"kind": "hike_mushroom", "off": Vector2i(3, 3), "angle": -0.3, "scale": 0.92, "variant": 1},
	])

	# --- Scattered ground clutter (leaf litter, grass tufts, pebbles), thinned
	#     out of the central clearing so the camp stays readable.
	var clutter := ["hike_leaf_litter", "hike_grass", "hike_pebbles", "hike_grass", "hike_leaf_litter", "hike_mushroom"]
	for i: int in range(58):
		var ox := int((i * 5) % 21) - 10
		var oy := int((i * 7 + int(i / 3)) % 19) - 9
		if absi(ox) <= 2 and absi(oy) <= 2:
			continue
		var kind: String = clutter[i % clutter.size()]
		var scale := 0.72 + float((i * 3) % 5) * 0.09
		specs.append({"kind": kind, "off": Vector2i(ox, oy), "angle": float(i) * 0.41, "scale": scale, "lift": 0.018, "variant": i})
	return specs
