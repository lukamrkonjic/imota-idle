extends RefCounted
## One generated chunk of world data (surface layer 0 or a cave layer < 0).
## Pure data — rendering lives in chunk_renderer.gd, nodes in world.gd.
##
## sites[i]   {skill, node, level, tx, ty, resources, respawn_sec,
##             available, respawn_at, kind}
## pois[i]    {type, label, anchor: Vector2i, safe, respawn, minimap,
##             parts: [{kind, label, tx, ty, station?, hook?, hookMessage?,
##                      color?, boss_name?, target_layer?}]}
## monsters[i] {name, level, tx, ty, aggressive}

const WG := preload("res://scripts/worldgen/wg.gd")

var layer: int = 0
var cx: int = 0
var cy: int = 0
var tiles := PackedByteArray()    # tile byte ids, CHUNK_TILES^2, row-major
var biomes_t := PackedByteArray() # effective biome index per tile (sub or parent)
var parent_biomes_t := PackedByteArray()
var sub_biomes_t := PackedByteArray() # 255 = none
var collision := PackedByteArray() # 1 = blocked by a solid structure (entities don't
                                   # block tiles by themselves); water/walls already
                                   # block via tile flags. Derived from `structures`.
var elev := PackedByteArray()      # terraced terrain elevation in steps, 0 = flat.
                                   # Low steps can be walkable foothills; tall peaks
                                   # are blocked by tile flags / reachability limits.
var zone: Dictionary = {}
var safe := false                 # campsite/village chunk: no monster spawns
var sites: Array = []
var pois: Array = []
var monsters: Array = []
var structures: Array = []  # loose entity parts from multi-chunk megastructures
                            # (cities/ruins); same shape as poi parts, abs tx/ty
# Transient (never baked/saved): a {key -> neighbour Chunk} snapshot the renderer
# fills on the main thread before building its mesh on a worker, so cross-seam
# elevation/tile reads (_resolve) never touch the shared WorldGen.chunks dict from
# the thread. Cleared after the build is applied.
var render_neighbors: Dictionary = {}


func setup(p_layer: int, p_cx: int, p_cy: int) -> void:
	layer = p_layer
	cx = p_cx
	cy = p_cy
	tiles.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	biomes_t.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	parent_biomes_t.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	sub_biomes_t.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	collision.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	elev.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	biomes_t.fill(255)
	parent_biomes_t.fill(255)
	sub_biomes_t.fill(255)
	collision.fill(0)
	elev.fill(0)


func key() -> String:
	return WG.key(layer, cx, cy)


## World-space top-left of the chunk's isometric bounding box.
func origin() -> Vector2:
	return WG.chunk_aabb(cx, cy).position


static func idx(tx: int, ty: int) -> int:
	return ty * WG.CHUNK_TILES + tx


func tile_id(tx: int, ty: int) -> int:
	return tiles[idx(tx, ty)]


func biome_at(tx: int, ty: int) -> int:
	return biomes_t[idx(tx, ty)]


func parent_biome_at(tx: int, ty: int) -> int:
	return parent_biomes_t[idx(tx, ty)]


func sub_biome_at(tx: int, ty: int) -> int:
	return sub_biomes_t[idx(tx, ty)]


## True when a solid structure occupies this tile (in addition to tile-based
## walkability, which already blocks water/walls/hazards).
func is_blocked(tx: int, ty: int) -> bool:
	var i := idx(tx, ty)
	return i < collision.size() and collision[i] != 0


## Global tile coords of a local tile.
func global_tile(tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * WG.CHUNK_TILES + tx, cy * WG.CHUNK_TILES + ty)


## World-space pixel center of a local tile.
func tile_world(tx: int, ty: int) -> Vector2:
	var g := global_tile(tx, ty)
	return WG.tile_to_world(g.x, g.y)


func is_tile_free(tx: int, ty: int, occupied: Dictionary) -> bool:
	return not occupied.has(idx(tx, ty))
