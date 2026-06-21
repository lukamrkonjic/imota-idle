extends Node2D
## Clickable world entity: a Node2D that carries an entity's position, interaction
## data, and size — the LOGIC substrate. The visible body is a 3D mesh rig built by
## the 3D renderer; this node is never drawn. These art modules are retained only to
## MEASURE entity heights (icon_height) for click-picking, hover tooltips and 3D
## HP-bar placement.
## Origin (0,0) is the object's foot on the ground.

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const EnemyArt := preload("res://scripts/world/art/characters/enemy_art.gd")
const STATION_LABELS := {
	"bank": "Bank chest",
	"shop": "General store",
	"anvil": "Anvil",
	"fire": "Fire",
	"altar": "Altar",
}

var kind := "tree"          # tree|rock|bush|fish|enemy|tent|campfire|chest|sign|anvil
							# |altar|obelisk|cave|ladder_up|ladder_down|stall
							# |landmark_tree|meteor|mammoth
var tier_color := Color(0.23, 0.53, 0.25)
var display_size := 50.0
var variant := 0
var label := ""
var sub_label := ""
var click_radius := 30.0
var enemy_shape := "humanoid"
var is_boss := false
var tent_color := Color(0.64, 0.47, 0.31)
var glow_color := Color(0.7, 0.55, 0.95)  # altars/shrines
var attuned := false                       # obelisks
var roof_color := Color(0.5, 0.3, 0.3)     # houses
var prop_kind := ""                         # city_prop subtype
var mountain_snow := 0.0                     # mountains: 0..1 snow cap coverage
var roof_alpha := 1.0                        # houses — fades as the player nears (read by the 3D renderer)

var action: Dictionary = {}

var hp_fraction := -1.0
# Read by the 3D renderer each frame: dimmed → death pose, hovered/highlight_outline → contour outline.
var dimmed := false
var hovered := false
var show_labels := false
var highlight_outline := false


func set_hp_fraction(f: float) -> void:
	hp_fraction = f


func icon_height() -> float:
	match kind:
		"tree":
			return TreeArt.estimated_height(TreeArt.classify(label), display_size) + 10.0
		"rock":
			return display_size * 0.38
		"bush":
			return display_size * 0.34
		"fish":
			return display_size * 0.24
		"enemy":
			var sp := EnemyArt.shape_for_name(label if not label.is_empty() else str(action.get("name", "")))
			var tall := sp in ["cow", "pig", "sheep", "wolf", "goat", "brainbasher", "goblin"]
			return display_size * (1.35 if is_boss else (0.92 if tall else 0.8))
		"tent":
			return display_size * 0.95
		"chest":
			return display_size * 0.5
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
			return TreeArt.estimated_height("magic", display_size) + 10.0
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
			return IsoSprites.house_height(variant)
		"building":
			return IsoSprites.building_height(display_size, variant)
		"mountain":
			return IsoSprites.mountain_height(display_size, variant)
		"fountain":
			return 40.0
		"city_wall":
			return 82.0
		"bridge":
			return 10.0
		"city_prop":
			return 30.0
	return display_size * 0.5


## The on-screen name, resolved to the renamed displayName for Bloobs content
## (gather nodes, enemies) and cached so it costs one lookup per entity, not one
## per frame. POI/station/landmark labels are procedural and pass through.
var _display_label := ""
var _display_label_ready := false

func display_label() -> String:
	if _display_label_ready:
		return _display_label
	_display_label_ready = true
	_display_label = label
	match str(action.get("type", "")):
		"gather":
			var node: Dictionary = DataRegistry.get_gather_node(str(action.get("skill", "")), str(action.get("node", label)))
			if not node.is_empty():
				_display_label = str(node.get("displayName", label))
		"enemy":
			_display_label = DataRegistry.enemy_display_name(str(action.get("name", label)))
	return _display_label


func is_interactable() -> bool:
	return str(action.get("type", "")) in [
		"gather", "enemy", "station", "descend", "ascend", "obelisk", "landmark", "npc"]


func tooltip_content() -> Dictionary:
	var details: PackedStringArray = []
	var title := label
	var subtitle := sub_label
	match str(action.get("type", "")):
		"gather":
			var skill := str(action.get("skill", ""))
			var node: Dictionary = DataRegistry.get_gather_node(skill, label)
			if not node.is_empty():
				title = str(node.get("displayName", label))
				var gives: PackedStringArray = []
				for it: String in node["items"]:
					gives.append(DataRegistry.item_display_name(it))
				details.append("Gives: %s" % ", ".join(gives))
				details.append("%.0f XP per gather" % float(node["xp"]))
			if dimmed:
				details.append("Depleted — respawning soon")
		"enemy":
			# Always render the renamed display name, never the raw legacy name.
			title = DataRegistry.enemy_display_name(str(action.get("name", label if not label.is_empty() else "Enemy")))
			if subtitle.is_empty():
				subtitle = "Lvl %d" % int(action.get("level", 1))
			var enemy: Dictionary = DataRegistry.get_enemy(str(action.get("name", label)))
			if not enemy.is_empty():
				var hp := int(enemy.get("maxHealth", int(enemy.get("level", 1)) * 4))
				details.append("Hitpoints: %d" % hp)
				var style := str(enemy.get("style", ""))
				if not style.is_empty():
					details.append("Style: %s" % style)
				var slayer_req := int(enemy.get("beastMasteryReq", 0))
				if slayer_req > 0:
					details.append("Slayer req: %d" % slayer_req)
				var drops: Array = enemy.get("drops", [])
				if not drops.is_empty():
					var drop_bits: PackedStringArray = []
					for d: Variant in drops.slice(0, 4):
						if d is Dictionary:
							drop_bits.append(DataRegistry.item_display_name(str(d.get("item", "?"))))
					var extra := drops.size() - 4
					if extra > 0:
						drop_bits.append("+%d more" % extra)
					if not drop_bits.is_empty():
						details.append("Drops: %s" % ", ".join(drop_bits))
			if dimmed:
				details.append("Respawning soon")
			elif bool(action.get("aggressive", false)):
				details.append("Aggressive")
		"station":
			var st := str(action.get("station", ""))
			title = STATION_LABELS.get(st, label if not label.is_empty() else st.capitalize())
			subtitle = ""
			match st:
				"bank":
					details.append("Store and withdraw items")
				"shop":
					details.append("Buy and sell goods")
				"anvil":
					details.append("Smith metal gear and tools")
				"fire":
					details.append("Cook food and burn logs")
				"altar":
					details.append("Pray for Prayer bonuses")
		"descend":
			subtitle = ""
			details.append("Leads deeper underground")
		"ascend":
			subtitle = ""
			details.append("Returns to the surface")
		"obelisk":
			subtitle = "Obelisk" if attuned else "Unattuned obelisk"
			details.append("Fast travel once attuned")
		"hook":
			details.append(str(action.get("message", "Coming soon.")))
		"landmark":
			subtitle = "Landmark"
		"npc":
			subtitle = "NPC"
			details.append("Click to talk")
	return {
		"title": title,
		"subtitle": subtitle,
		"action": action_text(),
		"details": details,
	}


func action_text() -> String:
	match str(action.get("type", "")):
		"gather":
			return "%s %s" % [SkillRegistry.verb(str(action["skill"])), display_label()]
		"enemy":
			return "Attack %s (%s)" % [display_label(), sub_label]
		"station":
			var st := str(action["station"])
			if st == "bank":
				return "Open Bank"
			if st == "shop":
				return "Browse Shop"
			return "Use %s" % (STATION_LABELS.get(st, label) if not label.is_empty() else st.capitalize())
		"descend":
			return "Enter %s" % label
		"ascend":
			return "Climb up"
		"obelisk":
			return "Attune Obelisk" if not attuned else "Teleport (Obelisk)"
		"hook":
			return "Inspect %s" % label
		"landmark":
			return "Marvel at %s" % label
		"npc":
			return "Talk to %s" % label
	return ""
