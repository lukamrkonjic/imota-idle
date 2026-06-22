extends Control
## OSRS-style minimap cluster: a circular 2D top-down map with small orb zoom buttons on
## the rim. Call setup(hud) after instancing. The inner MinimapControl samples the BAKED
## world map image (data/world/baked/<id>_map.png) so the WHOLE world always shows —
## persistent, never offloaded — then overlays entity/POI dots, the route, and the player.

const UiScale := preload("res://scripts/ui/ui_scale.gd")

var hud: CanvasLayer
var minimap: MinimapControl

const MAP_SIZE := Vector2(150, 150)
const ORB_SIZE := Vector2(24, 24)


func setup(h: CanvasLayer) -> void:
	hud = h
	custom_minimum_size = UiScale.v2(Vector2(160, 162))
	size = custom_minimum_size

	minimap = MinimapControl.new()
	minimap.hud = hud
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP   # catch clicks for click-to-navigate
	minimap.clip_contents = true
	minimap.position = UiScale.v2(Vector2(0, 0))
	minimap.custom_minimum_size = UiScale.v2(MAP_SIZE)
	minimap.size = minimap.custom_minimum_size
	add_child(minimap)

	var center := UiScale.v2(MAP_SIZE * 0.5)
	var rim := UiScale.f(MAP_SIZE.x * 0.5 - 4.0)

	var zoom_out := _make_orb_button("−")
	zoom_out.tooltip_text = "Zoom out (see more)"
	zoom_out.position = center + Vector2(-rim * 0.72, rim * 0.72) - UiScale.v2(ORB_SIZE * 0.5)
	zoom_out.pressed.connect(minimap.zoom_out)
	add_child(zoom_out)

	var zoom_in := _make_orb_button("+")
	zoom_in.tooltip_text = "Zoom in (see less)"
	zoom_in.position = center + Vector2(rim * 0.72, rim * 0.72) - UiScale.v2(ORB_SIZE * 0.5)
	zoom_in.pressed.connect(minimap.zoom_in)
	add_child(zoom_in)


func _make_orb_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = UiScale.v2(ORB_SIZE)
	btn.size = btn.custom_minimum_size
	btn.add_theme_font_size_override("font_size", UiScale.i(14))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.16, 0.14)
	normal.border_color = Color(0.55, 0.5, 0.35)
	normal.set_border_width_all(UiScale.i(2))
	normal.set_corner_radius_all(UiScale.i(12))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	return btn


class MinimapControl extends Control:
	## Persistent 2D minimap: samples the baked overview image (1px/tile) around the player.
	const WG := preload("res://scripts/worldgen/wg.gd")
	const ZOOM_MIN := -2
	const ZOOM_MAX := 5
	const OCEAN := Color(0.205, 0.30, 0.47)   # out-of-bounds / beyond the baked map
	var hud: CanvasLayer
	var zoom_level := 0
	var _t := 0.0
	# baked map image, cached
	var _img_ok := false
	var _bytes := PackedByteArray()
	var _iw := 0
	var _ih := 0
	var _min_tx := 0
	var _min_ty := 0

	func zoom_in() -> void:
		zoom_level = mini(ZOOM_MAX, zoom_level + 1); queue_redraw()

	func zoom_out() -> void:
		zoom_level = maxi(ZOOM_MIN, zoom_level - 1); queue_redraw()

	# Screen pixels per world tile on the minimap.
	func _px() -> float:
		return clampf(2.2 * pow(1.28, float(zoom_level)), 1.0, 18.0)

	func _ensure_map() -> bool:
		if _img_ok:
			return true
		if WorldGen.reg == null or WorldGen.reg.spec == null:
			return false
		var spec: RefCounted = WorldGen.reg.spec
		var b: Rect2i = spec.bounds
		_min_tx = b.position.x * WG.CHUNK_TILES
		_min_ty = b.position.y * WG.CHUNK_TILES
		var path := "res://data/world/baked/" + str(spec.id) + "_map.png"
		var raw := FileAccess.get_file_as_bytes(path)
		if raw.size() == 0:
			return false
		var img := Image.new()
		if img.load_png_from_buffer(raw) != OK:
			return false
		img.convert(Image.FORMAT_RGB8)
		_iw = img.get_width(); _ih = img.get_height()
		_bytes = img.get_data()
		_img_ok = true
		return true

	# Click inside the disc -> walk toward that world position (top-down un-rotate).
	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if hud == null or hud.world == null or hud.world.player == null:
			return
		var rel: Vector2 = event.position - size * 0.5
		if rel.length() > size.x * 0.5 - 3.0:
			return
		var px := _px()
		var ang := _map_angle()
		var toff := (rel.rotated(-ang) if ang != 0.0 else rel) / px
		var pt: Vector2i = WG.world_to_tile(hud.world.player.position)
		var world_pos: Vector2 = WG.tile_to_world(pt.x + int(round(toff.x)), pt.y + int(round(toff.y)))
		EventBus.navigate_requested.emit(world_pos)
		accept_event()

	func _map_angle() -> float:
		if GameSettings.minimap_lock_north:
			return 0.0
		var w: Node = hud.world if hud != null else null
		if w == null:
			return 0.0
		var r3d: Node = w.render_3d
		if r3d == null or not r3d.is_active():
			return 0.0
		return r3d.cam_yaw()

	func _process(delta: float) -> void:
		_t += delta
		if not GameSettings.minimap_lock_north:
			queue_redraw()
			return
		if _t >= 0.2:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var r := size.x / 2.0
		var c := size / 2.0
		draw_circle(c, r, OCEAN.darkened(0.4))
		var ang := _map_angle()
		if hud != null and hud.world != null and hud.world.player != null:
			_draw_baked(c, r, ang)
			_draw_route(c, r, ang)
			_draw_dots(c, r, ang)
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(0.55, 0.5, 0.35), 2.5)
		_draw_compass(c, r, ang)
		draw_circle(c, 3.0, Color.WHITE)

	# Fill the disc in screen space; each cell inverse-maps to a tile of the baked image.
	func _draw_baked(c: Vector2, r: float, ang: float) -> void:
		if not _ensure_map():
			return
		var px := _px()
		var pt: Vector2i = WG.world_to_tile(hud.world.player.position)
		var n := int(ceil(r / px)) + 1
		var limit := r - 1.0
		var cell := Vector2(px, px)
		for iy in range(-n, n + 1):
			for ix in range(-n, n + 1):
				var rel := Vector2(float(ix), float(iy)) * px
				if rel.length() > limit:
					continue
				var toff := rel.rotated(-ang) / px if ang != 0.0 else rel / px
				var mx := pt.x + int(round(toff.x)) - _min_tx
				var my := pt.y + int(round(toff.y)) - _min_ty
				var col := OCEAN
				if mx >= 0 and mx < _iw and my >= 0 and my < _ih:
					var idx := (my * _iw + mx) * 3
					col = Color8(_bytes[idx], _bytes[idx + 1], _bytes[idx + 2])
				draw_rect(Rect2(c + rel - cell * 0.5, cell), col)

	func _draw_dots(c: Vector2, r: float, ang: float) -> void:
		var px := _px()
		var pt: Vector2i = WG.world_to_tile(hud.world.player.position)
		for e: Node2D in hud.world.entities:
			var atype := str(e.action.get("type", ""))
			if atype.is_empty():
				continue
			var et: Vector2i = WG.world_to_tile(e.position)
			var rel := Vector2(et.x - pt.x, et.y - pt.y) * px
			if ang != 0.0:
				rel = rel.rotated(ang)
			if rel.length() > r - 5.0:
				continue
			var col := Color(0.9, 0.2, 0.2)
			match atype:
				"gather":
					col = {
						"woodcutting": Color(0.3, 0.8, 0.3), "mining": Color(0.7, 0.7, 0.75),
						"fishing": Color(0.35, 0.6, 0.95), "foraging": Color(0.65, 0.9, 0.3),
					}.get(str(e.action.get("skill", "")), Color.WHITE)
				"station": col = Color(1.0, 0.85, 0.2)
				"descend", "ascend": col = Color(0.75, 0.75, 0.8)
				"obelisk": col = Color(0.85, 0.4, 0.9)
				"landmark": col = Color.WHITE
				"hook": col = Color(0.78, 0.56, 0.34)
			draw_circle(c + rel, 2.0, col)

	func _draw_route(c: Vector2, r: float, ang: float) -> void:
		var route: Dictionary = hud.world.active_route()
		if route.is_empty():
			return
		var px := _px()
		var pt: Vector2i = WG.world_to_tile(hud.world.player.position)
		var lim := r - 3.0
		var prev := c
		for wp: Vector2 in route["points"]:
			var wt: Vector2i = WG.world_to_tile(wp)
			var rel := Vector2(wt.x - pt.x, wt.y - pt.y) * px
			if ang != 0.0:
				rel = rel.rotated(ang)
			var p := c + _clamp_to_circle(rel, lim)
			draw_line(prev, p, Color(0.98, 0.95, 0.85, 0.85), 1.5)
			prev = p
		var dt: Vector2i = WG.world_to_tile(Vector2(route["dest"]))
		var drel := Vector2(dt.x - pt.x, dt.y - pt.y) * px
		if ang != 0.0:
			drel = drel.rotated(ang)
		if drel.length() <= lim:
			_draw_flag(c + drel)

	func _clamp_to_circle(v: Vector2, radius: float) -> Vector2:
		return v if v.length() <= radius else v.normalized() * radius

	func _draw_compass(c: Vector2, r: float, ang: float) -> void:
		var font := get_theme_default_font()
		if font == null:
			font = ThemeDB.fallback_font
		if font == null:
			return
		var fs := clampi(int(r * 0.17), 9, 18)
		var d := r - r * 0.11
		_compass_label(font, fs, c + Vector2(0.0, -d).rotated(ang), "N")
		_compass_label(font, fs, c + Vector2(d, 0.0).rotated(ang), "E")
		_compass_label(font, fs, c + Vector2(0.0, d).rotated(ang), "S")
		_compass_label(font, fs, c + Vector2(-d, 0.0).rotated(ang), "W")

	func _compass_label(font: Font, fs: int, at: Vector2, s: String) -> void:
		var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := at - Vector2(sz.x * 0.5, -sz.y * 0.30)
		draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.65))
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.93, 0.88, 0.70, 0.95))

	func _draw_flag(p: Vector2) -> void:
		var top := p - Vector2(0.0, 10.0)
		draw_line(p, top, Color(0.15, 0.12, 0.08), 1.6)
		draw_colored_polygon(PackedVector2Array([
			top, top + Vector2(8.0, 2.5), top + Vector2(0.0, 5.0)]),
			Color(0.86, 0.16, 0.12))
		draw_circle(p, 1.8, Color(0.96, 0.93, 0.72))
