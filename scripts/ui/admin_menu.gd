extends RefCounted
class_name AdminMenu
## Dev admin panel — biomes, items, skills. Biome list is data-driven from biomes.json.

const UiScale := preload("res://scripts/ui/ui_scale.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const STONE := UiTheme.STONE
const STONE_DARK := UiTheme.STONE_DARK
const ACCENT := UiTheme.GOLD

var _hud: CanvasLayer
var _popup: PopupPanel
var _tabs: TabContainer
var _item_search: LineEdit
var _item_list: VBoxContainer
var _item_cache: Array = []
var _item_filter := ""


func setup(hud: CanvasLayer) -> void:
	_hud = hud
	_build_item_cache()
	_build_popup()


func open() -> void:
	_refresh_biome_tab()
	_refresh_structures_tab()
	_refresh_places_tab()
	_filter_items(_item_search.text if _item_search != null else "")
	_popup.popup_centered()


func close() -> void:
	if _popup != null:
		_popup.hide()


func is_open() -> bool:
	return _popup != null and _popup.visible


func _build_item_cache() -> void:
	_item_cache.clear()
	for item_id: String in DataRegistry.items_by_id.keys():
		var item: Dictionary = DataRegistry.items_by_id[item_id]
		_item_cache.append({
			"id": item_id,
			"name": str(item.get("name", item_id)),
		})
	_item_cache.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]) < str(b["name"]))


func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.add_theme_stylebox_override("panel", _panel_style())
	var root := VBoxContainer.new()
	root.custom_minimum_size = UiScale.v2(Vector2(520, 540))
	root.add_theme_constant_override("separation", UiScale.i(8))
	_popup.add_child(root)

	var title := Label.new()
	title.text = "Admin Menu"
	title.add_theme_font_size_override("font_size", UiScale.i(17))
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_build_biome_tab()
	_build_structures_tab()
	_build_places_tab()
	_build_items_tab()
	_build_skills_tab()
	_build_misc_tab()

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _popup.hide())
	root.add_child(close)

	_hud.add_child(_popup)


func _build_biome_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Biomes"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.set_meta("biome_list", VBoxContainer.new())
	var list: VBoxContainer = scroll.get_meta("biome_list")
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var hint := Label.new()
	hint.text = "Teleport near the nearest parent or sub-biome, snapped to safe flat ground."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.i(11))
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	list.add_child(hint)
	_tabs.add_child(scroll)


func _refresh_biome_tab() -> void:
	var scroll: ScrollContainer = _tabs.get_node("Biomes") as ScrollContainer
	var list: VBoxContainer = scroll.get_meta("biome_list")
	for i: int in range(1, list.get_child_count()):
		list.get_child(i).queue_free()

	var parent_hdr := Label.new()
	parent_hdr.text = "Parent biomes"
	parent_hdr.add_theme_font_size_override("font_size", UiScale.i(13))
	parent_hdr.add_theme_color_override("font_color", ACCENT)
	list.add_child(parent_hdr)
	for entry: Dictionary in WorldGen.list_surface_biomes():
		_add_biome_row(list, entry, false)

	var sub_hdr := Label.new()
	sub_hdr.text = "Sub-biomes / micro-regions"
	sub_hdr.add_theme_font_size_override("font_size", UiScale.i(13))
	sub_hdr.add_theme_color_override("font_color", ACCENT)
	list.add_child(sub_hdr)
	for entry: Dictionary in WorldGen.list_sub_biomes():
		_add_biome_row(list, entry, true)


func _add_biome_row(list: VBoxContainer, entry: Dictionary, is_sub: bool) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	if is_sub:
		lbl.text = "  %s  (%s · %s)" % [str(entry["name"]), str(entry["id"]), str(entry.get("parent", ""))]
	else:
		lbl.text = "%s  (%s)" % [str(entry["name"]), str(entry["id"])]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	var tp := Button.new()
	tp.text = "Go"
	var biome_id: String = str(entry["id"])
	tp.pressed.connect(func() -> void: _teleport_biome(biome_id))
	row.add_child(tp)
	list.add_child(row)


func _teleport_biome(biome_id: String) -> void:
	var world: Node2D = _hud.get("world")
	if world == null:
		return
	var from: Vector2 = world.player.position if world.get("player") != null else Vector2.ZERO
	var hit: Dictionary = WorldGen.find_nearest_biome(from, biome_id)
	if hit.is_empty():
		_hud.call("_push_chat", "[color=#a01010]No %s biome found nearby.[/color]" % biome_id)
		return
	EventBus.teleport_requested.emit(hit["pos"])
	_hud.call("_push_chat", "[color=#5a3a8a]Teleported to %s (~%.0f tiles away).[/color]" % [
		str(hit["name"]), float(hit["distance"]) / WG.TILE])
	_popup.hide()


# ------------------------------------------------------------- structures ----
## Teleport to the nearest of each POI type — settlements (campsites, villages,
## capital cities), ruins, dungeons, altars, shrines, obelisks and landmarks.
const STRUCTURE_SEARCH_RINGS := 60


func _build_structures_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Structures"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.set_meta("structure_list", VBoxContainer.new())
	var list: VBoxContainer = scroll.get_meta("structure_list")
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var hint := Label.new()
	hint.text = "Teleport to the nearest structure of each type — cities, ruins, dungeons, altars, shrines, obelisks and landmarks (searched outward from you)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.i(11))
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	list.add_child(hint)
	_tabs.add_child(scroll)


func _refresh_structures_tab() -> void:
	var scroll: ScrollContainer = _tabs.get_node("Structures") as ScrollContainer
	var list: VBoxContainer = scroll.get_meta("structure_list")
	for i: int in range(1, list.get_child_count()):
		list.get_child(i).queue_free()

	var entries: Array = []
	for type: String in WorldGen.reg.pois:
		var def: Dictionary = WorldGen.reg.pois[type]
		# Part-less POIs (resource_depot, fishing_hotspot) only ring an anchor
		# with gather sites — no structure entity to teleport to, so skip them.
		if Array(def.get("parts", [])).is_empty():
			continue
		entries.append({
			"type": type,
			"label": str(def.get("label", type)),
			"mode": str(def.get("placement", {}).get("mode", "chance")),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["label"]) < str(b["label"]))
	for entry: Dictionary in entries:
		_add_structure_row(list, entry)


func _add_structure_row(list: VBoxContainer, entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s  (%s · %s)" % [str(entry["label"]), str(entry["type"]), str(entry["mode"])]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	var tp := Button.new()
	tp.text = "Go"
	var type_id: String = str(entry["type"])
	var nice: String = str(entry["label"])
	tp.pressed.connect(func() -> void: _teleport_structure(type_id, nice))
	row.add_child(tp)
	list.add_child(row)


func _teleport_structure(type: String, nice: String) -> void:
	var world: Node2D = _hud.get("world")
	if world == null:
		return
	var from: Vector2 = world.player.position if world.get("player") != null else Vector2.ZERO
	var def: Dictionary = WorldGen.reg.pois.get(type, {})
	var hit: Dictionary
	if def.has("mega"):
		# Multi-chunk cities/ruin fields are found from the deterministic planner.
		hit = WorldGen.find_nearest_structure(from, str(def["mega"].get("kind", "")))
	else:
		hit = WorldGen.find_nearest_poi(0, from, [type], STRUCTURE_SEARCH_RINGS)
	if hit.is_empty():
		_hud.call("_push_chat", "[color=#a01010]No %s found within range.[/color]" % nice)
		return
	EventBus.teleport_requested.emit(hit["pos"])
	_hud.call("_push_chat", "[color=#5a3a8a]Teleported to %s (~%.0f tiles away).[/color]" % [
		nice, from.distance_to(hit["pos"]) / WG.TILE])
	_popup.hide()


# ----------------------------------------------------------------- places ----
## Authored, hand-placed locations from the active WorldSpec — settlements,
## landmarks, and pinned anchors (dungeons/bosses). Unlike the Structures tab
## (which ring-searches the generator), these teleport to EXACT designed tiles.

func _build_places_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Places"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.set_meta("places_list", VBoxContainer.new())
	var list: VBoxContainer = scroll.get_meta("places_list")
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var hint := Label.new()
	hint.text = "Hand-authored places in the fixed world: settlements, landmarks and key sites. Teleports near the designed tile on safe flat ground."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.i(11))
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	list.add_child(hint)
	_tabs.add_child(scroll)


func _refresh_places_tab() -> void:
	var scroll: ScrollContainer = _tabs.get_node("Places") as ScrollContainer
	var list: VBoxContainer = scroll.get_meta("places_list")
	for i: int in range(1, list.get_child_count()):
		list.get_child(i).queue_free()

	var spec: RefCounted = WorldGen.reg.spec
	if not spec.active:
		var none := Label.new()
		none.text = "No authored world is active."
		list.add_child(none)
		return

	_places_header(list, "Settlements")
	for s: Dictionary in spec.settlements:
		var t: Vector2i = s["tile"]
		var svc: String = ", ".join(PackedStringArray(s.get("services", [])))
		_add_place_row(list, "%s — %s" % [str(s["label"]), str(s["kind"])],
			"%s%s" % [str(s["theme"]), ("  ·  " + svc) if not svc.is_empty() else ""], t)

	_places_header(list, "Landmarks")
	for f: Dictionary in spec.features:
		if str(f.get("kind", "")) == "landmark" and f.has("tile"):
			_add_place_row(list, str(f.get("label", "Landmark")), "landmark", f["tile"])

	_places_header(list, "Dungeons & bosses")
	for a: Dictionary in spec.anchors:
		var ch: Vector2i = a["chunk"]
		var tile := Vector2i(ch.x * WG.CHUNK_TILES + WG.CHUNK_TILES / 2, ch.y * WG.CHUNK_TILES + WG.CHUNK_TILES / 2)
		var sub: String = str(a.get("poi", ""))
		if not str(a.get("boss", "")).is_empty():
			sub += "  ·  boss: " + str(a["boss"])
		_add_place_row(list, str(a.get("label", a.get("id", ""))), sub, tile)


func _places_header(list: VBoxContainer, text: String) -> void:
	var hdr := Label.new()
	hdr.text = text
	hdr.add_theme_font_size_override("font_size", UiScale.i(13))
	hdr.add_theme_color_override("font_color", ACCENT)
	list.add_child(hdr)


func _add_place_row(list: VBoxContainer, title: String, sub: String, tile: Vector2i) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "  %s  (%s)" % [title, sub] if not sub.is_empty() else "  %s" % title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	var tp := Button.new()
	tp.text = "Go"
	var dest := tile
	var nice := title
	tp.pressed.connect(func() -> void: _teleport_tile(dest, nice))
	row.add_child(tp)
	list.add_child(row)


func _teleport_tile(tile: Vector2i, nice: String) -> void:
	var world: Node2D = _hud.get("world")
	if world == null:
		return
	var pos: Vector2 = WG.tile_to_world(tile.x, tile.y)
	EventBus.teleport_requested.emit(pos)
	_hud.call("_push_chat", "[color=#5a3a8a]Teleported to %s.[/color]" % nice)
	_popup.hide()


func _build_items_tab() -> void:
	var wrap := VBoxContainer.new()
	wrap.name = "Items"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_item_search = LineEdit.new()
	_item_search.placeholder_text = "Search items by name or id…"
	_item_search.text_changed.connect(_filter_items)
	wrap.add_child(_item_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_list)
	wrap.add_child(scroll)
	_tabs.add_child(wrap)


func _filter_items(query: String) -> void:
	_item_filter = query.strip_edges().to_lower()
	for c: Node in _item_list.get_children():
		c.queue_free()
	var shown := 0
	const LIMIT := 60
	var total := 0
	for entry: Dictionary in _item_cache:
		var name_l := str(entry["name"]).to_lower()
		var id_l := str(entry["id"]).to_lower()
		if not _item_filter.is_empty() and _item_filter not in name_l and _item_filter not in id_l:
			continue
		total += 1
		if shown >= LIMIT:
			continue
		shown += 1
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(entry["name"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.tooltip_text = str(entry["id"])
		row.add_child(lbl)
		for qty: int in [1, 10, 100]:
			var btn := Button.new()
			btn.text = "+%d" % qty
			var item_id: String = str(entry["id"])
			var q := qty
			btn.pressed.connect(func() -> void: _give_item(item_id, q))
			row.add_child(btn)
		_item_list.add_child(row)
	if total > LIMIT:
		var more := Label.new()
		more.text = "Showing %d of %d matches — refine your search." % [LIMIT, total]
		more.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		more.add_theme_font_size_override("font_size", UiScale.i(11))
		_item_list.add_child(more)


func _give_item(item_id: String, qty: int) -> void:
	if GameState.admin_give_item(item_id, qty) <= 0:
		_hud.call("_push_chat", "[color=#a01010]Unknown item: %s[/color]" % item_id)
		return
	_hud.call("_push_chat", "[color=#1a6e1a]Admin: gave %dx %s.[/color]" % [
		qty, DataRegistry.item_display_name(item_id)])


func _build_skills_tab() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiScale.i(10))

	var max_all := Button.new()
	max_all.text = "Max all skills (level %d)" % DataRegistry.max_level
	max_all.pressed.connect(func() -> void:
		GameState.admin_max_all_skills()
		_hud.call("_refresh_all")
		_hud.call("_push_chat", "[color=#1a6e1a]All skills set to max level.[/color]"))
	box.add_child(max_all)

	var reset_all := Button.new()
	reset_all.text = "Reset all skills (level 1)"
	reset_all.pressed.connect(func() -> void:
		GameState.admin_reset_all_skills()
		_hud.call("_refresh_all")
		_hud.call("_push_chat", "[color=#8a1a1a]All skills reset to level 1.[/color]"))
	box.add_child(reset_all)

	for skill: String in GameState.SKILLS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (now %d)" % [skill.capitalize(), GameState.level(skill)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Max"
		var sk := skill
		btn.pressed.connect(func() -> void:
			GameState.admin_max_skill(sk)
			_hud.call("_refresh_all")
			_hud.call("_push_chat", "[color=#1a6e1a]%s maxed.[/color]" % sk.capitalize()))
		row.add_child(btn)
		box.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(box)
	var wrap := VBoxContainer.new()
	wrap.name = "Skills"
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(scroll)
	_tabs.add_child(wrap)


func _build_misc_tab() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiScale.i(8))

	_add_misc_button(box, "Full heal", func() -> void:
		GameState.set_hp(GameState.max_hp()))
	_add_misc_button(box, "+1,000 coins", func() -> void:
		GameState.add_coins(1000))
	_add_misc_button(box, "Deposit inventory → bank", func() -> void:
		GameState.deposit_all())
	_add_misc_button(box, "Teleport to spawn", func() -> void:
		var world: Node2D = _hud.get("world")
		if world != null:
			EventBus.teleport_requested.emit(WorldGen.spawn_position())
			_popup.hide())

	# Weather override — flip the global weather on the fly. "Auto" hands it back to the
	# climate-gated scheduler; the others force that weather everywhere (for testing/showcase).
	var wlabel := Label.new()
	wlabel.text = "Weather"
	wlabel.add_theme_font_size_override("font_size", UiScale.i(13))
	wlabel.add_theme_color_override("font_color", ACCENT)
	box.add_child(wlabel)
	var wstatus := Label.new()
	wstatus.text = "Current: %s" % Weather.label()
	wstatus.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	box.add_child(wstatus)
	Weather.changed.connect(func(m: String) -> void:
		if is_instance_valid(wstatus):
			wstatus.text = "Current: %s" % m.capitalize())
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", UiScale.i(4))
	for m: String in Weather.MODES:
		var b := Button.new()
		b.text = m.capitalize()
		var mm: String = m
		b.pressed.connect(func() -> void: Weather.set_mode(mm))
		wrow.add_child(b)
	box.add_child(wrow)

	# Time-of-day override — jump to a phase, or freeze the cycle.
	var dlabel := Label.new()
	dlabel.text = "Time of day"
	dlabel.add_theme_font_size_override("font_size", UiScale.i(13))
	dlabel.add_theme_color_override("font_color", ACCENT)
	box.add_child(dlabel)
	var dstatus := Label.new()
	dstatus.text = "Now: %s" % DayNight.label()
	dstatus.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	box.add_child(dstatus)
	DayNight.phase_changed.connect(func(_p: String) -> void:
		if is_instance_valid(dstatus):
			dstatus.text = "Now: %s" % DayNight.label())
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", UiScale.i(4))
	for tod: Array in [["Dawn", 0.25], ["Noon", 0.5], ["Dusk", 0.75], ["Midnight", 0.0]]:
		var b := Button.new()
		b.text = str(tod[0])
		var tt: float = tod[1]
		b.pressed.connect(func() -> void:
			DayNight.set_time(tt)
			if is_instance_valid(dstatus):
				dstatus.text = "Now: %s" % DayNight.label())
		drow.add_child(b)
	var freeze := Button.new()
	freeze.text = "Freeze"
	freeze.toggle_mode = true
	freeze.toggled.connect(func(on: bool) -> void: DayNight.scale = 0.0 if on else 1.0)
	drow.add_child(freeze)
	box.add_child(drow)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var wrap := VBoxContainer.new()
	wrap.name = "Misc"
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(scroll)
	_tabs.add_child(wrap)


func _add_misc_button(parent: Control, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _panel_style() -> StyleBoxFlat:
	return UiTheme.panel_style()
