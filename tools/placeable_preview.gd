extends SubViewportContainer
class_name PlaceablePreview
## A small "showcase turntable" for the world editor: pick a biome, micro-biome,
## terrain tile, structure, house, prop or creature in the sidebar and this panel
## renders ONE example of it with the real in-game pixel art, slowly spinning on
## an isometric tile so you can read its silhouette before placing it. Anything
## that is randomly generated on placement (variants, roof colours, decor scatter)
## just gets one rolled instance; the 🎲 button in the editor re-rolls it.
##
## It reuses the actual art path (WorldEntity / WorldDecor / IsoSprites), so the
## preview can never drift from what the world really spawns.

const WorldEntity := preload("res://scripts/world/world_entity.gd")
const WorldDecor := preload("res://scripts/world/world_decor.gd")
const WorldEntitySpawner := preload("res://scripts/world/world_entity_spawner.gd")
const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const StampLibrary := preload("res://scripts/worldgen/stamp_library.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const VIEW := Vector2i(176, 172)
const ROOF_COLORS := ["7a3b3b", "3b5a7a", "4a6b3a", "6b5a3a", "5a3b6b", "7a6b3a"]

var reg: RefCounted

var _vp: SubViewport
var _disc: _Turntable          # spins: the ground tile + planted/orbiting decor
var _upright: Node2D            # fixed: structures / creatures / gather nodes stand here
var _overlay: _Caption         # fixed: caption text at the bottom
var _origin := Vector2(float(VIEW.x) * 0.5, float(VIEW.y) * 0.62)
var _planted: Array[Node2D] = []   # decor that orbits with the disc but stays upright
var _spin := 0.0
var _variant := 0
var _reshow := Callable()       # re-runs the current selection (for re-roll)


func _ready() -> void:
	custom_minimum_size = VIEW
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.disable_3d = true
	add_child(_vp)

	_disc = _Turntable.new()
	_disc.position = _origin
	_vp.add_child(_disc)

	_upright = Node2D.new()
	_upright.position = _origin
	_vp.add_child(_upright)

	_overlay = _Caption.new()
	_overlay.size = VIEW
	_vp.add_child(_overlay)

	show_empty("Pick something to preview")


func _process(delta: float) -> void:
	_spin += delta * 0.7
	_disc.rotation = _spin
	# Keep planted decor upright while it orbits with the spinning tile.
	for d: Node2D in _planted:
		if is_instance_valid(d):
			d.rotation = -_spin


# ──────────────────────────────── public API ────────────────────────────────

## Re-roll the random parts (variant / colour / decor scatter) of the current item.
func reroll() -> void:
	_variant = (_variant + 1) % 100000
	if _reshow.is_valid():
		_reshow.call()


func show_empty(msg: String) -> void:
	_reshow = Callable()
	_clear()
	_disc.set_ground([Color(0.30, 0.34, 0.30)])
	_overlay.set_text(msg)


## A parent or micro-biome: textured ground + a scatter of that biome's clutter.
func show_biome(biome_id: String) -> void:
	_reshow = func() -> void: show_biome(biome_id)
	_clear()
	var idx := int(reg.biome_index.get(biome_id, -1))
	if idx < 0:
		show_empty("Unknown biome")
		return
	var name := str(reg.biomes[idx].get("name", biome_id))
	_disc.set_ground(_biome_ground_cols(idx))
	_scatter_biome_decor(biome_id, idx)
	_overlay.set_text(name)


## A single terrain/road/wall tile — just the spinning ground surface.
func show_terrain(tile_name: String, label: String) -> void:
	_reshow = func() -> void: show_terrain(tile_name, label)
	_clear()
	var tid := int(reg.tile_index.get(tile_name, -1))
	if tid < 0:
		show_empty("Unknown tile")
		return
	_disc.set_ground((reg.tile_def(tid)["colors"] as Array).duplicate())
	_overlay.set_text(label)


## A placed structure / house / prop, described by an editor STRUCTURES part dict.
func show_structure(part: Dictionary, label: String) -> void:
	_reshow = func() -> void: show_structure(part, label)
	_clear()
	_disc.set_ground(_neutral_ground())
	var e := _entity_from_part(part)
	_stand(e)
	_overlay.set_text(label)


## A bestiary creature / NPC, by display name.
func show_creature(name: String) -> void:
	_reshow = func() -> void: show_creature(name)
	_clear()
	_disc.set_ground(_neutral_ground())
	var e := WorldEntity.new()
	e.kind = "enemy"
	e.label = name
	e.enemy_shape = IsoSprites.enemy_shape(name)
	e.display_size = 40.0
	var enemy: Dictionary = DataRegistry.get_enemy(name)
	e.tier_color = WorldEntitySpawner.tier_color(int(enemy.get("level", 1)))
	_stand(e)
	var lvl := int(enemy.get("level", 0))
	_overlay.set_text(name if lvl <= 0 else "%s  ·  Lvl %d" % [name, lvl])


## A natural stamp (pond, grove, outcrop…): its dominant ground + the gather
## nodes it plants, so you see what a placement actually drops.
func show_stamp(stamp: Dictionary, label: String) -> void:
	_reshow = func() -> void: show_stamp(stamp, label)
	_clear()
	var built: Dictionary = StampLibrary.build(stamp, _variant, 0, false)
	_disc.set_ground(_stamp_ground_cols(built))
	var sites: Array = built.get("sites", [])
	var n: int = mini(sites.size(), 5)
	for i: int in n:
		var s: Dictionary = sites[i]
		var e := _gather_node_entity(str(s.get("skill", "")))
		if e == null:
			continue
		var ang := TAU * float(i) / float(maxi(n, 1))
		e.position = Vector2(cos(ang), sin(ang) * 0.5) * (14.0 if n > 1 else 0.0)
		_upright.add_child(e)
	if _upright.get_child_count() == 0:
		_overlay.set_text(label + "  (terrain only)")
	else:
		_overlay.set_text(label)
	_fit_upright()


# ──────────────────────────────── internals ─────────────────────────────────

func _clear() -> void:
	for c: Node in _upright.get_children():
		c.queue_free()
	for d: Node2D in _planted:
		if is_instance_valid(d):
			d.queue_free()
	_planted.clear()
	_upright.scale = Vector2.ONE


## Add an upright entity standing on the tile centre, scaled to frame nicely.
func _stand(e: Node2D) -> void:
	_upright.add_child(e)
	_fit_upright()


## Scale the upright holder so its tallest art fits the window with headroom.
func _fit_upright() -> void:
	var h := 24.0
	for c: Node in _upright.get_children():
		if c.has_method("icon_height"):
			h = maxf(h, float(c.call("icon_height")))
	var s := clampf((float(VIEW.y) * 0.56) / h, 0.45, 2.1)
	_upright.scale = Vector2(s, s)


func _entity_from_part(part: Dictionary) -> Node2D:
	var kind := str(part.get("kind", ""))
	var e := WorldEntity.new()
	e.kind = kind
	e.label = str(part.get("label", ""))
	e.variant = _variant
	e.display_size = 40.0
	e.roof_alpha = 1.0          # preview shows the full roof (no approach-fade)
	match kind:
		"tent":
			e.display_size = 54.0
			e.tent_color = _roll_roof()
			e.glow_color = e.tent_color
		"house":
			e.roof_color = _roll_roof()
		"building":
			e.display_size = float(part.get("foot", 6))
			e.roof_color = _roll_roof()
		"mountain":
			e.display_size = float(part.get("foot", 3))
			e.mountain_snow = float(part.get("snow", 0.4))
		"city_wall":
			e.variant = int(part.get("piece", 0))
		"city_prop":
			e.prop_kind = str(part.get("prop", "crate"))
		"obelisk":
			e.attuned = true
	return e


## A representative gather-node entity (tree/rock/bush/fish) for a skill.
func _gather_node_entity(skill: String) -> Node2D:
	var entries: Array = reg.node_table.get(skill, [])
	if entries.is_empty():
		return null
	var best: Dictionary = entries[0]
	for en: Dictionary in entries:
		if int(en["level"]) < int(best["level"]):
			best = en
	var cfg: Dictionary = reg.skill_cfg(skill)
	var e := WorldEntity.new()
	e.kind = str(cfg.get("kind", "bush"))
	e.label = str(best["name"])
	e.variant = _variant
	if e.kind == "tree":
		var TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
		e.display_size = TreeArt.tree_size(int(best["level"]), e.label)
	else:
		e.display_size = IsoSprites.node_size(e.kind)
	e.tier_color = WorldEntitySpawner.tier_color(int(best["level"]))
	return e


func _roll_roof() -> Color:
	return Color.from_string("#" + ROOF_COLORS[_variant % ROOF_COLORS.size()], Color(0.5, 0.3, 0.3))


func _neutral_ground() -> Array:
	var tid := int(reg.tile_index.get("grass", -1))
	if tid < 0:
		return [Color(0.34, 0.46, 0.28)]
	return (reg.tile_def(tid)["colors"] as Array).duplicate()


func _biome_ground_cols(idx: int) -> Array:
	var weights: Array = reg.biomes[idx].get("_tile_weights", [])
	var cols: Array = []
	for w: Array in weights:
		var td: Dictionary = reg.tile_def(int(w[0]))
		for c: Color in td.get("colors", []):
			cols.append(c)
		if cols.size() >= 4:
			break
	if cols.is_empty():
		return _neutral_ground()
	return cols


func _stamp_ground_cols(built: Dictionary) -> Array:
	var counts: Dictionary = {}
	for c: Dictionary in built.get("cells", []):
		var tn := str(c.get("tile", ""))
		if not tn.is_empty():
			counts[tn] = int(counts.get(tn, 0)) + 1
	var best := ""
	var best_n := -1
	for tn: String in counts:
		if int(counts[tn]) > best_n and reg.tile_index.has(tn):
			best_n = int(counts[tn])
			best = tn
	if best.is_empty():
		return _neutral_ground()
	return (reg.tile_def(int(reg.tile_index[best]))["colors"] as Array).duplicate()


## Scatter a handful of this biome's ground-decor clutter onto the tile so the
## biome reads as more than a flat colour (real WorldDecor art, biome kinds).
func _scatter_biome_decor(biome_id: String, _idx: int) -> void:
	var cfg: Dictionary = reg.ground_decor(biome_id)
	var kinds: Array = cfg.get("kinds", [])
	if kinds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome_id) + _variant * 7919
	var count := 7
	for i: int in count:
		var entry: Dictionary = kinds[rng.randi() % kinds.size()]
		var d := WorldDecor.new()
		d.kind = str(entry.get("kind", "grass"))
		d.variant = rng.randi() % 10000
		# Spread across the diamond surface (2:1 iso), upright via counter-spin.
		var u := rng.randf_range(-1.0, 1.0)
		var v := rng.randf_range(-1.0, 1.0)
		if absf(u) + absf(v) > 1.0:
			u *= 0.5
			v *= 0.5
		d.position = Vector2(u * 36.0, v * 18.0)
		_disc.add_child(d)
		_planted.append(d)


# ─────────────────────────── spinning tile renderer ──────────────────────────

class _Turntable:
	extends Node2D

	const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
	const HW := 48.0
	const HH := 24.0
	const DEPTH := 9.0

	var cols: Array = [Color(0.34, 0.46, 0.28)]

	func set_ground(p_cols: Array) -> void:
		cols = p_cols if not p_cols.is_empty() else [Color(0.34, 0.46, 0.28)]
		queue_redraw()

	func _draw() -> void:
		var top: Color = cols[0]
		# Earthy side skirt gives the tile a little thickness.
		PixelDraw.px_diamond(self, 0.0, DEPTH, HW, HH, top.darkened(0.5))
		PixelDraw.px_diamond(self, 0.0, DEPTH * 0.5, HW, HH, top.darkened(0.28))
		PixelDraw.px_diamond(self, 0.0, 0.0, HW, HH, top)
		# Dither in the other ground colours so the surface isn't a flat fill.
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		for i: int in 70:
			var u := rng.randf_range(-1.0, 1.0)
			var v := rng.randf_range(-1.0, 1.0)
			if absf(u) + absf(v) > 0.92:
				continue
			var c: Color = cols[rng.randi() % cols.size()]
			if c == top and cols.size() > 1:
				continue
			PixelDraw.px_rect(self, u * HW - 1.0, v * HH - 1.0, 2.0, 2.0, c)


# ───────────────────────────── caption renderer ──────────────────────────────

class _Caption:
	extends Control

	var _text := ""
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_text(t: String) -> void:
		_text = t
		queue_redraw()

	func _draw() -> void:
		if _text.is_empty():
			return
		var w := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
		var pos := Vector2((size.x - w) * 0.5, size.y - 8.0)
		draw_string(_font, pos + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.85))
		draw_string(_font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.9, 0.72))
