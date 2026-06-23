extends SubViewportContainer
class_name PlaceablePreview
## A small showcase for the world editor: pick a biome, terrain tile, structure, prop,
## settlement or creature and this panel renders the REAL in-game 3D model on a turntable,
## so you can read it before placing. In the 3D pixel-art port an entity's visible body IS a
## 3D mesh (PropMeshes.entity_parts / enemy_rig), so the preview renders those in a tiny 3D
## SubViewport (same ortho-cam + sun + ambient recipe as the offline prop baker).

const WorldEntity := preload("res://scripts/world/world_entity.gd")
const WorldEntitySpawner := preload("res://scripts/world/world_entity_spawner.gd")
const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const StampLibrary := preload("res://scripts/worldgen/stamp_library.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const VIEW := Vector2i(232, 224)
const ROOF_COLORS := ["7a3b3b", "3b5a7a", "4a6b3a", "6b5a3a", "5a3b6b", "7a6b3a"]

var reg: RefCounted

var _vp: SubViewport
var _cam: Camera3D
var _model_root: Node3D          # the spinning model
var _ground: MeshInstance3D      # the tinted ground disc under it
var _caption: Label
var _variant := 0
var _reshow := Callable()


func _ready() -> void:
	custom_minimum_size = VIEW
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.transparent_bg = false
	# Isolate from the editor's 3D scene — without its OWN World3D the SubViewport renders the editor's
	# terrain (the ocean we kept seeing) plus our model. With it, the viewport contains ONLY the model,
	# camera, light and the flat HUD-coloured environment background.
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)
	_model_root = Node3D.new()
	world.add_child(_model_root)

	_ground = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.15
	disc.bottom_radius = 1.15
	disc.height = 0.08
	disc.radial_segments = 36
	_ground.mesh = disc
	_ground.position = Vector3(0, -0.04, 0)
	world.add_child(_ground)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(_cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.16)   # flat HUD panel colour — never the rendered world
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.82)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam.environment = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -125.0, 0.0)
	sun.light_energy = 1.15
	world.add_child(sun)

	_caption = Label.new()
	_caption.add_theme_color_override("font_color", Color(0.86, 0.89, 0.82))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_caption.add_theme_constant_override("outline_size", 4)
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -22
	_caption.offset_bottom = -4
	add_child(_caption)

	_frame_camera(AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 1.0, 1.2)))
	show_empty("Pick something to preview")


func _process(delta: float) -> void:
	if _model_root != null:
		_model_root.rotation.y += delta * 0.7   # gentle turntable


# ──────────────────────────────── public API ────────────────────────────────

func reroll() -> void:
	_variant = (_variant + 1) % 100000
	if _reshow.is_valid():
		_reshow.call()


func show_empty(msg: String) -> void:
	_reshow = Callable()
	_clear_model()
	_tint_ground(Color(0.30, 0.40, 0.26))
	_caption.text = msg
	_frame_camera(AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 0.4, 1.2)))


func show_biome(biome_id: String) -> void:
	_reshow = func() -> void: show_biome(biome_id)
	_clear_model()
	var idx := int(reg.biome_index.get(biome_id, -1))
	_tint_ground(_avg(_biome_ground_cols(idx)) if idx >= 0 else Color(0.34, 0.46, 0.28))
	# A representative tree (the biome's dominant canopy species) so the biome reads as itself.
	if idx >= 0:
		var cfg: Dictionary = reg.canopy(biome_id)
		var kinds: Array = cfg.get("kinds", [])
		if not kinds.is_empty():
			_add_parts(PropMeshes.decor_parts(str(kinds[0].get("kind", "canopy_broadleaf"))))
	_caption.text = (str(reg.biomes[idx].get("name", biome_id)) if idx >= 0 else biome_id)
	_frame_to_model(1.6)


func show_terrain(tile_name: String, label: String) -> void:
	_reshow = func() -> void: show_terrain(tile_name, label)
	_clear_model()
	var tid := int(reg.tile_index.get(tile_name, -1))
	var cols: Array = (reg.tile_def(tid)["colors"] as Array) if tid >= 0 else []
	_tint_ground(_avg(cols) if not cols.is_empty() else Color(0.5, 0.45, 0.35))
	_caption.text = label
	_frame_camera(AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 0.4, 1.2)))


## A placed structure / house / prop / decor, described by an editor STRUCTURES part dict.
func show_structure(part: Dictionary, label: String) -> void:
	_reshow = func() -> void: show_structure(part, label)
	_clear_model()
	_tint_ground(Color(0.32, 0.42, 0.27))
	var e := _entity_from_part(part)
	_add_parts(PropMeshes.entity_parts(e))
	e.free()
	_caption.text = label
	_frame_to_model(1.0)


func show_creature(name: String) -> void:
	_reshow = func() -> void: show_creature(name)
	_clear_model()
	_tint_ground(Color(0.32, 0.42, 0.27))
	var e := WorldEntity.new()
	e.kind = "enemy"
	e.label = name
	e.enemy_shape = IsoSprites.enemy_shape(name)
	e.display_size = 40.0
	var enemy: Dictionary = DataRegistry.get_enemy(name)
	e.tier_color = WorldEntitySpawner.tier_color(int(enemy.get("level", 1)))
	var rig: Node3D = PropMeshes.enemy_rig(e)
	e.free()
	if rig != null:
		_model_root.add_child(rig)
	var lvl := int(enemy.get("level", 0))
	_caption.text = name if lvl <= 0 else "%s · Lvl %d" % [name, lvl]
	_frame_to_model(1.4)


## A natural stamp (pond, grove, outcrop…): its dominant ground + a couple of the gather
## nodes it plants, so you see what a placement drops.
func show_stamp(stamp: Dictionary, label: String) -> void:
	_reshow = func() -> void: show_stamp(stamp, label)
	_clear_model()
	var built: Dictionary = StampLibrary.build(stamp, _variant, 0, false)
	_tint_ground(_avg(_stamp_ground_cols(built)))
	var sites: Array = built.get("sites", [])
	var n: int = mini(sites.size(), 3)
	var tallest := 0.6
	for i: int in n:
		var ent := _gather_node_entity(str((sites[i] as Dictionary).get("skill", "")))
		if ent == null:
			continue
		var ang := TAU * float(i) / float(maxi(n, 1))
		var off := Vector3(cos(ang), 0.0, sin(ang)) * (0.55 if n > 1 else 0.0)
		tallest = maxf(tallest, _add_parts(PropMeshes.entity_parts(ent), off))
		ent.free()
	_caption.text = label if n > 0 else label + "  (terrain only)"
	_frame_to_model(maxf(1.2, tallest))


# ──────────────────────────────── internals ─────────────────────────────────

func _clear_model() -> void:
	for c: Node in _model_root.get_children():
		c.queue_free()
	_model_root.rotation = Vector3.ZERO


func _tint_ground(col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = col
	m.roughness = 1.0
	_ground.material_override = m


## Build MeshInstance3Ds from a PropMeshes part list (skipping the blob shadow), at an optional
## ground offset. Returns the tallest point so the camera can frame it.
func _add_parts(parts: Array, base := Vector3.ZERO) -> float:
	var top := 0.5
	for p: Dictionary in parts:
		if bool(p.get("shadow", false)):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = p["mat"]
		mi.transform = Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"] + base)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model_root.add_child(mi)
		top = maxf(top, float(p["off"].y) + float(p["scl"].y) * 0.5 + base.y)
	return top


## Merged world-space AABB of every MeshInstance3D under the model (recursive).
func _model_aabb() -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [_model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = (n as MeshInstance3D).transform * (n as MeshInstance3D).get_aabb()
			box = a if first else box.merge(a)
			first = false
	if first:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return box


func _frame_to_model(min_h: float) -> void:
	var box := _model_aabb()
	box = box.merge(AABB(Vector3(-1.1, -0.1, -1.1), Vector3(2.2, maxf(min_h, 0.4), 2.2)))
	_frame_camera(box)


func _frame_camera(box: AABB) -> void:
	var target := box.get_center()
	var pitch := deg_to_rad(32.0)
	var yaw := deg_to_rad(40.0)
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = target + dir * 10.0
	_cam.look_at(target, Vector3.UP)
	_cam.size = maxf(1.4, box.size.length() * 0.62)


func _avg(cols: Array) -> Color:
	if cols.is_empty():
		return Color(0.34, 0.46, 0.28)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for c: Color in cols:
		r += c.r
		g += c.g
		b += c.b
	var n := float(cols.size())
	return Color(r / n, g / n, b / n)


func _entity_from_part(part: Dictionary) -> Node2D:
	var kind := str(part.get("kind", ""))
	var e := WorldEntity.new()
	e.kind = kind
	e.label = str(part.get("label", ""))
	e.variant = _variant
	e.display_size = 40.0
	e.roof_alpha = 1.0
	match kind:
		"tent":
			e.display_size = 54.0
			e.tent_color = _roll_roof()
			e.glow_color = e.tent_color
		"house":
			e.roof_color = _roll_roof()
		"building":
			e.display_size = float(part.get("foot", 6))
			e.roof_color = _roll_roof()
		"mountain":
			e.display_size = float(part.get("foot", 3))
			e.mountain_snow = float(part.get("snow", 0.4))
		"city_wall":
			e.variant = int(part.get("piece", 0))
		"city_prop":
			e.prop_kind = str(part.get("prop", "crate"))
		"decor":
			e.prop_kind = str(part.get("prop", "grass"))
		"obelisk":
			e.attuned = true
	return e


## A representative gather-node entity (tree/rock/bush/fish) for a skill.
func _gather_node_entity(skill: String) -> Node2D:
	var entries: Array = reg.node_table.get(skill, [])
	if entries.is_empty():
		return null
	var best: Dictionary = entries[0]
	for en: Dictionary in entries:
		if int(en["level"]) < int(best["level"]):
			best = en
	var cfg: Dictionary = reg.skill_cfg(skill)
	var e := WorldEntity.new()
	e.kind = str(cfg.get("kind", "bush"))
	e.label = str(best["name"])
	e.variant = _variant
	if e.kind == "tree":
		var TreeArt := preload("res://scripts/world/art/trees/tree_art.gd")
		e.display_size = TreeArt.tree_size(int(best["level"]), e.label)
	else:
		e.display_size = IsoSprites.node_size(e.kind)
	e.tier_color = WorldEntitySpawner.tier_color(int(best["level"]))
	return e


func _roll_roof() -> Color:
	return Color.from_string("#" + ROOF_COLORS[_variant % ROOF_COLORS.size()], Color(0.5, 0.3, 0.3))


func _neutral_ground() -> Array:
	var tid := int(reg.tile_index.get("grass", -1))
	if tid < 0:
		return [Color(0.34, 0.46, 0.28)]
	return (reg.tile_def(tid)["colors"] as Array).duplicate()


func _biome_ground_cols(idx: int) -> Array:
	if idx < 0:
		return _neutral_ground()
	var weights: Array = reg.biomes[idx].get("_tile_weights", [])
	var cols: Array = []
	for w: Array in weights:
		var td: Dictionary = reg.tile_def(int(w[0]))
		for c: Color in td.get("colors", []):
			cols.append(c)
		if cols.size() >= 4:
			break
	return cols if not cols.is_empty() else _neutral_ground()


func _stamp_ground_cols(built: Dictionary) -> Array:
	var counts: Dictionary = {}
	for c: Dictionary in built.get("cells", []):
		var tn := str(c.get("tile", ""))
		if not tn.is_empty():
			counts[tn] = int(counts.get(tn, 0)) + 1
	var best := ""
	var best_n := -1
	for tn: String in counts:
		if int(counts[tn]) > best_n and reg.tile_index.has(tn):
			best_n = int(counts[tn])
			best = tn
	if best.is_empty():
		return _neutral_ground()
	return (reg.tile_def(int(reg.tile_index[best]))["colors"] as Array).duplicate()
