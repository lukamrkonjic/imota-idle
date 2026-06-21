extends Node2D
## Aldreth World Editor (v2) — the production designer for the FIXED finite world.
##
## Top-down 1px-per-tile view of the baked world with hand-authoring tools:
##   • Biome brush   — paint a parent/micro-biome (sets biome + ground tile; the
##                     game auto-spawns that biome's decals/clutter at runtime).
##   • Terrain brush — paint a specific tile (grass/road/wall/water/…).
##   • Structure     — drop houses, halls, fountains, walls, lamps, ruins…
##   • Erase         — brush that removes placed content (structures + monsters),
##                     and, with "Erase biomes" on, restores the generated terrain.
##   • Set Spawn     — click a walkable tile to set the player spawn.
##
## Editing is undoable (compact per-stroke command records; a continuous drag is
## one undo step). Generate World rebuilds the whole continent via the shared
## FiniteWorldGenerator. Save writes data/world/baked/<id>.world (+ map + spawn).
##
## Controls: right-drag pan · wheel zoom (over map only) · [ ] brush size ·
## Ctrl+Z undo · Ctrl+Y / Ctrl+Shift+Z redo · Ctrl+S save · 1-6 tools.
##
## Live 3D view: the "🧊 3D View" toolbar button docks the REAL game renderer
## (world.tscn) in a panel. Because the editor edits the same WorldGen chunk objects
## the renderer reads, painting terrain/biome/water and then re-meshing the touched
## chunks shows the true in-game 3D look. Press F to aim the 3D camera at the cursor;
## arrow keys orbit it. The panel's "⛶ Maximize" button (or M) blows it up to a large
## authoring view: with a Structure/Stamp tool selected, CLICK in the 3D view to place
## the picked object at the cursor (trees, rocks, houses…), live; with Pan selected a
## click re-aims the camera. Arrows keep orbiting. (Self-test: run with `-- --we-selftest`.)
##
## Run:  godot --path . res://tools/world_editor.tscn

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const BakedWorldStore := preload("res://scripts/worldgen/baked_world_store.gd")
const FiniteWorldGenerator := preload("res://scripts/worldgen/finite_world_generator.gd")
const StampLibrary := preload("res://scripts/worldgen/stamp_library.gd")
const PlaceablePreview := preload("res://tools/placeable_preview.gd")

const OUT_DIR := "res://data/world/baked/"

enum Tool { PAN, BIOME, TERRAIN, STAMP, STRUCTURE, ERASE, SPAWN, CREATURE }

const TERRAIN := [
	["grass", "Grass"], ["grass_dark", "Dark grass"], ["dirt", "Dirt path"],
	["cobble", "Cobble road"], ["gravel", "Gravel"], ["sand", "Sand"],
	["shallow", "Shallows"], ["water", "Water"], ["deep_water", "Deep water"],
	["rock", "Rock"], ["snow", "Snow"], ["marsh", "Marsh"], ["mud", "Mud"],
	["wheat_ripe", "Wheat"], ["plaza", "Plaza"], ["plank_floor", "Plank floor"],
	["building_wall", "Building wall"], ["lava_rock", "Lava rock"], ["ash", "Ash"],
]

const STRUCTURES := [
	["House", {"kind": "house"}], ["Hall (large)", {"kind": "building", "foot": 7}],
	["Fountain", {"kind": "fountain", "label": "Fountain"}],
	["Well", {"kind": "city_prop", "prop": "well"}], ["Lamp post", {"kind": "city_prop", "prop": "lamp"}],
	["Crate", {"kind": "city_prop", "prop": "crate"}], ["Barrel", {"kind": "city_prop", "prop": "barrel"}],
	["Cart", {"kind": "city_prop", "prop": "cart"}], ["Hay", {"kind": "city_prop", "prop": "hay"}],
	["Flower box", {"kind": "city_prop", "prop": "flowerbox"}],
	["Wall segment", {"kind": "city_wall", "piece": 0}], ["Wall gate", {"kind": "city_wall", "piece": 1}],
	["Wall tower", {"kind": "city_wall", "piece": 2}], ["Tent", {"kind": "tent"}],
	["Campfire", {"kind": "campfire"}], ["Sign", {"kind": "sign", "label": "Sign"}],
	["Anvil", {"kind": "anvil", "station": "anvil"}], ["Altar", {"kind": "altar", "label": "Altar"}],
	["Obelisk", {"kind": "obelisk", "label": "Obelisk"}], ["Chest", {"kind": "chest"}],
	["Broken arch", {"kind": "ruin_arch", "label": "Ruins"}], ["Broken pillar", {"kind": "ruin_pillar"}],
	["Broken wall", {"kind": "broken_wall"}], ["Rubble", {"kind": "rubble_pile"}],
	["Broken statue", {"kind": "broken_statue", "label": "Statue"}],
	# Props/scenery models (each renders as its own 3D entity in-game).
	["Stall", {"kind": "stall", "label": "Stall"}], ["Lantern", {"kind": "lantern"}],
	["Bridge", {"kind": "bridge"}], ["Mammoth", {"kind": "mammoth", "label": "Mammoth"}],
	["Meteor", {"kind": "meteor", "label": "Meteor"}],
	# Nature models (decorative — tree label picks the species).
	["Tree (oak)", {"kind": "tree", "label": "Oak Tree"}], ["Tree (pine)", {"kind": "tree", "label": "Pine Tree"}],
	["Tree (fir)", {"kind": "tree", "label": "Fir Tree"}], ["Tree (maple)", {"kind": "tree", "label": "Maple Tree"}],
	["Rock", {"kind": "rock"}], ["Bush", {"kind": "bush"}],
	# Ground-clutter decor placed as standalone models.
	["Mushroom", {"kind": "decor", "prop": "mushroom"}], ["Flowers", {"kind": "decor", "prop": "flower"}],
	["Fern", {"kind": "decor", "prop": "fern"}], ["Reeds", {"kind": "decor", "prop": "reed"}],
	["Shrub", {"kind": "decor", "prop": "shrub"}], ["Grass tuft", {"kind": "decor", "prop": "grass"}],
	["Pebbles", {"kind": "decor", "prop": "pebble"}],
]

const ROOF_COLORS := ["7a3b3b", "3b5a7a", "4a6b3a", "6b5a3a", "5a3b6b", "7a6b3a"]
const STRUCT_MARK := Color(0.95, 0.85, 0.4)
const SPAWN_MARK := Color(0.3, 1.0, 0.45)

var _reg: RefCounted
var _spec: RefCounted
var _bounds := Rect2i()
var _min_tx := 0
var _min_ty := 0
var _w := 1
var _h := 1

var _chunks: Dictionary = {}
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _cam: Camera2D
var _overlay: Node2D
var _img_dirty := false

var _tool := Tool.PAN
var _brush := 2
var _erase_biomes := false
var _sel_biome := ""
var _sel_terrain := "grass"
var _sel_struct := 0
var _sel_stamp := 0
var _sel_creature := ""
var _stamp_variant := 0
var _stamp_rot := 0
var _stamp_flip := false
var _spawn_tile := Vector2i.ZERO
var _show_structs := true
var _show_spawn := true
var _show_collision := false
var _show_biomes := false
var _show_danger := false
var _show_walk := false
var _show_elevation := false

var _panning := false
var _painting := false
var _hover_tile := Vector2i.ZERO
var _ui_hover := false

# undo/redo — each entry is a "stroke" dict (see _begin_stroke).
var _history: Array = []
var _redo: Array = []
var _stroke: Dictionary = {}
var _stroke_active := false

# UI
var _hud: CanvasLayer
var _status: Label
var _coords: Label
var _palette_box: VBoxContainer
var _tool_buttons: Dictionary = {}
var _brush_label: Label
var _erase_biomes_check: CheckBox
var _undo_btn: Button
var _redo_btn: Button
var _busy := false
var _preview: PlaceablePreview
var _preview_panel: PanelContainer
var _selected_choice_btn: Button
var _reroll_btn: Button

# Live 3D view — embeds the real game world (world.tscn) in a SubViewport so you can
# see the actual 3D result (elevation, water, models) of what you paint on the 2D map.
# Lazy: the heavy game scene is only instanced when you toggle the panel on.
const _GAME_SCENE := preload("res://scenes/world.tscn")
var _v3d_panel: PanelContainer
var _v3d_container: SubViewportContainer
var _v3d_vp: SubViewport
var _v3d_world: Node2D            # the embedded world.tscn instance (its render_3d does the 3D)
var _v3d_on := false
var _v3d_max := false             # large/navigable mode vs the small docked corner panel
var _v3d_btn: Button
var _v3d_max_btn: Button
var _v3d_focus_tile := Vector2i(-2147483648, 0)   # last tile the 3D camera was sent to
const _V3D_SIZE := Vector2i(540, 380)


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	_reg = WorldGen.reg
	_spec = _reg.spec
	if not _spec.active or not _spec.finite:
		push_error("World editor needs a finite authored world (set bounds in worldspec).")
		get_tree().quit(1)
		return
	_bounds = _spec.bounds
	_min_tx = _bounds.position.x * WG.CHUNK_TILES
	_min_ty = _bounds.position.y * WG.CHUNK_TILES
	_w = _bounds.size.x * WG.CHUNK_TILES
	_h = _bounds.size.y * WG.CHUNK_TILES
	if _sel_biome.is_empty():
		_sel_biome = str(WorldGen.list_surface_biomes()[0]["id"])
	if _sel_creature.is_empty():
		_sel_creature = "Chickens" if DataRegistry.enemies.has("Chickens") \
			else (str(DataRegistry.enemies.keys()[0]) if not DataRegistry.enemies.is_empty() else "")
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.11))
	_load_world()
	_build_view()
	_build_ui()
	_build_3d_view_panel()
	_set_tool(Tool.PAN)
	_refresh_palette()
	_refresh_history_buttons()
	for _a: String in OS.get_cmdline_user_args():
		if _a.begins_with("--we-selftest"):
			_run_selftest.call_deferred()
			break


## Dev verification: find a scattered set-piece POI in the baked world, aim the 3D
## camera at it, and screenshot. Pass a POI type to target a specific one. Run:
##   godot --path . res://tools/world_editor.tscn -- --we-selftest=haunted_ruins
func _run_selftest() -> void:
	var want := "haunted_ruins"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--we-selftest="):
			want = a.trim_prefix("--we-selftest=")
	# biome:<id> — find a tile of that biome (away from the coast/spawn) and frame it.
	if want.begins_with("biome:"):
		var bid := want.trim_prefix("biome:")
		var bidx := int(_reg.biome_index.get(bid, -1))
		var spot := Vector2i(-2147483648, 0)
		# Prefer an INTERIOR tile (a 5x5 patch all the same biome) so we frame a dense
		# stand, not a sparse border. Fall back to any matching tile.
		var fallback := Vector2i(-2147483648, 0)
		for c: RefCounted in _chunks.values():
			if Vector2(c.cx, c.cy).length() < 6.0:
				continue  # skip the spawn hub
			for ly: int in range(3, WG.CHUNK_TILES - 3):
				for lx: int in range(3, WG.CHUNK_TILES - 3):
					if c.biome_at(lx, ly) != bidx:
						continue
					if fallback.x == -2147483648:
						fallback = Vector2i(c.cx * WG.CHUNK_TILES + lx, c.cy * WG.CHUNK_TILES + ly)
					var interior := true
					for oy: int in range(-2, 3):
						for ox: int in range(-2, 3):
							if c.biome_at(lx + ox, ly + oy) != bidx:
								interior = false
								break
						if not interior: break
					if interior:
						spot = Vector2i(c.cx * WG.CHUNK_TILES + lx, c.cy * WG.CHUNK_TILES + ly)
						break
				if spot.x != -2147483648: break
			if spot.x != -2147483648: break
		if spot.x == -2147483648:
			spot = fallback
		print("[we-selftest] biome '%s' (idx %d) at %s" % [bid, bidx, str(spot)])
		_toggle_3d_view()
		if spot.x != -2147483648:
			_focus_3d(spot)
		await get_tree().create_timer(9.0).timeout
		if _v3d_world != null:
			var nodes: Array = _v3d_world.get("_decor_nodes")
			var canopy := 0
			var by_kind: Dictionary = {}
			for nd in nodes:
				var kk := str(nd.get("kind"))
				if kk.begins_with("canopy_"):
					canopy += 1
					by_kind[kk] = int(by_kind.get(kk, 0)) + 1
			print("[we-selftest] decor nodes=%d  canopy=%d  by_kind=%s" % [nodes.size(), canopy, str(by_kind)])
		if _v3d_vp != null:
			_v3d_vp.get_texture().get_image().save_png("user://we3d_biome.png")
		print("[we-selftest] saved we3d_biome.png (%s)" % bid)
		get_tree().quit()
		return
	var order: Array = [want, "haunted_ruins", "cursed_keep", "old_watchtower", "abandoned_farmstead", "wayfarers_wreck"]
	var found := Vector2i(-2147483648, 0)
	var found_type := ""
	for poi_type: String in order:
		for c: RefCounted in _chunks.values():
			for poi: Dictionary in c.pois:
				if str(poi.get("type", "")) == poi_type:
					var anc: Vector2i = poi["anchor"]
					found = Vector2i(c.cx * WG.CHUNK_TILES + anc.x, c.cy * WG.CHUNK_TILES + anc.y)
					found_type = poi_type
					break
			if found_type != "": break
		if found_type != "": break
	print("[we-selftest] target '%s' found=%s at %s" % [want, found_type, str(found)])
	var dumped := false
	for c: RefCounted in _chunks.values():
		if dumped:
			break
		for poi: Dictionary in c.pois:
			if str(poi.get("type", "")) == found_type:
				var summ: Array = []
				for pt: Dictionary in poi["parts"]:
					var tag := str(pt.get("kind"))
					if pt.has("enemy_name"): tag += "=" + str(pt["enemy_name"])
					elif pt.has("prop"): tag += "=" + str(pt["prop"])
					summ.append(tag)
				print("[we-selftest] parts: ", summ)
				dumped = true
				break
	_toggle_3d_view()
	if found_type != "":
		_focus_3d(found)
	await get_tree().create_timer(9.0).timeout
	if _v3d_vp != null:
		_v3d_vp.get_texture().get_image().save_png("user://we3d_poi.png")
	print("[we-selftest] saved we3d_poi.png (%s)" % found_type)
	get_tree().quit()


# ─────────────────────────────── load / view ────────────────────────────────

func _load_world() -> void:
	_img = Image.create_empty(_w, _h, false, Image.FORMAT_RGB8)
	for cy: int in range(_bounds.position.y, _bounds.end.y):
		for cx: int in range(_bounds.position.x, _bounds.end.x):
			var chunk: RefCounted = WorldGen.get_chunk(0, cx, cy)
			_chunks["%d:%d" % [cx, cy]] = chunk
			_blit_chunk(chunk)
	_tex = ImageTexture.create_from_image(_img)
	if WorldGen.baked.loaded and WorldGen.baked.has_spawn:
		_spawn_tile = WorldGen.baked.spawn_tile
	else:
		_spawn_tile = Vector2i(_min_tx + _w / 2, _min_ty + _h / 2)


func _blit_chunk(chunk: RefCounted) -> void:
	var bx: int = chunk.cx * WG.CHUNK_TILES - _min_tx
	var by: int = chunk.cy * WG.CHUNK_TILES - _min_ty
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			_img.set_pixel(bx + lx, by + ly, _tile_color(chunk.tile_id(lx, ly)))


func _tile_color(tid: int) -> Color:
	var cols: Array = _reg.tile_def(tid)["colors"]
	return cols[0]


func _build_view() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = _tex
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_overlay = Node2D.new()
	_overlay.z_index = 5
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay.bind(_overlay))
	_cam = Camera2D.new()
	_cam.position = Vector2(_w, _h) * 0.5
	_cam.zoom = Vector2(3.0, 3.0)
	add_child(_cam)
	_cam.make_current()


# ─────────────────────────────── input ──────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and not _ui_hover:
			_zoom_at(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _ui_hover:
			_zoom_at(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and not _ui_hover:
			_painting = event.pressed
			if event.pressed:
				_begin_stroke()
				_apply_tool(true)
			else:
				_commit_stroke()
	elif event is InputEventMouseMotion and _panning:
		_cam.position -= event.relative / _cam.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed: _do_redo()
				else: _do_undo()
			KEY_Y: _do_redo()
			KEY_S: _save()
		return
	match event.keycode:
		KEY_BRACKETLEFT: _set_brush(_brush - 1)
		KEY_BRACKETRIGHT: _set_brush(_brush + 1)
		KEY_R:
			if _tool == Tool.STAMP:
				_stamp_rot = (_stamp_rot + 1) % 4
				_status.text = "Stamp rotation: %d°" % (_stamp_rot * 90)
		KEY_F:
			if _tool == Tool.STAMP:
				_stamp_flip = not _stamp_flip
				_status.text = "Stamp flip: %s" % ("on" if _stamp_flip else "off")
			elif _v3d_on:
				_focus_3d(_hover_tile)
				_status.text = "3D camera → tile (%d, %d)" % [_hover_tile.x, _hover_tile.y]
		KEY_M: _toggle_3d_maximize()
		KEY_1: _set_tool(Tool.PAN)
		KEY_2: _set_tool(Tool.BIOME)
		KEY_3: _set_tool(Tool.TERRAIN)
		KEY_4: _set_tool(Tool.STAMP)
		KEY_5: _set_tool(Tool.STRUCTURE)
		KEY_6: _set_tool(Tool.ERASE)
		KEY_7: _set_tool(Tool.SPAWN)
		KEY_8: _set_tool(Tool.CREATURE)


func _zoom_at(factor: float) -> void:
	var before := get_global_mouse_position()
	_cam.zoom = (_cam.zoom * factor).clamp(Vector2(0.4, 0.4), Vector2(24.0, 24.0))
	var after := get_global_mouse_position()
	_cam.position += before - after


func _process(_delta: float) -> void:
	# Pointer is "over UI" whenever any editor Control is under the cursor — used
	# to keep the mouse wheel scrolling lists instead of zooming the map.
	_ui_hover = get_viewport().gui_get_hovered_control() != null
	var t := _tile_under_mouse()
	if t != _hover_tile:
		_hover_tile = t
		_update_coords()
	if _painting and not _ui_hover and _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE]:
		_apply_tool(false)
	if _img_dirty:
		_img_dirty = false
		_tex.update(_img)
	_overlay.queue_redraw()
	_position_preview_panel()


## Float the preview panel just to the right of the currently selected sidebar
## item, tracking it as the palette scrolls. Falls back beside the sidebar top
## for tools with no list selection (Pan / Erase / Set Spawn).
func _position_preview_panel() -> void:
	if _preview_panel == null:
		return
	var vp := get_viewport_rect().size
	var ph: float = _preview_panel.size.y
	if _selected_choice_btn != null and is_instance_valid(_selected_choice_btn) \
			and _selected_choice_btn.is_visible_in_tree():
		var r := _selected_choice_btn.get_global_rect()
		var y: float = clampf(r.position.y - 6.0, 8.0, maxf(8.0, vp.y - ph - 8.0))
		_preview_panel.position = Vector2(r.end.x + 10.0, y)
	else:
		_preview_panel.position = Vector2(200.0, 60.0)


func _tile_under_mouse() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x) + _min_tx, floori(p.y) + _min_ty)


# ─────────────────────────────── tools / brush ──────────────────────────────

func _apply_tool(just_pressed: bool) -> void:
	match _tool:
		Tool.BIOME: _paint(_paint_biome_tile)
		Tool.TERRAIN: _paint(_paint_terrain_tile)
		Tool.ERASE: _paint(_erase_tile)
		Tool.STAMP:
			if just_pressed:
				_place_stamp(_hover_tile)
				_commit_stroke()
		Tool.STRUCTURE:
			if just_pressed:
				_place_structure(_hover_tile)
				_commit_stroke()
		Tool.SPAWN:
			if just_pressed:
				_set_spawn(_hover_tile)
				_commit_stroke()


func _paint(fn: Callable) -> void:
	var r := _brush - 1
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue
			fn.call(_hover_tile.x + dx, _hover_tile.y + dy)


func _chunk_at_tile(gtx: int, gty: int) -> RefCounted:
	var c := WG.tile_to_chunk(Vector2i(gtx, gty))
	return _chunks.get("%d:%d" % [c.x, c.y], null)


func _tile_def_at(gtx: int, gty: int) -> Dictionary:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return {}
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	return _reg.tile_def(chunk.tile_id(lx, ly))


func _is_walkable_tile(gtx: int, gty: int) -> bool:
	var td := _tile_def_at(gtx, gty)
	if td.is_empty():
		return false
	return bool(td.get("walkable", false)) and not bool(td.get("water", false)) and not bool(td.get("hazard", false))


func _tile_state(chunk: RefCounted, ci: int) -> Array:
	return [chunk.tiles[ci], chunk.biomes_t[ci], chunk.parent_biomes_t[ci], chunk.sub_biomes_t[ci]]


func _apply_state(gtx: int, gty: int, state: Array) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var ci: int = Chunk.idx(lx, ly)
	chunk.tiles[ci] = int(state[0])
	chunk.biomes_t[ci] = int(state[1])
	chunk.parent_biomes_t[ci] = int(state[2])
	chunk.sub_biomes_t[ci] = int(state[3])
	_set_px(gtx, gty, _tile_color(int(state[0])))


## Capture the before-state once per tile in the active stroke, apply new state,
## and record after-state — so the whole drag collapses into one undo step.
func _record_and_set(gtx: int, gty: int, new_state: Array) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var ci: int = Chunk.idx(lx, ly)
	var key := Vector2i(gtx, gty)
	if not _stroke["tiles"].has(key):
		_stroke["tiles"][key] = [_tile_state(chunk, ci), null]
	_apply_state(gtx, gty, new_state)
	_stroke["tiles"][key][1] = new_state.duplicate()


func _paint_terrain_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var tid := int(_reg.tile_index.get(_sel_terrain, -1))
	if tid < 0:
		return
	var ci: int = Chunk.idx(gtx - chunk.cx * WG.CHUNK_TILES, gty - chunk.cy * WG.CHUNK_TILES)
	_record_and_set(gtx, gty, [tid, chunk.biomes_t[ci], chunk.parent_biomes_t[ci], chunk.sub_biomes_t[ci]])


func _paint_biome_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var idx := int(_reg.biome_index.get(_sel_biome, -1))
	if idx < 0:
		return
	var is_sub: bool = bool(_reg.biomes[idx].get("isSubBiome", false))
	var parent := idx
	var sub := 255
	if is_sub:
		parent = int(_reg.biome_index.get(str(_reg.biomes[idx].get("parentBiome", "")), idx))
		sub = idx
	_record_and_set(gtx, gty, [_biome_primary_tile(idx), idx, parent, sub])


func _biome_primary_tile(idx: int) -> int:
	var weights: Array = _reg.biomes[idx].get("_tile_weights", [])
	if weights.is_empty():
		return int(_reg.tile_index.get("grass", 0))
	return int(weights[0][0])


func _erase_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var key := "%d:%d" % [chunk.cx, chunk.cy]
	_erase_from(chunk, "structures", lx, ly, key)
	_erase_from(chunk, "monsters", lx, ly, key)
	FiniteWorldGenerator.apply_structure_collision(chunk)
	if _erase_biomes:
		# Restore the generated (procedural) terrain/biome for this tile.
		var gtid: int = WorldGen.surface_tile_id(gtx, gty)
		var gb: int = WorldGen.generator.classifier.biome_idx(float(gtx), float(gty))
		var gp: int = WorldGen.generator.classifier.parent_biome_idx(float(gtx), float(gty))
		_record_and_set(gtx, gty, [gtid, gb, gp, 255])


func _erase_from(chunk: RefCounted, arr_name: String, lx: int, ly: int, key: String) -> void:
	var arr: Array = _chunk_array(chunk, arr_name)
	for i: int in range(arr.size() - 1, -1, -1):
		var item: Dictionary = arr[i]
		if int(item.get("tx", -999)) == lx and int(item.get("ty", -999)) == ly:
			_stroke["removed"].append({"key": key, "arr": arr_name, "item": item})
			arr.remove_at(i)


func _chunk_array(chunk: RefCounted, arr_name: String) -> Array:
	match arr_name:
		"monsters": return chunk.monsters
		"sites": return chunk.sites
		_: return chunk.structures


# ─────────────────────────────── stamps ──────────────────────────────────────

## Paint a reusable natural stamp (pond, grove, outcrop…) at the cursor. Tiles +
## biomes go down as recorded tile edits; resource counts drop gather sites.
## Each placement bumps the variant so repeats vary; R rotates, F flips.
func _place_stamp(center: Vector2i) -> void:
	var stamps: Array = StampLibrary.all()
	if stamps.is_empty() or _sel_stamp >= stamps.size():
		return
	var stamp: Dictionary = stamps[_sel_stamp]
	var built: Dictionary = StampLibrary.build(stamp, _stamp_variant, _stamp_rot, _stamp_flip)
	for c: Dictionary in built["cells"]:
		var gx: int = center.x + int(c["dx"])
		var gy: int = center.y + int(c["dy"])
		var chunk: RefCounted = _chunk_at_tile(gx, gy)
		if chunk == null:
			continue
		var ci: int = Chunk.idx(gx - chunk.cx * WG.CHUNK_TILES, gy - chunk.cy * WG.CHUNK_TILES)
		var tile_name := str(c["tile"])
		var tid: int = int(chunk.tiles[ci])
		if not tile_name.is_empty() and _reg.tile_index.has(tile_name):
			tid = int(_reg.tile_index[tile_name])
		var biome_name := str(c.get("biome", ""))
		var b: int = int(chunk.biomes_t[ci])
		var p: int = int(chunk.parent_biomes_t[ci])
		var s: int = int(chunk.sub_biomes_t[ci])
		if not biome_name.is_empty() and _reg.biome_index.has(biome_name):
			b = int(_reg.biome_index[biome_name])
			p = b
			s = 255
		_record_and_set(gx, gy, [tid, b, p, s])
	for site: Dictionary in built["sites"]:
		_add_stamp_site(center.x + int(site["dx"]), center.y + int(site["dy"]), str(site["skill"]))
	_stamp_variant += 1
	_status.text = "Stamped %s (variant %d)" % [str(stamp["name"]), _stamp_variant]


## Add a natural gather site for a skill at a tile (editor stamp). Picks the
## lowest-level node of that skill so it's valid anywhere, builds the standard
## site dict, and records it for undo.
func _add_stamp_site(gx: int, gy: int, skill: String) -> void:
	var chunk: RefCounted = _chunk_at_tile(gx, gy)
	if chunk == null:
		return
	var entries: Array = _reg.node_table.get(skill, [])
	if entries.is_empty():
		return
	var best: Dictionary = entries[0]
	for e: Dictionary in entries:
		if int(e["level"]) < int(best["level"]):
			best = e
	var cfg: Dictionary = _reg.skill_cfg(skill)
	var lx: int = gx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gy - chunk.cy * WG.CHUNK_TILES
	var site := {
		"skill": skill, "node": best["name"], "level": int(best["level"]),
		"kind": str(cfg.get("kind", "bush")), "tx": lx, "ty": ly,
		"resources": int(cfg.get("resources", 8)), "remaining": int(cfg.get("resources", 8)),
		"respawn_sec": float(cfg.get("respawnSec", 25.0)), "available": true, "respawn_at": 0.0,
	}
	chunk.sites.append(site)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "sites", "item": site})


func _place_structure(t: Vector2i) -> void:
	var chunk: RefCounted = _chunk_at_tile(t.x, t.y)
	if chunk == null:
		return
	var entry: Array = STRUCTURES[_sel_struct]
	var part: Dictionary = (entry[1] as Dictionary).duplicate(true)
	part["tx"] = t.x - chunk.cx * WG.CHUNK_TILES
	part["ty"] = t.y - chunk.cy * WG.CHUNK_TILES
	if not part.has("label"):
		part["label"] = ""
	if part["kind"] in ["house", "building", "tent"]:
		part["color"] = ROOF_COLORS[(t.x + t.y) % ROOF_COLORS.size()]
	chunk.structures.append(part)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "structures", "item": part})
	# Buildings/walls collide via non-walkable wall tiles (same as the baked city),
	# so editor-placed ones get real collision too. Lone props use the derived
	# collision layer. Footprint tile changes are recorded in the stroke (undoable).
	var kind: String = str(part["kind"])
	if kind in ["building", "house", "city_wall"]:
		var wall := int(_reg.tile_index.get("building_wall", -1))
		var floor_tile := int(_reg.tile_index.get("plank_floor", _reg.tile_index.get("cobble", -1)))
		var r := 1 if kind != "building" else maxi(1, int(part.get("foot", 6)) / 2)
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var gx: int = t.x + dx
				var gy: int = t.y + dy
				var ch2: RefCounted = _chunk_at_tile(gx, gy)
				if ch2 != null and wall >= 0:
					var tile_id := wall
					if kind in ["building", "house"]:
						var edge := dx == -r or dx == r or dy == -r or dy == r
						var in_door := false
						var door_x := -maxi(0, r / 2)
						var door_depth := 3 if kind == "building" else 2
						for i: int in range(-1, 2):
							in_door = in_door or (dx == door_x + i and dy == r)
							in_door = in_door or (dx == door_x + i and dy == r - 1)
						if kind == "building":
							in_door = in_door or (dx == door_x and dy == r - door_depth + 1)
						tile_id = floor_tile if (not edge or in_door) and floor_tile >= 0 else wall
					var ci2: int = Chunk.idx(gx - ch2.cx * WG.CHUNK_TILES, gy - ch2.cy * WG.CHUNK_TILES)
					_record_and_set(gx, gy, [tile_id, ch2.biomes_t[ci2], ch2.parent_biomes_t[ci2], ch2.sub_biomes_t[ci2]])
	FiniteWorldGenerator.apply_structure_collision(chunk)
	_status.text = "Placed %s at (%d, %d)" % [str(entry[0]), t.x, t.y]


func _set_spawn(t: Vector2i) -> void:
	if not _is_walkable_tile(t.x, t.y):
		_status.text = "Spawn must be on walkable land (not water/hazard)."
		return
	_stroke["spawn"] = [_spawn_tile, t]
	_spawn_tile = t
	_status.text = "Player spawn set to (%d, %d)" % [t.x, t.y]


func _set_px(gtx: int, gty: int, col: Color) -> void:
	var ix := gtx - _min_tx
	var iy := gty - _min_ty
	if ix < 0 or iy < 0 or ix >= _w or iy >= _h:
		return
	_img.set_pixel(ix, iy, col)
	_img_dirty = true


# ─────────────────────────────── undo / redo ────────────────────────────────

func _begin_stroke() -> void:
	_stroke = {"tiles": {}, "added": [], "removed": [], "spawn": null}
	_stroke_active = true


func _stroke_empty() -> bool:
	return _stroke["tiles"].is_empty() and _stroke["added"].is_empty() \
		and _stroke["removed"].is_empty() and _stroke["spawn"] == null


func _commit_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if _stroke_empty():
		return
	_history.append(_stroke)
	_redo.clear()
	if _history.size() > 200:
		_history.pop_front()
	_resync_3d_tiles(_stroke["tiles"].keys())
	_refresh_history_buttons()


func _do_undo() -> void:
	if _history.is_empty():
		return
	var s: Dictionary = _history.pop_back()
	for key: Vector2i in s["tiles"]:
		_apply_state(key.x, key.y, s["tiles"][key][0])
	for a: Dictionary in s["added"]:
		_chunk_array(_chunks[a["key"]], a["arr"]).erase(a["item"])
	for r: Dictionary in s["removed"]:
		_chunk_array(_chunks[r["key"]], r["arr"]).append(r["item"])
	if s["spawn"] != null:
		_spawn_tile = s["spawn"][0]
	_refresh_stroke_collision(s)
	_resync_3d_tiles(s["tiles"].keys())
	_redo.append(s)
	_status.text = "Undid 1 action (%d left)" % _history.size()
	_refresh_history_buttons()


func _do_redo() -> void:
	if _redo.is_empty():
		return
	var s: Dictionary = _redo.pop_back()
	for key: Vector2i in s["tiles"]:
		_apply_state(key.x, key.y, s["tiles"][key][1])
	for a: Dictionary in s["added"]:
		_chunk_array(_chunks[a["key"]], a["arr"]).append(a["item"])
	for r: Dictionary in s["removed"]:
		_chunk_array(_chunks[r["key"]], r["arr"]).erase(r["item"])
	if s["spawn"] != null:
		_spawn_tile = s["spawn"][1]
	_refresh_stroke_collision(s)
	_resync_3d_tiles(s["tiles"].keys())
	_history.append(s)
	_status.text = "Redid 1 action"
	_refresh_history_buttons()


## Recompute collision for chunks touched by an undone/redone stroke's structures.
func _refresh_stroke_collision(s: Dictionary) -> void:
	var keys: Dictionary = {}
	for a: Dictionary in s["added"]:
		keys[a["key"]] = true
	for r: Dictionary in s["removed"]:
		keys[r["key"]] = true
	for key: String in keys:
		if _chunks.has(key):
			FiniteWorldGenerator.apply_structure_collision(_chunks[key])


func _refresh_history_buttons() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = _history.is_empty()
		_undo_btn.text = "↶ Undo (%d)" % _history.size()
	if _redo_btn != null:
		_redo_btn.disabled = _redo.is_empty()
		_redo_btn.text = "↷ Redo (%d)" % _redo.size()


# ─────────────────────────────── overlay ─────────────────────────────────────

func _draw_overlay(c: CanvasItem) -> void:
	var zoom: float = _cam.zoom.x
	if _show_collision or _show_biomes or _show_danger or _show_walk or _show_elevation:
		var view := _view_rect_tiles()
		var classifier: RefCounted = WorldGen.generator.classifier
		for key: String in _chunks:
			var chunk: RefCounted = _chunks[key]
			var bx: int = chunk.cx * WG.CHUNK_TILES
			var by: int = chunk.cy * WG.CHUNK_TILES
			if bx + WG.CHUNK_TILES < view.position.x or bx > view.end.x \
					or by + WG.CHUNK_TILES < view.position.y or by > view.end.y:
				continue
			if _show_danger:
				# One translucent tint per chunk by distance-from-centre danger.
				var d: float = classifier.danger01(float(bx + 8), float(by + 8))
				c.draw_rect(Rect2(float(bx - _min_tx), float(by - _min_ty), WG.CHUNK_TILES, WG.CHUNK_TILES),
					Color(d, 1.0 - d, 0.15, 0.22))
			if _show_collision or _show_biomes or _show_walk or _show_elevation:
				for ly: int in WG.CHUNK_TILES:
					for lx: int in WG.CHUNK_TILES:
						var px := float(bx + lx - _min_tx)
						var py := float(by + ly - _min_ty)
						if _show_collision and chunk.is_blocked(lx, ly):
							c.draw_rect(Rect2(px, py, 1.0, 1.0), Color(0.9, 0.2, 0.2, 0.45))
						if _show_walk:
							var td: Dictionary = _reg.tile_def(chunk.tile_id(lx, ly))
							if not bool(td.get("walkable", false)) or bool(td.get("water", false)) or bool(td.get("hazard", false)):
								c.draw_rect(Rect2(px, py, 1.0, 1.0), Color(0.15, 0.25, 0.9, 0.35))
						if _show_biomes:
							var bidx: int = chunk.biome_at(lx, ly)
							if bidx != 255 and bidx < _reg.biomes.size():
								c.draw_rect(Rect2(px, py, 1.0, 1.0), _biome_tint(bidx))
						if _show_elevation and chunk.elev.size() > 0:
							var elev: int = chunk.elev[Chunk.idx(lx, ly)]
							if elev > 0:
								c.draw_rect(Rect2(px, py, 1.0, 1.0),
									_elev_tint(float(elev) / float(classifier.ELEV_MAX_STEPS)))
	if _show_structs:
		var view := _view_rect_tiles()
		for key: String in _chunks:
			var chunk: RefCounted = _chunks[key]
			var bx: int = chunk.cx * WG.CHUNK_TILES
			var by: int = chunk.cy * WG.CHUNK_TILES
			if bx + WG.CHUNK_TILES < view.position.x or bx > view.end.x \
					or by + WG.CHUNK_TILES < view.position.y or by > view.end.y:
				continue
			for p: Dictionary in chunk.structures:
				var gx: float = float(bx + int(p.get("tx", 0)) - _min_tx) + 0.5
				var gy: float = float(by + int(p.get("ty", 0)) - _min_ty) + 0.5
				c.draw_rect(Rect2(gx - 0.5, gy - 0.5, 1.0, 1.0), STRUCT_MARK)
	if _show_spawn:
		var sp := Vector2(float(_spawn_tile.x - _min_tx) + 0.5, float(_spawn_tile.y - _min_ty) + 0.5)
		var r := 2.5
		c.draw_colored_polygon(PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)]), SPAWN_MARK)
		c.draw_arc(sp, r + 1.5, 0.0, TAU, 16, Color(0, 0, 0, 0.7), 1.0 / zoom)
	var ct := Vector2(float(_hover_tile.x - _min_tx) + 0.5, float(_hover_tile.y - _min_ty) + 0.5)
	if _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE]:
		c.draw_arc(ct, float(maxi(_brush - 1, 0)) + 0.5, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.0 / zoom)
	elif _tool == Tool.STAMP:
		var stamps: Array = StampLibrary.all()
		if _sel_stamp < stamps.size():
			var sr := float(int(stamps[_sel_stamp].get("radius", 3)))
			c.draw_arc(ct, sr + 0.5, 0.0, TAU, 24, Color(0.5, 1.0, 0.6, 0.9), 1.0 / zoom)


## High-contrast height heat ramp for the elevation overlay: a vivid
## blue -> cyan -> green -> yellow -> orange -> red -> white gradient so each
## elevation band reads clearly (t is steps / max steps).
static var _ELEV_RAMP: Array[Color] = [
	Color(0.10, 0.20, 0.95),   # lowest  - deep blue
	Color(0.00, 0.80, 0.95),   # cyan
	Color(0.15, 0.90, 0.20),   # green
	Color(0.95, 0.95, 0.10),   # yellow
	Color(0.98, 0.55, 0.05),   # orange
	Color(0.95, 0.10, 0.10),   # red
	Color(1.00, 1.00, 1.00),   # highest - white peaks
]
func _elev_tint(t: float) -> Color:
	t = clampf(t, 0.0, 1.0) * float(_ELEV_RAMP.size() - 1)
	var i := int(t)
	var col: Color
	if i >= _ELEV_RAMP.size() - 1:
		col = _ELEV_RAMP[_ELEV_RAMP.size() - 1]
	else:
		col = _ELEV_RAMP[i].lerp(_ELEV_RAMP[i + 1], t - float(i))
	col.a = 0.85
	return col


## Deterministic translucent tint per biome index for the biome overlay.
func _biome_tint(bidx: int) -> Color:
	var h := float((bidx * 2654435761) % 360) / 360.0
	return Color.from_hsv(h, 0.6, 0.9, 0.33)


func _view_rect_tiles() -> Rect2i:
	var half := get_viewport_rect().size / _cam.zoom * 0.5
	var tl := _cam.position - half
	return Rect2i(
		Vector2i(floori(tl.x) + _min_tx - 2, floori(tl.y) + _min_ty - 2),
		Vector2i(int(half.x * 2.0) + 4, int(half.y * 2.0) + 4))


# ─────────────────────────────── UI ──────────────────────────────────────────

func _build_ui() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	top.position = Vector2(8, 8)
	_track_ui_hover(top)
	_hud.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 10)
	top.add_child(tb)
	var title := Label.new()
	title.text = "  %s — World Editor   " % str(_spec.spec_name)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	tb.add_child(title)
	_undo_btn = _toolbar_button(tb, "↶ Undo", _do_undo)
	_redo_btn = _toolbar_button(tb, "↷ Redo", _do_redo)
	_toolbar_button(tb, "💾 Save (Ctrl+S)", _save)
	_toolbar_button(tb, "✓ Validate", _validate)
	_toolbar_button(tb, "🌿 Generate Natural", _confirm_generate_natural)
	_toolbar_button(tb, "⟳ Generate Full", _confirm_generate)
	_v3d_btn = _toolbar_button(tb, "🧊 3D View", _toggle_3d_view)
	_v3d_btn.toggle_mode = true
	_status = Label.new()
	_status.text = "Loaded %d chunks" % _chunks.size()
	_status.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	tb.add_child(_status)

	# Left panel: tools + brush + palette (one connected column)
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	left.position = Vector2(8, 50)
	left.custom_minimum_size = Vector2(184, 0)
	_track_ui_hover(left)
	_hud.add_child(left)
	var lb := VBoxContainer.new()
	lb.add_theme_constant_override("separation", 3)
	left.add_child(lb)

	_header(lb, "Tools")
	for ts: Array in [[Tool.PAN, "1 Pan/View"], [Tool.BIOME, "2 Biome"], [Tool.TERRAIN, "3 Terrain"],
			[Tool.STAMP, "4 Stamp"], [Tool.STRUCTURE, "5 Structure"], [Tool.ERASE, "6 Erase"],
			[Tool.SPAWN, "7 Set Spawn"], [Tool.CREATURE, "8 Creatures"]]:
		var b := Button.new()
		b.text = str(ts[1])
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(176, 0)
		var tl: int = ts[0]
		b.pressed.connect(func() -> void: _set_tool(tl))
		lb.add_child(b)
		_tool_buttons[tl] = b

	_brush_label = Label.new()
	_brush_label.text = "Brush size: %d" % _brush
	lb.add_child(_brush_label)
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 24
	slider.value = _brush
	slider.custom_minimum_size = Vector2(176, 0)
	slider.value_changed.connect(func(v: float) -> void: _set_brush(int(v)))
	lb.add_child(slider)

	_erase_biomes_check = CheckBox.new()
	_erase_biomes_check.text = "Erase biomes too"
	_erase_biomes_check.toggled.connect(func(on: bool) -> void: _erase_biomes = on)
	lb.add_child(_erase_biomes_check)

	_header(lb, "Overlays")
	_overlay_check(lb, "Structures", _show_structs, func(on: bool) -> void: _show_structs = on)
	_overlay_check(lb, "Player spawn", _show_spawn, func(on: bool) -> void: _show_spawn = on)
	_overlay_check(lb, "Collision/water", _show_collision, func(on: bool) -> void: _show_collision = on)
	_overlay_check(lb, "Biome tint", _show_biomes, func(on: bool) -> void: _show_biomes = on)
	_overlay_check(lb, "Danger/level", _show_danger, func(on: bool) -> void: _show_danger = on)
	_overlay_check(lb, "Walkability", _show_walk, func(on: bool) -> void: _show_walk = on)
	_overlay_check(lb, "Elevation", _show_elevation, func(on: bool) -> void: _show_elevation = on)

	var sep := HSeparator.new()
	lb.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(176, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lb.add_child(scroll)
	_palette_box = VBoxContainer.new()
	_palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_palette_box)

	_coords = Label.new()
	_coords.add_theme_font_size_override("font_size", 10)
	_coords.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	lb.add_child(_coords)
	var hint := Label.new()
	hint.text = "RMB pan · wheel zoom · [ ] size\nCtrl+Z undo · Ctrl+Y redo"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lb.add_child(hint)

	_build_preview_panel()


## Showcase panel that floats just to the right of the selected sidebar item
## (positioned each frame in _process). Shows the currently selected biome / tile
## / structure / creature with the real game art on a static iso tile. Updated by
## _update_preview() on every selection.
func _build_preview_panel() -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	_preview_panel.position = Vector2(200, 60)
	_preview_panel.top_level = true   # position is in screen space, not the HUD layout
	_track_ui_hover(_preview_panel)
	_hud.add_child(_preview_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_preview_panel.add_child(box)
	_header(box, "Preview")
	_preview = PlaceablePreview.new()
	_preview.reg = _reg
	box.add_child(_preview)
	_reroll_btn = Button.new()
	_reroll_btn.text = "🎲 Re-roll variant"
	_reroll_btn.pressed.connect(func() -> void: _preview.reroll())
	box.add_child(_reroll_btn)


# ───────────────────────────── live 3D view ─────────────────────────────────
# Embeds the real game (world.tscn) in a SubViewport. Because the editor edits the
# SAME WorldGen chunk objects the embedded renderer reads, painting on the 2D map and
# then re-meshing the touched chunks shows the true in-game 3D result.

## Build the (initially hidden) docked 3D panel shell. The heavy game scene inside is
## created lazily the first time the panel is shown (see _toggle_3d_view).
func _build_3d_view_panel() -> void:
	_v3d_panel = PanelContainer.new()
	_v3d_panel.add_theme_stylebox_override("panel", _panel(Color(0.06, 0.07, 0.09)))
	_v3d_panel.top_level = true
	_v3d_panel.visible = false
	_track_ui_hover(_v3d_panel)
	_hud.add_child(_v3d_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_v3d_panel.add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_header(bar, "3D View")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_v3d_max_btn = Button.new()
	_v3d_max_btn.text = "⛶ Maximize"
	_v3d_max_btn.toggle_mode = true
	_v3d_max_btn.tooltip_text = "Fill the screen with a large 3D authoring view (M). With a Structure/Stamp tool, click in it to place at the cursor; otherwise click re-aims the camera. Arrows orbit."
	_v3d_max_btn.pressed.connect(_toggle_3d_maximize)
	bar.add_child(_v3d_max_btn)
	var hint := Label.new()
	hint.text = "click: place / re-aim · arrows orbit"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	bar.add_child(hint)
	_v3d_container = SubViewportContainer.new()
	_v3d_container.custom_minimum_size = _V3D_SIZE
	_v3d_container.stretch = true
	# Docked = view-only (mouse passes to the 2D map). Maximized flips to STOP so the
	# editor receives clicks here for 3D placement / camera re-aim (see _apply_v3d_layout).
	_v3d_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_v3d_container.gui_input.connect(_on_v3d_gui_input)
	box.add_child(_v3d_container)
	_v3d_panel.position = Vector2(get_viewport().get_visible_rect().size) - Vector2(_V3D_SIZE) - Vector2(24, 24)


## Show/hide the 3D view; instantiates the embedded game world on first show.
func _toggle_3d_view() -> void:
	_v3d_on = not _v3d_on
	_v3d_panel.visible = _v3d_on
	if _v3d_btn != null:
		_v3d_btn.button_pressed = _v3d_on
	if _v3d_on and _v3d_world == null:
		_spawn_embedded_world()
	if _v3d_on:
		_focus_3d(_hover_tile if _in_bounds_tile(_hover_tile) else _spawn_tile)
	else:
		_v3d_max = false   # always reopen in the small docked corner


## Toggle the 3D panel between the small docked corner and a large authoring view that
## fills most of the screen. In large mode the editor receives clicks in the 3D view:
## a placement tool drops its object at the cursor; otherwise the click re-aims the camera.
func _toggle_3d_maximize() -> void:
	if not _v3d_on:
		# Turning maximize on also turns the 3D view on (convenience).
		_toggle_3d_view()
	_v3d_max = not _v3d_max
	_apply_v3d_layout()


## Apply the current docked/maximized layout to the 3D panel: size the SubViewport,
## reposition the panel, and switch input between view-only (docked) and interactive
## (maximized, so clicks walk the embedded player).
func _apply_v3d_layout() -> void:
	if _v3d_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if _v3d_max:
		# Fill the screen to the right of the left tool panel, with small margins.
		var sz := Vector2i(maxi(360, int(vp.x) - 226), maxi(280, int(vp.y) - 70))
		_v3d_container.custom_minimum_size = Vector2(sz)
		if _v3d_vp != null:
			_v3d_vp.size = sz
			_v3d_vp.handle_input_locally = false       # the EDITOR owns clicks (place / re-aim)
		_v3d_container.mouse_filter = Control.MOUSE_FILTER_STOP
		_v3d_panel.position = Vector2(210, 52)
		# Pin the camera to the authoring focus (no wandering player); click re-aims it.
		_focus_3d(_v3d_focus_tile if _in_bounds_tile(_v3d_focus_tile) else _spawn_tile)
	else:
		_v3d_container.custom_minimum_size = _V3D_SIZE
		if _v3d_vp != null:
			_v3d_vp.size = _V3D_SIZE
			_v3d_vp.handle_input_locally = false       # view-only: editor keeps the mouse
		_v3d_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_v3d_panel.position = Vector2(vp) - Vector2(_V3D_SIZE) - Vector2(24, 24)
		# Re-pin the camera to the last authoring focus so the 2D map drives the view again.
		_focus_3d(_v3d_focus_tile if _in_bounds_tile(_v3d_focus_tile) else _spawn_tile)
	_v3d_panel.reset_size.call_deferred()
	if _v3d_max_btn != null:
		_v3d_max_btn.button_pressed = _v3d_max
		_v3d_max_btn.text = "🗗 Restore" if _v3d_max else "⛶ Maximize"


func _spawn_embedded_world() -> void:
	_status.text = "Booting 3D view…"
	_v3d_vp = SubViewport.new()
	_v3d_vp.size = _V3D_SIZE
	_v3d_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_v3d_vp.handle_input_locally = false   # editor owns input; this is a viewer
	_v3d_container.add_child(_v3d_vp)
	_v3d_world = _GAME_SCENE.instantiate()
	_v3d_vp.add_child(_v3d_world)
	# Hide the embedded game's own HUD — we only want the 3D world image.
	var ehud: Node = _v3d_world.get_node_or_null("HUD")
	if ehud != null:
		(ehud as CanvasLayer).visible = false


## Aim the 3D camera at a world tile by teleporting the embedded player there (the
## renderer's camera eases to follow it) and re-centring its chunk streaming.
func _focus_3d(tile: Vector2i) -> void:
	if not _v3d_on or _v3d_world == null:
		return
	_v3d_focus_tile = tile
	var pos := WG.tile_to_world(tile.x, tile.y)
	var pl: Node2D = _v3d_world.get("player")
	if pl != null:
		pl.position = pos
	var cm: Node = _v3d_world.get("chunk_manager")
	if cm != null:
		cm.call("update_center", pos)
	# Pin the 3D camera to this authoring point so the live player never drifts the view.
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("editor_cam_target", pos)


## Re-mesh the chunks a stroke (or undo/redo) touched so terrain/biome/water edits show
## up in the 3D view. (Structure entities placed via the 3D view are refreshed separately
## by _refresh_3d_entities.)
func _resync_3d_tiles(tiles: Array) -> void:
	if not _v3d_on or _v3d_world == null:
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("rebuild_chunk"):
		return
	var seen := {}
	for t: Vector2i in tiles:
		var cx := floori(float(t.x) / float(WG.CHUNK_TILES))
		var cy := floori(float(t.y) / float(WG.CHUNK_TILES))
		var k := Vector2i(cx, cy)
		if seen.has(k):
			continue
		seen[k] = true
		rend.call("rebuild_chunk", cx, cy)


## Clicks inside the maximized 3D view (mouse_filter STOP routes them here). With a
## placement tool active, drop the selected structure/stamp at the cursor's tile and
## refresh the 3D entities live; otherwise re-aim the camera at the clicked point.
func _on_v3d_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _v3d_on or _busy:
		return
	var tile := _v3d_tile_under_mouse()
	if tile.x == -2147483648 or not _in_bounds_tile(tile):
		return
	match _tool:
		Tool.STRUCTURE:
			_begin_stroke()
			_place_structure(tile)
			_commit_stroke()
			_refresh_3d_entities(tile)
		Tool.STAMP:
			_begin_stroke()
			_place_stamp(tile)
			_commit_stroke()
			_refresh_3d_entities(tile)
		Tool.SPAWN:
			_begin_stroke()
			_set_spawn(tile)
			_commit_stroke()
		_:
			_focus_3d(tile)
			_status.text = "3D camera → (%d, %d)" % [tile.x, tile.y]
	_v3d_container.accept_event()


## World tile under the 3D-view cursor: map the container-local mouse into the
## SubViewport's pixel space, then raycast through the embedded camera to the ground.
func _v3d_tile_under_mouse() -> Vector2i:
	const NONE := Vector2i(-2147483648, 0)
	if _v3d_world == null or _v3d_vp == null:
		return NONE
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("screen_to_iso"):
		return NONE
	var csize := _v3d_container.size
	if csize.x <= 0.0 or csize.y <= 0.0:
		return NONE
	var local := _v3d_container.get_local_mouse_position()
	var sub_px := Vector2(local.x / csize.x, local.y / csize.y) * Vector2(_v3d_vp.size)
	var iso: Vector2 = rend.call("screen_to_iso", sub_px)
	return WG.world_to_tile(iso)


## Respawn the embedded world's entities for the placed tile's chunk (+ neighbours, so
## footprints that cross a chunk border show), then force a static-batch rebuild so the
## new structure appears in the 3D view without a reload.
func _refresh_3d_entities(tile: Vector2i) -> void:
	if _v3d_world == null:
		return
	var sp: Object = _v3d_world.get("_entity_spawner")
	var containers: Dictionary = _v3d_world.get("_chunk_containers")
	if sp == null or containers == null:
		return
	var c0 := WG.tile_to_chunk(tile)
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var chunk: RefCounted = _chunks.get("%d:%d" % [c0.x + dx, c0.y + dy])
			if chunk == null or not containers.has(chunk.key()):
				continue
			sp.call("on_chunk_unloaded", chunk)
			sp.call("on_chunk_loaded", chunk, true)
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("_static_sig", "")   # force the static prop batch to rebuild


func _in_bounds_tile(t: Vector2i) -> bool:
	return t.x >= _min_tx and t.x < _min_tx + _w and t.y >= _min_ty and t.y < _min_ty + _h


func _toolbar_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _overlay_check(parent: Control, text: String, on: bool, cb: Callable) -> void:
	var cb_box := CheckBox.new()
	cb_box.text = text
	cb_box.button_pressed = on
	cb_box.toggled.connect(cb)
	parent.add_child(cb_box)


func _track_ui_hover(_ctrl: Node) -> void:
	# No-op: _ui_hover is derived each frame from gui_get_hovered_control() in
	# _process (per-control enter/exit wrongly flips false when moving onto a
	# child button). Kept as a hook in case per-panel handling is wanted later.
	pass


func _set_tool(t: int) -> void:
	_tool = t
	for k: int in _tool_buttons:
		(_tool_buttons[k] as Button).button_pressed = (k == t)
	_refresh_palette()


func _set_brush(v: int) -> void:
	_brush = clampi(v, 1, 24)
	if _brush_label != null:
		_brush_label.text = "Brush size: %d" % _brush


func _refresh_palette() -> void:
	if _palette_box == null:
		return
	_selected_choice_btn = null
	for c: Node in _palette_box.get_children():
		c.queue_free()
	match _tool:
		Tool.BIOME:
			_header(_palette_box, "Parent biomes")
			for e: Dictionary in WorldGen.list_surface_biomes():
				_choice(str(e["name"]), str(e["id"]), _sel_biome == str(e["id"]),
					func(id: String) -> void: _sel_biome = id)
			_header(_palette_box, "Micro-biomes")
			for e: Dictionary in WorldGen.list_sub_biomes():
				_choice("  " + str(e["name"]), str(e["id"]), _sel_biome == str(e["id"]),
					func(id: String) -> void: _sel_biome = id)
		Tool.TERRAIN:
			_header(_palette_box, "Terrain / roads / walls")
			for e: Array in TERRAIN:
				_choice(str(e[1]), str(e[0]), _sel_terrain == str(e[0]),
					func(id: String) -> void: _sel_terrain = id)
		Tool.STAMP:
			_header(_palette_box, "Natural stamps")
			var stamps: Array = StampLibrary.all()
			for i: int in stamps.size():
				var ii := i
				_choice(str(stamps[i]["name"]), str(i), _sel_stamp == i,
					func(_id: String) -> void:
						_sel_stamp = ii
						_stamp_variant = 0)
			if _sel_stamp < stamps.size():
				_add_stamp_preview(stamps[_sel_stamp])
			_note("Click to place. R rotate, F flip. Each placement varies.")
		Tool.STRUCTURE:
			_header(_palette_box, "Structures")
			for i: int in STRUCTURES.size():
				var ii := i
				_choice(str(STRUCTURES[i][0]), str(i), _sel_struct == i,
					func(_id: String) -> void: _sel_struct = ii)
		Tool.CREATURE:
			_header(_palette_box, "Creatures (preview)")
			_note("Browse the bestiary art. Creatures are placed by world generation, not painted.")
			for e: Dictionary in _creature_list():
				var nm := str(e["name"])
				_choice("%s  ·  Lv%d" % [nm, int(e["level"])], nm, _sel_creature == nm,
					func(id: String) -> void: _sel_creature = id)
		Tool.SPAWN:
			_note("Click a walkable tile to set the player spawn. Current: (%d, %d)" % [_spawn_tile.x, _spawn_tile.y])
		Tool.ERASE:
			_note("Brush to remove placed structures & monsters. Tick 'Erase biomes too' to also restore generated terrain.")
		_:
			_note("Right-drag to pan, wheel to zoom. Pick a tool to edit.")
	_update_preview()


## Bestiary entries sorted by level then name, for the creature preview browser.
func _creature_list() -> Array:
	var out: Array = []
	for nm: String in DataRegistry.enemies:
		out.append({"name": nm, "level": int(DataRegistry.enemies[nm].get("level", 1))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	return out


## Drive the showcase turntable from the current tool + selection.
func _update_preview() -> void:
	if _preview == null:
		return
	match _tool:
		Tool.BIOME:
			_preview.show_biome(_sel_biome)
		Tool.TERRAIN:
			var label := _sel_terrain
			for e: Array in TERRAIN:
				if str(e[0]) == _sel_terrain:
					label = str(e[1])
			_preview.show_terrain(_sel_terrain, label)
		Tool.STRUCTURE:
			var entry: Array = STRUCTURES[_sel_struct]
			_preview.show_structure((entry[1] as Dictionary), str(entry[0]))
		Tool.STAMP:
			var stamps: Array = StampLibrary.all()
			if _sel_stamp < stamps.size():
				_preview.show_stamp(stamps[_sel_stamp], str(stamps[_sel_stamp]["name"]))
		Tool.CREATURE:
			if _sel_creature.is_empty():
				_preview.show_empty("No creatures in the bestiary")
			else:
				_preview.show_creature(_sel_creature)
		_:
			_preview.show_empty("Pick a paint/place tool to preview")


func _header(parent: Control, text: String) -> void:
	var h := Label.new()
	h.text = text
	h.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	parent.add_child(h)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 11)
	_palette_box.add_child(l)


## Small swatch preview of the selected stamp (tile colours) under the palette.
func _add_stamp_preview(stamp: Dictionary) -> void:
	var built: Dictionary = StampLibrary.build(stamp, 0, 0, false)
	var cells: Array = built["cells"]
	if cells.is_empty():
		return
	var mn := Vector2i(9999, 9999)
	var mx := Vector2i(-9999, -9999)
	for c: Dictionary in cells:
		mn = Vector2i(mini(mn.x, int(c["dx"])), mini(mn.y, int(c["dy"])))
		mx = Vector2i(maxi(mx.x, int(c["dx"])), maxi(mx.y, int(c["dy"])))
	var w: int = mx.x - mn.x + 1
	var h: int = mx.y - mn.y + 1
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for c: Dictionary in cells:
		var tname := str(c["tile"])
		if tname.is_empty() or not _reg.tile_index.has(tname):
			continue
		var cols: Array = _reg.tile_def(int(_reg.tile_index[tname]))["colors"]
		img.set_pixel(int(c["dx"]) - mn.x, int(c["dy"]) - mn.y, cols[0])
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(160, 120)
	_palette_box.add_child(tr)


func _choice(label: String, id: String, selected: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = selected
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(170, 0)
	b.pressed.connect(func() -> void:
		cb.call(id)
		_refresh_palette())
	if selected:
		_selected_choice_btn = b
	_palette_box.add_child(b)


func _update_coords() -> void:
	if _coords == null:
		return
	var info := "(%d, %d)" % [_hover_tile.x, _hover_tile.y]
	var chunk: RefCounted = _chunk_at_tile(_hover_tile.x, _hover_tile.y)
	if chunk != null:
		var lx: int = _hover_tile.x - chunk.cx * WG.CHUNK_TILES
		var ly: int = _hover_tile.y - chunk.cy * WG.CHUNK_TILES
		var bidx: int = chunk.biome_at(lx, ly)
		if bidx != 255 and bidx < _reg.biomes.size():
			info += "  " + str(_reg.biomes[bidx].get("id", ""))
	_coords.text = info


func _panel(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	return s


# ─────────────────────────────── generate ───────────────────────────────────

func _confirm_generate() -> void:
	_confirm_generate_mode(false, "Regenerate the whole world?",
		"This rebuilds the ENTIRE finite world (terrain + cities, ruins, roads…)\n"
		+ "and REPLACES all current edits. Unsaved work is lost (Save first).\n"
		+ "This clears the undo history.\n\nProceed?")


func _confirm_generate_natural() -> void:
	_confirm_generate_mode(true, "Generate a natural world draft?",
		"This rebuilds the finite world with NATURAL terrain + life only —\n"
		+ "grass, forests, water, hills, resources, wildlife. NO cities, roads,\n"
		+ "walls or man-made content (you add those by hand afterwards).\n\n"
		+ "REPLACES current edits and clears undo. Save first to keep them.\n\nProceed?")


func _confirm_generate_mode(natural: bool, title: String, body: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.dialog_text = body
	dlg.ok_button_text = "Generate"
	_track_ui_hover(dlg)
	_hud.add_child(dlg)
	dlg.confirmed.connect(func() -> void: _generate_world(natural))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _generate_world(natural_only: bool = false) -> void:
	_busy = true
	_status.text = "Generating world… (this can take ~30s)"
	await get_tree().process_frame
	var svc: RefCounted = FiniteWorldGenerator.new()
	# Fresh random seed → a whole new natural continent each time (not the same
	# fixed layout). The result is baked straight into the editor's chunks.
	svc.setup(_reg, randi())
	svc.natural_only = natural_only
	var chunks: Dictionary = await svc.generate_region(self,
		func(done: int, total: int) -> void:
			_status.text = "Generating… %d/%d chunks" % [done, total])
	_chunks = chunks
	_img = Image.create_empty(_w, _h, false, Image.FORMAT_RGB8)
	for key: String in _chunks:
		_blit_chunk(_chunks[key])
	_tex.update(_img)
	_spawn_tile = svc.default_spawn_tile()
	_history.clear()
	_redo.clear()
	_refresh_history_buttons()
	_busy = false
	_status.text = "Regenerated %d chunks. Undo history cleared. Save to keep." % _chunks.size()


# ─────────────────────────────── validate ───────────────────────────────────

func _validate() -> void:
	var issues: Array = []
	if not _is_walkable_tile(_spawn_tile.x, _spawn_tile.y):
		issues.append("Player spawn (%d,%d) is not walkable land." % [_spawn_tile.x, _spawn_tile.y])
	if not _bounds.has_point(WG.tile_to_chunk(_spawn_tile)):
		issues.append("Player spawn is outside the world bounds.")
	# Structures referencing unknown station ids.
	var stations: Dictionary = {}
	for key: String in _chunks:
		for p: Dictionary in _chunks[key].structures:
			if p.has("station"):
				stations[str(p["station"])] = true
	# Bank reachable near spawn (within a few chunks)?
	var bank_near := false
	var sc := WG.tile_to_chunk(_spawn_tile)
	for key: String in _chunks:
		var chunk: RefCounted = _chunks[key]
		if absi(chunk.cx - sc.x) > 3 or absi(chunk.cy - sc.y) > 3:
			continue
		for p: Dictionary in chunk.structures:
			if str(p.get("station", "")) == "bank":
				bank_near = true
		for poi: Dictionary in chunk.pois:
			for part: Dictionary in poi.get("parts", []):
				if str(part.get("station", "")) == "bank":
					bank_near = true
	if not bank_near:
		issues.append("No bank within ~3 chunks of spawn (starter area should have one).")

	var dlg := AcceptDialog.new()
	dlg.title = "Validation — %d issue(s)" % issues.size()
	dlg.dialog_text = "✓ No issues found." if issues.is_empty() else "• " + "\n• ".join(PackedStringArray(issues))
	_track_ui_hover(dlg)
	_hud.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	_status.text = "Validation: %d issue(s)" % issues.size()


# ─────────────────────────────── save ───────────────────────────────────────

func _save() -> void:
	_status.text = "Saving…"
	var chunks_doc: Dictionary = {}
	for key: String in _chunks:
		var chunk: RefCounted = _chunks[key]
		FiniteWorldGenerator.apply_structure_collision(chunk)   # derive fresh collision
		chunks_doc[key] = {
			"t": BakedWorldStore.encode(chunk.tiles),
			"b": BakedWorldStore.encode(chunk.biomes_t),
			"p": BakedWorldStore.encode(chunk.parent_biomes_t),
			"s": BakedWorldStore.encode(chunk.sub_biomes_t),
			"k": BakedWorldStore.encode(chunk.collision),
			"e": BakedWorldStore.encode(chunk.elev),
			"zone": chunk.zone.duplicate(true),
			"safe": chunk.safe,
			"sites": chunk.sites.duplicate(true),
			"pois": chunk.pois.duplicate(true),
			"monsters": chunk.monsters.duplicate(true),
			"structures": chunk.structures.duplicate(true),
		}
	var doc := {
		"version": 1,
		"id": _spec.id,
		"bounds": {"min": [_bounds.position.x, _bounds.position.y],
			"max": [_bounds.end.x - 1, _bounds.end.y - 1]},
		"spawn": [_spawn_tile.x, _spawn_tile.y],
		"chunks": chunks_doc,
	}
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world_path: String = OUT_DIR + str(_spec.id) + ".world"
	var f := FileAccess.open(world_path, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s" % world_path
		return
	f.store_string(var_to_str(doc))
	f.close()
	_img.save_png(OUT_DIR + str(_spec.id) + "_map.png")
	_status.text = "Saved %d chunks + spawn → %s" % [_chunks.size(), world_path]
	print("World editor saved: ", ProjectSettings.globalize_path(world_path))
