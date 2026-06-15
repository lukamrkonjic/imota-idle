extends Node
class_name SpriteAtlas
## Runtime side of the editor sprite-bake pipeline. Loads the baked atlas page
## textures + manifest produced by tools/bake_sprites.gd and lets world props draw
## themselves as a region of a SHARED page texture. Because every prop that shares
## a page draws the same Texture2D, Godot's 2D batcher merges them into a handful
## of draw calls instead of one-per-prop — this is what actually kills the lag.
##
## Safe + incremental: if the atlas (or a specific key) is missing, callers fall
## back to live procedural drawing, so the game never renders blank.

const DIR := "res://generated/sprite_atlas/"
const MANIFEST := DIR + "manifest.json"

static var instance: SpriteAtlas = null

var loaded := false
var _pages: Array[Texture2D] = []
# key:String -> {"tex":Texture2D, "region":Rect2, "pivot":Vector2}
var _sprites: Dictionary = {}


func _ready() -> void:
	instance = self
	_load()


func _load() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var txt := FileAccess.get_file_as_string(MANIFEST)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SpriteAtlas: manifest unreadable")
		return
	for p: Variant in data.get("pages", []):
		_pages.append(_load_page(str(p)))
	var sprites: Dictionary = data.get("sprites", {})
	for key: String in sprites.keys():
		var s: Dictionary = sprites[key]
		var pg := int(s.get("page", -1))
		if pg < 0 or pg >= _pages.size() or _pages[pg] == null:
			continue
		var r: Array = s.get("region", [0, 0, 0, 0])
		var pv: Array = s.get("pivot", [0, 0])
		_sprites[key] = {
			"tex": _pages[pg],
			"region": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
			"pivot": Vector2(float(pv[0]), float(pv[1])),
		}
	loaded = not _sprites.is_empty()
	if loaded:
		print("SpriteAtlas: %d sprites across %d page(s)" % [_sprites.size(), _pages.size()])


# Load straight from the PNG bytes into an ImageTexture so we don't depend on
# Godot's editor import step for a generated asset (works in exported builds too).
func _load_page(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_warning("SpriteAtlas: failed to decode %s" % path)
		return null
	return ImageTexture.create_from_image(img)


func has(key: String) -> bool:
	return _sprites.has(key)


## Draw the baked sprite `key` onto `canvas` with its foot/origin at the canvas
## origin (0,0). Returns false if the key isn't baked so the caller can fall back
## to live drawing. An empty (zero-size) baked region is a valid "draws nothing".
func draw_to(canvas: CanvasItem, key: String, modulate: Color = Color.WHITE, pos: Vector2 = Vector2.ZERO) -> bool:
	var s: Dictionary = _sprites.get(key, {})
	if s.is_empty():
		return false
	var region: Rect2 = s["region"]
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return true  # baked-empty: nothing to draw, but handled
	var pivot: Vector2 = s["pivot"]
	canvas.draw_texture_rect_region(s["tex"], Rect2(pos - pivot, region.size), region, modulate)
	return true
