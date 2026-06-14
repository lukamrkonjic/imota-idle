extends RefCounted
## Orchestrates chunk generation: terrain fields -> tiles/biomes -> zone ->
## POIs -> skill sites -> monsters for the surface, and delegates negative
## layers to the cave generator. Owns the sub-systems; everything is seeded
## from one world seed and consumes the data registries, never hard-coded
## content lists.

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const BiomeClassifier := preload("res://scripts/worldgen/biome_classifier.gd")
const ZoneMap := preload("res://scripts/worldgen/zone_map.gd")
const PoiPlacement := preload("res://scripts/worldgen/poi_placement.gd")
const SkillSiteSpawner := preload("res://scripts/worldgen/skill_site_spawner.gd")
const MonsterSpawner := preload("res://scripts/worldgen/monster_spawner.gd")
const CaveGenerator := preload("res://scripts/worldgen/cave_generator.gd")
const PlacementGrid := preload("res://scripts/worldgen/placement_grid.gd")
const StructurePlanner := preload("res://scripts/worldgen/structure_planner.gd")

var reg: RefCounted
var world_seed: int = 0

var placement_grid: RefCounted = PlacementGrid.new()
var classifier: RefCounted = BiomeClassifier.new()
var zone_map: RefCounted = ZoneMap.new()
var poi_placer: RefCounted = PoiPlacement.new()
var site_spawner: RefCounted = SkillSiteSpawner.new()
var monster_spawner: RefCounted = MonsterSpawner.new()
var cave_gen: RefCounted = CaveGenerator.new()
var structure_planner: RefCounted = StructurePlanner.new()


func setup(p_reg: RefCounted, p_seed: int) -> void:
	reg = p_reg
	world_seed = p_seed
	placement_grid.clear()
	classifier.setup(reg, p_seed)
	zone_map.setup(reg, classifier, p_seed)
	poi_placer.setup(reg, classifier, zone_map, p_seed)
	site_spawner.setup(reg, p_seed)
	monster_spawner.setup(reg, p_seed)
	cave_gen.setup(reg, zone_map, site_spawner, monster_spawner, p_seed)
	structure_planner.setup(reg, classifier, p_seed)


## Generate chunk data. For cave layers, above_chunk must be the chunk one
## layer up (the caller — WorldGen autoload — resolves it from its cache).
func generate(layer: int, cx: int, cy: int, above_chunk: RefCounted = null) -> RefCounted:
	if layer < 0:
		return cave_gen.generate(layer, cx, cy, above_chunk)
	var chunk: RefCounted = Chunk.new()
	chunk.setup(0, cx, cy)
	chunk.zone = zone_map.zone_for_chunk(cx, cy)
	classifier.map_gen.fill_chunk(chunk)
	var n := WG.CHUNK_TILES
	for ty: int in n:
		var gy := float(cy * n + ty)
		for tx: int in n:
			var gx := float(cx * n + tx)
			var f: Vector3 = classifier.fields(gx, gy)
			var i := Chunk.idx(tx, ty)
			chunk.tiles[i] = classifier.tile_at(gx, gy, f, chunk.biomes_t[i], chunk, tx, ty)
	var occupied: Dictionary = {}
	poi_placer.place(chunk, occupied, placement_grid)
	structure_planner.stamp(chunk, occupied)
	site_spawner.populate(chunk, occupied, placement_grid)
	monster_spawner.populate(chunk, occupied)
	return chunk


## Natural-only surface chunk: terrain + biomes + natural resources + wildlife,
## but NO man-made content (no POIs, settlements, cities, ruins, roads, walls).
## Used by the editor's "Generate Natural World" draft so designers lay cities,
## roads and quests on top by hand afterwards.
func generate_natural(cx: int, cy: int) -> RefCounted:
	var chunk: RefCounted = Chunk.new()
	chunk.setup(0, cx, cy)
	chunk.zone = zone_map.zone_for_chunk(cx, cy)
	classifier.map_gen.fill_chunk(chunk)
	var n := WG.CHUNK_TILES
	for ty: int in n:
		var gy := float(cy * n + ty)
		for tx: int in n:
			var gx := float(cx * n + tx)
			var f: Vector3 = classifier.fields(gx, gy)
			var i := Chunk.idx(tx, ty)
			chunk.tiles[i] = classifier.tile_at(gx, gy, f, chunk.biomes_t[i], chunk, tx, ty)
	var occupied: Dictionary = {}
	site_spawner.populate(chunk, occupied, placement_grid)   # natural gather resources
	monster_spawner.populate(chunk, occupied)                # natural wildlife
	return chunk
