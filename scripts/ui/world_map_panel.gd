extends Control
class_name WorldMapPanel
## Full-screen world map for the fixed continent (toggled with M).
##
## Because the world is authored and finite, the map is drawn from the baked
## overview image (res://data/world/baked/<id>_map.png) plus the authored
## overlays from the WorldSpec (settlements, landmarks, region labels) and a
## live player marker. Undiscovered chunks are dimmed by fog-of-war
## (WorldGen.store.explored), while the overall coastline silhouette stays
## visible so players can still plan journeys.

const WG := preload("res://scripts/worldgen/wg.gd")
const BAKED_DIR := "res://data/world/baked/"

var hud: CanvasLayer
var _tex: Texture2D
var _min_tx := 0
var _min_ty := 0
var _tiles_w := 1
var _tiles_h := 1
var _map_rect := Rect2()
var _font: Font


func setup(p_hud: CanvasLayer) -> void:
	hud = p_hud
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var spec: RefCounted = WorldGen.reg.spec
	if spec.finite:
		_min_tx = spec.bounds.position.x * WG.CHUNK_TILES
		_min_ty = spec.bounds.position.y * WG.CHUNK_TILES
		_tiles_w = spec.bounds.size.x * WG.CHUNK_TILES
		_tiles_h = spec.bounds.size.y * WG.CHUNK_TILES
	var path: String = BAKED_DIR + str(spec.id) + "_map.png"
	if ResourceLoader.exists(path):
		_tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			_tex = ImageTexture.create_from_image(img)


func toggle() -> void:
	visible = not visible
	if visible:
		queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Click the map to close; M / Esc handled by the HUD.
	if event is InputEventMouseButton and event.pressed:
		visible = false


# --- coordinate mapping --------------------------------------------------------

func _compute_map_rect() -> void:
	var avail := size * 0.86
	var scale := minf(avail.x / float(_tiles_w), avail.y / float(_tiles_h))
	var w := float(_tiles_w) * scale
	var h := float(_tiles_h) * scale
	_map_rect = Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _tile_to_screen(gtx: float, gty: float) -> Vector2:
	var fx := (gtx - float(_min_tx)) / float(_tiles_w)
	var fy := (gty - float(_min_ty)) / float(_tiles_h)
	return _map_rect.position + Vector2(fx * _map_rect.size.x, fy * _map_rect.size.y)


# --- draw ----------------------------------------------------------------------

func _draw() -> void:
	# Dim the world behind the map.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.82))
	_compute_map_rect()

	# Sea backdrop + the baked continent.
	draw_rect(_map_rect.grow(8.0), Color(0.10, 0.13, 0.20))
	if _tex != null:
		draw_texture_rect(_tex, _map_rect, false)
	else:
		draw_rect(_map_rect, Color(0.18, 0.22, 0.18))
		_text_center("Run tools/world_bake.tscn to build the map", _map_rect.get_center(), 16, Color.WHITE)
	draw_rect(_map_rect, Color(0.55, 0.5, 0.35), false, 2.0)

	_draw_fog()
	_draw_overlays()
	_draw_player()
	_draw_title()


func _draw_fog() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	if not spec.finite:
		return
	var b: Rect2i = spec.bounds
	var cw := _map_rect.size.x / float(b.size.x)
	var ch := _map_rect.size.y / float(b.size.y)
	for cy: int in range(b.position.y, b.end.y):
		for cx: int in range(b.position.x, b.end.x):
			if WorldGen.store.is_explored(cx, cy):
				continue
			var p := _map_rect.position + Vector2(
				float(cx - b.position.x) * cw, float(cy - b.position.y) * ch)
			# Translucent so the coastline silhouette still reads under the fog.
			draw_rect(Rect2(p, Vector2(cw + 1.0, ch + 1.0)), Color(0.05, 0.06, 0.09, 0.6))


func _draw_overlays() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	# Roads (drawn faint; the baked image already shows them, this reinforces).
	for road: Dictionary in spec.roads:
		var pts: Array = road["points"]
		var col := Color(0.78, 0.66, 0.42, 0.5) if str(road["kind"]) == "major" else Color(0.6, 0.5, 0.34, 0.4)
		for i: int in range(pts.size() - 1):
			var a: Vector2i = pts[i]
			var b: Vector2i = pts[i + 1]
			draw_line(_tile_to_screen(a.x, a.y), _tile_to_screen(b.x, b.y), col,
				2.0 if str(road["kind"]) == "major" else 1.0)
	# Settlements.
	for s: Dictionary in spec.settlements:
		var t: Vector2i = s["tile"]
		var capital := str(s["kind"]) == "capital"
		var col := Color(1.0, 0.85, 0.3) if capital else Color(0.92, 0.92, 0.96)
		var sp := _tile_to_screen(t.x, t.y)
		_marker(sp, col, 6.0 if capital else 4.0, true)
		_label(str(s["label"]), sp + Vector2(8, -6), col)
	# Landmarks + dungeons + bosses from features/anchors.
	for f: Dictionary in spec.features:
		if str(f.get("kind", "")) == "landmark" and f.has("tile"):
			var t: Vector2i = f["tile"]
			var sp := _tile_to_screen(t.x, t.y)
			_marker(sp, Color(0.55, 0.85, 0.95), 3.0, false)
			_label(str(f.get("label", "")), sp + Vector2(7, -5), Color(0.7, 0.9, 1.0))
	for a: Dictionary in spec.anchors:
		var ch: Vector2i = a["chunk"]
		var sp := _tile_to_screen(ch.x * WG.CHUNK_TILES + 8, ch.y * WG.CHUNK_TILES + 8)
		var boss := not str(a.get("boss", "")).is_empty()
		var col := Color(0.9, 0.3, 0.3) if boss else Color(0.8, 0.6, 0.95)
		_marker(sp, col, 5.0, false)
		_label(str(a.get("label", "")), sp + Vector2(7, -5), col)


func _draw_player() -> void:
	if hud == null or hud.get("world") == null:
		return
	var player: Node2D = hud.world.player
	var t := WG.world_to_tile(player.position)
	var sp := _tile_to_screen(float(t.x), float(t.y))
	draw_circle(sp, 7.0, Color(0, 0, 0, 0.5))
	draw_circle(sp, 5.0, Color(0.3, 1.0, 0.4))
	draw_arc(sp, 8.0, 0.0, TAU, 24, Color.WHITE, 1.5)


func _draw_title() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	_text_center(str(spec.spec_name), Vector2(size.x * 0.5, _map_rect.position.y - 22.0), 22, Color(0.95, 0.9, 0.7))
	_text_center("Press M or click to close", Vector2(size.x * 0.5, _map_rect.end.y + 24.0), 13, Color(0.7, 0.7, 0.7))


# --- primitives ----------------------------------------------------------------

func _marker(p: Vector2, col: Color, r: float, diamond: bool) -> void:
	draw_circle(p, r + 1.5, Color(0, 0, 0, 0.6))
	if diamond:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
	else:
		draw_circle(p, r, col)


func _label(text: String, p: Vector2, col: Color) -> void:
	if text.is_empty():
		return
	draw_string(_font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _text_center(text: String, center: Vector2, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(_font, center - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
