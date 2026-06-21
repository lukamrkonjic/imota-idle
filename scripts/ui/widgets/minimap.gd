extends Control
## OSRS-style minimap cluster: a circular terrain map with small orb zoom buttons on
## the rim. Extracted from osrs_hud.gd. Call setup(hud) after instancing. The inner
## MinimapControl paints loaded chunks + entity/POI dots.

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
	minimap.clip_contents = true                        # keep route/flag drawing inside the map
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
	## Terrain minimap: paints the loaded chunks' ground tiles (so rivers,
	## biomes, and cave walls show up), then entity and POI dots.
	const WG := preload("res://scripts/worldgen/wg.gd")
	const BASE_SCALE := 0.052
	const TILE_PX := 3.0
	const ZOOM_MIN := -2
	const ZOOM_MAX := 5
	var hud: CanvasLayer
	var zoom_level := 0
	var _t := 0.0

	func zoom_in() -> void:
		zoom_level = mini(ZOOM_MAX, zoom_level + 1)
		queue_redraw()

	func zoom_out() -> void:
		zoom_level = maxi(ZOOM_MIN, zoom_level - 1)
		queue_redraw()

	func _view_scale() -> float:
		return BASE_SCALE * pow(1.35, float(zoom_level))

	# World-units -> minimap-pixels (matches _draw_terrain / _draw_dots).
	func _map_scale() -> float:
		return _view_scale() * (TILE_PX / 2.5)

	# Click-to-navigate: a click inside the map disc walks the player toward that world
	# position. The path controller decides reachability — an unreachable pick doesn't start
	# a route (so no flag appears); a reachable one starts a route the overlay draws as a
	# line + destination flag.
	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if hud == null or hud.world == null or hud.world.player == null:
			return
		var rel: Vector2 = event.position - size * 0.5
		if rel.length() > size.x * 0.5 - 3.0:
			return   # outside the circular map
		var k := _map_scale()
		if k <= 0.0:
			return
		var world_pos: Vector2 = hud.world.player.position + rel / k
		EventBus.navigate_requested.emit(world_pos)   # decoupled: no world.call("...")
		accept_event()

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.25:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var r := size.x / 2.0
		var c := size / 2.0
		draw_circle(c, r, Color(0.08, 0.09, 0.08, 0.95))
		if hud != null and hud.world != null:
			_draw_terrain(c, r)
			_draw_route(c, r)
			_draw_dots(c, r)
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(0.55, 0.5, 0.35), 2.5)
		_draw_compass(c, r)
		draw_circle(c, 3.0, Color.WHITE)

	# Fixed compass. The minimap never rotates (world coords are drawn directly,
	# player at centre), so it is always north-up — N/E/S/W sit at the rim.
	func _draw_compass(c: Vector2, r: float) -> void:
		var font := get_theme_default_font()
		if font == null:
			font = ThemeDB.fallback_font
		if font == null:
			return
		var fs := clampi(int(r * 0.17), 9, 18)
		var inset := r * 0.11
		_compass_label(font, fs, c + Vector2(0.0, -(r - inset)), "N")
		_compass_label(font, fs, c + Vector2(r - inset, 0.0), "E")
		_compass_label(font, fs, c + Vector2(0.0, r - inset), "S")
		_compass_label(font, fs, c + Vector2(-(r - inset), 0.0), "W")

	func _compass_label(font: Font, fs: int, at: Vector2, s: String) -> void:
		var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := at - Vector2(sz.x * 0.5, -sz.y * 0.30)   # centre the glyph on `at`
		draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.65))
		var col := Color(0.95, 0.30, 0.25, 0.95) if s == "N" else Color(0.93, 0.88, 0.70, 0.95)
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw_terrain(c: Vector2, r: float) -> void:
		var player: Node2D = hud.world.player
		var reg: RefCounted = WorldGen.reg
		var scale := _view_scale()
		var px := WG.TILE * scale * TILE_PX / 2.5
		var limit_sq := (r - 2.0) * (r - 2.0)
		for chunk: RefCounted in hud.world.chunk_manager.loaded_chunks():
			for ty: int in 16:
				for tx: int in 16:
					var gtx: int = chunk.cx * WG.CHUNK_TILES + tx
					var gty: int = chunk.cy * WG.CHUNK_TILES + ty
					var world_pos := WG.tile_to_world(gtx, gty)
					var rel := (world_pos - player.position) * scale * (TILE_PX / 2.5)
					if rel.length_squared() > limit_sq:
						continue
					var cols: Array = reg.tile_def(chunk.tile_id(tx, ty))["colors"]
					draw_rect(Rect2(c + rel - Vector2(px, px) * 0.5, Vector2(px, px)), cols[0])

	func _draw_dots(c: Vector2, r: float) -> void:
		var player: Node2D = hud.world.player
		var scale := _view_scale()
		for e: Node2D in hud.world.entities:
			# Only interactable entities get a dot; decorative props (walls, pillars,
			# houses, ruins) carry an empty action and would otherwise add hundreds of
			# pointless dots + iterations every redraw.
			var atype := str(e.action.get("type", ""))
			if atype.is_empty():
				continue
			var rel := (e.position - player.position) * scale * (TILE_PX / 2.5)
			if rel.length() > r - 5.0:
				continue
			var col := Color(0.9, 0.2, 0.2)
			match atype:
				"gather":
					col = {
						"woodcutting": Color(0.3, 0.8, 0.3), "mining": Color(0.7, 0.7, 0.75),
						"fishing": Color(0.35, 0.6, 0.95), "foraging": Color(0.65, 0.9, 0.3),
					}.get(str(e.action.get("skill", "")), Color.WHITE)
				"station":
					col = Color(1.0, 0.85, 0.2)
				"descend", "ascend":
					col = Color(0.75, 0.75, 0.8)
				"obelisk":
					col = Color(0.85, 0.4, 0.9)
				"landmark":
					col = Color.WHITE
				"hook":
					col = Color(0.78, 0.56, 0.34)
			draw_circle(c + rel, 2.0, col)

	# Active walk route: a line from the player (centre) through the remaining waypoints to
	# the destination flag. Drawn only while a route is being walked (see active_route()).
	func _draw_route(c: Vector2, r: float) -> void:
		var route: Dictionary = hud.world.active_route()   # typed read, not call("...")
		if route.is_empty():
			return
		var player: Node2D = hud.world.player
		var k := _map_scale()
		var lim := r - 3.0
		var pts: PackedVector2Array = route["points"]
		var prev := c   # player sits at the map centre
		for wp: Vector2 in pts:
			var p := c + _clamp_to_circle((wp - player.position) * k, lim)
			draw_line(prev, p, Color(0.98, 0.95, 0.85, 0.85), 1.5)
			prev = p
		var drel: Vector2 = (Vector2(route["dest"]) - player.position) * k
		if drel.length() <= lim:
			_draw_flag(c + drel)

	func _clamp_to_circle(v: Vector2, radius: float) -> Vector2:
		return v if v.length() <= radius else v.normalized() * radius

	func _draw_flag(p: Vector2) -> void:
		var top := p - Vector2(0.0, 10.0)
		draw_line(p, top, Color(0.15, 0.12, 0.08), 1.6)                 # pole
		draw_colored_polygon(PackedVector2Array([
			top, top + Vector2(8.0, 2.5), top + Vector2(0.0, 5.0)]),
			Color(0.86, 0.16, 0.12))                                   # red pennant
		draw_circle(p, 1.8, Color(0.96, 0.93, 0.72))                    # base
