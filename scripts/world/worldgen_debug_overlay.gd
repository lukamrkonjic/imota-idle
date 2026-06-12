extends Node2D
## In-game worldgen inspector. F3 cycles: off -> biome -> elevation ->
## climate -> anchors. Draws translucent per-tile overlays for the loaded
## chunks plus a screen-space header (seed, chunk, zone, mode). Worldgen is
## impossible to tune blind; this is the visual half of tools/world_debug.gd.
## Pure presentation: reads WorldGen + the world's chunk manager, writes
## nothing, costs nothing while off.

const WG := preload("res://scripts/worldgen/wg.gd")

const MODES: Array = ["off", "biome", "elevation", "climate", "anchors"]

var world: Node2D
var mode := 0

var _header: Label
var _header_layer: CanvasLayer
var _last_player_chunk := Vector2i(2000000, 2000000)


func _ready() -> void:
	z_index = 800
	_header_layer = CanvasLayer.new()
	_header_layer.layer = 90
	add_child(_header_layer)
	_header = Label.new()
	_header.position = Vector2(10, 36)
	_header.add_theme_color_override("font_color", Color(1, 1, 0.7))
	_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_header.add_theme_constant_override("outline_size", 6)
	_header_layer.add_child(_header)
	_header_layer.visible = false
	if world != null and world.chunk_manager != null:
		world.chunk_manager.chunk_loaded.connect(func(_c: RefCounted) -> void:
			if mode > 0:
				queue_redraw())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		mode = (mode + 1) % MODES.size()
		_header_layer.visible = mode > 0
		queue_redraw()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if mode == 0 or world == null or world.player == null:
		return
	var pc := WG.world_to_chunk(world.player.position)
	if pc != _last_player_chunk:
		_last_player_chunk = pc
		queue_redraw()
	_update_header(pc)


func _update_header(pc: Vector2i) -> void:
	var zone: Dictionary = WorldGen.zone_at(world.player.position)
	var elev: int = WorldGen.elevation_at(world.player.position)
	_header.text = "F3 worldgen: %s | seed %d | chunk %d,%d | elev %d | %s (req %d, %s)" % [
		str(MODES[mode]), int(WorldGen.store.world_seed), pc.x, pc.y, elev,
		str(zone.get("name", "?")), int(zone.get("req", 1)), str(zone.get("biome", "?"))]


func _draw() -> void:
	if mode == 0 or world == null:
		return
	match str(MODES[mode]):
		"biome":
			_draw_tiles(func(chunk: RefCounted, tx: int, ty: int) -> Color:
				var b: int = chunk.biome_at(tx, ty)
				if b == 255:
					return Color.TRANSPARENT
				return Color.from_hsv(float(b) / float(WorldGen.reg.biomes.size()), 0.7, 0.85, 0.40))
		"elevation":
			_draw_tiles(func(chunk: RefCounted, tx: int, ty: int) -> Color:
				var lvl: int = chunk.elev_at(tx, ty)
				if lvl <= 1:
					return Color(0.2, 0.35, 0.8, 0.40)
				var v := float(lvl) / 7.0
				return Color(v, v, v, 0.45))
		"climate":
			_draw_tiles(func(chunk: RefCounted, tx: int, ty: int) -> Color:
				if chunk.layer != 0:
					return Color.TRANSPARENT
				var g: Vector2i = chunk.global_tile(tx, ty)
				var f: Vector3 = WorldGen.generator.classifier.fields(float(g.x), float(g.y))
				return Color(f.z, 0.15, f.y, 0.40))
		"anchors":
			_draw_anchors()


func _draw_tiles(color_for: Callable) -> void:
	for chunk: RefCounted in world.chunk_manager.loaded_chunks():
		var origin: Vector2 = chunk.origin()
		for ty: int in WG.CHUNK_TILES:
			for tx: int in WG.CHUNK_TILES:
				var col: Color = color_for.call(chunk, tx, ty)
				if col.a <= 0.0:
					continue
				draw_rect(Rect2(origin + Vector2(tx, ty) * WG.TILE, Vector2(WG.TILE, WG.TILE)), col)


func _draw_anchors() -> void:
	var planner: RefCounted = WorldGen.generator.anchors
	var font := ThemeDB.fallback_font
	# Road corridors (straight centerlines; the painted tiles wobble around them).
	for seg: Dictionary in planner.road_segments():
		var from: Vector2 = Vector2(seg["from"]) * WG.TILE
		var to: Vector2 = Vector2(seg["to"]) * WG.TILE
		draw_line(from, to, Color(0.76, 0.55, 0.30, 0.8), 6.0)
	# Zone cell grid, faint.
	var pc := WG.world_to_chunk(world.player.position)
	var cell_px := float(WG.ZONE_CELL) * WG.CHUNK_SIZE
	var base_cell := Vector2(floorf(float(pc.x) / WG.ZONE_CELL), floorf(float(pc.y) / WG.ZONE_CELL))
	for d: int in range(-2, 4):
		var x := (base_cell.x + float(d)) * cell_px
		var y := (base_cell.y + float(d)) * cell_px
		draw_line(Vector2(x, (base_cell.y - 2.0) * cell_px), Vector2(x, (base_cell.y + 4.0) * cell_px), Color(1, 1, 1, 0.12), 2.0)
		draw_line(Vector2((base_cell.x - 2.0) * cell_px, y), Vector2((base_cell.x + 4.0) * cell_px, y), Color(1, 1, 1, 0.12), 2.0)
	# Anchor markers + labels.
	for a: Dictionary in planner.planned_anchors():
		var pos: Vector2 = planner.anchor_world_pos(a)
		var hosted := not str(a.get("poi", "")).is_empty() or str(a["id"]) == "starting_town"
		var col := Color(1.0, 0.85, 0.3, 0.95) if hosted else Color(1, 1, 1, 0.5)
		draw_circle(pos, 14.0, Color(0, 0, 0, 0.55))
		draw_circle(pos, 10.0, col)
		draw_string(font, pos + Vector2(16, 6),
			"%s (ring %d)" % [str(a["label"]), int(a["ring"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
