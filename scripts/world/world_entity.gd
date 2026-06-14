extends Node2D
## Clickable 2D world entity drawn in the Aldenfall pixel style.
## Origin (0,0) is the object's foot on the ground; sprites rise upward.

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const EnemyArt := preload("res://scripts/world/art/characters/enemy_art.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const ANIMATED_KINDS := ["fish", "enemy", "campfire", "anvil", "altar", "obelisk", "meteor", "fountain"]
const GATHER_VERB := {"woodcutting": "Chop", "mining": "Mine", "fishing": "Fish", "foraging": "Pick"}
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
var tent_color := Color(0.42, 0.33, 0.55)
var glow_color := Color(0.7, 0.55, 0.95)  # altars/shrines
var attuned := false                       # obelisks
var roof_color := Color(0.5, 0.3, 0.3)     # houses
var prop_kind := ""                         # city_prop subtype
var mountain_snow := 0.0                     # mountains: 0..1 snow cap coverage
var roof_alpha := 1.0:                      # houses — fades as the player nears
	set(v):
		if is_equal_approx(roof_alpha, v):
			return
		roof_alpha = v
		queue_redraw()

var action: Dictionary = {}

var hp_fraction := -1.0
var dimmed := false:
	set(v):
		dimmed = v
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()
var show_labels := false:
	set(v):
		if show_labels == v:
			return
		show_labels = v
		queue_redraw()
var highlight_outline := false:
	set(v):
		if highlight_outline == v:
			return
		highlight_outline = v
		queue_redraw()

var _t := 0.0
var _font: Font

const OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(-2.0, 0.0), Vector2(2.0, 0.0), Vector2(0.0, -2.0), Vector2(0.0, 2.0),
	Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(-2.0, 2.0), Vector2(2.0, 2.0),
]


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_t = float(variant % 100) * 0.13
	set_process(kind in ANIMATED_KINDS)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_hp_fraction(f: float) -> void:
	hp_fraction = f
	queue_redraw()


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
			return 56.0
		"bridge":
			return 10.0
		"city_prop":
			return 30.0
	return display_size * 0.5


func _draw() -> void:
	if highlight_outline:
		SilhouetteDraw.active = true
		for off: Vector2 in OUTLINE_OFFSETS:
			draw_set_transform(off, 0.0, Vector2.ONE)
			_draw_sprite()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		SilhouetteDraw.active = false
	_draw_sprite()
	if show_labels:
		_draw_labels()
	if hp_fraction >= 0.0:
		var bar_w := 44.0
		var top := Vector2(-bar_w / 2.0, -icon_height() - 26.0)
		draw_rect(Rect2(top, Vector2(bar_w, 6)), Color(0.55, 0.1, 0.1))
		draw_rect(Rect2(top, Vector2(bar_w * clampf(hp_fraction, 0.0, 1.0), 6)), Color(0.15, 0.7, 0.15))


func _draw_sprite() -> void:
	match kind:
		"tree", "rock", "bush", "fish":
			IsoSprites.draw_prop(self, kind, display_size, tier_color, variant, dimmed, _t, label)
		"enemy":
			if dimmed:
				PixelDraw.draw_tight_character_shadow(
					self, EnemyArt._shadow_half_width(enemy_shape, display_size, is_boss), 4.0, 0.28)
			else:
				var enemy_name := label if not label.is_empty() else str(action.get("name", ""))
				IsoSprites.draw_enemy(self, enemy_name, enemy_shape, display_size, tier_color, is_boss, _t)
		"tent":
			IsoSprites.draw_tent(self, display_size, tent_color)
		"campfire":
			IsoSprites.draw_campfire(self, _t)
		"chest":
			IsoSprites.draw_chest(self, display_size, PixelPalette.hex(0x8A6848), dimmed)
		"sign":
			IsoSprites.draw_sign(self)
		"anvil":
			IsoSprites.draw_anvil(self, _t)
		"altar":
			IsoSprites.draw_altar(self, _t, glow_color)
		"obelisk":
			IsoSprites.draw_obelisk(self, _t, attuned)
		"cave":
			IsoSprites.draw_cave_mouth(self)
		"ladder_up":
			IsoSprites.draw_ladder(self, true)
		"ladder_down":
			IsoSprites.draw_ladder(self, false)
		"stall":
			IsoSprites.draw_stall(self)
		"landmark_tree":
			TreeArt.draw(self, "Magic Tree", display_size, tier_color, false, _t)
		"meteor":
			IsoSprites.draw_meteor(self, _t)
		"mammoth":
			IsoSprites.draw_mammoth(self)
		"ruin_arch":
			IsoSprites.draw_ruin_arch(self, variant)
		"ruin_pillar":
			IsoSprites.draw_ruin_pillar(self, variant)
		"broken_wall":
			IsoSprites.draw_broken_wall(self, variant)
		"rubble_pile":
			IsoSprites.draw_rubble_pile(self, variant)
		"broken_statue":
			IsoSprites.draw_broken_statue(self, variant)
		"house":
			IsoSprites.draw_house_body(self, variant, roof_color)
			IsoSprites.draw_house_roof(self, variant, roof_color, roof_alpha)
		"building":
			IsoSprites.draw_building_body(self, display_size, variant, roof_color)
			IsoSprites.draw_building_roof(self, display_size, variant, roof_color, roof_alpha)
		"mountain":
			IsoSprites.draw_mountain(self, display_size, variant, mountain_snow)
		"fountain":
			IsoSprites.draw_fountain(self, _t)
		"city_wall":
			IsoSprites.draw_city_wall(self, variant)
		"bridge":
			IsoSprites.draw_bridge(self)
		"city_prop":
			IsoSprites.draw_city_prop(self, prop_kind, variant, _t)


func _draw_labels() -> void:
	var h := icon_height()
	if not label.is_empty():
		_plate(label, Vector2(0, -h - 12.0), 11, Color(0.95, 0.92, 0.72))
	if not sub_label.is_empty():
		_plate(sub_label, Vector2(0, -h - 2.0), 10, Color(0.78, 0.78, 0.78))


func is_interactable() -> bool:
	return str(action.get("type", "")) in [
		"gather", "enemy", "station", "descend", "ascend", "obelisk", "landmark"]


func _plate(text: String, at: Vector2, size: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	var pos := at + Vector2(-tw / 2.0, 0)
	draw_string(_font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func tooltip_content() -> Dictionary:
	var details: PackedStringArray = []
	var title := label
	var subtitle := sub_label
	match str(action.get("type", "")):
		"gather":
			var skill := str(action.get("skill", ""))
			var node: Dictionary = DataRegistry.get_gather_node(skill, label)
			if not node.is_empty():
				details.append("Gives: %s" % ", ".join(PackedStringArray(node["items"])))
				details.append("%.0f XP per gather" % float(node["xp"]))
			if dimmed:
				details.append("Depleted — respawning soon")
		"enemy":
			if title.is_empty():
				title = DataRegistry.enemy_display_name(str(action.get("name", "Enemy")))
			if subtitle.is_empty():
				subtitle = "Lvl %d" % int(action.get("level", 1))
			var enemy: Dictionary = DataRegistry.get_enemy(str(action.get("name", label)))
			if not enemy.is_empty():
				var hp := int(enemy.get("maxHealth", int(enemy.get("level", 1)) * 4))
				details.append("Hitpoints: %d" % hp)
				var style := str(enemy.get("style", ""))
				if not style.is_empty():
					details.append("Style: %s" % style)
				var bm_req := int(enemy.get("beastMasteryReq", 0))
				if bm_req > 0:
					details.append("Beastmastery req: %d" % bm_req)
				var drops: Array = enemy.get("drops", [])
				if not drops.is_empty():
					var drop_bits: PackedStringArray = []
					for d: Variant in drops.slice(0, 4):
						if d is Dictionary:
							drop_bits.append(str(d.get("item", "?")))
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
					details.append("Pray for devotion bonuses")
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
	return {
		"title": title,
		"subtitle": subtitle,
		"action": action_text(),
		"details": details,
	}


func action_text() -> String:
	match str(action.get("type", "")):
		"gather":
			return "%s %s" % [GATHER_VERB.get(str(action["skill"]), "Gather"), label]
		"enemy":
			return "Attack %s (%s)" % [label, sub_label]
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
	return ""
