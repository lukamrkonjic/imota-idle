extends Node
class_name BakeQueue
## Central, throttled rasteriser for render-to-texture bakes. Bakes stay as
## GPU-resident ViewportTextures; forcing get_image() here creates a synchronous
## GPU-to-CPU readback, which is exactly the kind of stall that shows up while
## walking streams fresh entity art into the cache.

const MAX_IN_FLIGHT := 1
const START_INTERVAL_MSEC := 50

static var instance: BakeQueue = null

var _queue: Array = []   # each: [size:Vector2i, offset:Vector2, paint:Callable, on_done:Callable, guard:Callable]
var _in_flight := 0
var _kept_viewports: Array[SubViewport] = []
var _perf_process_usec := 0.0
var _perf_frames := 0
var _perf_jobs_started := 0
var paused := false
var _next_start_msec := 0


class _Baker extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	instance = self


## Queue a bake. `paint.call(canvas)` draws the art; `offset` shifts it into the
## viewport (usually -bounds.position); `on_done.call(texture)` receives the
## viewport texture. `guard` and `paint` should be BOUND method Callables on the
## requesting object so their is_valid() goes false when it is freed; then we skip
## cleanly and call `on_skip`.
func enqueue(size: Vector2i, offset: Vector2, paint: Callable, on_done: Callable,
		guard: Callable, on_skip := Callable()) -> void:
	_queue.append([size, offset, paint, on_done, guard, on_skip])


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	var jobs := 0
	var now := Time.get_ticks_msec()
	if not paused and now >= _next_start_msec and _in_flight < MAX_IN_FLIGHT and not _queue.is_empty():
		_run(_queue.pop_front())
		jobs += 1
		_next_start_msec = now + START_INTERVAL_MSEC
	_perf_process_usec += float(Time.get_ticks_usec() - started)
	_perf_frames += 1
	_perf_jobs_started += jobs


func consume_perf_timings() -> Dictionary:
	var n := maxi(1, _perf_frames)
	var out := {
		"total": int(_perf_process_usec / float(n)),
		"jobs": _perf_jobs_started,
		"queue": _queue.size(),
		"in_flight": _in_flight,
		"kept": _kept_viewports.size(),
	}
	_perf_process_usec = 0.0
	_perf_frames = 0
	_perf_jobs_started = 0
	return out


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
		var on_done: Callable = job[3]
		if on_done.is_valid():
			var tex := vp.get_texture()
			on_done.call(tex)
			# ViewportTexture stays valid only while its SubViewport exists. Keep
			# the viewport GPU-resident, disable future updates, and drop the
			# painter so the source entity is not retained by its bound Callable.
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			baker.painter = Callable()
			baker.queue_free()
			_kept_viewports.append(vp)
		else:
			vp.queue_free()
	else:
		var skip1: Callable = job[5]
		if skip1.is_valid():
			skip1.call()
		vp.queue_free()
	_in_flight -= 1
