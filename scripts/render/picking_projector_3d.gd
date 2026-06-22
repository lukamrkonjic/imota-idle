extends RefCounted
class_name PickingProjector3D
## Screen<->world projection through the LIVE 3D camera (extracted from the WorldRender3D
## monolith). The 2D substrate still owns movement/picking targets, but its Camera2D no longer
## matches what's on screen (the 3D camera does), so clicks must be projected through THIS camera
## and entity bodies unprojected back to window pixels. Stays aligned with the presented
## SubViewport image via the presenter's integer-scale + offset mapping.

const WG := preload("res://scripts/worldgen/wg.gd")
const TILE_S := 1.0
const _TERR_MAX_Y := 14.0   # generous ceiling above the tallest summit (ELEV_MAX*ELEV_H + relief)
const _TERR_MIN_Y := -3.0   # below the deepest water basin

var world: Node2D
var camera_rig: WorldCameraRig3D
var presenter: RenderViewportPresenter
var _height_iso: Callable    # height_at(iso: Vector2) -> float
var _height_grid: Callable   # height_at_grid(gx, gy) -> float
var _iso_to_3d: Callable     # iso_to_3d(iso: Vector2, y: float) -> Vector3


func setup(w: Node2D, rig: WorldCameraRig3D, present: RenderViewportPresenter, height_provider: Callable, height_grid_provider: Callable, iso_to_3d_provider: Callable) -> void:
	world = w
	camera_rig = rig
	presenter = present
	_height_iso = height_provider
	_height_grid = height_grid_provider
	_iso_to_3d = iso_to_3d_provider


## Map a screen pixel to the 2D iso world position it visually points at, by casting through the
## 3D camera onto the terrain.
func screen_to_iso(screen: Vector2) -> Vector2:
	var win: Vector2 = world.get_viewport().get_visible_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return world.get_global_mouse_position()
	var cam := camera_rig.get_camera()
	# Window pixel -> SubViewport pixel (invert the presenter's integer scale + centred offset).
	var sub_px := presenter.window_to_subviewport_px(screen)
	var origin := cam.project_ray_origin(sub_px)
	var dir := cam.project_ray_normal(sub_px)
	var hit := ray_to_ground(origin, dir)
	# 3D (x,z) -> grid -> iso world position (inverse of iso_to_3d / WG.tile_to_world).
	return WG.grid_to_iso(Vector2(hit.x / TILE_S, hit.z / TILE_S))


## Inverse of screen_to_iso: where an entity at iso position `pos` (lifted `lift` world units
## above the terrain) lands on screen, in window pixels.
func iso_to_screen(pos: Vector2, lift := 0.0) -> Vector2:
	var p3: Vector3 = _iso_to_3d.call(pos, float(_height_iso.call(pos)) + lift)
	var sub_px: Vector2 = camera_rig.get_camera().unproject_position(p3)
	return presenter.subviewport_to_window_px(sub_px)


## Window pixels per world unit (orthographic, vertical) — turns a world-space pick radius into
## a screen-space one so tolerance is consistent at any zoom.
func world_px_per_unit() -> float:
	var cam := camera_rig.get_camera()
	var sub := presenter.get_subviewport()
	if cam == null or cam.size <= 0.0 or sub == null:
		return 1.0
	# Display px per world unit = (internal px per world unit) * integer present scale.
	return float(sub.size.y) * presenter.get_present_scale() / cam.size


## First (nearest) intersection of a ray with the terrain height field. March forward from where
## the ray enters the terrain's vertical band and stop at the FIRST sample that dips below the
## sampled surface, then bisect — so a click on a tall mountain returns that mountain, not the
## distant low ground the ray would eventually cross.
func ray_to_ground(origin: Vector3, dir: Vector3) -> Vector3:
	if dir.y > -0.00001:
		# Ray parallel or pointing up — fall back to the flat ground plane.
		var tp := (0.0 - origin.y) / dir.y if absf(dir.y) > 0.00001 else 0.0
		return origin + dir * maxf(tp, 0.0)
	# Restrict the march to the slab the terrain occupies (enter at the top, exit at the floor).
	var t_enter: float = maxf((_TERR_MAX_Y - origin.y) / dir.y, 0.0)
	var t_exit: float = (_TERR_MIN_Y - origin.y) / dir.y
	if t_exit <= t_enter:
		var tp2 := (0.0 - origin.y) / dir.y
		return origin + dir * maxf(tp2, 0.0)
	var steps := 96
	var dt := (t_exit - t_enter) / float(steps)
	var prev_t := t_enter
	for i: int in steps + 1:
		var t := t_enter + dt * float(i)
		var p := origin + dir * t
		var h: float = _height_grid.call(p.x / TILE_S, p.z / TILE_S)
		if p.y <= h:
			# Crossed below the surface between prev_t and t — bisect for the precise hit.
			var lo := prev_t
			var hi := t
			for _b: int in 8:
				var mt := (lo + hi) * 0.5
				var mp := origin + dir * mt
				if mp.y <= float(_height_grid.call(mp.x / TILE_S, mp.z / TILE_S)):
					hi = mt
				else:
					lo = mt
			return origin + dir * hi
		prev_t = t
	# Ray passed over all terrain (e.g. pointing at open sky/sea) — flat plane fallback.
	var tp3 := (0.0 - origin.y) / dir.y
	return origin + dir * maxf(tp3, 0.0)
