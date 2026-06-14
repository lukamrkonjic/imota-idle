extends RefCounted
class_name BrokenWallArt
## A toppled, gap-toothed stone wall built from isometric brick blocks that march
## along an iso grid line (down-right), each course a different height so the
## crumbled crest reads as a broken silhouette. Variant rotates the height
## pattern and segment count so walls vary in length.

const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")

const HEIGHTS := [24.0, 34.0, 14.0, 30.0, 10.0, 32.0, 18.0, 28.0]


static func draw(canvas: CanvasItem, variant: int = 0) -> void:
	var stone := PixelPalette.pal("stone_b")
	var moss := PixelPalette.pal("grass_a").lerp(stone, 0.3)
	var n := 5 + variant % 3
	# Bricks step along the SE iso axis: +x tile direction is (+hw, +hh) on screen.
	var hw := 7.0
	var hh := hw * 0.5
	var step := Vector2(hw, hh)
	PixelDraw.draw_foot_shadow(canvas, float(n) * hw * 0.6 + 2.0, 6.0)
	# Start so the run is roughly centred on the origin.
	var start := -step * float(n - 1) * 0.5
	for i: int in n:
		var bh: float = HEIGHTS[(i + variant) % HEIGHTS.size()]
		var p := start + step * float(i)
		var base := stone if i % 2 == 0 else PixelPalette.shade(stone, 0.9)
		PixelDraw.iso_block(canvas, p.x, p.y, hw, hh, bh, base)
		# moss along the lit top edge of the course
		PixelDraw.px_rect(canvas, p.x - 1.0, p.y - bh - 1.0, hw, 2.0, moss, 0.5)
