extends Node2D
## Non-interactive water-surface decoration (fish schools at spots, lilies).

const WaterSurfaceArt := preload("res://scripts/world/art/water/water_surface_art.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var kind := "fish_shadow"
var variant := 0


func _ready() -> void:
	z_index = -88
	queue_redraw()


func _draw() -> void:
	if not ChunkRenderer.build_meshes:   # 2D body hidden under the 3D render — skip the occluded draw
		return
	var t := WaterSurfaceArt.anim_time() + float(variant % 1000) * 0.037
	WaterSurfaceArt.draw(self, kind, variant, t)
