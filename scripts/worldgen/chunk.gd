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
var biomes_t := PackedByteArray() # biome index per tile (255 in caves)
var elev_t := PackedByteArray()   # elevation level 0..7 per tile (0 in caves)
var zone: Dictionary = {}
var safe := false                 # campsite/village chunk: no monster spawns
var sites: Array = []
var pois: Array = []
var monsters: Array = []


func setup(p_layer: int, p_cx: int, p_cy: int) -> void:
	layer = p_layer
	cx = p_cx
	cy = p_cy
	tiles.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	biomes_t.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	biomes_t.fill(255)
	elev_t.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)


func key() -> String:
	return WG.key(layer, cx, cy)


## World-space pixel position of the chunk's top-left corner.
func origin() -> Vector2:
	return Vector2(float(cx) * WG.CHUNK_SIZE, float(cy) * WG.CHUNK_SIZE)


static func idx(tx: int, ty: int) -> int:
	return ty * WG.CHUNK_TILES + tx


func tile_id(tx: int, ty: int) -> int:
	return tiles[idx(tx, ty)]


func biome_at(tx: int, ty: int) -> int:
	return biomes_t[idx(tx, ty)]


func elev_at(tx: int, ty: int) -> int:
	return elev_t[idx(tx, ty)]


## Global tile coords of a local tile.
func global_tile(tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * WG.CHUNK_TILES + tx, cy * WG.CHUNK_TILES + ty)


## World-space pixel center of a local tile.
func tile_world(tx: int, ty: int) -> Vector2:
	var g := global_tile(tx, ty)
	return WG.tile_to_world(g.x, g.y)


func is_tile_free(tx: int, ty: int, occupied: Dictionary) -> bool:
	return not occupied.has(idx(tx, ty))
