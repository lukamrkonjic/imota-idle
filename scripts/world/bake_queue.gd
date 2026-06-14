extends Node
class_name BakeQueue
## Central, throttled rasteriser for ALL render-to-texture bakes (terrain chunks
## and entity sprites). Each bake ends in vp.get_texture().get_image(), a
## synchronous GPU->CPU readback that stalls the main thread. Doing many in one
## frame (which happens constantly while the player MOVES and new chunks/entities
## stream in) is the big hitch source. So every bake goes through this queue and
## only a couple of readbacks are allowed per frame — work is amortised, the
## frame never blocks on a pile of GPU stalls.

const MAX_IN_FLIGHT := 2

static var instance: BakeQueue = null

var _queue: Array = []   # each: [size:Vector2i, offset:Vector2, paint:Callable, on_done:Callable, guard:Callable]
var _in_flight := 0


class _Baker extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	instance = self


## Queue a bake. `paint.call(canvas)` draws the art; `offset` shifts it into the
## viewport (usually -bounds.position); `on_done.call(texture)` receives the baked
## texture. `guard` and `paint` should be BOUND method Callables on the requesting
## object so their is_valid() goes false when it is freed — then we skip cleanly
## and call `on_skip` (e.g. to let a shared look be re-requested by a live entity).
func enqueue(size: Vector2i, offset: Vector2, paint: Callable, on_done: Callable,
		guard: Callable, on_skip := Callable()) -> void:
	_queue.append([size, offset, paint, on_done, guard, on_skip])


func _process(_delta: float) -> void:
	while _in_flight < MAX_IN_FLIGHT and not _queue.is_empty():
		_run(_queue.pop_front())


func _still_wanted(job: Array) -> bool:
	var paint: Callable = job[2]
	var guard: Callable = job[4]
	# A bound Callable on a freed object reports is_valid() == false.
	if not paint.is_valid() or not guard.is_valid():
		return false
	return bool(guard.call())


func _run(job: Array) -> void:
	if not _still_wanted(job):
		var skip0: Callable = job[5]
		if skip0.is_valid():
			skip0.call()
		return
	_in_flight += 1
	var size: Vector2i = job[0]
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(1, size.x), maxi(1, size.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var baker := _Baker.new()
	baker.position = job[1]
	baker.painter = job[2]
	vp.add_child(baker)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if is_inside_tree() and _still_wanted(job):
		var img := vp.get_texture().get_image()
		if img != null and img.get_width() > 0:
			var on_done: Callable = job[3]
			if on_done.is_valid():
				on_done.call(ImageTexture.create_from_image(img))
	else:
		var skip1: Callable = job[5]
		if skip1.is_valid():
			skip1.call()
	vp.queue_free()
	_in_flight -= 1
