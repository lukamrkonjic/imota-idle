extends RefCounted
class_name BiomeMapGenerator
## Whittaker field parent biomes + stamped sub-biome micro-regions.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const SMOOTH_PAD := 16
const SMOOTH_PASSES := 2
const MACRO_TILES := 12


var reg: RefCounted
var world_seed: int = 0
var classifier: RefCounted


func setup(p_reg: RefCounted, p_seed: int, p_classifier: RefCounted) -> void:
	reg = p_reg
	world_seed = p_seed
	classifier = p_classifier


func fill_chunk(chunk: RefCounted) -> void:
	var n: int = WG.CHUNK_TILES
	var pad: int = SMOOTH_PAD
	var ox: int = int(chunk.cx) * n - pad
	var oy: int = int(chunk.cy) * n - pad
	var w: int = n + pad * 2
	var h: int = n + pad * 2
	var size: int = w * h

	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(size)

	for ly: int in h:
		for lx: int in w:
			var gtx: int = ox + lx
			var gty: int = oy + ly
			parents[ly * w + lx] = _parent_idx(gtx, gty)

	for _pass: int in SMOOTH_PASSES:
		_smooth_field(parents, w, h)

	for ty: int in n:
		for tx: int in n:
			var gi := (ty + pad) * w + (tx + pad)
			var ci := Chunk.idx(tx, ty)
			var gtx: int = ox + tx + pad
			var gty: int = oy + ty + pad
			var parent: int = parents[gi]
			var sub: int = _sub_idx_for(parent, gtx, gty)
			chunk.parent_biomes_t[ci] = parent
			chunk.sub_biomes_t[ci] = sub
			chunk.biomes_t[ci] = sub if sub != 255 else parent


func parent_idx_at(tx: float, ty: float) -> int:
	return _parent_idx(floori(tx), floori(ty))


func sub_idx_at(tx: float, ty: float) -> int:
	var gtx := floori(tx)
	var gty := floori(ty)
	return _sub_idx_for(_parent_idx(gtx, gty), gtx, gty)


func effective_idx_at(tx: float, ty: float) -> int:
	var sub: int = sub_idx_at(tx, ty)
	if sub != 255:
		return sub
	return parent_idx_at(tx, ty)


func parent_id_at(tx: float, ty: float) -> String:
	return str(reg.biomes[_parent_idx(floori(tx), floori(ty))]["id"])


func effective_id_at(tx: float, ty: float) -> String:
	return str(reg.biomes[effective_idx_at(tx, ty)]["id"])


## Distance-to-border blend weight for render-time edge art (0 = interior).
func border_blend_at(gtx: int, gty: int) -> float:
	var my_idx: int = _parent_idx(gtx, gty)
	if my_idx < 0:
		return 0.0
	var min_dist := 999
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			if dx == 0 and dy == 0:
				continue
			if _parent_idx(gtx + dx, gty + dy) != my_idx:
				min_dist = mini(min_dist, maxi(absi(dx), absi(dy)))
	if min_dist > 3:
		return 0.0
	return 1.0 - float(mini(min_dist, 3) - 1) / 2.0


func transition_at(_gtx: int, _gty: int) -> Dictionary:
	return {}


func transition_near(_gtx: int, _gty: int, _my_idx: int, _parent_at: Callable) -> Dictionary:
	return {}


func _parent_idx(gtx: int, gty: int) -> int:
	return int(reg.biome_index.get(_parent_id(gtx, gty), reg.biomes.size() - 1))


func _parent_id(gtx: int, gty: int) -> String:
	# Biomes follow the noise + continent + progression model everywhere, so the
	# map reads as natural terrain (not square authored regions). WorldSpec
	# regions still provide zone NAMES / level reqs and anchor POIs; they no
	# longer paint biomes. Sub-biome stamping adds micro-variety on top.
	var f: Vector3 = classifier.classify_fields_warped(float(gtx), float(gty))
	return _pick_parent_id(f.x, f.y, f.z, float(gtx), float(gty))


## Geographic biome identity. Each biome has a fixed HOME DIRECTION on the
## continent so the world is describable ("desert is east, snow is north, the
## volcano is the NE corner"), with warped/organic band borders. A safe central
## hub (plains/farmland) sits at the middle; the coast/sea is the rim. Difficulty
## still rises outward (danger01), but placement is directional, not a radial blob.
##
##            tundra/snow (far N)
##              rocky_hills (N)
##   forest (W)   plains hub   savanna→desert (E)
##              swamp (S) · jungle (SE)
##                  ocean (rim)              volcanic = NE corner
func _pick_parent_id(h: float, m: float, t: float, tx: float, ty: float) -> String:
	# In a finite world, ONLY the signed continent/coastline field may create
	# ocean. Treating every low macro-height pocket as sea produced enormous
	# inland ocean biomes on perfectly ordinary valleys and mountain shelves.
	# Inland lakes/rivers are separate tile passes and keep the surrounding biome.
	if reg.spec.active and reg.spec.finite:
		var shore: float = classifier.coast_sink(tx, ty)
		if shore > 0.72:
			return "ocean"
		if shore > 0.34:
			return "beach"
	else:
		if h < 0.30:
			return "ocean"
		if h < 0.345:
			return "beach"
	# Very high ground always reads as mountains, whatever the region underneath.
	if h >= 0.84:
		return "rocky_hills"
	# HAND-AUTHORED layout: the nearest worldspec region paints the biome here. So the
	# whole macro map is designed (not noise bands) — edit data/world/worldspec to move
	# a biome. Borders are warped + radius-weighted so neighbours blend gradually.
	var rb := _region_biome_id(tx, ty)
	return rb if not rb.is_empty() else "plains"


## Additively-weighted Voronoi over the authored regions, with a warped sample point so
## borders meander organically instead of forming clean circles. A region with a larger
## radius claims proportionally more ground; gaps between regions go to the nearest one,
## so adjacent zones transition gradually (no hard biome cliffs).
func _region_biome_id(tx: float, ty: float) -> String:
	var regs: Array = reg.spec.regions
	if regs.is_empty():
		return ""
	var ct := float(WG.CHUNK_TILES)
	# Two-octave warp: a big low-frequency swirl bends whole borders, a mid-frequency
	# term frays them so neighbouring biomes interlock organically (no polygon edges).
	var wx: float = classifier._domain_warp.get_noise_2d(tx * 0.0016, ty * 0.0016) * 440.0 \
		+ classifier._domain_warp.get_noise_2d(tx * 0.0065 + 11.0, ty * 0.0065 + 5.0) * 95.0
	var wy: float = classifier._domain_warp.get_noise_2d(tx * 0.0016 + 71.0, ty * 0.0016 + 29.0) * 440.0 \
		+ classifier._domain_warp.get_noise_2d(tx * 0.0065 + 41.0, ty * 0.0065 + 23.0) * 95.0
	var p := Vector2(tx + wx, ty + wy)
	# Track the TWO nearest regions; near their shared border, a high-frequency noise
	# threshold flips between them so the boundary frays into an interlocking, organic
	# transition instead of a clean polygon edge.
	var best := ""
	var best_score := INF
	var second := ""
	var second_score := INF
	for r: Dictionary in regs:
		var biome := str(r.get("biome", ""))
		if biome.is_empty():
			continue
		var c := Vector2(float(r["cx"]) * ct + ct * 0.5, float(r["cy"]) * ct + ct * 0.5)
		var score := p.distance_to(c) - float(r["radius"]) * ct * 0.55
		if score < best_score:
			second = best
			second_score = best_score
			best = biome
			best_score = score
		elif score < second_score:
			second = biome
			second_score = score
	if not second.is_empty() and second != best:
		const BAND := 150.0   # tiles of frayed overlap along a border (wide => big organic lobes)
		var gap: float = second_score - best_score
		if gap < BAND:
			# Chunky mid-frequency fray so the two biomes interlock in lobes/bays, not a
			# thin ragged seam; the closer to the true border, the more 50/50 the mix.
			var fr: float = classifier._domain_warp.get_noise_2d(tx * 0.013 + 7.0, ty * 0.013 + 19.0) * 0.5 + 0.5
			if fr < 0.5 * (1.0 - gap / BAND):
				return second
	return best


func _sub_idx_for(parent_idx: int, gtx: int, gty: int) -> int:
	if parent_idx < 0 or parent_idx >= reg.biomes.size():
		return 255
	var parent_id: String = str(reg.biomes[parent_idx]["id"])
	var best_sub := 255
	var best_pri := -1
	for rule: Dictionary in reg.sub_biomes:
		var allowed: Array = rule.get("allowedParents", [])
		if not parent_id in allowed:
			continue
		if not _sub_stamp_covers(rule, gtx, gty):
			continue
		var sub_id: String = str(rule["id"])
		var sub_idx: int = int(reg.biome_index.get(sub_id, 255))
		if sub_idx == 255:
			continue
		var pri: int = int(reg.biomes[sub_idx].get("priority", 0))
		if pri > best_pri:
			best_pri = pri
			best_sub = sub_idx
	return best_sub


func _sub_stamp_covers(rule: Dictionary, gtx: int, gty: int) -> bool:
	var spacing: int = int(rule.get("macroSpacing", 4)) * MACRO_TILES
	var salt: int = int(rule.get("_salt", 0))
	var mx: int = int(floorf(float(gtx) / float(spacing)))
	var my: int = int(floorf(float(gty) / float(spacing)))
	for dmy: int in range(-1, 2):
		for dmx: int in range(-1, 2):
			var cmx: int = mx + dmx
			var cmy: int = my + dmy
			if not _macro_stamp_active(rule, cmx, cmy, spacing, salt):
				continue
			var center: Vector2i = _macro_stamp_center(cmx, cmy, spacing, salt)
			var size: float = _macro_stamp_size(rule, cmx, cmy, salt)
			var dx: float = float(gtx - center.x)
			var dy: float = float(gty - center.y)
			var dist: float = sqrt(dx * dx + dy * dy)
			var wobble: float = WG.r01(world_seed, cmx * 17 + salt, cmy * 19 + salt, 901) * 0.32 + 0.78
			if dist <= size * wobble * 0.55:
				return true
	return false


func _macro_stamp_active(rule: Dictionary, mx: int, my: int, spacing: int, salt: int) -> bool:
	if WG.r01(world_seed, mx, my, 500 + salt) > float(rule.get("chance", 0.1)):
		return false
	var center: Vector2i = _macro_stamp_center(mx, my, spacing, salt)
	# NOTE: we deliberately do NOT require the stamp's exact CENTRE tile to be the parent
	# biome. _sub_idx_for already gates every painted tile by its own parent, so a stamp
	# only ever deposits its sub-biome on valid parent tiles. Requiring the centre to land
	# inside the parent made small/thin parents (volcanic, badlands) unreachable by the
	# coarse macro grid — that's why geyser_field / thorn_waste never generated.
	if bool(rule.get("requiresWater", false)):
		if not classifier._touches_water_tile(float(center.x), float(center.y)):
			return false
	return true


func _macro_stamp_center(mx: int, my: int, spacing: int, salt: int) -> Vector2i:
	var jx: float = WG.r01(world_seed, mx, my, 510 + salt) * 0.72 + 0.14
	var jy: float = WG.r01(world_seed, mx, my, 511 + salt) * 0.72 + 0.14
	return Vector2i(
		mx * spacing + int(float(spacing) * jx),
		my * spacing + int(float(spacing) * jy))


func _macro_stamp_size(rule: Dictionary, mx: int, my: int, salt: int) -> float:
	var lo: float = float(rule.get("minSize", 24))
	var hi: float = float(rule.get("maxSize", 80))
	return lerpf(lo, hi, WG.r01(world_seed, mx, my, 520 + salt))


## Mode filter — softens speckle while keeping large coherent biome blobs.
func _smooth_field(parents: PackedInt32Array, w: int, h: int) -> void:
	var next := parents.duplicate()
	for y: int in h:
		for x: int in w:
			var i := y * w + x
			var my_idx: int = parents[i]
			var counts: Dictionary = {}
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var n_idx: int = parents[ny * w + nx]
					counts[n_idx] = int(counts.get(n_idx, 0)) + 1
			var best_idx: int = my_idx
			var best_c: int = 0
			for b_idx: int in counts:
				var c: int = counts[b_idx]
				if c > best_c:
					best_c = c
					best_idx = b_idx
			next[i] = best_idx
	for i: int in parents.size():
		parents[i] = next[i]
