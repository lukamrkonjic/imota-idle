extends Node2D
## Floating name tags over sim-players, drawn on the 3D screen-space overlay so the world reads like
## a populated MMO ("name-tagged players" — SIM_PLAYERS_PLAN §3). Each sim's name is projected above
## its head through the live 3D camera every frame, in a cool player-blue to distinguish them from
## monsters. Off-screen sims are skipped. Cheap: a handful of draw_string calls for the capped roster.

var director: RefCounted        # SimDirector
var render_3d: WorldRender3D

const NAME_COL := Color(0.74, 0.86, 1.0)
const OUTLINE := Color(0.04, 0.05, 0.08, 0.95)
const FONT_SIZE := 11
var _font: Font


func _ready() -> void:
	z_index = 685   # under HP bars / hitsplats / bubbles, over the world
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if director == null or render_3d == null or not render_3d.is_active():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for sim in director.sims():
		var e: Node2D = sim.entity
		if not is_instance_valid(e):
			continue
		var head: float = render_3d.mover_top(e) + 0.18
		var p: Vector2 = render_3d.iso_to_screen(e.position, head)
		if p.x < -64.0 or p.y < -32.0 or p.x > vp.x + 64.0 or p.y > vp.y + 32.0:
			continue   # off-screen — skip projection draw
		_draw_name(str(sim.pname), p)


func _draw_name(text: String, center: Vector2) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var pos := Vector2(center.x - w * 0.5, center.y)
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NAME_COL)
