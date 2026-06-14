extends RefCounted
class_name PlacementGrid
## Global interactable spacing — POI parts in adjacent chunks share one grid so
## tents/chests/stations never stack or sit within one tile of each other.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const CLEARANCE := 2

var _blocked: Dictionary = {}
var _registered_chunks: Dictionary = {}


func clear() -> void:
	_blocked.clear()
	_registered_chunks.clear()


func _key(gtx: int, gty: int) -> String:
	return "%d,%d" % [gtx, gty]


func is_area_clear(gtx: int, gty: int, clearance: int = CLEARANCE) -> bool:
	for dy: int in range(-clearance, clearance + 1):
		for dx: int in range(-clearance, clearance + 1):
			if _blocked.has(_key(gtx + dx, gty + dy)):
				return false
	return true


func occupy_tile(gtx: int, gty: int, clearance: int = CLEARANCE) -> void:
	for dy: int in range(-clearance, clearance + 1):
		for dx: int in range(-clearance, clearance + 1):
			_blocked[_key(gtx + dx, gty + dy)] = true


func _local_tiles(anchor: Vector2i, parts: Array) -> Array:
	var out: Array = [anchor]
	var seen: Dictionary = {Chunk.idx(anchor.x, anchor.y): true}
	for raw: Dictionary in parts:
		var local := Vector2i(anchor.x + int(raw.get("dx", 0)), anchor.y + int(raw.get("dy", 0)))
		var key: int = Chunk.idx(local.x, local.y)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(local)
	return out


func can_place_footprint(chunk: RefCounted, anchor: Vector2i, parts: Array) -> bool:
	var seen: Dictionary = {}
	for local: Vector2i in _local_tiles(anchor, parts):
		if seen.has(Chunk.idx(local.x, local.y)):
			return false
		seen[Chunk.idx(local.x, local.y)] = true
	for local: Vector2i in _local_tiles(anchor, parts):
		var gtx: int = chunk.cx * WG.CHUNK_TILES + local.x
		var gty: int = chunk.cy * WG.CHUNK_TILES + local.y
		if not is_area_clear(gtx, gty):
			return false
	return true


func place_footprint(chunk: RefCounted, anchor: Vector2i, parts: Array) -> void:
	for local: Vector2i in _local_tiles(anchor, parts):
		var gtx: int = chunk.cx * WG.CHUNK_TILES + local.x
		var gty: int = chunk.cy * WG.CHUNK_TILES + local.y
		occupy_tile(gtx, gty)


func register_chunk_pois(chunk: RefCounted) -> void:
	var key: String = chunk.key()
	if _registered_chunks.has(key):
		return
	_registered_chunks[key] = true
	for poi: Dictionary in chunk.pois:
		var anchor: Vector2i = poi["anchor"]
		var parts: Array = []
		for part: Dictionary in poi.get("parts", []):
			parts.append({
				"dx": int(part["tx"]) - anchor.x,
				"dy": int(part["ty"]) - anchor.y,
			})
		place_footprint(chunk, anchor, parts)
