extends RefCounted
class_name WorldVisualController
## Fog, ambient tint, zone/biome announcements, label visibility, XP float.

const WG := preload("res://scripts/worldgen/wg.gd")
const UiScale := preload("res://scripts/ui/ui_scale.gd")

var world: Node2D

var _zone_id := ""
var _biome_id := ""
var _darkness: ColorRect
var _visibility_timer := 0.0
var _xp_float_cooldown := 0.0
var _alt_hints_active := false
var _wind_redraw_accum := 0.0
var _ambience_accum := 0.0
var _water_anim_accum := 0.0
var _cached_visible_rect := Rect2()
var _darkness_vp := Vector2.ZERO

# Rolling entity-visibility cursor. The per-entity view test (a method + several
# property reads over ~1000+ entities) used to run for the whole world in one
# frame every 0.18s — a ~2.5ms spike that landed as a periodic walk hitch. It is
# now sliced across frames against the current camera rect. The slice is sized so
# a full pass still takes ~0.18s (≈ VIS_PASS_FRAMES frames), so an entity is
# re-tested exactly as often as before and the total work is unchanged — the
# spike is just spread into a flat sub-millisecond per-frame cost.
const VIS_PASS_FRAMES := 11
const VIS_SLICE_MIN := 96
# Live-animate only entities within this world-space distance of the player (~the
# immediate surroundings); everything farther freezes to a baked blit.
const ANIM_NEAR_DIST_SQ := 400.0 * 400.0
var _vis_cursor := 0
var _vis_accum: Array = []

const TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
const WaterSurfaceArt := preload("res://scripts/world/art/water/water_surface_art.gd")


func setup(w: Node2D) -> void:
	world = w


func build_darkness() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	world.add_child(layer)
	_darkness = ColorRect.new()
	_darkness.set_anchors_preset(Control.PRESET_FULL_RECT)
	_darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec2 center = vec2(640.0, 360.0);
uniform float radius = 260.0;
uniform float softness = 110.0;
uniform float max_alpha = 0.52;
void fragment() {
	float d = distance(FRAGCOORD.xy, center);
	float a = smoothstep(radius - softness, radius + softness, d);
	COLOR = vec4(0.133, 0.133, 0.157, a * max_alpha);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_darkness.material = m
	_darkness.visible = false
	layer.add_child(_darkness)


func process_tick(delta: float) -> void:
	_xp_float_cooldown = maxf(_xp_float_cooldown - delta, 0.0)
	TreeArt.advance_wind(delta)
	_cached_visible_rect = _visible_world_rect()
	# Cheap (a handful of AABB tests) and done every frame so terrain shows/hides
	# right at the view edge with no late pop when panning or walking fast.
	world.chunk_manager.set_view_rect(_cached_visible_rect)
	if world.current_layer == 0:
		_wind_redraw_accum += delta
		if _wind_redraw_accum >= 0.12:
			_wind_redraw_accum = 0.0
			_queue_visible_tree_redraw()
		_ambience_accum += delta
		if _ambience_accum >= 0.15:
			_ambience_accum = 0.0
			if is_instance_valid(world._ambience):
				world._ambience.queue_redraw()
		if world._camera.zoom.x >= 0.7:
			_water_anim_accum += delta
			if _water_anim_accum >= 0.15:
				_water_anim_accum = 0.0
				WaterSurfaceArt.advance_time(0.15)
				_queue_visible_water_redraw()
	_update_interactable_outlines()
	_update_zone_and_biome()
	_update_darkness()
	_update_visibility_budget(delta)
	_update_house_roofs(delta)


func reset_biome_tracking() -> void:
	_biome_id = ""


func show_xp_float(skill: String, amount: float) -> void:
	if _xp_float_cooldown > 0.0:
		return
	_xp_float_cooldown = 0.25
	var lbl := Label.new()
	lbl.text = "+%.0f %s xp" % [amount, skill.capitalize()]
	lbl.add_theme_font_size_override("font_size", UiScale.i(13))
	lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.position = world.player.position + Vector2(-32, -78)
	lbl.z_index = 100
	world.add_child(lbl)
	var tw := world.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)


func _update_zone_and_biome() -> void:
	var zone: Dictionary = WorldGen.zone_at(world.player.position)
	if str(zone["id"]) != _zone_id:
		_zone_id = str(zone["id"])
		if not WorldGen.store.visited_zones.has(_zone_id):
			WorldGen.store.visited_zones[_zone_id] = true
			EventBus.combat_log.emit("[color=#5a3a8a]Now entering %s (level %d %s zone).[/color]" % [
				str(zone["name"]), int(zone["req"]), str(zone["tier"])])
		EventBus.zone_changed.emit(str(zone["name"]), int(zone["req"]))
	if world.current_layer == 0:
		var biome_id: String = WorldGen.biome_id_at(world.player.position)
		if biome_id != _biome_id:
			_biome_id = biome_id
			var b: Dictionary = WorldGen.reg.biome_by_id(biome_id)
			EventBus.biome_changed.emit(biome_id, str(b.get("music", "")))


func _update_darkness() -> void:
	if _darkness != null:
		_darkness.visible = false
	if world.current_layer < 0:
		if world.unexplored_backdrop != null:
			world.unexplored_backdrop.visible = false
		return
	if world.unexplored_backdrop != null:
		world.unexplored_backdrop.visible = not (
			WorldGen.reg.spec.active and WorldGen.reg.spec.finite)


func _update_visibility_budget(delta: float) -> void:
	# Entities are sliced every frame (the dominant cost) against the rect already
	# computed this tick; containers + decor are far cheaper and stay throttled.
	_update_entity_visibility_slice(_cached_visible_rect)
	_visibility_timer -= delta
	if _visibility_timer > 0.0:
		return
	_visibility_timer = 0.18
	var zoom: float = world._camera.zoom.x
	var rect := _cached_visible_rect
	for key: String in world._chunk_containers.keys():
		var container: Node2D = world._chunk_containers[key]
		if container.has_meta("streaming_complete") and not bool(container.get_meta("streaming_complete")):
			container.visible = false
			continue
		# The chunk AABB is fixed for a container's lifetime, so parse the key once
		# and cache it — the per-frame string split over the whole active ring was
		# pure waste.
		var aabb: Rect2 = container.get_meta("vis_aabb", Rect2())
		if aabb.size == Vector2.ZERO:
			var parts: PackedStringArray = key.split(":")
			if parts.size() != 3:
				container.visible = true
				continue
			aabb = WG.chunk_aabb(int(parts[1]), int(parts[2])).grow(WG.CHUNK_SIZE * 0.75)
			container.set_meta("vis_aabb", aabb)
		container.visible = aabb.intersects(rect)
	# Zoom LOD: tiny clutter is invisible (and very expensive) when zoomed out, so
	# stop drawing ground/water decor past these thresholds.
	var show_decor: bool = zoom >= 0.84
	var show_water: bool = zoom >= 0.7
	for d: Node2D in world._decor_nodes:
		if not is_instance_valid(d):
			continue
		d.visible = show_decor and rect.has_point(d.global_position)
	for d: Node2D in world._water_decor_nodes:
		if not is_instance_valid(d):
			continue
		d.visible = show_water and rect.has_point(d.global_position)


## Advance the rolling entity-visibility pass by one slice. Each entity's view
## flag is updated against the current rect; the freshly-visible set is committed
## to world._visible_entities only when a full pass completes, so hot consumers
## (hover, outlines, tree redraw) always read a coherent list.
func _update_entity_visibility_slice(rect: Rect2) -> void:
	var ents: Array = world.entities
	var n := ents.size()
	if n == 0:
		world._visible_entities = []
		_vis_accum = []
		_vis_cursor = 0
		return
	var slice := maxi(VIS_SLICE_MIN, ceili(float(n) / float(VIS_PASS_FRAMES)))
	var pp: Vector2 = world.player.position
	var processed := 0
	while processed < slice:
		if _vis_cursor >= n:
			# Pass complete: publish the new visible set and start the next sweep.
			world._visible_entities = _vis_accum
			_vis_accum = []
			_vis_cursor = 0
			return
		var e: Node2D = ents[_vis_cursor]
		_vis_cursor += 1
		processed += 1
		if not is_instance_valid(e):
			continue
		var in_view := _entity_intersects_rect(e, rect)
		e.visible = in_view
		# Only entities close to the player run live procedural animation; distant
		# visible ones freeze to a cheap baked blit. Live procedural art is the
		# dominant walking render cost (disabling baking quadrupled the slow frames).
		e.set_animate_near(in_view and e.position.distance_squared_to(pp) < ANIM_NEAR_DIST_SQ)
		if in_view:
			_vis_accum.append(e)
		elif e.highlight_outline:
			e.highlight_outline = false


func _entity_intersects_rect(e: Node2D, rect: Rect2) -> bool:
	var h := float(e.call("icon_height")) if e.has_method("icon_height") else float(e.get("display_size"))
	var r := maxf(maxf(float(e.get("click_radius")), float(e.get("display_size")) * 0.75), 28.0)
	var pos := e.global_position
	var bounds := Rect2(pos - Vector2(r, h + r), Vector2(r * 2.0, h + r * 2.0))
	return rect.intersects(bounds)


## Fade a house's roof out as the player steps inside, so city interiors and
## their crafting stations become visible and clickable (OSRS-style).
func _update_house_roofs(delta: float) -> void:
	if world.current_layer != 0:
		return
	var pp: Vector2 = world.player.position
	for e: Node2D in world._roofed_entities:
		# Tight radius so the roof only lifts when you're actually under the footprint,
		# not flickering as you walk past or beside it.
		var radius := 34.0 if e.kind == "house" else maxf(64.0, float(e.display_size) * float(WG.ISO_HW) * 0.8)
		var target := 0.0 if pp.distance_to(e.position) < radius else 1.0
		if not is_equal_approx(e.roof_alpha, target):
			e.roof_alpha = move_toward(e.roof_alpha, target, delta * 4.5)


func _visible_world_rect() -> Rect2:
	var vp := world.get_viewport().get_visible_rect().size
	var zoom: float = world._camera.zoom.x
	var world_size: Vector2 = vp / zoom
	var margin := WG.CHUNK_SIZE * 0.4
	return Rect2(
		world._camera.global_position - world_size * 0.5 - Vector2(margin, margin),
		world_size + Vector2(margin * 2.0, margin * 2.0))


func _queue_visible_tree_redraw() -> void:
	var rect := _cached_visible_rect if _cached_visible_rect.size != Vector2.ZERO else _visible_world_rect()
	for raw: Variant in _visible_entity_list():
		if not is_instance_valid(raw):
			continue
		var e: Node2D = raw
		if e.kind != "landmark_tree":
			continue
		if rect.has_point(e.position):
			e.queue_redraw()


func _queue_visible_water_redraw() -> void:
	var rect := _cached_visible_rect if _cached_visible_rect.size != Vector2.ZERO else _visible_world_rect()
	for d: Node2D in world._water_decor_nodes:
		if not is_instance_valid(d):
			continue
		if d.kind == "lily":
			continue
		if rect.has_point(d.global_position):
			d.queue_redraw()


func _update_interactable_outlines() -> void:
	var alt := Input.is_key_pressed(KEY_ALT)
	if not alt and not _alt_hints_active:
		return
	_alt_hints_active = alt
	var rect := _cached_visible_rect if _cached_visible_rect.size != Vector2.ZERO else _visible_world_rect()
	for raw: Variant in _visible_entity_list():
		if not is_instance_valid(raw):
			continue
		var e: Node2D = raw
		if not e.has_method("is_interactable") or not e.call("is_interactable"):
			e.highlight_outline = false
			continue
		e.highlight_outline = alt and rect.has_point(e.position)


func _visible_entity_list() -> Array:
	if world._visible_entities.is_empty():
		return world.entities
	return world._visible_entities
