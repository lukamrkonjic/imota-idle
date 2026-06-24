extends RefCounted
class_name EntityDimensions
## On-screen height of a world entity, in pixels — used for click-picking bounds, hover-tooltip
## anchoring and 3D HP-bar lift.
##
## Lives here, not on WorldEntity, so the LOGIC substrate (world_entity.gd) doesn't import the art
## modules. This measurement bridge is the ONE place that reads art geometry; swap the art style and
## you touch this adapter, not the core entity logic. Pass any WorldEntity-like node as `e`.

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const EnemyArt := preload("res://scripts/world/art/characters/enemy_art.gd")


static func icon_height(e) -> float:
	var ds := float(e.display_size)
	match str(e.kind):
		"tree":
			return TreeArt.estimated_height(TreeArt.classify(str(e.label)), ds) + 10.0
		"rock":
			return ds * 0.38
		"bush":
			return ds * 0.34
		"fish":
			return ds * 0.24
		"enemy":
			var label := str(e.label)
			var sp := EnemyArt.shape_for_name(label if not label.is_empty() else str(e.action.get("name", "")))
			var tall := sp in ["cow", "pig", "sheep", "wolf", "goat", "brainbasher", "goblin"]
			return ds * (1.35 if bool(e.is_boss) else (0.92 if tall else 0.8))
		"tent":
			return ds * 0.95
		"chest":
			return ds * 0.5
		"campfire", "anvil", "sign":
			return 26.0
		"altar":
			return 32.0
		"obelisk":
			return 60.0
		"cave":
			return 32.0
		"burrow":
			return 32.0
		"ladder_up":
			return 34.0
		"ladder_down":
			return 12.0
		"stall":
			return 28.0
		"landmark_tree":
			return TreeArt.estimated_height("magic", ds) + 10.0
		"meteor":
			return 16.0
		"mammoth":
			return 40.0
		"ruin_arch":
			return 104.0
		"ruin_pillar":
			return 82.0
		"broken_wall":
			return 38.0
		"rubble_pile":
			return 22.0
		"broken_statue":
			return 70.0
		"house":
			return IsoSprites.house_height(int(e.variant))
		"building":
			return IsoSprites.building_height(ds, int(e.variant))
		"mountain":
			return IsoSprites.mountain_height(ds, int(e.variant))
		"fountain":
			return 40.0
		"city_wall":
			return 82.0
		"bridge":
			return 10.0
		"city_prop":
			return 30.0
	return ds * 0.5
