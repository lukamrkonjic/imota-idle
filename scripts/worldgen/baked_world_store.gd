extends RefCounted
class_name BakedWorldStore
## Read-only loader for a FIXED, pre-baked world (see tools/world_bake.gd).
##
## The whole finite continent is shipped as one file:
##   res://data/world/baked/<id>.world
## written with var_to_str(), so Vector2i / Color / nested arrays round-trip with
## no JSON conversion. The heavy per-tile arrays (tiles / biomes / parent / sub)
## are base64-encoded PackedByteArrays for compactness; everything else (zone,
## sites, pois, monsters, structures) is stored natively.
##
## At runtime WorldGen.get_chunk() consults this BEFORE the generator, so inside
## the authored world nothing is generated from noise — travel is seamless and
## the world is identical for everyone. Out-of-bounds is open ocean (a trivial
## filler chunk, no generation). Procedural zones (region fixed:false) are not
## baked and fall through to the generator.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const DIR := "res://data/world/baked/"

var loaded := false
var world_id := ""
var bounds := Rect2i()
var has_spawn := false
var spawn_tile := Vector2i.ZERO   # authored player spawn (global tile), if any
var _chunks: Dictionary = {}     # "cx:cy" -> entry dict
var _ocean_tile := 0
var _ocean_biome := 255
var _reg: RefCounted = null
# Index remap LUTs (baked byte index -> current byte index, by stable id). Empty =
# identity (older bakes with no id table, or ids unchanged). See _build_remaps.
var _biome_remap: PackedByteArray = PackedByteArray()
var _tile_remap: PackedByteArray = PackedByteArray()


func setup(reg: RefCounted) -> void:
	_reg = reg
	_ocean_tile = int(reg.tile_index.get("deep_water", 0))
	_ocean_biome = int(reg.biome_index.get("ocean", 255))


## Load the baked file for `id`. Safe when absent: leaves loaded == false and the
## caller keeps using the generator (so the game still runs before a first bake).
func load_world(id: String) -> bool:
	loaded = false
	world_id = id
	_chunks.clear()
	var path := DIR + id + ".world"
	if not FileAccess.file_exists(path):
		push_warning("BakedWorldStore: no baked world at %s (run tools/world_bake.tscn)" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = str_to_var(text)
	if not parsed is Dictionary:
		push_error("BakedWorldStore: corrupt baked world %s" % path)
		return false
	var doc: Dictionary = parsed
	var b: Dictionary = doc.get("bounds", {})
	if not b.is_empty():
		var mn: Array = b["min"]
		var mx: Array = b["max"]
		bounds = Rect2i(int(mn[0]), int(mn[1]), int(mx[0]) - int(mn[0]) + 1, int(mx[1]) - int(mn[1]) + 1)
	var sp: Array = doc.get("spawn", [])
	if sp.size() == 2:
		spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
		has_spawn = true
	_chunks = doc.get("chunks", {})
	_build_remaps(doc)
	loaded = true
	return true


## Build baked-index -> current-index LUTs from the bake's permanent id tables.
## Absent tables (older bakes) => identity (no remap). Removed ids resolve through
## reg.deprecated_biomes/_tiles; if nothing resolves, a safe default is used.
func _build_remaps(doc: Dictionary) -> void:
	_biome_remap = PackedByteArray()
	_tile_remap = PackedByteArray()
	if _reg == null:
		return
	var default_biome: int = int(_reg.biome_index.get("plains", maxi(0, _reg.biomes.size() - 1)))
	var default_tile: int = int(_reg.tile_index.get("grass", 0))
	_biome_remap = _make_remap(doc.get("biomeIds", []), _reg.biome_index, _reg.deprecated_biomes, default_biome, true)
	_tile_remap = _make_remap(doc.get("tileIds", []), _reg.tile_index, _reg.deprecated_tiles, default_tile, false)


func _make_remap(baked_ids: Array, index: Dictionary, deprecated: Dictionary, default_idx: int, biome: bool) -> PackedByteArray:
	if baked_ids.is_empty():
		return PackedByteArray()   # identity — nothing to remap
	var lut := PackedByteArray()
	lut.resize(256)
	for i: int in 256:
		lut[i] = default_idx
	if biome:
		lut[255] = 255             # sub-biome 'none' sentinel is not an id
	for baked_idx: int in mini(baked_ids.size(), 256):
		var id := str(baked_ids[baked_idx])
		var resolved := _resolve(id, index, deprecated)
		if resolved >= 0:
			lut[baked_idx] = resolved
	return lut


func _resolve(id: String, index: Dictionary, deprecated: Dictionary) -> int:
	if index.has(id):
		return int(index[id])
	for fb: String in deprecated.get(id, PackedStringArray()):
		if index.has(fb):
			return int(index[fb])
		for fb2: String in deprecated.get(fb, PackedStringArray()):
			if index.has(fb2):
				return int(index[fb2])
	return -1


static func _remap(arr: PackedByteArray, lut: PackedByteArray) -> PackedByteArray:
	if lut.is_empty():
		return arr
	var out := PackedByteArray()
	out.resize(arr.size())
	for i: int in arr.size():
		out[i] = lut[arr[i]]
	return out


func has(cx: int, cy: int) -> bool:
	return loaded and _chunks.has("%d:%d" % [cx, cy])


## Reconstruct a full Chunk from the baked entry. Returns null when not baked.
func build_chunk(cx: int, cy: int) -> RefCounted:
	var key := "%d:%d" % [cx, cy]
	if not _chunks.has(key):
		return null
	var e: Dictionary = _chunks[key]
	var chunk: RefCounted = Chunk.new()
	chunk.setup(0, cx, cy)
	chunk.tiles = _remap(_decode(e.get("t", "")), _tile_remap)
	chunk.biomes_t = _remap(_decode(e.get("b", "")), _biome_remap)
	chunk.parent_biomes_t = _remap(_decode(e.get("p", "")), _biome_remap)
	chunk.sub_biomes_t = _remap(_decode(e.get("s", "")), _biome_remap)
	if e.has("k"):                       # collision layer (older bakes lack it)
		chunk.collision = _decode(e.get("k", ""))
	if e.has("e"):                       # terrain elevation (older bakes lack it)
		chunk.elev = _decode(e.get("e", ""))
	chunk.zone = (e.get("zone", {}) as Dictionary).duplicate(true)
	chunk.safe = bool(e.get("safe", false))
	chunk.sites = (e.get("sites", []) as Array).duplicate(true)
	chunk.pois = (e.get("pois", []) as Array).duplicate(true)
	chunk.monsters = (e.get("monsters", []) as Array).duplicate(true)
	chunk.structures = (e.get("structures", []) as Array).duplicate(true)
	return chunk


## A trivial all-ocean chunk for everything beyond the finite bounds — no noise.
func ocean_chunk(cx: int, cy: int) -> RefCounted:
	var chunk: RefCounted = Chunk.new()
	chunk.setup(0, cx, cy)
	chunk.tiles.fill(_ocean_tile)
	chunk.biomes_t.fill(_ocean_biome)
	chunk.parent_biomes_t.fill(_ocean_biome)
	chunk.sub_biomes_t.fill(255)
	chunk.safe = true
	chunk.zone = {"id": "ocean", "name": "The Open Sea", "req": 1, "tier": "", "biome": "ocean"}
	return chunk


static func _decode(b64: String) -> PackedByteArray:
	if b64.is_empty():
		var empty := PackedByteArray()
		empty.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
		return empty
	return Marshalls.base64_to_raw(b64)


# --- bake-side helpers (used by tools/world_bake.gd) ----------------------------

static func encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes)
