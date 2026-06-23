extends RefCounted
class_name BiomeMapGenerator
## Whittaker field parent biomes + stamped sub-biome micro-regions.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const SMOOTH_PAD := 16
const SMOOTH_PASSES := 2
const MACRO_TILES := 12

# Biome placement mode:
#   "authored" — each region PAINTS its biome directly onto its (warped) ellipse;
#                everywhere else is AUTHORED_BASE. Hand-made worlds: what you place
#                is what you get (no climate spreading). Default.
#   "climate"  — the original climate-suitability model (kept for procedural worlds /
#                future use; flip this back to restore it).
const BIOME_MODE := "authored"
const AUTHORED_BASE := "forest"   # base biome where no region covers a land tile


var reg: RefCounted
var world_seed: int = 0
var classifier: RefCounted

# Biome-edge blending: the per-tile biome lookup is domain-warped by this organic multi-octave
# noise, so each biome's blobs bleed a few tiles across their border and interleave with the
# neighbour — soft, noisy, gradual edges. Interiors (all neighbours the same) are unchanged, so
# biome cores stay distinct. BLEND_RADIUS is the (configurable) max bleed in tiles.
const BLEND_RADIUS := 11    # coherent blob bleed (tiles) — how far patches of a biome reach in
const BLEND_JITTER := 9.0   # per-tile random bleed (tiles) — width + speckle of the sprinkled mix
var _blend_noise: FastNoiseLite


func setup(p_reg: RefCounted, p_seed: int, p_classifier: RefCounted) -> void:
	reg = p_reg
	world_seed = p_seed
	classifier = p_classifier
	_blend_noise = FastNoiseLite.new()
	_blend_noise.seed = p_seed + 7777
	_blend_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Higher frequency than a smooth domain warp: small (~2-3 tile) blobs so a border interleaves
	# into PATCHES rather than just shifting the line wavily.
	_blend_noise.frequency = 0.32
	_blend_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_blend_noise.fractal_octaves = 3


## Domain-warp offset (in tiles) for the biome lookup at a tile. A coherent blob component gives
## organic patches; a per-tile jitter guarantees adjacent tiles sample DIFFERENT spots, so even a
## perfectly clean mask line (e.g. the islands') breaks into interleaved patches of both biomes —
## not just a wavy clean edge. Interiors are unaffected (all neighbours are the same biome).
func _blend_offset(gtx: int, gty: int) -> Vector2i:
	if _blend_noise == null:
		return Vector2i.ZERO
	var bx := _blend_noise.get_noise_2d(float(gtx), float(gty)) * BLEND_RADIUS
	var by := _blend_noise.get_noise_2d(float(gtx) + 311.0, float(gty) + 57.0) * BLEND_RADIUS
	bx += (WG.r01(world_seed, gtx, gty, 4441) - 0.5) * 2.0 * BLEND_JITTER
	by += (WG.r01(world_seed, gtx, gty, 4451) - 0.5) * 2.0 * BLEND_JITTER
	return Vector2i(int(round(bx)), int(round(by)))


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
			var ci := Chunk.idx(tx, ty)
			var gtx: int = ox + tx + pad
			var gty: int = oy + ty + pad
			# Soft noisy edges: sample the (smoothed) biome field at a warped offset so borders
			# interleave into a mixed band. The apron (SMOOTH_PAD) keeps the offset in-bounds.
			var off := _blend_offset(gtx, gty)
			var slx := clampi(tx + pad + off.x, 0, w - 1)
			var sly := clampi(ty + pad + off.y, 0, h - 1)
			var parent: int = parents[sly * w + slx]
			# sub-biome computed at the SAMPLED tile so micro-regions blend across the seam too
			var sub: int = _sub_idx_for(parent, ox + slx, oy + sly)
			chunk.parent_biomes_t[ci] = parent
			chunk.sub_biomes_t[ci] = sub
			chunk.biomes_t[ci] = sub if sub != 255 else parent


func parent_idx_at(tx: float, ty: float) -> int:
	var gtx := floori(tx)
	var gty := floori(ty)
	var off := _blend_offset(gtx, gty)   # same noisy edge-blend as the baked map
	return _parent_idx(gtx + off.x, gty + off.y)


func sub_idx_at(tx: float, ty: float) -> int:
	var gtx := floori(tx)
	var gty := floori(ty)
	var off := _blend_offset(gtx, gty)
	var px := gtx + off.x
	var py := gty + off.y
	return _sub_idx_for(_parent_idx(px, py), px, py)


func effective_idx_at(tx: float, ty: float) -> int:
	# One warped sample shared by parent + sub, so the blended edge is self-consistent.
	var gtx := floori(tx)
	var gty := floori(ty)
	var off := _blend_offset(gtx, gty)
	var px := gtx + off.x
	var py := gty + off.y
	var parent := _parent_idx(px, py)
	var sub := _sub_idx_for(parent, px, py)
	return sub if sub != 255 else parent


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


# Temporarily PARKED biomes: remapped to a stand-in at generation time so they vanish
# from the world without touching their data, ids, or the authored mask (save-safe — the
# biome definitions stay in biomes.json). Re-add a biome by deleting its entry here and
# rebaking. Savanna is parked as beach for now (re-add savanna later).
const _PARKED_BIOMES := {"savanna": "beach", "savanna_scrub": "beach"}


func _remap_biome_id(id: String) -> String:
	return str(_PARKED_BIOMES.get(id, id))


func _is_parked_idx(idx: int) -> bool:
	return idx >= 0 and idx < reg.biomes.size() and _PARKED_BIOMES.has(str(reg.biomes[idx]["id"]))


func _parent_idx(gtx: int, gty: int) -> int:
	return int(reg.biome_index.get(_remap_biome_id(_parent_id(gtx, gty)), reg.biomes.size() - 1))


func _parent_id(gtx: int, gty: int) -> String:
	# AUTHORED BIOME MASK (tools/trace_world.py): each land tile's biome is read
	# straight from the traced reference, so the world matches the art exactly. The
	# coastline (ocean/beach) still comes from the land-mask coast field.
	if classifier.has_biome_mask():
		if reg.spec.active and reg.spec.finite:
			var shore: float = classifier.coast_sink(float(gtx), float(gty))
			if shore > 0.72:
				return "ocean"
			if shore > 0.34:
				return "beach"
		var mi: int = classifier.mask_biome_idx(float(gtx), float(gty))
		if mi >= 0:
			return reg.parent_biome_id(mi)
		return AUTHORED_BASE
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
	# AUTHORED MODE: the covering region paints its biome directly (warped ellipse,
	# highest priority then most specific); land with no region is the base biome.
	# Sub-biome regions resolve to their parent here; the sub stamps on top later.
	if BIOME_MODE == "authored":
		_ensure_climate_cache()
		var rb := _region_parent_at(tx, ty)
		return rb if not rb.is_empty() else AUTHORED_BASE
	# CLIMATE-SUITABILITY MODEL (no region polygons). Every tile has continuous, region-
	# biased temperature/moisture/elevation fields; we pick the biome whose authored climate
	# envelope (data/world/biomes.json `climate`) fits best. Transitions are gradual and
	# geographically sensible — the climate gradient between two zones passes through
	# whatever biome's range sits between them (desert->savanna->plains, snow->tundra->boreal).
	_ensure_climate_cache()
	var cl := _climate_at(tx, ty)   # Vector3(temperature, moisture, elevation), all 0..1
	var best := "plains"
	var best_s := -1.0
	for bd: Dictionary in _clim_biomes:
		# final = climateSuitability * regionalInfluence. Temperate "major" biomes have
		# influence 1 everywhere (the connective tissue); EXTREME biomes (desert/volcanic/
		# jungle/tundra/badlands) are confined to their anchored, domain-warped basin, so
		# they form coherent territories instead of scattered fragments.
		var infl: float = _regional_influence(bd, tx, ty)
		if infl <= 0.0:
			continue
		var s: float = _suitability(bd, cl.x, cl.y, cl.z) * infl
		# A smooth, biome-ID-keyed wobble frays seams organically. Scaled by influence so it
		# can't speckle an extreme biome outside its basin. Keyed by id (not list order).
		var off: float = bd["off"]
		s += (classifier._domain_warp.get_noise_2d(tx * 0.012 + off, ty * 0.012 + off) * 0.5 + 0.5) * 0.09 * infl
		if s > best_s:
			best_s = s
			best = str(bd["id"])
	return best


# --- climate-suitability biome model -----------------------------------------
var _clim_ready := false
var _clim_biomes: Array = []        # [{id, t0,t1,m0,m1,e0,e1, off, extreme}] biomes with a climate
var _region_anchors: Array = []     # [{c:Vector2, r:float, t:float, m:float}] authored climate pulls
var _extreme_anchors: Dictionary = {}  # biome_id -> [{c:Vector2, r:float}] confinement basins

## Drop the cached region/climate tables so the next query rebuilds them from the
## current reg.spec.regions. Used by tools/biome_shuffle.gd to re-render biome
## dispositions after reassigning region biomes, without rebuilding the land SDF.
func reset_region_cache() -> void:
	_clim_ready = false
	_clim_biomes.clear()
	_region_anchors.clear()
	_extreme_anchors.clear()


## Authored mode: biome of the highest-priority region whose WARPED ellipse covers
## this tile (ties -> most specific / smallest). "" when no region covers it.
func _region_parent_at(tx: float, ty: float) -> String:
	var best := ""
	var best_pri := -1.0
	var best_area := INF
	for a: Dictionary in _region_anchors:
		if _anchor_ed(a, tx, ty, 1.0) > 1.0:
			continue
		var pri: float = a["pri"]
		var area: float = float(a["rx"]) * float(a["ry"])
		if pri > best_pri + 0.0001 or (absf(pri - best_pri) <= 0.0001 and area < best_area):
			best_pri = pri
			best_area = area
			best = str(a["biome"])
	return best


func _ensure_climate_cache() -> void:
	if _clim_ready:
		return
	_clim_ready = true
	for b: Dictionary in reg.biomes:
		var c: Dictionary = b.get("climate", {})
		if c.is_empty():
			continue
		var tr: Array = c.get("t", [0.0, 1.0])
		var mr: Array = c.get("m", [0.0, 1.0])
		var er: Array = c.get("e", [0.0, 1.0])
		_clim_biomes.append({
			"id": str(b["id"]),
			"t0": float(tr[0]), "t1": float(tr[1]),
			"m0": float(mr[0]), "m1": float(mr[1]),
			"e0": float(er[0]), "e1": float(er[1]),
			"off": float(absi(str(b["id"]).hash()) % 977),
			"extreme": str(b.get("climateScale", "major")) == "extreme"})
	var ct := float(WG.CHUNK_TILES)
	for r: Dictionary in reg.spec.regions:
		var biome := str(r.get("biome", ""))
		var bdef: Dictionary = reg.biome_by_id(biome)
		var bc: Dictionary = bdef.get("climate", {})
		if bc.is_empty():
			# Region biome is a SUB-biome (geyser_field, snowdrift, oasis...) with no climate of
			# its own. Inherit its parent biome's climate so the region still anchors a coherent
			# territory and the sub-biome can stamp on the right parent (geyser_field -> volcanic).
			var par := _first_allowed_parent(biome)
			if par.is_empty():
				continue
			biome = par
			bdef = reg.biome_by_id(par)
			bc = bdef.get("climate", {})
			if bc.is_empty():
				continue
		var c2 := Vector2(float(r["cx"]) * ct + ct * 0.5, float(r["cy"]) * ct + ct * 0.5)
		var tr2: Array = bc.get("t", [0.5, 0.5])
		var mr2: Array = bc.get("m", [0.5, 0.5])
		var er2: Array = bc.get("e", [0.3, 0.3])
		# Anchor carries the region biome's climate CENTRE on all three axes (incl. elevation),
		# so a volcanic/tundra/alpine region forces the high/low ground its biome needs — the
		# authored layout, not raw terrain noise, decides what grows at a region core. EXTREME
		# regions steer harder (strength 1.8): a volcano/desert is a strong local anomaly that
		# overrides latitude + neighbouring climates, so its core reliably reads as its biome.
		# Geometry is the authored ELLIPSE (rx/ry/rotation in tiles + organic edge warp), so the
		# biome territory is shaped + rotated, never a circle. Higher `priority` => steers harder.
		var is_extreme := str(bdef.get("climateScale", "major")) == "extreme"
		var anc := {"c": c2,
			"rx": maxf(float(r.get("rx", r.get("radius", 1.0))) * ct, 1.0),
			"ry": maxf(float(r.get("ry", r.get("radius", 1.0))) * ct, 1.0),
			"rot": float(r.get("rot", 0.0)),
			"wseed": float(r.get("warp_seed", 0)), "wstr": float(r.get("warp_strength", 0.0)),
			"pri": maxf(float(r.get("priority", 40)) / 40.0, 0.25),
			"t": (float(tr2[0]) + float(tr2[1])) * 0.5,
			"m": (float(mr2[0]) + float(mr2[1])) * 0.5,
			"e": (float(er2[0]) + float(er2[1])) * 0.5,
			"s": 1.8 if is_extreme else 1.0, "biome": biome}
		_region_anchors.append(anc)
		# Extreme biomes also seed a confinement basin around their (elliptical) anchor.
		if is_extreme:
			if not _extreme_anchors.has(biome):
				_extreme_anchors[biome] = []
			(_extreme_anchors[biome] as Array).append(anc)


## First allowed parent of a sub-biome rule that itself HAS a climate envelope, so a sub-biome
## region inherits a real climate (skips parents that are themselves climate-less sub-biomes,
## e.g. corrupted_bog -> bog has none -> swamp does). "" if none qualifies.
func _first_allowed_parent(sub_id: String) -> String:
	for rule: Dictionary in reg.sub_biomes:
		if str(rule.get("id", "")) == sub_id:
			var ap: Array = rule.get("allowedParents", [])
			for par: Variant in ap:
				if not reg.biome_by_id(str(par)).get("climate", {}).is_empty():
					return str(par)
			return str(ap[0]) if not ap.is_empty() else ""
	return ""


## Warped elliptical normalised distance from an anchor: 0 at the centre, ~1 on the authored
## ellipse (rotation-aware), with an organic edge warp keyed by the region's warp seed/strength
## so territory borders are irregular, never clean ellipses. `scale` widens the ellipse (used to
## turn the core ellipse into a broad confinement basin for extreme biomes).
func _anchor_ed(a: Dictionary, tx: float, ty: float, scale: float) -> float:
	var dx := tx - (a["c"] as Vector2).x
	var dy := ty - (a["c"] as Vector2).y
	var rot: float = a["rot"]
	var ca := cos(-rot)
	var sa := sin(-rot)
	var lx := (dx * ca - dy * sa) / (float(a["rx"]) * scale)
	var ly := (dx * sa + dy * ca) / (float(a["ry"]) * scale)
	var ed := sqrt(lx * lx + ly * ly)
	# Organic edge warp — region-scale lobes, kept modest so it frays the border without ever
	# tearing the sample off a region core.
	var seed: float = a["wseed"]
	var w: float = classifier._domain_warp.get_noise_2d(tx * 0.006 + seed * 0.13, ty * 0.006 + seed * 0.07) * float(a["wstr"])
	return ed + w


## Regional influence 0..1: how strongly a biome is "allowed" here at the continental scale.
## Major (temperate) biomes are 1 everywhere — the connective tissue. EXTREME biomes are 1 in
## their anchored basin core and fade to 0 well outside (a wide transition belt), so deserts/
## volcanoes/jungles/tundra stay coherent territories — shaped by the authored ellipse, not a
## circle. (No anchors for an extreme biome => it can't appear.)
func _regional_influence(bd: Dictionary, tx: float, ty: float) -> float:
	if not bool(bd["extreme"]):
		return 1.0
	var anchors: Array = _extreme_anchors.get(str(bd["id"]), [])
	if anchors.is_empty():
		return 0.0
	var best := 0.0
	for a: Dictionary in anchors:
		# Solid core within the ellipse, fading to 0 by ~2.2x it => a broad basin + transition belt.
		best = maxf(best, 1.0 - smoothstep(1.0, 2.2, _anchor_ed(a, tx, ty, 1.0)))
	return best


## Continuous climate at a world tile: base temperature/moisture (warped multi-octave noise
## + latitude, from the classifier) gently steered toward nearby authored region anchors, plus
## terrain elevation. Smooth everywhere — the source of organic, gradual biome transitions.
func _climate_at(tx: float, ty: float) -> Vector3:
	# BROAD, low-frequency climate so biomes form large readable regions (continental scale),
	# not high-frequency speckle. Warp the sample point so the bands aren't axis-aligned.
	var wx: float = classifier._domain_warp.get_noise_2d(tx * 0.0022, ty * 0.0022) * 220.0
	var wy: float = classifier._domain_warp.get_noise_2d(tx * 0.0022 + 53.0, ty * 0.0022 + 17.0) * 220.0
	var sx := tx + wx
	var sy := ty + wy
	var g: Dictionary = classifier.geo(tx, ty)
	var lat: float = float(g["n"])   # +1 far north .. -1 far south
	# Temperature: warm baseline, colder toward the north, plus a gentle low-frequency drift.
	# Sample the climate noise at scaled-down coordinates => much lower effective frequency =>
	# broad, continental temperature/moisture regions (the large-scale structure) instead of
	# mid-frequency speckle competing with the major regions.
	# Baseline TEMPERATE: midpoint ~0.50 (mid-plains) so the connective tissue reads as lush
	# forest/plains, not hot savanna. Latitude cools the far north; broad noise drifts it.
	var tnoise: float = classifier._climate.get_noise_2d(sx * 0.5, sy * 0.5) * 0.5 + 0.5
	# Gentle latitude swing: cold far-north, LUSH-temperate middle (player start), warm-but-not-
	# scorching south — so the south reads swampy-wet, not desert. (Desert is confined to its
	# peninsula by regional influence, NOT a hot latitude band.)
	var temp: float = clampf(0.47 - lat * 0.21 + (tnoise - 0.5) * 0.26, 0.0, 1.0)
	# Moisture: broad low-frequency field, biased WET so the temperate middle is dominated by
	# forest/dense_forest (with wheat/plains as drier patches, not a monoculture). The southern
	# swamp comes from large authored swamp REGIONS, not a blanket wetness — so the desert
	# peninsula stays arid.
	var moist: float = clampf(classifier._moist_macro.get_noise_2d(sx * 0.55, sy * 0.55) * 0.5 + 0.62, 0.0, 1.0)
	var elev: float = clampf(classifier._mtn.mountain_height_field(tx, ty), 0.0, 1.0)
	# Authored regions steer the local climate toward their biome's centre on ALL THREE axes.
	# Tight, strong falloff (core r*0.35 -> rim r*1.6) so a region core is authoritative — its
	# intended biome actually grows there — while still blending smoothly into its neighbours.
	var wsum := 0.0
	var tt := 0.0
	var mt := 0.0
	var et := 0.0
	# Each authored region steers the local climate over its (warped, rotation-aware) ELLIPSE —
	# solid in the core, fading out past the edge — so territories are shaped + organic, not discs.
	# Weight scales by extreme-strength AND priority, so a specific micro-region overrides the
	# broad territory it sits inside.
	for a: Dictionary in _region_anchors:
		var ed := _anchor_ed(a, tx, ty, 1.0)
		var w: float = (1.0 - smoothstep(0.35, 1.55, ed)) * float(a["s"]) * float(a["pri"])
		if w > 0.001:
			wsum += w
			tt += float(a["t"]) * w
			mt += float(a["m"]) * w
			et += float(a["e"]) * w
	if wsum > 0.0:
		var blend: float = clampf(wsum, 0.0, 1.0) * 0.90   # how strongly regions steer climate
		temp = lerpf(temp, tt / wsum, blend)
		moist = lerpf(moist, mt / wsum, blend)
		# Elevation steers toward the region's biome CLASS (not max), so a mountainous region
		# (volcanic/alpine/tundra) gets high ground AND a lowland one (jungle/swamp) gets low
		# ground — the authored layout sets the landform, not whatever terrain noise happens here.
		elev = lerpf(elev, et / wsum, blend)
	temp = clampf(temp - elev * 0.12, 0.0, 1.0)   # higher ground is a little colder
	return Vector3(temp, moist, elev)


## Biome climate fit: 1.0 inside the envelope on every axis, falling smoothly to 0 over a
## tolerance outside it. Product of the three axes so a biome must fit temperature AND
## moisture AND elevation to score.
func _suitability(bd: Dictionary, temp: float, moist: float, elev: float) -> float:
	return _fit(temp, bd["t0"], bd["t1"], 0.22) * _fit(moist, bd["m0"], bd["m1"], 0.22) * _fit(elev, bd["e0"], bd["e1"], 0.30)

static func _fit(v: float, lo: float, hi: float, tol: float) -> float:
	if v >= lo and v <= hi:
		return 1.0
	var dd: float = (lo - v) if v < lo else (v - hi)
	return clampf(1.0 - dd / tol, 0.0, 1.0)


func _sub_idx_for(parent_idx: int, gtx: int, gty: int) -> int:
	if parent_idx < 0 or parent_idx >= reg.biomes.size():
		return 255
	# Honor a micro-biome the mask classified explicitly (e.g. salt_marsh, flower_meadow)
	# when it belongs to this parent; otherwise fall through to procedural stamping so
	# marsh_pool / oasis / scorched / grove etc. still appear within their parents.
	if classifier.has_biome_mask():
		var mi: int = classifier.mask_biome_idx(float(gtx), float(gty))
		if mi >= 0 and mi != parent_idx and bool(reg.biomes[mi].get("isSubBiome", false)) and not _is_parked_idx(mi):
			if int(reg.biome_index.get(reg.parent_biome_id(mi), -1)) == parent_idx:
				return mi
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
	# Drop a parked sub-biome (e.g. savanna_scrub) so the remapped parent shows cleanly.
	return 255 if _is_parked_idx(best_sub) else best_sub


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
			var wobble: float = WG.r01(world_seed, cmx * 17 + salt, cmy * 19 + salt, 901) * 0.32 + 0.78
			# Displace the SAMPLE POINT so the boundary frays into an ORGANIC blob, not a disc.
			# Uses HIGH-frequency noise: _moist (~60-tile lobes) deforms the overall shape and
			# _surface_detail (~9-tile fray) roughens the edge. (The big domain_warp field is far
			# too low-frequency here — it would just translate the whole disc.) Amplitude scales
			# with the stamp so small islets and large basins both read as natural patches.
			var fs: float = float(salt) * 4.0
			var amp: float = size * 0.5
			var hx: float = classifier._moist.get_noise_2d(float(gtx) + fs, float(gty) - fs) * amp \
				+ classifier._surface_detail.get_noise_2d(float(gtx) + fs, float(gty)) * amp * 0.45
			var hy: float = classifier._moist.get_noise_2d(float(gtx) + 311.0 + fs, float(gty) + 173.0) * amp \
				+ classifier._surface_detail.get_noise_2d(float(gtx), float(gty) + 211.0 + fs) * amp * 0.45
			var dx: float = float(gtx - center.x) + hx
			var dy: float = float(gty - center.y) + hy
			if sqrt(dx * dx + dy * dy) <= size * wobble * 0.55:
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
