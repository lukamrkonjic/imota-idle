extends Node
class_name EntitySpriteCache
## Shared cache that rasterises a static entity's procedural art ONCE into a
## texture (keyed by its appearance) so every entity with the same look draws as a
## single quad instead of re-issuing dozens of non-batching polygons each frame.
## This is the entity-side equivalent of the terrain chunk bake.
##
## Many entities share a look (all "Regular Tree" variant 2 at size 50 → one
## texture), so the number of bakes is bounded by DISTINCT appearances, not entity
## count. Lazy by default; prewarm(...) can bake a known set up-front (e.g. on a
## loading screen before entering a fully-generated zone like a mine).

var _cache: Dictionary = {}     # key:String -> {"tex":Texture2D, "offset":Vector2}
var _pending: Dictionary = {}   # key:String -> Array[Callable] (redraw callbacks)


## A throwaway node that paints the entity art into the bake SubViewport.
class _Baker extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## Ready texture entry for `key`, or an empty dict if it still needs baking.
func entry(key: String) -> Dictionary:
	return _cache.get(key, {})


## Ensure `key` is baked. `painter.call(canvas)` must draw the art at the entity
## origin; `bounds` is its art-space bounding box. `on_ready` is invoked once the
## texture lands (typically the entity's queue_redraw). Deduplicates concurrent
## requests for the same key.
func request(key: String, bounds: Rect2, painter: Callable, on_ready: Callable) -> void:
	if _cache.has(key):
		if on_ready.is_valid():
			on_ready.call()
		return
	if _pending.has(key):
		if on_ready.is_valid():
			_pending[key].append(on_ready)
		return
	_pending[key] = [on_ready] if on_ready.is_valid() else []
	_bake(key, bounds, painter)


## Bake a batch of (key, bounds, painter) up-front without waiting per-entity.
## Intended for a loading screen ahead of a generated zone.
func prewarm(jobs: Array) -> void:
	for j: Dictionary in jobs:
		request(str(j["key"]), j["bounds"], j["painter"], Callable())


func _bake(key: String, bounds: Rect2, painter: Callable) -> void:
	var size := Vector2i(maxi(1, ceili(bounds.size.x)), maxi(1, ceili(bounds.size.y)))
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var baker := _Baker.new()
	baker.position = -bounds.position
	baker.painter = painter
	vp.add_child(baker)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := vp.get_texture().get_image()
	if img != null and img.get_width() > 0:
		_cache[key] = {"tex": ImageTexture.create_from_image(img), "offset": bounds.position}
	vp.queue_free()
	for cb: Callable in _pending.get(key, []):
		if cb.is_valid():
			cb.call()
	_pending.erase(key)
