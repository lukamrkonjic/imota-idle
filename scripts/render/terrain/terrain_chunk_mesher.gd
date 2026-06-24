extends RefCounted
class_name TerrainChunkMesher
## Terrain + water MESH GENERATION and the terrain HEIGHT FIELD (extracted from the
## WorldRender3D monolith). Pure geometry service: given a chunk and the loaded-data lookup
## (the apron/halo of neighbour chunks), it emits a Node3D of ground + water mesh instances,
## and answers height queries (used by movers, props, picking, the camera follow). It knows
## nothing about the camera, fog, movers or UI.
##
## Water mesh emission lives HERE (not in a separate WaterMesher) because it shares the same
## per-frame caches, coastline field and corner-level memos as the ground — splitting it would
## mean threading those through providers with no behaviour change. (Refactor acceptance #3.)

const WG := preload("res://scripts/worldgen/wg.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

const TILE_S := 1.0                 # 3D units per tile
const ELEV_H := WG.ELEV_H           # height per elevation step (single source in wg.gd)

# Water basin model. The surface rides the LOCAL sea-level rolling baseline minus
# WATER_SINK, so it follows the meadow swells and is always WATER_SINK below the dry
# shore (no flat sheet floating on a pedestal). The lakebed dips further: a shallow
# clearance at the shore ramping to the full interior drop in open water.
const WATER_SINK := 0.16        # surface below the local dry-land baseline
const WATER_SHORE_DEPTH := 0.12 # lakebed clearance just under the surface at the shore
const WATER_DEEP_DROP := 0.62   # extra interior lakebed depth (deep_water) below the surface
const SHORE := Color(0.80, 0.75, 0.58)  # sandy shore tone under/at water edges
const WATER_PLANE_MARGIN := 3
const WATER_SUBDIV := 5            # sub-quads per tile edge (25 quads / tile near the coast)
const WATER_BED_CLEARANCE := 0.07  # how far submerged ground sits below the sheet
const SHORE_SMOOTH := 4
const SHORE_RADIUS := 4.0       # kernel reach in cells (round, Euclidean — NOT square)
const SHORE_SD_SCALE := 5.2     # maps (wf - 0.5) -> signed distance to coast, in cells
const SHORE_RAMP_LO := 0.12     # coast-field value where the shore ramp starts easing land down to the water surface

var world: Node2D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _chunk_by_key: Dictionary = {}   # chunk key -> chunk RefCounted (owned by TerrainMeshManager)

# Per-frame memo caches (cleared once per frame by the coordinator via clear_frame_caches()).
var _occ_cache: Dictionary = {}   # global tile -> is_water
var _ti_cache: Dictionary = {}    # Vector2i tile -> tile info
var _cc_cache: Dictionary = {}    # Vector2i corner -> corner colour
var _cb_cache: Dictionary = {}    # Vector2i corner -> beach fraction
var _vfh_cache: Dictionary = {}   # Vector2i tile -> visual floor height
var _ccl_cache: Dictionary = {}   # Vector2i corner -> smoothed corner height


func setup(w: Node2D, ground_mat: ShaderMaterial, water_mat: ShaderMaterial) -> void:
	world = w
	_ground_mat = ground_mat
	_water_mat = water_mat


## The TerrainMeshManager hands us a reference to its loaded-data lookup (same Dictionary
## object it clears + refills each frame), so height/colour sampling sees the live apron.
func set_chunk_lookup(chunk_by_key: Dictionary) -> void:
	_chunk_by_key = chunk_by_key


func clear_frame_caches() -> void:
	_occ_cache.clear()
	_ti_cache.clear()
	_cc_cache.clear()
	_cb_cache.clear()
	_vfh_cache.clear()
	_ccl_cache.clear()


## Smooth, continuous, SEAMLESS terrain: each grid corner's height/normal/color
## is averaged from the tiles around it (sampled globally so chunk borders match),
## giving rolling sculpted land instead of flat terraced diamonds. Water tiles dip
## the floor into a basin and get a separate animated water surface on top.
func build_chunk_terrain(chunk: RefCounted) -> Node3D:
	var n := WG.CHUNK_TILES
	var cx0: int = int(chunk.cx) * n
	var cy0: int = int(chunk.cy) * n
	var wfc := {}  # memoized corner water-fraction (the ONE shared coastline field)
	var wlc := {}  # memoized corner water-surface level (watertight, calm sheet)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false
	for ty: int in n:
		for tx: int in n:
			var gtx := cx0 + tx
			var gty := cy0 + ty
			var info := _tile_info(gtx, gty)
			# Plateau the tile sits on: gameplay floor (terraced, noise-free). Each corner is
			# emitted on THIS plateau so cliffs stay vertical (see _corner_height_for).
			var ref_top := float(info["top"]) if not info.is_empty() else 0.0
			# Four shared corners (continuous across cells -> one smooth surface). Steep
			# terrace risers come through as steep smooth slopes (no axis-aligned vertical
			# faces, which would staircase into sawtooth teeth along diagonal contours).
			_emit_corner(st, gtx, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty + 1, ref_top, wfc, wlc)
			_emit_corner(st, gtx, gty, ref_top, wfc, wlc)
			_emit_corner(st, gtx + 1, gty + 1, ref_top, wfc, wlc)
			_emit_corner(st, gtx, gty + 1, ref_top, wfc, wlc)
			# The water sheet covers the water bodies + a small coastal margin and is FINELY
			# TESSELLATED. Each sub-vertex bakes the smoothed coast field (UV.x), sampled
			# BICUBICALLY, so the shader's 0.5 contour (the shoreline) is a smooth curve at
			# sub-tile resolution — decoupled from the coarse terrain mesh, so the coast can
			# never staircase into per-tile teeth.
			if _water_plane_tile(gtx, gty):
				has_water = true
				_emit_water_tile(wst, gtx, gty, wfc, wlc)
	var root := Node3D.new()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	if has_water:
		var water := MeshInstance3D.new()
		water.mesh = wst.commit()
		water.material_override = _water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
	return root


# A tile the continuous water plane covers: any water tile, or dry land within a few
# tiles of water (the coastal margin the sheet dips into so the depth shader can carve
# the shoreline per-pixel). Cheap-gated by the per-frame water occupancy cache.
func _water_plane_tile(gtx: int, gty: int) -> bool:
	for dy: int in range(-WATER_PLANE_MARGIN, WATER_PLANE_MARGIN + 1):
		for dx: int in range(-WATER_PLANE_MARGIN, WATER_PLANE_MARGIN + 1):
			if _coast_water(gtx + dx, gty + dy):
				return true
	return false


## Final VISUAL height of a ground corner: smoothed terrain, eased DOWN to the local water
## surface as it nears the shore (so land and water meet flush — no floating bank / sub-water
## gap, which fluid can't do in reality), then pushed a touch under the sheet where actually
## submerged. minf() guarantees we only ever LOWER coastal land — never lift low ground or a
## bed — so banks slope into the water like a real beach instead of perching above it. Used for
## BOTH the vertex and the shading normal so the ramp lights correctly. (Corner height ignores
## ref_top, so this is deterministic per corner like _corner_height_for.)
func _visual_corner_y(ci: int, cj: int, ref_top: float, wfc: Dictionary, wlc: Dictionary) -> float:
	var h := _corner_height_for(ci, cj, ref_top)
	var wf := _coast_wf(ci, cj, wfc)
	if wf > SHORE_RAMP_LO:
		# Ease land DOWN to EXACTLY the water surface at the waterline — never below it on the land
		# side, or the dipped beach would peek out under the shoreline. Land meets water flush at
		# the contour and rises away from there; the water shader fills anything that does end up
		# below the sheet (see _emit_water_tile's submersion term), so there are no exposed holes.
		var surf := _water_corner_level(ci, cj, wlc)
		h = minf(h, lerpf(h, surf, smoothstep(SHORE_RAMP_LO, 0.5, wf)))
	# Corners touching an actual water tile sit just below the sheet so no terrain facet pokes up
	# through the contour on the water side (the submersion fill then covers them with water).
	if _corner_touches_water(ci, cj):
		h = minf(h, _water_corner_level(ci, cj, wlc) - WATER_BED_CLEARANCE)
	return h


## A 3x3 box-blur of the visual ground height around a corner. Used ONLY to bake the water
## submersion (UV.y) — softening the per-tile staircase so the waterline / foam / water edge that
## ride the submersion contour curve gently instead of stepping tile-by-tile. The real terrain mesh
## keeps its un-blurred height; this is a coast-shape filter, not a geometry change.
func _smooth_ground_y(ci: int, cj: int, wfc: Dictionary, wlc: Dictionary) -> float:
	var sum := _visual_corner_y(ci, cj, 0.0, wfc, wlc) * 2.0
	var w := 2.0
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		sum += _visual_corner_y(ci + off.x, cj + off.y, 0.0, wfc, wlc)
		w += 1.0
	return sum / w


func _emit_corner(st: SurfaceTool, ci: int, cj: int, ref_top: float, wfc: Dictionary, wlc: Dictionary) -> void:
	var h := _visual_corner_y(ci, cj, ref_top, wfc, wlc)
	# Smooth normal from the FINAL visual height field (central differences), so the shore ramp
	# and water bed are lit correctly — sampling the raw terrain height would shade the beach flat.
	var hx := _visual_corner_y(ci + 1, cj, ref_top, wfc, wlc) - _visual_corner_y(ci - 1, cj, ref_top, wfc, wlc)
	var hz := _visual_corner_y(ci, cj + 1, ref_top, wfc, wlc) - _visual_corner_y(ci, cj - 1, ref_top, wfc, wlc)
	st.set_normal(Vector3(-hx, 2.0 * TILE_S, -hz).normalized())
	st.set_color(_corner_color(ci, cj))
	# UV carries beach data for toon_ground: y = beach fraction (sand vs other, smoothed
	# over the corner so the sand/grass edge can be dithered), x = wetness from the shared
	# coast field (sand darkens/saturates near the waterline).
	var beach := _corner_beach(ci, cj)
	var wet: float = clampf((_coast_wf(ci, cj, wfc) - 0.30) / 0.16, 0.0, 1.0) if beach > 0.0 else 0.0
	st.set_uv(Vector2(wet, beach))
	st.set_uv2(Vector2(_corner_snow(ci, cj), 0.0))
	st.add_vertex(Vector3(float(ci) * TILE_S, h, float(cj) * TILE_S))


# Beach fraction at a grid corner: how many of the 4 touching tiles are sand (0..1). A
# fractional value near the biome edge lets the shader dither the sand/grass boundary.
func _corner_beach(ci: int, cj: int) -> float:
	var ck := Vector2i(ci, cj)
	if _cb_cache.has(ck):
		return _cb_cache[ck]
	var cnt := 0
	var sand := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if info.is_empty():
			continue
		cnt += 1
		if str(info["tile"]) in ["sand", "sand_dune"]:
			sand += 1
	var b: float = float(sand) / float(cnt) if cnt > 0 else 0.0
	_cb_cache[ck] = b
	return b


# Snow fraction at a shared corner, used by the toon shader to swap the mossy grass
# lighting ramp for slate/periwinkle alpine lighting without a hard tile seam.
func _corner_snow(ci: int, cj: int) -> float:
	var cnt := 0
	var frozen := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if info.is_empty():
			continue
		cnt += 1
		if str(info["tile"]) in TerrainStyle.SNOW_TILES:
			frozen += 1
	return float(frozen) / float(cnt) if cnt > 0 else 0.0


## Smooth visual corner height: average of the up-to-4 tiles touching the grid corner.
## ref_top is unused now (kept in the signature so terrace/mover/prop callers share one
## entry point). Continuous across cells, so terrace risers render as steep smooth slopes
## rather than vertical faces that would staircase into sawtooth along diagonal contours.
func _corner_height_for(ci: int, cj: int, _ref_top: float) -> float:
	var ck := Vector2i(ci, cj)
	if _ccl_cache.has(ck):
		return _ccl_cache[ck]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			sum += _visual_floor_height(ci + off.x, cj + off.y, info)
			cnt += 1
	var h: float = sum / float(cnt) if cnt > 0 else 0.0
	_ccl_cache[ck] = h
	return h


func _corner_color(ci: int, cj: int) -> Color:
	var ck := Vector2i(ci, cj)
	if _cc_cache.has(ck):
		return _cc_cache[ck]
	var col := _corner_color_compute(ci, cj)
	_cc_cache[ck] = col
	return col


func _corner_color_compute(ci: int, cj: int) -> Color:
	var infos := []
	var families := {}
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty():
			infos.append(info)
			var family := _surface_family(str(info["tile"]))
			families[family] = int(families.get(family, 0)) + 1
	if infos.is_empty():
		return PixelPalette.pal("grass_a")
	var family := ""
	var best := 0
	for f: String in families:
		if int(families[f]) > best:
			best = int(families[f])
			family = f
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var cnt := 0
	for info: Dictionary in infos:
		if best < 3 or _surface_family(str(info["tile"])) == family:
			var c: Color = info["col"]
			r += c.r
			g += c.g
			b += c.b
			cnt += 1
	return Color(r / float(cnt), g / float(cnt), b / float(cnt))


## Per-global-tile info {top, water, tile, col}, or {} if the chunk isn't loaded.
## Memoised for the frame: the terrain build + every mover's height sample hit the
## same tiles thousands of times, and grading the colour (_grade_ground) is not free.
func _tile_info(gtx: int, gty: int) -> Dictionary:
	var cache_key := Vector2i(gtx, gty)
	if _ti_cache.has(cache_key):
		return _ti_cache[cache_key]
	var info := _tile_info_compute(gtx, gty)
	_ti_cache[cache_key] = info
	return info


func _tile_info_compute(gtx: int, gty: int) -> Dictionary:
	var ck := WG.tile_to_chunk(Vector2i(gtx, gty))
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk == null:
		return {}
	var lx: int = gtx - ck.x * WG.CHUNK_TILES
	var ly: int = gty - ck.y * WG.CHUNK_TILES
	var tid: int = chunk.tile_id(lx, ly)
	var tdef: Dictionary = WorldGen.reg.tile_def(tid)
	var tile_name := str(WorldGen.reg.tile_order[tid])
	var biome_idx: int = chunk.parent_biome_at(lx, ly)
	var biome_id := "" if biome_idx == 255 or biome_idx >= WorldGen.reg.biomes.size() else str(WorldGen.reg.biomes[biome_idx]["id"])
	var water := bool(tdef.get("water", false))
	var elev: int = chunk.elev[ly * WG.CHUNK_TILES + lx]
	var top: float = float(elev) * ELEV_H
	var slope: int = _tile_slope_steps(gtx, gty, elev) if (not water and elev > 0) else 0
	var curve: int = _tile_curvature_steps(gtx, gty, elev) if (not water and elev > 0) else 0
	var col: Color = SHORE if water else TerrainStyle.grade(tdef["colors"][0], tile_name, gtx, gty, elev, slope, curve)
	if not water:
		# Shift toward the effective (sub-)biome's tint so biomes read distinctly; lighter on
		# raised ground so mountains keep their alpine look.
		var eff: int = chunk.biome_at(lx, ly)
		col = TerrainStyle.biome_tinted(col, tile_name, WorldGen.reg.biome_tint(eff), 0.10 if elev > 0 else 0.34)
		# A Short Hike-style painterly patches: soft broad blobs of lighter/darker shades + a
		# rare biome accent, so the ground isn't one flat colour.
		col = TerrainStyle.terrain_patch(col, tile_name, biome_id, gtx, gty)
	return {
		"top": top,
		"water": water,
		"tile": tile_name,
		"biome": biome_id,
		"col": col,
	}


func _visual_floor_height(gtx: int, gty: int, info: Dictionary) -> float:
	# Per-frame memo: each tile's floor height is sampled ~4x per chunk build (once per
	# touching corner) plus by mover height queries — all with the same deterministic result.
	var fk := Vector2i(gtx, gty)
	if _vfh_cache.has(fk):
		return _vfh_cache[fk]
	var top := float(info["top"])
	var tile := str(info["tile"])
	var h: float
	if bool(info["water"]):
		# Lakebed rides the SAME sea-level rolling baseline as the water surface, dipped
		# below it: a shallow clearance at the rim ramping to a deeper bed under open
		# water, keyed off the tile depth (shallow -> water -> deep_water). Parallel to
		# the surface, so narrow rivers and broad lakes both nestle without a flat floor.
		var depth := WATER_SHORE_DEPTH
		if tile == "water":
			depth += WATER_DEEP_DROP * 0.45
		elif tile == "deep_water":
			depth += WATER_DEEP_DROP
		h = _rolling_hill(gtx, gty) - WATER_SINK - depth
	elif _is_path(tile):
		# Road/path bed: FOLLOWS the (smoothed) terrain height so a road slopes up and down hills
		# like a mountain road, but stays a smooth, recessed bed — no rocky bumpiness. The recess
		# deepens on raised ground so the road reads as CARVED into the slope (a bench cut into the
		# mountainside); the mesher's corner smoothing then bevels the shoulders down into the bed.
		# Subtle on flat ground (matches the old gentle path height).
		var carve := 0.09 + clampf(float(_elev_raw(gtx, gty)), 0.0, 16.0) * 0.024
		h = _smoothed_elevation_height(gtx, gty) + _rolling_hill(gtx, gty) * 0.28 - carve
	elif top > 0.0:
		# Elevation is authoritative for the mountain surface. Biome/structure passes
		# can leave gravel, snow, or another gameplay tile on a raised cell; all of
		# them must share the same smoothed geometry or visible seams reappear.
		h = _smoothed_elevation_height(gtx, gty) + _rolling_hill(gtx, gty) * 0.42 + _rocky_lift(gtx, gty) * 0.35
	elif _is_rock(tile):
		h = _smoothed_elevation_height(gtx, gty) + _rolling_hill(gtx, gty) * 0.42 + _rocky_lift(gtx, gty) * 0.35
	else:
		h = top + _rolling_hill(gtx, gty)
	_vfh_cache[fk] = h
	return h


func _smoothed_elevation_height(gtx: int, gty: int) -> float:
	var sum := float(_elev_raw(gtx, gty)) * 4.0
	var weight := 4.0
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		sum += float(_elev_raw(gtx + off.x, gty + off.y)) * 2.0
		weight += 2.0
	for off: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		sum += float(_elev_raw(gtx + off.x, gty + off.y))
		weight += 1.0
	return sum / weight * ELEV_H


# Water-surface level at a grid CORNER. The sheet rides the LOCAL sea-level rolling
# baseline (water is always elev 0) minus WATER_SINK. We average ONLY the WATER tiles
# touching the corner, so high land on the shore never lifts the sheet up its flank — a
# mountain tarn stays at the bottom of its basin. Memoised over shared corners (wlc) so
# neighbouring water tiles agree exactly: the surface is watertight and calm.
func _water_corner_level(ci: int, cj: int, wlc: Dictionary) -> float:
	var key := Vector2i(ci, cj)
	if wlc.has(key):
		return wlc[key]
	var sum := 0.0
	var cnt := 0
	for off: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var info := _tile_info(ci + off.x, cj + off.y)
		if not info.is_empty() and bool(info["water"]):
			sum += _rolling_hill(ci + off.x, cj + off.y)
			cnt += 1
	var base: float = sum / float(cnt) if cnt > 0 else _rolling_hill(ci, cj)
	var lvl := base - WATER_SINK
	wlc[key] = lvl
	return lvl


# Water-surface height at a tile CENTRE (for movers/decor/fish that ride the sheet).
# Matches the mesh: the sheet rides the sea-level rolling baseline minus WATER_SINK.
func _water_surface_at(gtx: int, gty: int) -> float:
	return _rolling_hill(gtx, gty) - WATER_SINK


# True if any of the four tiles touching this grid corner is water (cheap occupancy read).
func _corner_touches_water(ci: int, cj: int) -> bool:
	return _coast_water(ci - 1, cj - 1) or _coast_water(ci, cj - 1) \
		or _coast_water(ci - 1, cj) or _coast_water(ci, cj)


# Emit ONE water tile as a finely tessellated patch. Each sub-vertex bakes the smoothed
# coast field (UV.x) sampled BICUBICALLY, so the shader's 0.5 contour is smooth at sub-tile
# resolution. Heights bilerp the four watertight corner levels (the sheet is near-flat).
func _emit_water_tile(wst: SurfaceTool, gtx: int, gty: int, wfc: Dictionary, wlc: Dictionary) -> void:
	var lA := _water_corner_level(gtx, gty, wlc)
	var lB := _water_corner_level(gtx + 1, gty, wlc)
	var lC := _water_corner_level(gtx + 1, gty + 1, wlc)
	var lD := _water_corner_level(gtx, gty + 1, wlc)
	# Ground (terrain) height under each corner. UV.y bakes the SUBMERSION (surface - ground): the
	# shader fills water wherever this is positive, so any terrain below the sheet — a dip, a hole,
	# a low cove the tile map never marked as water — is covered up to the brim, with no exposed
	# sub-water land peeking under the shoreline. Bilerped across sub-vertices like the surface.
	# SMOOTHED (3x3 corner average) so the submersion contour — and thus the waterline, foam and
	# water edge that ride it — reads as a soft curve instead of the raw per-tile staircase.
	var gA := _smooth_ground_y(gtx, gty, wfc, wlc)
	var gB := _smooth_ground_y(gtx + 1, gty, wfc, wlc)
	var gC := _smooth_ground_y(gtx + 1, gty + 1, wfc, wlc)
	var gD := _smooth_ground_y(gtx, gty + 1, wfc, wlc)
	# Only the COASTAL RING needs tessellation (that's where the 0.5 contour lives). Open
	# deep water (every corner well offshore) and far-inland margin (every corner on land)
	# are flat in wf — emit them as a cheap 2-tri quad so the subdivision cost stays tiny.
	var c00 := _coast_wf(gtx, gty, wfc)
	var c10 := _coast_wf(gtx + 1, gty, wfc)
	var c11 := _coast_wf(gtx + 1, gty + 1, wfc)
	var c01 := _coast_wf(gtx, gty + 1, wfc)
	var lo: float = minf(minf(c00, c10), minf(c11, c01))
	var hi: float = maxf(maxf(c00, c10), maxf(c11, c01))
	if lo >= 0.9 or hi <= 0.12:
		var x0 := float(gtx) * TILE_S
		var z0 := float(gty) * TILE_S
		var x1 := x0 + TILE_S
		var z1 := z0 + TILE_S
		var qa := [[Vector3(x0, lA, z0), c00, lA - gA], [Vector3(x1, lB, z0), c10, lB - gB], [Vector3(x1, lC, z1), c11, lC - gC],
			[Vector3(x0, lA, z0), c00, lA - gA], [Vector3(x1, lC, z1), c11, lC - gC], [Vector3(x0, lD, z1), c01, lD - gD]]
		for v: Array in qa:
			wst.set_normal(Vector3.UP)
			wst.set_uv(Vector2(float(v[1]), float(v[2])))
			wst.add_vertex(v[0])
		return
	var s := WATER_SUBDIV
	var pos := []        # (s+1)x(s+1) sub-vertex positions
	var wfv := []        # matching bicubic water-fraction
	var subv := []       # matching submersion depth (surface - ground)
	for j: int in range(s + 1):
		var fz := float(j) / float(s)
		var prow := []
		var wrow := []
		var srow := []
		for i: int in range(s + 1):
			var fx := float(i) / float(s)
			var hy := lerpf(lerpf(lA, lB, fx), lerpf(lD, lC, fx), fz)
			var gy := lerpf(lerpf(gA, gB, fx), lerpf(gD, gC, fx), fz)
			var wx := float(gtx) + fx
			var wz := float(gty) + fz
			prow.append(Vector3(wx * TILE_S, hy, wz * TILE_S))
			wrow.append(_wf_cubic(wx, wz, wfc))
			srow.append(hy - gy)
		pos.append(prow)
		wfv.append(wrow)
		subv.append(srow)
	for j: int in range(s):
		for i: int in range(s):
			var quad := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1),
				Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for c: Vector2i in quad:
				wst.set_normal(Vector3.UP)
				wst.set_uv(Vector2(float(wfv[c.y][c.x]), float(subv[c.y][c.x])))
				wst.add_vertex(pos[c.y][c.x])


# Catmull-Rom cubic through p1,p2 (p0,p3 are the outer tangents), t in [0,1].
func _cubic1(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))


# Bicubic sample of the smoothed coast field at a fractional world position. Built on the
# memoised integer-corner _coast_wf grid, so it's smooth (C1) and exact at integer corners
# (no cracks between neighbouring water tiles). This is what makes the coastline curve.
func _wf_cubic(fx: float, fz: float, wfc: Dictionary) -> float:
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var rows := []
	for dz: int in range(-1, 3):
		rows.append(_cubic1(
			_coast_wf(x0 - 1, z0 + dz, wfc), _coast_wf(x0, z0 + dz, wfc),
			_coast_wf(x0 + 1, z0 + dz, wfc), _coast_wf(x0 + 2, z0 + dz, wfc), tx))
	return clampf(_cubic1(rows[0], rows[1], rows[2], rows[3], tz), 0.0, 1.0)


## Gentle rolling-hill undulation laid over ALL land (an "A Short Hike / Swiss
## meadow" swell). Long wavelengths + low slope so it's pretty and always walkable —
## it's visual only (the 2D walk grid ignores it), so it never blocks movement; it
## just lifts the ground the player/props/enemies stand on into soft rolling hills.
func _rolling_hill(gtx: int, gty: int) -> float:
	var x := float(gtx)
	var y := float(gty)
	# Layered swells (periods ~30-90 tiles) give real, light-catching rolling hills:
	# enough relief that the toon shading paints lit/shaded flanks, but long enough
	# wavelengths that the slopes stay gentle and natural — never bumpy. Visual only,
	# so however tall it rolls it never blocks walking.
	var broad := sin(x * 0.072 + 0.7) * cos(y * 0.063 - 1.2)
	var roll := sin((x * 0.7 + y * 0.7) * 0.085 + 1.8)
	var mid := sin(x * 0.155 - 0.4) * cos(y * 0.138 + 0.9)
	var fine := sin((x - y) * 0.21 + 2.3)
	return broad * 0.52 + roll * 0.28 + mid * 0.2 + fine * 0.09


func _rocky_lift(gtx: int, gty: int) -> float:
	var chip := sin(float(gtx) * 0.91 + float(gty) * 0.37)
	return maxf(chip, 0.0) * 0.08


# Tile classification + terrain colour live in TerrainStyle (one swappable art module);
# these thin wrappers keep the render-side call sites unchanged.
func _surface_family(tile: String) -> String:
	return TerrainStyle.surface_family(tile)


func _is_path(tile: String) -> bool:
	return TerrainStyle.is_path(tile)


func _is_rock(tile: String) -> bool:
	return TerrainStyle.is_rock(tile)


## Raw baked elevation step at a global tile (0 if the chunk/apron isn't loaded). Cheap
## array read — used for slope (no noise re-eval).
func _elev_raw(gtx: int, gty: int) -> int:
	var ck := WG.tile_to_chunk(Vector2i(gtx, gty))
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk == null or chunk.elev.size() == 0:
		return 0
	var lx: int = gtx - ck.x * WG.CHUNK_TILES
	var ly: int = gty - ck.y * WG.CHUNK_TILES
	return chunk.elev[ly * WG.CHUNK_TILES + lx]


## Local terrain steepness in elevation steps: the largest drop to a 4-neighbour. Flat
## shelves read ~0-1; steep cliff risers read high. Drives slope-aware materials/snow.
func _tile_slope_steps(gtx: int, gty: int, e: int) -> int:
	var m := 0
	m = maxi(m, absi(_elev_raw(gtx + 1, gty) - e))
	m = maxi(m, absi(_elev_raw(gtx - 1, gty) - e))
	m = maxi(m, absi(_elev_raw(gtx, gty + 1) - e))
	m = maxi(m, absi(_elev_raw(gtx, gty - 1) - e))
	return m


## Signed local curvature: positive on convex shelf lips/crests, negative in bowls.
## This breaks material regions away from simple elevation rings.
func _tile_curvature_steps(gtx: int, gty: int, e: int) -> int:
	var neighbours := _elev_raw(gtx + 1, gty) + _elev_raw(gtx - 1, gty) \
		+ _elev_raw(gtx, gty + 1) + _elev_raw(gtx, gty - 1)
	return e * 4 - neighbours


# Build one seamless tiling noise texture for the water shader. `freq_mul` scales the
# feature size, `oct` the fractal detail, `seed` decorrelates the layers. Generated once
# at setup; seamless+normalized so it tiles across the whole world without visible seams.
static func make_water_noise(freq_mul: float, oct: int, seed: int) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.seed = seed
	fnl.frequency = 0.012 * freq_mul
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = oct
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.normalize = true
	tex.noise = fnl
	return tex


# Water occupancy for the coastline field — read straight from the LOADED chunk tile (the
# same source the water mesh uses), NOT the classifier. surface_tile_def_at() re-runs the
# biome-noise eval per tile and was the single biggest chunk-build cost (tens of ms on a
# fresh region); the loaded tile id is a cheap array read and, thanks to the apron index,
# is available for the chunk + its margin. Tiles outside the loaded data read as land.
# Cached per frame (a loaded tile's water-ness is deterministic).
func _coast_water(gtx: int, gty: int) -> bool:
	var key := Vector2i(gtx, gty)
	if _occ_cache.has(key):   # per-frame cache (cleared each frame) -> never stale across load/layer
		return _occ_cache[key]
	var w := false
	var ck := WG.tile_to_chunk(key)
	var chunk: RefCounted = _chunk_by_key.get(WG.key(world.current_layer, ck.x, ck.y))
	if chunk != null:
		var lx: int = gtx - ck.x * WG.CHUNK_TILES
		var ly: int = gty - ck.y * WG.CHUNK_TILES
		w = bool(WorldGen.reg.tile_def(chunk.tile_id(lx, ly)).get("water", false))
	_occ_cache[key] = w
	return w


# Low-passed water fraction (0 land .. 1 open water) at a grid CORNER. A DISTANCE-WEIGHTED
# (triangular) kernel over a radius-3 neighbourhood: this is THE one authoritative coastline
# field. The weighting (centre tiles count most) gives a smooth, rounded 0.5 iso-line — broad
# stylized bends instead of tile staircases — while keeping the contour within ~half a cell
# of the true boundary (so bays/peninsulas are preserved). Both the water mesh and the shore
# overlay read this same field, so their layers can never disagree. Memoized over shared
# corners so neighbouring tiles agree exactly (no cracks).
func _coast_wf(ci: int, cj: int, wfc: Dictionary) -> float:
	var key := Vector2i(ci, cj)
	if wfc.has(key):
		return wfc[key]
	var sum := 0.0
	var wsum := 0.0
	for dy: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
		for dx: int in range(-SHORE_SMOOTH, SHORE_SMOOTH):
			# Tile (ci+dx, cj+dy) sits with its centre 0.5 off the corner. Weight by a
			# ROUND (Euclidean) smooth falloff: a square/Chebyshev kernel makes the 0.5
			# iso-line diamond-shaped, which reads as an angular sawtooth coast. The radial
			# bump rounds the contour so bays and headlands curve smoothly.
			var rx := float(dx) + 0.5
			var ry := float(dy) + 0.5
			var d := sqrt(rx * rx + ry * ry)
			var w := smoothstep(SHORE_RADIUS, 0.0, d)   # 1 at centre -> 0 at the reach
			if w <= 0.0:
				continue
			if _coast_water(ci + dx, cj + dy):
				sum += w
			wsum += w
	var wf: float = sum / wsum if wsum > 0.0 else 0.0
	wfc[key] = wf
	return wf


# -------------------------------------------------------------------- height field ----

## Map a 2D iso-pixel position to a 3D world position (Y from elevation/height).
func iso_to_3d(pos: Vector2, y: float) -> Vector3:
	var g := WG.iso_to_grid(pos)
	return Vector3(g.x * TILE_S, y, g.y * TILE_S)


func world_to_grid(pos: Vector2) -> Vector2:
	return WG.iso_to_grid(pos)


## Terrain height (3D Y) at a 2D iso position, sampled from the loaded chunk.
func height_at_iso(pos: Vector2) -> float:
	var g := WG.iso_to_grid(pos)
	return height_at_grid(g.x, g.y)


## Terrain height (3D Y) at fractional grid coordinates (gx,gy = 3D x/z over TILE_S).
func height_at_grid(gx: float, gy: float) -> float:
	var t := Vector2i(floori(gx), floori(gy))
	var info := _tile_info(t.x, t.y)
	if not info.is_empty() and bool(info["water"]):
		return _water_surface_at(t.x, t.y)
	# Sample on this tile's plateau so a mover near a cliff lip rides its own flat top, not a
	# corner-average sagging toward the drop.
	var ref_top := float(info["top"]) if not info.is_empty() else 0.0
	var fx := gx - floorf(gx)
	var fy := gy - floorf(gy)
	var h00 := _corner_height_for(t.x, t.y, ref_top)
	var h10 := _corner_height_for(t.x + 1, t.y, ref_top)
	var h01 := _corner_height_for(t.x, t.y + 1, ref_top)
	var h11 := _corner_height_for(t.x + 1, t.y + 1, ref_top)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)
