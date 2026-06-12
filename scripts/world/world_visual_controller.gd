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
	_update_zone_and_biome()
	_update_darkness()
	_update_visibility_budget(delta)


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
	if world.current_layer < 0:
		_darkness.visible = false
		if world.unexplored_backdrop != null:
			world.unexplored_backdrop.visible = false
		return
	if world.unexplored_backdrop != null:
		world.unexplored_backdrop.visible = true
	_darkness.visible = true
	var vp := world.get_viewport().get_visible_rect().size
	var mat: ShaderMaterial = _darkness.material
	mat.set_shader_parameter("center", vp * 0.5)
	mat.set_shader_parameter("radius", minf(vp.x, vp.y) * 0.62)
	mat.set_shader_parameter("softness", minf(vp.x, vp.y) * 0.28)
	mat.set_shader_parameter("max_alpha", 0.34)


func _update_visibility_budget(delta: float) -> void:
	_visibility_timer -= delta
	if _visibility_timer > 0.0:
		return
	_visibility_timer = 0.18
	var vp := world.get_viewport().get_visible_rect().size
	var zoom: float = world._camera.zoom.x
	var world_size: Vector2 = vp / zoom
	var margin := WG.CHUNK_SIZE * 0.35
	var rect := Rect2(world._camera.global_position - world_size * 0.5 - Vector2(margin, margin), world_size + Vector2(margin * 2.0, margin * 2.0))
	for key: String in world._chunk_containers.keys():
		world._chunk_containers[key].visible = true
	var label_near := WG.TILE * (5.0 if zoom >= 0.82 else 2.8)
	for e: Node2D in world.entities:
		var should_label: bool = e != world.hovered_entity and (
			zoom >= 1.0 or e == world.combat_target_entity
			or e.position.distance_to(world.player.position) <= label_near)
		e.show_labels = should_label
	var show_decor: bool = zoom >= 0.84
	for d: Node2D in world._decor_nodes:
		if not is_instance_valid(d):
			continue
		d.visible = show_decor and rect.has_point(d.global_position)
