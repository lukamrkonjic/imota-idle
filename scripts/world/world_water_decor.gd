extends Node2D
## Non-interactive water-surface decoration (fish schools at spots, lilies).

const WaterSurfaceArt := preload("res://scripts/world/art/water/water_surface_art.gd")

var kind := "fish_shadow"
var variant := 0


func _ready() -> void:
	z_index = -88
	queue_redraw()


func _draw() -> void:
	var t := WaterSurfaceArt.anim_time() + float(variant % 1000) * 0.037
	WaterSurfaceArt.draw(self, kind, variant, t)
