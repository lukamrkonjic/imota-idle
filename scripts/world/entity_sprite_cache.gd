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

const BakeQueue := preload("res://scripts/world/bake_queue.gd")

var _cache: Dictionary = {}     # key:String -> {"tex":Texture2D, "offset":Vector2}
var _pending: Dictionary = {}   # key:String -> Array[Callable] (redraw callbacks)


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
	if BakeQueue.instance == null:
		return
	BakeQueue.instance.enqueue(
		Vector2i(ceili(bounds.size.x), ceili(bounds.size.y)),
		-bounds.position,
		painter,  # bound to the entity: invalid (and skipped) if it frees first
		func(tex: Texture2D) -> void: _on_baked(key, bounds.position, tex),
		func() -> bool: return not _cache.has(key),
		func() -> void: _pending.erase(key))  # skipped -> allow a live entity to re-request


func _on_baked(key: String, offset: Vector2, tex: Texture2D) -> void:
	_cache[key] = {"tex": tex, "offset": offset}
	for cb: Callable in _pending.get(key, []):
		if cb.is_valid():
			cb.call()
	_pending.erase(key)


## Bake a batch of (key, bounds, painter) up-front (still throttled through the
## BakeQueue). Intended for a loading screen ahead of a generated zone.
func prewarm(jobs: Array) -> void:
	for j: Dictionary in jobs:
		request(str(j["key"]), j["bounds"], j["painter"], Callable())
