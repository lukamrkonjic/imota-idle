extends Node2D
## Tiny non-interactive ground decoration. Drawing delegated to art/ground_decor/*.

const GroundDecorArt := preload("res://scripts/world/art/ground_decor/ground_decor_art.gd")
const SpriteAtlas := preload("res://scripts/world/sprite_atlas.gd")
## Must match tools/bake_sprites.gd DECOR_VARIANTS — runtime maps variant into the
## baked range so it always hits a real cell.
const ATLAS_VARIANTS := 24

var kind := "grass"
var variant := 0
var tint := Color.WHITE


func _ready() -> void:
	# Baked atlas sprites are sampled when the camera zooms; nearest keeps them
	# crisp and matches the live pixel art.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -90
	queue_redraw()


func _draw() -> void:
	# Prefer the shared atlas (one batched draw call across all decor); fall back
	# to live procedural drawing if the look isn't baked.
	var atlas := SpriteAtlas.instance
	if atlas != null:
		var key := "decor|%s|%d" % [kind, variant % ATLAS_VARIANTS]
		if atlas.draw_to(self, key, tint):
			return
	GroundDecorArt.draw(self, kind, variant, tint)
