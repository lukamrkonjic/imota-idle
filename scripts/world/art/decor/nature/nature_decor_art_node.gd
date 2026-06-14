@tool
extends Node2D
class_name NatureDecorArtNode

const Catalog := preload("res://scripts/world/art/decor/nature/nature_decor_art_catalog.gd")

@export var decor_id := Catalog.DEFAULT_ID:
	set(value):
		decor_id = value
		queue_redraw()

@export var variant := 0:
	set(value):
		variant = value
		queue_redraw()

@export var tint := Color(0, 0, 0, 0):
	set(value):
		tint = value
		queue_redraw()


func _draw() -> void:
	Catalog.draw_id(self, decor_id, variant, tint)
