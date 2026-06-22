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
const CAM_YAW_SPEED := 1.7    # rad/sec — Left/Right orbit (full 360°)
const CAM_PITCH_SPEED := 1.1  # rad/sec — Up/Down tilt
const CAM_PITCH_MIN := 0.16   # absolute floor; the EFFECTIVE min is budget-aware (effective_min_pitch)
const CAM_PITCH_MAX := 1.40   # near top-down (kept off the gimbal pole)
# Camera BUDGET CURVE — zoom and pitch are NOT independent: a low (cinematic) pitch and a far
# zoom-out are competing features the renderer can't afford together (a grazing camera sees far
# more ground). So the minimum allowed pitch is coupled to the live zoom: zoomed IN allows a low
# cinematic angle (small footprint, cheap); zoomed OUT forces a higher, more top-down angle (a
# RuneScape-style overview) so the footprint never outruns the terrain budget. ORTHO span here is
# the real zoom range (size = CAM_SIZE_BASE/zoom, zoom in [0.55..4.5] -> ortho ~4.3..35.5).
const BUDGET_ORTHO_CLOSE := 9.0     # at/below this ortho (zoomed in) the lowest pitch is allowed
const BUDGET_ORTHO_FAR := 30.0      # at/above this ortho (zoomed out) the top-down floor applies
const BUDGET_PITCH_CLOSE := 0.24    # ~14° — cinematic low angle, allowed only when zoomed in
const BUDGET_PITCH_FAR := 0.62      # ~36° — strategic top-down floor when zoomed far out
# Up/Down sweep the camera between two coupled poses, eased smoothly (NOT a linear tilt):
#   hold Up   -> overview  : max zoom-OUT + top-down
#   hold Down -> cinematic : zoom-IN + lowest pitch
# PAN_EASE is the smoothing rate (lower = slower, more gradual glide).
const PAN_EASE := 1.7
const ZOOM_OUT_MAX := 0.55                              # matches WorldInputController.ZOOM_MIN (max zoom-out)
const ZOOM_CINEMATIC := CAM_SIZE_BASE / BUDGET_ORTHO_CLOSE   # zoom-in where the lowest pitch unlocks
# Radians of yaw/pitch per pixel of middle-mouse drag (before the cam_rotate_speed multiplier).
const CAM_DRAG_YAW := 0.006
const CAM_DRAG_PITCH := 0.004
const CAM_FOLLOW_SPEED := 12.0   # eased-follow rate, matches the 2D Camera2D position_smoothing_speed
# Cap how far the projected footprint may reach from the follow target (tiles). A near-horizon
# ray would otherwise shoot to the far plane and blow the terrain budget; budget-aware pitch
# normally keeps the footprint well inside this, but the cap is the hard safety bound.
const MAX_FOOTPRINT_TILES := 224.0   # == TERRAIN_RING_HARD_MAX(14) * CHUNK_TILES(16)
# Coverage auto-zoom: when the view would reach past LOADED terrain (the finite world's edge, or
# an area still streaming in), zoom IN so that unmeshed void never enters the screen instead of
# showing a beige cutoff. Smoothly eased so it reads as the camera tightening, not a snap.
const COVER_ZOOM_MIN := 0.40         # never auto-zoom tighter than this fraction of the desired size
const COVER_ZOOM_LERP := 5.0         # ease rate toward the coverage-limited size
const COVER_SLACK := 0.96            # only zoom in once a corner reaches past 96% of loaded extent

var world: Node2D
var world3d: Node3D
var presenter: RenderViewportPresenter
var cam: Camera3D
var _height: Callable             # height_at_iso(iso: Vector2) -> float
var _coverage_query := Callable() # func(grid: Vector2) -> bool : is terrain DATA loaded at this grid pt

var _cam_yaw := PI / 4.0           # orbit angle around the player (Left/Right arrows)
var _cam_pitch := 0.413            # elevation above horizon (Up/Down arrows); matches old iso
var _cam_follow := Vector2.INF     # smoothed follow target (iso); INF = uninitialised (snap on first use)
var _cover_zoom := 1.0             # smoothed coverage zoom factor [COVER_ZOOM_MIN .. 1]
var editor_cam_target = null       # world editor: Vector2 to pin the camera to (overrides player follow); null = off


func setup(w: Node2D, w3d: Node3D, present: RenderViewportPresenter, height_provider: Callable) -> void:
	world = w
	world3d = w3d
	presenter = present
	_height = height_provider
	_setup_camera()


## Inject the terrain-coverage probe used by the auto-zoom (keeps the rig decoupled from terrain).
func set_coverage_query(cb: Callable) -> void:
	_coverage_query = cb


func _setup_camera() -> void:
	# Orthographic camera at the game's 2:1 isometric angle (yaw 45, pitch ~30).
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.8
	cam.near = 0.05
	cam.far = 400.0
	world3d.add_child(cam)


## Minimum allowed pitch for the CURRENT zoom (the camera budget curve). Driven by the user's
## DESIRED zoom (the 2D camera), not the live coverage-shrunk ortho, so it's a stable input: as
## you zoom out the floor rises toward a top-down overview; as you zoom in it drops to a cinematic
## low angle. This is what makes "far zoom-out + low pitch" an unreachable state — you trade one
## for the other. The view-distance slider tightens it further (less terrain budget -> higher floor).
func effective_min_pitch() -> float:
	var zoom := 1.65
	if world != null and world._camera != null and world._camera.zoom.x > 0.01:
		zoom = world._camera.zoom.x
	var ortho := CAM_SIZE_BASE / zoom
	var f := clampf((ortho - BUDGET_ORTHO_CLOSE) / (BUDGET_ORTHO_FAR - BUDGET_ORTHO_CLOSE), 0.0, 1.0)
	var floor_pitch := lerpf(BUDGET_PITCH_CLOSE, BUDGET_PITCH_FAR, f)
	# Low view distance can afford even less terrain, so lift the whole curve a touch.
	var vd := clampf(GameSettings.view_distance, 0.0, 1.0)
	floor_pitch += lerpf(0.10, 0.0, vd)
	return clampf(floor_pitch, CAM_PITCH_MIN, CAM_PITCH_MAX)


## Arrow keys: Left/Right spin the yaw a full 360°. Up/Down sweep the camera smoothly between a
## top-down OVERVIEW (max zoom-out) and a low CINEMATIC pose (zoomed in) — pitch and zoom are
## eased toward the held pose together, so holding Down pans all the way down (auto zooming in) and
## holding Up pans all the way up (auto zooming out to max). Picking adapts automatically because
## screen_to_iso casts through the live camera.
func update_input(delta: float) -> void:
	var spd: float = GameSettings.cam_rotate_speed   # user-tunable orbit/tilt multiplier
	if Input.is_key_pressed(KEY_LEFT):
		_cam_yaw -= CAM_YAW_SPEED * spd * delta
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_yaw += CAM_YAW_SPEED * spd * delta
	if world != null and world._camera != null:
		var cur_zoom: float = world._camera.zoom.x
		var tgt_zoom := cur_zoom
		var tgt_pitch := _cam_pitch
		if Input.is_key_pressed(KEY_UP):
			tgt_zoom = ZOOM_OUT_MAX        # overview: ease out to max + tilt top-down
			tgt_pitch = CAM_PITCH_MAX
		elif Input.is_key_pressed(KEY_DOWN):
			tgt_zoom = maxf(cur_zoom, ZOOM_CINEMATIC)   # cinematic: ease IN (never pop out) + tilt down
			tgt_pitch = CAM_PITCH_MIN      # the floor clamp below pins pitch to the live budget floor
		# Frame-rate-independent exponential ease toward the held pose (no-op when neither is held).
		var k := 1.0 - exp(-PAN_EASE * spd * delta)
		if not is_equal_approx(tgt_zoom, cur_zoom):
			var nz := lerpf(cur_zoom, tgt_zoom, k)
			world._camera.zoom = Vector2(nz, nz)
		_cam_pitch = lerpf(_cam_pitch, tgt_pitch, k)
	# Clamp to the live budget floor (reflecting the eased zoom) so the world edge can't be exposed;
	# this is also what pins the descending pitch to the floor while Down zooms in.
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
	cam.position = c + dir * CAM_DIST
	cam.look_at(c + Vector3(0, 0.75, 0), Vector3.UP)
	# Coverage auto-zoom: tighten the view so its ground footprint never reaches past loaded
	# terrain (the world edge / a streaming area) — the user sees the camera zoom in instead of a
	# beige cutoff. Computed from the footprint at the DESIRED size (set above) so it's stable.
	var target_cover := _coverage_zoom_target()
	_cover_zoom = lerpf(_cover_zoom, target_cover, clampf(COVER_ZOOM_LERP * delta, 0.0, 1.0))
	cam.size = desired_size * _cover_zoom
	_snap_camera()


## Largest fraction of the desired ortho size that keeps the footprint inside what the renderer
## can show (1.0 = no zoom needed). Two limits, take the tighter: (a) a fixed terrain BUDGET radius
## — the camera budget curve's safety backstop so a wide low-pitch view is pulled in even over
## fully-loaded ground; (b) the actually-LOADED terrain toward each corner (the finite world edge
## or a streaming area). The eased result is the "pan-down/zoom-out gently pulls the camera in".
func _coverage_zoom_target() -> float:
	if editor_cam_target != null:
		return 1.0   # editor pins a fixed survey framing — don't fight its zoom
	var poly := get_ground_footprint_polygon()
	if poly.size() < 4:
		return 1.0
	var target := get_target_grid()
	var budget := _budget_radius_tiles()
	var factor := 1.0
	for corner: Vector2 in poly:
		var off := corner - target
		var reach := off.length()
		if reach < 8.0:
			continue
		# (a) terrain budget: never let the footprint reach past the affordable radius.
		if reach > budget:
			factor = minf(factor, maxf(budget / reach, COVER_ZOOM_MIN))
		# (b) loaded terrain toward this corner (world edge / still streaming).
		if _coverage_query.is_valid():
			var safe := _loaded_reach(target, off / reach, reach)
			if safe < reach * COVER_SLACK:
				factor = minf(factor, maxf(safe / reach, COVER_ZOOM_MIN))
	return factor


## The terrain coverage budget (tiles): how far the renderer comfortably meshes from the target.
## Scales with the view-distance slider; stays under the hard streaming cap so data always covers it.
func _budget_radius_tiles() -> float:
	var vd := clampf(GameSettings.view_distance, 0.0, 1.0)
	return lerpf(96.0, 184.0, vd)


## How far loaded terrain DATA extends from `target` along `dir`, up to `max_reach` tiles (stops
## at the first unloaded sample — the world edge or a not-yet-streamed area).
func _loaded_reach(target: Vector2, dir: Vector2, max_reach: float) -> float:
	var step := float(WG.CHUNK_TILES) * 0.5
	var last := 0.0
	var d := step
	while d <= max_reach + step:
		if _coverage_query.call(target + dir * minf(d, max_reach)):
			last = minf(d, max_reach)
			d += step
		else:
			break
	return last


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


## Current coverage auto-zoom factor (1.0 = none; < 1 = tightened to hide unloaded terrain).
func get_cover_zoom() -> float:
	return _cover_zoom


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
		g = Vector2(o.x / TILE_S, o.z / TILE_S) + horiz.normalized() * MAX_FOOTPRINT_TILES
	# Safety bound: never let a corner exceed the visual budget radius from the target.
	var off := g - center
	if off.length() > MAX_FOOTPRINT_TILES:
		g = center + off.normalized() * MAX_FOOTPRINT_TILES
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
