extends Node2D
## Tiny non-interactive ground decoration. Drawing delegated to art/ground_decor/*.

const GroundDecorArt := preload("res://scripts/world/art/ground_decor/ground_decor_art.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

var kind := "grass"
var variant := 0
var tint := Color.WHITE


func _ready() -> void:
	z_index = -90
	queue_redraw()


func _draw() -> void:
	# This node is the DATA source the 3D StaticPropBatcher reads; its 2D body is hidden under the 3D
	# render, so skip the (occluded) 2D draw while the 3D path is active. build_meshes = the shared
	# "2D substrate visible" flag (false in-game).
	if not ChunkRenderer.build_meshes:
		return
	GroundDecorArt.draw(self, kind, variant, tint)
