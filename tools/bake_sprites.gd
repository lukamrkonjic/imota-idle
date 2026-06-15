extends Node
## Editor-time sprite baker. Renders the game's procedural art ONCE into a packed
## texture atlas (PNG pages) + a manifest, so at runtime props draw as regions of a
## shared page texture instead of re-drawing their (expensive) procedural art live
## every time they stream into view. This removes the per-step "bake warmup" stall
## that makes walking lag. Run windowed (needs the GPU), NOT headless:
##
##   godot --path . res://tools/bake_sprites.tscn
##
## Output: res://generated/sprite_atlas/{page_N.png, manifest.json}
## Re-run after changing any baked art. Runtime falls back to live drawing for any
## look not in the manifest, so this is always safe to (re)generate.

const GroundDecorArt := preload("res://scripts/world/art/ground_decor/ground_decor_art.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")
const WG := preload("res://scripts/worldgen/wg.gd")

const OUT_DIR := "res://generated/sprite_atlas/"
const PAGE := 2048
const PAD := 2

# Decor: look is fully determined by (kind, variant); tint is always white.
const DECOR_VARIANTS := 24
const DECOR_KINDS := [
	"grass", "fern", "flower", "shrub", "stick", "pebble", "reed", "mushroom",
	"cactus", "vine", "moss", "lichen", "driftwood", "shell", "bone", "bramble",
	"rubble",
]
const DECOR_CELL := Vector2i(192, 192)
const DECOR_ORIGIN := Vector2(96, 150)

# Entity harvest: stream the real world at these chunk centres (origin cluster +
# far jumps for biome variety) and bake every distinct static-entity look seen.
const HARVEST_SETTLE_FRAMES := 90

var _pages: Array[Image] = []
var _cx := PAD
var _cy := PAD
var _shelf_h := 0
var _sprites: Dictionary = {}
var _seen: Dictionary = {}     # sprite_key -> true (global dedup)
var _count := 0
var _empty := 0
var _world: Node2D


func _ready() -> void:
	print("\n=== SPRITE BAKE START ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_new_page()
	await _bake_decor()
	await _bake_entities()
	_finish()


func _bake_decor() -> void:
	for kind: String in DECOR_KINDS:
		for v: int in range(DECOR_VARIANTS):
			var key := "decor|%s|%d" % [kind, v]
			await _bake_one(key, DECOR_CELL, DECOR_ORIGIN, func(c: CanvasItem) -> void:
				GroundDecorArt.draw(c, kind, v, Color.WHITE))
	print("  decor: %d sprites" % _count)


func _bake_entities() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame

	var centres: Array[Vector2i] = []
	for cy: int in range(-2, 3):
		for cx: int in range(-2, 3):
			centres.append(Vector2i(cx, cy))
	for far: Vector2i in [Vector2i(40, 0), Vector2i(0, 40), Vector2i(40, 40),
			Vector2i(-40, 25), Vector2i(25, -40), Vector2i(-30, -30), Vector2i(80, 80)]:
		centres.append(far)

	var before := _count
	for c: Vector2i in centres:
		var pos := WG.tile_to_world(c.x * WG.CHUNK_TILES + 8, c.y * WG.CHUNK_TILES + 8)
		_world.player.position = pos
		_world.chunk_manager.call("update_center", pos)
		for _i: int in HARVEST_SETTLE_FRAMES:
			await get_tree().process_frame
		await _harvest_visible()
	print("  entities: %d sprites from %d centres" % [_count - before, centres.size()])


## Bake every not-yet-seen static-entity look currently in the world.
func _harvest_visible() -> void:
	var ents: Array = _world.entities.duplicate()
	for e: Node2D in ents:
		if not is_instance_valid(e):
			continue
		var kind: String = e.get("kind")
		# Animated kinds never use the baked cache at runtime, so don't bake them.
		if kind in WorldEntity.ANIMATED_KINDS:
			continue
		var key: String = e.call("_sprite_key")
		if _seen.has(key):
			continue
		_seen[key] = true
		var bounds: Rect2 = e.call("_sprite_bounds")
		if bounds.size.x < 1.0 or bounds.size.y < 1.0:
			continue
		var cell := Vector2i(ceili(bounds.size.x), ceili(bounds.size.y))
		# Skip absurd sizes that would blow the atlas (none expected).
		if cell.x > PAGE - PAD * 2 or cell.y > PAGE - PAD * 2:
			continue
		var origin := -bounds.position
		await _bake_one("ent|" + key, cell, origin, Callable(e, "_paint_into"))


## Render one painter into a SubViewport, trim it, pack it into the atlas.
func _bake_one(key: String, cell: Vector2i, origin: Vector2, painter: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(1, cell.x), maxi(1, cell.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var baker := _Baker.new()
	baker.position = origin
	baker.painter = painter
	vp.add_child(baker)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()

	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_sprites[key] = {"page": 0, "region": [0, 0, 0, 0], "pivot": [0, 0]}
		_empty += 1
		return
	var pos := _alloc(used.size)
	_pages[pos.z].blit_rect(img, used, Vector2i(pos.x, pos.y))
	var pivot := origin - Vector2(used.position)
	_sprites[key] = {
		"page": pos.z,
		"region": [pos.x, pos.y, used.size.x, used.size.y],
		"pivot": [pivot.x, pivot.y],
	}
	_count += 1


## Shelf-allocate a w*h rect; returns Vector3i(x, y, page). Opens new shelves /
## pages as needed.
func _alloc(size: Vector2i) -> Vector3i:
	var w := size.x + PAD
	var h := size.y + PAD
	if _cx + w > PAGE:
		_cx = PAD
		_cy += _shelf_h + PAD
		_shelf_h = 0
	if _cy + h > PAGE:
		_new_page()
		_cx = PAD
		_cy = PAD
		_shelf_h = 0
	var x := _cx
	var y := _cy
	_cx += w
	_shelf_h = maxi(_shelf_h, size.y)
	return Vector3i(x, y, _pages.size() - 1)


func _new_page() -> void:
	var img := Image.create(PAGE, PAGE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_pages.append(img)


func _finish() -> void:
	var page_paths: Array = []
	for i: int in _pages.size():
		var path := OUT_DIR + "page_%d.png" % i
		var err := _pages[i].save_png(path)
		if err != OK:
			push_error("save_png failed (%s): %d" % [path, err])
		page_paths.append(path)
	var manifest := {"pages": page_paths, "sprites": _sprites}
	var f := FileAccess.open(OUT_DIR + "manifest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
	print("=== SPRITE BAKE DONE: %d sprites (%d empty) on %d page(s) ===" % [
		_count, _empty, _pages.size()])
	print(JSON.stringify({"out": ProjectSettings.globalize_path(OUT_DIR)}))
	get_tree().quit(0)


class _Baker extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)
