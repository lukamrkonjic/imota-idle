extends Node2D
## Camera-locked ambient particles — leaves, dust, snow by biome.

const AmbienceArt := preload("res://scripts/world/art/ambience/ambience_art.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")

var world: Node2D


func setup(w: Node2D) -> void:
	world = w


func _ready() -> void:
	z_index = 12


func _draw() -> void:
	if world == null or world._camera == null or world.current_layer != 0:
		return
	global_position = world._camera.global_position
	var biome_id := WorldGen.biome_id_at(global_position)
	if AmbienceArt.mode_for(biome_id).is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var zoom: float = world._camera.zoom.x
	AmbienceArt.draw(self, biome_id, TreeArt.wind_time(), vp / zoom)
