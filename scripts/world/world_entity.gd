extends Node2D
## Clickable world entity: a Node2D that carries an entity's position, interaction
## data, and size — the LOGIC substrate. The visible body is a 3D mesh rig built by
## the 3D renderer; this node is never drawn. Height measurement (for click-picking,
## hover tooltips and 3D HP-bar placement) lives in EntityDimensions, so this logic
## node no longer imports any art module.
## Origin (0,0) is the object's foot on the ground.

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
var yaw := 0.0                               # structures: Y-rotation (bridge decks orient along the path)
var prop_scale := 1.0                        # structures/decor: uniform size multiplier (editor Scale slider)
var height_offset := 0.0                     # structures: extra 3D height (bridge decks ride above the water)
# Bridge span: the two SOLID-GROUND endpoints (iso pos) + this segment's 0..1 position along the
# span. The renderer lerps the deck height between the endpoints' terrain heights so the bridge
# stays LEVEL and floats over the water/gap rather than sagging into it. bridge_t < 0 = not a span.
var bridge_a := Vector2.ZERO
var bridge_b := Vector2.ZERO
var bridge_t := -1.0
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
	return EntityDimensions.icon_height(self)


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
