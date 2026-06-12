extends Node2D
## Tiny non-interactive ground decoration. Drawing delegated to art/ground_decor/*.

const GroundDecorArt := preload("res://scripts/world/art/ground_decor/ground_decor_art.gd")

var kind := "grass"
var variant := 0
var tint := Color.WHITE


func _ready() -> void:
	z_index = -90
	queue_redraw()


func _draw() -> void:
	GroundDecorArt.draw(self, kind, variant, tint)
