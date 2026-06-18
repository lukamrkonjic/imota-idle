extends Node2D
## Screen-space combat HP bars over the player and the current target. The 2D
## world's floating bars are hidden under the 3D renderer, so during a fight we
## draw both bars here on the FX overlay, projected through the 3D camera and
## anchored to each body's size (small mobs low, big mobs high).

var world: Node2D
var render_3d: Node

const BAR_W := 52.0
const BAR_H := 7.0


func _ready() -> void:
	z_index = 690
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not CombatSim.active or render_3d == null or not render_3d.is_active():
		return
	var tgt: Node2D = world.combat_target_entity
	if is_instance_valid(tgt) and not tgt.dimmed:
		var maxh := maxf(float(CombatSim.enemy.get("maxHealth", 1)), 1.0)
		_bar(tgt.position, render_3d.mover_lift(tgt) + 0.55, CombatSim.enemy_hp / maxh)
	if world.player != null:
		var pf := float(GameState.current_hp) / maxf(float(GameState.max_hp()), 1.0)
		_bar(world.player.position, render_3d.mover_lift(world.player) + 0.65, pf)


func _bar(world_pos: Vector2, lift: float, frac: float) -> void:
	var c: Vector2 = render_3d.iso_to_screen(world_pos, lift)
	var top := c - Vector2(BAR_W * 0.5, BAR_H * 0.5)
	draw_rect(Rect2(top - Vector2(1.5, 1.5), Vector2(BAR_W + 3.0, BAR_H + 3.0)), Color(0.05, 0.05, 0.07, 0.7))
	draw_rect(Rect2(top, Vector2(BAR_W, BAR_H)), Color(0.55, 0.1, 0.1))
	draw_rect(Rect2(top, Vector2(BAR_W * clampf(frac, 0.0, 1.0), BAR_H)), Color(0.2, 0.76, 0.22))
