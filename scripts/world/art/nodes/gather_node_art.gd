extends RefCounted
class_name GatherNodeArt
## Gather-site props: trees, rocks, bushes, fishing spots.

const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const RockArt := preload("res://scripts/world/art/nodes/rock_art.gd")
const BushArt := preload("res://scripts/world/art/nodes/bush_art.gd")
const FishArt := preload("res://scripts/world/art/nodes/fish_art.gd")

const NODE_SIZE := {
	"tree": 78.0,
	"rock": 34.0,
	"bush": 26.0,
	"fish": 30.0,
}


static func node_size(kind: String) -> float:
	return NODE_SIZE.get(kind, 40.0)


static func estimated_height(kind: String, size: float, label: String = "") -> float:
	match kind:
		"tree":
			return TreeArt.estimated_height(TreeArt.classify(label), size) + 10.0
		"rock":
			return size * 0.38
		"bush":
			return size * 0.32
		"fish":
			return size * 0.22
		_:
			return size * 0.5


static func draw_prop(
	canvas: CanvasItem,
	kind: String,
	size: float,
	tier_color: Color,
	_variant: int,
	depleted: bool,
	t: float,
	label: String = "",
) -> void:
	match kind:
		"tree":
			TreeArt.draw(canvas, label, size, tier_color, depleted, t)
		"rock":
			RockArt.draw(canvas, size, tier_color, depleted)
		"bush":
			var berry := tier_color if tier_color.a > 0.01 else Color(0.75, 0.25, 0.38)
			BushArt.draw(canvas, size, berry, depleted)
		"fish":
			FishArt.draw(canvas, size, t)
