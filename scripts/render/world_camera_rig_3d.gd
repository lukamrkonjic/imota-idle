extends RefCounted
class_name WorldCameraRig3D
## The orthographic iso Camera3D and everything that drives it (extracted from the
## WorldRender3D monolith): eased player/editor follow, arrow-key + middle-mouse orbit,
## zoom mirrored from the 2D Camera2D, and the pixel-snapped render transform + sub-pixel
## residual ("Stable Pixel Motion"). Also answers camera-geometry queries — the projected
## GROUND FOOTPRINT (in grid/tile coords) the visual terrain coverage is built from.

const WG := preload("res://scripts/worldgen/wg.gd")

const TILE_S := 1.0

const CAM_SIZE_BASE := 19.5   # ortho size at the default 1.65 zoom
const CAM_DIST := 31.0
const AIM_HEIGHT := 0.75
const SCREEN_GROUND_CLEARANCE := 0.35
const CAM_YAW_SPEED := 1.7    # rad/sec — Left/Right orbit (full 360°)
const CAM_PITCH_SPEED := 1.1  # rad/sec — Up/Down tilt
const CAM_PITCH_MIN := 0.16   # the low (forward/grazing) floor; effective_min_pitch returns this (+ a small view-distance lift)
const CAM_PITCH_MAX := 1.05   # ~60° — tilted-down overview (lowered from near-top-down to see more forward)
# Pitch is INDEPENDENT of zoom (see effective_min_pitch): zooming out keeps the current angle
# instead of forcing the camera top-down. Streaming covers the larger ground footprint without
# changing the player's chosen framing.
# PAN_EASE is the smoothing rate for pitch changes.
const PAN_EASE := 1.7
# Radians of yaw/pitch per pixel of middle-mouse drag (before the cam_rotate_speed multiplier).
const CAM_DRAG_YAW := 0.006
const CAM_DRAG_PITCH := 0.004
const CAM_FOLLOW_SPEED := 12.0   # eased-follow rate, matches the 2D Camera2D position_smoothing_speed
# Cap how far the projected footprint may reach from the follow target (tiles). A near-horizon
# ray would otherwise shoot to the far plane and blow the terrain budget; budget-aware pitch
# normally keeps the footprint well inside this, but the cap is the hard safety bound.
const MAX_FOOTPRINT_TILES := 224.0   # == TERRAIN_RING_HARD_MAX(14) * CHUNK_TILES(16)

var world: Node2D
var world3d: Node3D
var presenter: RenderViewportPresenter
var cam: Camera3D
var _height: Callable             # height_at_iso(iso: Vector2) -> float

var _cam_yaw := PI / 4.0           # orbit angle around the player (Left/Right arrows)
var _cam_pitch := 0.413            # elevation above horizon (Up/Down arrows); matches old iso
var _cam_follow := Vector2.INF     # smoothed follow target (iso); INF = uninitialised (snap on first use)
var editor_cam_target = null       # world editor: Vector2 to pin the camera to (overrides player follow); null = off
var editor_footprint_chunks := 0   # world editor: raise the footprint reach (chunks) so a far zoom fills the view; 0 = gameplay cap


## How far (tiles) the projected footprint may reach from the target. Gameplay uses the perf-safe
## MAX_FOOTPRINT_TILES; the editor raises it from its View slider so the aerial view fills the screen.
func _footprint_cap() -> float:
	return float(editor_footprint_chunks * WG.CHUNK_TILES) if editor_footprint_chunks > 0 else MAX_FOOTPRINT_TILES


func setup(w: Node2D, w3d: Node3D, present: RenderViewportPresenter, height_provider: Callable) -> void:
	world = w
	world3d = w3d
	presenter = present
	_height = height_provider
	_setup_camera()


func _setup_camera() -> void:
	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.8
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)


## Minimum allowed pitch. It is deliberately independent from zoom: streaming and the fallback
## cover the larger footprint instead of altering the player's chosen framing.
func effective_min_pitch() -> float:
	var vd := clampf(GameSettings.view_distance, 0.0, 1.0)
	return clampf(CAM_PITCH_MIN + lerpf(0.10, 0.0, vd), CAM_PITCH_MIN, CAM_PITCH_MAX)


## Keep the entire orthographic image plane above terrain at grazing pitch. Moving backward along
## the view ray preserves framing, but makes every screen ray hit ground in front of the camera.
func _safe_camera_distance(ortho_size: float) -> float:
	var rise := maxf(sin(_cam_pitch), 0.01)
	var bottom_screen_drop := ortho_size * 0.5 * cos(_cam_pitch)
	var needed := (bottom_screen_drop + SCREEN_GROUND_CLEARANCE - AIM_HEIGHT) / rise
	return maxf(CAM_DIST, needed)


## Arrow keys: Left/Right spin yaw a full 360°. Up/Down ease only pitch; wheel zoom stays
## independent. Picking adapts automatically because screen_to_iso casts through the live camera.
func update_input(delta: float) -> void:
	var spd: float = GameSettings.cam_rotate_speed   # user-tunable orbit/tilt multiplier
	if Input.is_key_pressed(KEY_LEFT):
		_cam_yaw -= CAM_YAW_SPEED * spd * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_yaw += CAM_YAW_SPEED * spd * delta
	if world != null and world._camera != null:
		var tgt_pitch := _cam_pitch
		if Input.is_key_pressed(KEY_UP):
			# Tilt only. Mouse wheel owns zoom.
			tgt_pitch = CAM_PITCH_MAX
		elif Input.is_key_pressed(KEY_DOWN):
			# A low forward-looking angle is a valid persistent camera pose.
			tgt_pitch = CAM_PITCH_MIN
		# Frame-rate-independent exponential ease toward the held pose (no-op when neither is held).
		var k := 1.0 - exp(-PAN_EASE * spd * delta)
		_cam_pitch = lerpf(_cam_pitch, tgt_pitch, k)
	# Keep pitch within the supported low-forward to overview range without altering zoom.
	_cam_pitch = clampf(_cam_pitch, effective_min_pitch(), CAM_PITCH_MAX)
	_cam_yaw = wrapf(_cam_yaw, -PI, PI)


## Middle-mouse drag orbit: rotate the camera by a screen-pixel mouse delta. Drag
## moves the world WITH the cursor (grab-and-drag feel) on both axes.
func orbit_drag(rel: Vector2) -> void:
	var spd: float = GameSettings.cam_rotate_speed
	_cam_yaw = wrapf(_cam_yaw - rel.x * CAM_DRAG_YAW * spd, -PI, PI)
	_cam_pitch = clampf(_cam_pitch + rel.y * CAM_DRAG_PITCH * spd, effective_min_pitch(), CAM_PITCH_MAX)


func sync_camera(delta: float) -> void:
	# Eased follow (the "snappier follow-cam" from main): the 2D Camera2D uses
	# position_smoothing, but the 3D render camera is what's visible here, so replicate it.
	# The world editor pins the camera to a fixed authoring point so the live (and possibly
	# wandering/fighting) player never drifts the view. null = follow the player.
	var follow: Vector2 = editor_cam_target if editor_cam_target != null else world.player.position
	if _cam_follow == Vector2.INF:
		_cam_follow = follow   # first frame / teleport: snap, don't ease across the world
	elif _cam_follow.distance_to(follow) > 600.0:
		_cam_follow = follow   # big jump (teleport) — snap, never ease across a long gap
	else:
		_cam_follow = _cam_follow.lerp(follow, clampf(CAM_FOLLOW_SPEED * delta, 0.0, 1.0))
	var c := _iso_to_3d(_cam_follow, _height.call(_cam_follow))
	# Mouse-wheel zoom still drives the 2D camera (the logic substrate); mirror it
	# to the 3D ortho size so zoom works like before.
	var zoom: float = float(world._camera.zoom.x) if world._camera != null and world._camera.zoom.x > 0.01 else 1.65
	var desired_size := CAM_SIZE_BASE / zoom
	cam.size = desired_size
	# Orbit direction from the arrow-key yaw/pitch (default = the original iso angle). The camera
	# always looks straight at the player so the player stays centred at every tilt/zoom.
	var dir := Vector3(cos(_cam_pitch) * sin(_cam_yaw), sin(_cam_pitch), cos(_cam_pitch) * cos(_cam_yaw))
	# Pulling an orthographic camera along its view ray preserves the image. It lets the low edge of
	# a grazing view remain above ground and gives wide editor framing enough clip range.
	var cam_dist := _safe_camera_distance(desired_size)
	var reach := _footprint_cap()
	cam.far = maxf(400.0, cam_dist + reach * 2.0)
	if editor_footprint_chunks > 0:
		# Pull back ≥ the view's ground reach so the foreground never falls behind the near plane at
		# any pitch (the ground's depth half-extent is ≤ reach/2), and deepen far past the distance.
		cam_dist = maxf(cam_dist, reach * 1.5)
		cam.far = maxf(400.0, cam_dist + reach * 2.0)
	var aim := c + Vector3(0, AIM_HEIGHT, 0)
	cam.position = aim + dir * cam_dist
	cam.look_at(aim, Vector3.UP)
	cam.size = desired_size
	_snap_camera()


## Pixel-snapped RENDER camera + sub-pixel residual offset ("Stable Pixel Motion").
## SNAP the render camera's screen-plane translation to the internal pixel grid so edges land
## on the SAME internal texels frame to frame (no crawl); then slide the presented image by the
## residual we snapped away (rounded to whole display pixels) so apparent motion stays smooth.
func _snap_camera() -> void:
	var sub := presenter.get_subviewport()
	if sub == null or sub.size.y <= 0:
		return
	var wupp := cam.size / float(sub.size.y)   # world units per internal pixel (KEEP_HEIGHT)
	if wupp <= 0.0:
		return
	var b := cam.global_transform.basis
	var right := b.x   # camera screen-right (orthonormal)
	var up := b.y      # camera screen-up
	var fwd := -b.z    # camera forward (depth) — left unsnapped
	var logical := cam.position
	var r: float = round(logical.dot(right) / wupp) * wupp
	var u: float = round(logical.dot(up) / wupp) * wupp
	var f: float = logical.dot(fwd)
	cam.position = right * r + up * u + fwd * f   # snapped render position
	# Residual we snapped away (< half a pixel along each screen axis), as a fraction of an
	# internal pixel. Re-add it by sliding the presented image — content moves OPPOSITE to a
	# rightward camera nudge, and screen-Y is inverted vs camera-up. Rounded to whole display px.
	var scale := presenter.get_present_scale()
	var res_right := (logical.dot(right) - r) / wupp   # internal px, [-0.5, 0.5]
	var res_up := (logical.dot(up) - u) / wupp
	var shift := Vector2(round(-res_right * scale), round(res_up * scale))
	presenter.apply_residual_shift(shift)


# ---------------------------------------------------------------- camera queries ----

func get_camera() -> Camera3D:
	return cam


func get_yaw() -> float:
	return _cam_yaw


func get_pitch() -> float:
	return _cam_pitch


func set_pitch(v: float) -> void:
	_cam_pitch = clampf(v, CAM_PITCH_MIN, CAM_PITCH_MAX)


func get_target_iso() -> Vector2:
	return _cam_follow if _cam_follow != Vector2.INF else world.player.position


func get_target_grid() -> Vector2:
	return WG.iso_to_grid(get_target_iso())


func get_ortho_size() -> float:
	return cam.size if cam != null else 0.0


## Compatibility/debug value. The hybrid renderer never changes player zoom for terrain coverage.
func get_cover_zoom() -> float:
	return 1.0


## Camera forward direction projected onto the ground, in grid (x,z) coords, normalised.
func get_camera_forward_ground() -> Vector2:
	if cam == null:
		return Vector2.DOWN
	var f := -cam.global_transform.basis.z
	var g := Vector2(f.x, f.z)
	return g.normalized() if g.length() > 0.0001 else Vector2.DOWN


## Camera screen-right direction projected onto the ground, in grid (x,z) coords, normalised.
func get_camera_right_ground() -> Vector2:
	if cam == null:
		return Vector2.RIGHT
	var r := cam.global_transform.basis.x
	var g := Vector2(r.x, r.z)
	return g.normalized() if g.length() > 0.0001 else Vector2.RIGHT


# ------------------------------------------------------------- ground footprint ----

## The camera's projected ground footprint as a convex polygon in GRID/TILE coords (NOT iso
## pixels). For an ortho camera the four viewport corners project to a parallelogram on the
## ground plane; at low pitch the far edge is capped to MAX_FOOTPRINT_TILES from the target so
## a near-horizon ray can't blow the terrain budget (budget-aware pitch normally avoids this).
func get_ground_footprint_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	if cam == null or presenter == null:
		return result
	var sub := presenter.get_subviewport()
	if sub == null or sub.size.y <= 0:
		return result
	var vp := Vector2(sub.size)
	var center := get_target_grid()
	var py: float = _height.call(get_target_iso())
	for px: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0.0), vp, Vector2(0.0, vp.y)]:
		var o := cam.project_ray_origin(px)
		var d := cam.project_ray_normal(px)
		result.append(_ray_ground_grid(o, d, py, center))
	return result


## Intersect a camera ray with the ground plane (y = py) and return a GRID-coord point. The
## ortho camera looks AT the target from above, so within our pitch range every ray points down
## (d.y < 0) and the plane hit is always valid — we use the FULL ray parameter so the footprint
## stays centred on the target. Only the RESULTING point is clamped to the visual budget radius;
## clamping the ray parameter instead (the old bug) stopped grazing rays in mid-air and shifted
## the whole footprint off the player at low pitch, leaving the on-screen ground unmeshed.
func _ray_ground_grid(o: Vector3, d: Vector3, py: float, center: Vector2) -> Vector2:
	var g: Vector2
	if d.y < -0.0001:
		var t := (py - o.y) / d.y   # > 0 for a downward ray starting above the plane
		var hit := o + d * t
		g = Vector2(hit.x / TILE_S, hit.z / TILE_S)
	else:
		# Pathological (ray at/above the horizon — outside our pitch clamp): aim the corner far
		# along the ray's horizontal heading so coverage still reaches toward the horizon.
		var horiz := Vector2(d.x, d.z)
		if horiz.length() < 0.0001:
			return center
		g = Vector2(o.x / TILE_S, o.z / TILE_S) + horiz.normalized() * _footprint_cap()
	# Safety bound: never let a corner exceed the visual budget radius from the target.
	var cap := _footprint_cap()
	var off := g - center
	if off.length() > cap:
		g = center + off.normalized() * cap
	return g


## Chunk bounding box (chunk coords) of the footprint, grown by margin_chunks.
func get_ground_footprint_chunk_rect(margin_chunks: int) -> Rect2i:
	var poly := get_ground_footprint_polygon()
	var ct := float(WG.CHUNK_TILES)
	if poly.size() < 3:
		var c := WG.world_to_chunk(get_target_iso())
		return Rect2i(c.x - margin_chunks, c.y - margin_chunks, 2 * margin_chunks + 1, 2 * margin_chunks + 1)
	var min_g := poly[0]
	var max_g := poly[0]
	for p: Vector2 in poly:
		min_g = min_g.min(p)
		max_g = max_g.max(p)
	var cx0 := floori(min_g.x / ct) - margin_chunks
	var cy0 := floori(min_g.y / ct) - margin_chunks
	var cx1 := floori((max_g.x - 0.0001) / ct) + margin_chunks
	var cy1 := floori((max_g.y - 0.0001) / ct) + margin_chunks
	return Rect2i(cx0, cy0, cx1 - cx0 + 1, cy1 - cy0 + 1)


## Every chunk (keyed by WG.key for the current layer) whose tile-rect intersects the camera
## footprint, grown by a Chebyshev margin of margin_chunks. This is the visual-coverage set —
## camera-footprint-shaped, NOT a player-centred circle (the fog/cutoff fix).
func get_ground_footprint_chunk_set(margin_chunks: int) -> Dictionary:
	var out := {}
	var poly := get_ground_footprint_polygon()
	if poly.size() < 3:
		return out
	var layer: int = world.current_layer
	var ct := float(WG.CHUNK_TILES)
	var min_g := poly[0]
	var max_g := poly[0]
	for p: Vector2 in poly:
		min_g = min_g.min(p)
		max_g = max_g.max(p)
	var cx0 := floori(min_g.x / ct)
	var cy0 := floori(min_g.y / ct)
	var cx1 := floori((max_g.x - 0.0001) / ct)
	var cy1 := floori((max_g.y - 0.0001) / ct)
	for cy: int in range(cy0, cy1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			if not _rect_hits_quad(float(cx) * ct, float(cy) * ct, float(cx + 1) * ct, float(cy + 1) * ct, poly):
				continue
			if margin_chunks <= 0:
				out[WG.key(layer, cx, cy)] = true
			else:
				for dy: int in range(-margin_chunks, margin_chunks + 1):
					for dx: int in range(-margin_chunks, margin_chunks + 1):
						out[WG.key(layer, cx + dx, cy + dy)] = true
	return out


# Separating-Axis test: does an axis-aligned tile-rect intersect the (convex) footprint quad?
# Using the rect's edges + the quad's edge normals as separating axes. Robust where a chunk is
# crossed by the footprint without any corner of either shape lying inside the other.
func _rect_hits_quad(x0: float, y0: float, x1: float, y1: float, quad: PackedVector2Array) -> bool:
	var rc := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	if not _overlap_on_axis(Vector2(1, 0), rc, quad):
		return false
	if not _overlap_on_axis(Vector2(0, 1), rc, quad):
		return false
	var n := quad.size()
	for i: int in n:
		var a := quad[i]
		var b := quad[(i + 1) % n]
		var edge := b - a
		var axis := Vector2(-edge.y, edge.x)
		if axis.length_squared() < 1.0e-9:
			continue
		if not _overlap_on_axis(axis, rc, quad):
			return false
	return true


func _overlap_on_axis(axis: Vector2, a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var amin := INF
	var amax := -INF
	for p: Vector2 in a:
		var d := axis.dot(p)
		amin = minf(amin, d)
		amax = maxf(amax, d)
	var bmin := INF
	var bmax := -INF
	for p: Vector2 in b:
		var d := axis.dot(p)
		bmin = minf(bmin, d)
		bmax = maxf(bmax, d)
	return not (amax < bmin or bmax < amin)


func _iso_to_3d(pos: Vector2, y: float) -> Vector3:
	var g := WG.iso_to_grid(pos)
	return Vector3(g.x * TILE_S, y, g.y * TILE_S)
