extends Resource
class_name BakedTerrainSet
## Pre-baked STATIC terrain region meshes for a fixed authored world (written by tools/world_bake.gd,
## loaded by StaticTerrainRegions). The fixed continent is split into REGION_TILES-sized blocks; each
## block is meshed ONCE offline by TerrainChunkMesher.build_region_terrain (the exact same per-tile
## emitters the runtime chunk mesher uses, so the baked art is identical), giving one ground + one
## optional water ArrayMesh per region.
##
## Vertices are in GLOBAL tile/world coordinates (TILE_S = 1), matching the per-chunk path, so the
## loader instances each MeshInstance3D with an IDENTITY transform under terrain_root. Materials are
## NOT baked in — the loader applies the shared ground/water ShaderMaterials at runtime.
##
## `ground_meshes` and `water_meshes` are parallel arrays indexed by region; a water entry is null
## where the region has no water. (Saved as a binary .res so the ArrayMeshes embed as sub-resources.)

@export var world_id := ""
@export var region_tiles := 0
@export var ground_meshes: Array[Mesh] = []
@export var water_meshes: Array[Mesh] = []
