extends RefCounted
## Shared world-generation constants and deterministic hashing.
## Everything in worldgen derives randomness from WG.hash_i/r01 so a given
## world seed always produces the identical world, on every machine.

const TILE := 32.0                       # px per isometric block (32x32 pixel art)
const ISO_HW := TILE * 0.5                 # half-width of top diamond face
const ISO_HH := TILE * 0.25                # half-height (2:1 isometric ratio)
const BLOCK_RISE := 6.0                    # vertical extrusion for solid blocks
const ELEV_STEP_PX := 8.0                  # screen px a terrain raises per elevation step
const ELEV_H := ELEV_STEP_PX / TILE        # 3D world units per elevation step (8/32 = 0.25).
                                           # Single source for the step height: the render
                                           # layer's gameplay floor and the logic layer's
                                           # height authority both derive from this.
const MAX_REACHABLE_ELEV := 44             # = summit height: the whole mountain is climbable,
                                           # so the player can hike to the top. Sheer faces are
                                           # still natural barriers via MAX_CLIMB_STEP (a >2-step
                                           # drop between tiles isn't linked), so cliffs stay
                                           # unclimbable and the player routes up the gentle
                                           # slopes / trail instead.
const MAX_CLIMB_STEP := 2                  # biggest single-step elevation change the player
                                           # can walk up — gentle foothill slopes are
                                           # climbable; steeper rock faces route around
const CHUNK_TILES := 16                    # tiles per chunk side
const CHUNK_SIZE := TILE * float(CHUNK_TILES)  # legacy ortho estimate; use chunk_aabb()
const ZONE_CELL := 6                       # zone Voronoi cell size, in chunks
# Streaming radii are ZOOM-AWARE: the world scales them up as the camera zooms
# out so terrain + entities always fill the view with a margin, and back down when
# zoomed in. These are the MIN (most zoomed-in) values; MAX_* cap the worst case.
const VIEW_RADIUS := 6                     # min terrain chunks rendered (baked sprite, 1 draw
                                           # call each, so a wide ring is cheap).
const MAX_VIEW_RADIUS := 16                # streams one ring beyond the hard-max terrain ring (14 + 2)
const ACTIVE_RADIUS := 4                   # min chunks with spawned entities (houses/ore/etc).
const MAX_ACTIVE_RADIUS := 7               # cap so an extreme zoom-out can't spawn a runaway
                                           # number of entity nodes.
const NAV_RADIUS := 3                      # chunks of A* nav graph around the player. Decoupled
                                           # from (and much smaller than) the entity ring so the
                                           # debounced rebuild stays cheap no matter the zoom.
const DETAIL_RADIUS := 3                   # full-detail terrain radius; farther rendered as
                                           # cheap visual LOD to keep the wide view smooth.
const SITE_SEARCH_RADIUS := 14             # chunks scanned for auto-path targets


static func key(layer: int, cx: int, cy: int) -> String:
	return "%d:%d:%d" % [layer, cx, cy]


## Deterministic avalanche hash (splitmix-style). Constants stay below 2^31 so
## literals parse everywhere; intermediate overflow wraps, which is fine.
static func hash_i(p_seed: int, a: int, b: int = 0, c: int = 0) -> int:
	var h: int = p_seed + a * 0x9E3779B9 + b * 0x6C8E9CF5 + c * 0x5851F42D
	h = (h ^ (h >> 30)) * 0x45D9F3B
	h = (h ^ (h >> 27)) * 0x119DE1F3
	h = h ^ (h >> 31)
	return h & 0x7FFFFFFFFFFFFFFF


## Deterministic float in [0, 1).
static func r01(p_seed: int, a: int, b: int = 0, c: int = 0) -> float:
	return float(hash_i(p_seed, a, b, c) % 1000003) / 1000003.0


# Density multiplier at a stand centre (>1 to CONCENTRATE trees into clumps; clearings -> 0).
const CANOPY_CLUMP_PEAK := 2.2

## OSRS-style tree-clumping multiplier on a biome's canopy density. A smooth low-frequency
## cluster field concentrates trees into tight stands separated by big open clearings instead
## of an even per-tile scatter: ~0 across most of the map (clearings), up to CANOPY_CLUMP_PEAK×
## the biome density in a stand centre. Net effect is sparser woods that read as clusters.
## Shared by the runtime spawner and the editor's 2D canopy dots so the two always match.
static func canopy_density_mul(p_seed: int, gx: int, gy: int) -> float:
	var n := _smooth_val(p_seed, gx, gy, 9.0, 240) * 0.62 + _smooth_val(p_seed, gx, gy, 4.0, 241) * 0.38
	return smoothstep(0.55, 0.82, n) * CANOPY_CLUMP_PEAK


## Smooth bilinear value-noise on a coarse grid (period `scale` tiles), in [0, 1).
static func _smooth_val(p_seed: int, gx: int, gy: int, scale: float, salt: int) -> float:
	var x := float(gx) / scale
	var y := float(gy) / scale
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - float(x0)
	var fy := y - float(y0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(
		lerpf(r01(p_seed, x0, y0, salt), r01(p_seed, x0 + 1, y0, salt), fx),
		lerpf(r01(p_seed, x0, y0 + 1, salt), r01(p_seed, x0 + 1, y0 + 1, salt), fx), fy)


## Deterministic pick from a weighted dict {key: weight}. Returns "" if empty.
static func pick_weighted(weights: Dictionary, roll: float) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	if total <= 0.0:
		return ""
	var target := roll * total
	for k: String in weights:
		target -= float(weights[k])
		if target <= 0.0:
			return k
	return weights.keys().back()


## --- Projection authority -------------------------------------------------
## The single source of truth for converting between fractional GRID space
## (continuous tile coordinates; whole numbers land on tile corners, +0.5 on
## centres) and iso-pixel SCREEN space. Everything else — tile_to_world,
## world_to_tile, and the 3D renderer's iso_to_3d/height_at/screen_to_iso —
## routes through these two functions so the 2:1 diamond projection is defined
## in exactly one place. This is the seam the 3D-native migration pivots on.

## Fractional grid coords (gx, gy) from an iso-pixel position.
static func iso_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		(pos.x / ISO_HW + pos.y / ISO_HH) * 0.5,
		(pos.y / ISO_HH - pos.x / ISO_HW) * 0.5)


## Iso-pixel position from fractional grid coords (gx, gy).
static func grid_to_iso(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * ISO_HW, (g.x + g.y) * ISO_HH)


## Isometric screen position of a tile centre (2:1 diamond grid).
static func tile_to_world(tx: int, ty: int) -> Vector2:
	return grid_to_iso(Vector2(float(tx) + 0.5, float(ty) + 0.5))


## Inverse isometric projection — snap world position to tile grid.
static func world_to_tile(pos: Vector2) -> Vector2i:
	var g := iso_to_grid(pos)
	return Vector2i(floori(g.x), floori(g.y))


static func tile_to_chunk(t: Vector2i) -> Vector2i:
	return Vector2i(floori(float(t.x) / CHUNK_TILES), floori(float(t.y) / CHUNK_TILES))


static func world_to_chunk(pos: Vector2) -> Vector2i:
	return tile_to_chunk(world_to_tile(pos))


## Axis-aligned screen bounds for one chunk (isometric footprint).
static func chunk_aabb(cx: int, cy: int) -> Rect2:
	var tx0: int = cx * CHUNK_TILES
	var ty0: int = cy * CHUNK_TILES
	var tx1: int = tx0 + CHUNK_TILES - 1
	var ty1: int = ty0 + CHUNK_TILES - 1
	var corners := [
		tile_to_world(tx0, ty0),
		tile_to_world(tx1, ty0),
		tile_to_world(tx0, ty1),
		tile_to_world(tx1, ty1),
	]
	var min_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_x: float = min_x
	var max_y: float = min_y
	for p: Vector2 in corners:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	var pad := Vector2(ISO_HW, ISO_HH + BLOCK_RISE)
	return Rect2(Vector2(min_x, min_y) - pad, Vector2(max_x - min_x, max_y - min_y) + pad * 2.0)


## Convert a tile-space region to a world-space clamp rect (with margin tiles).
static func tile_region_world_rect(region: Rect2i, margin_tiles: int = 2) -> Rect2:
	var m: int = margin_tiles
	var corners := [
		tile_to_world(region.position.x + m, region.position.y + m),
		tile_to_world(region.end.x - 1 - m, region.position.y + m),
		tile_to_world(region.position.x + m, region.end.y - 1 - m),
		tile_to_world(region.end.x - 1 - m, region.end.y - 1 - m),
	]
	var min_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_x: float = min_x
	var max_y: float = min_y
	for p: Vector2 in corners:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
