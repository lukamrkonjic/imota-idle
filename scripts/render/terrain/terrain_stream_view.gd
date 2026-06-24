extends RefCounted
class_name TerrainStreamView
## Decides which chunks are VISUALLY needed by the camera, decoupled from the player-centred
## gameplay streaming. The visual coverage is camera-FOOTPRINT-shaped (an asymmetric ground
## parallelogram at low pitch), NOT a player-centred circle — that circle was the root cause of
## the beige fog/cutoff band at the bottom of the screen.
##
## Each frame it asks the camera rig for the footprint chunk sets, clamps them to a budget, and
## applies hysteresis (a short grace window) so orbiting/tilting never flickers chunks in and out.
## It builds NO meshes; the TerrainMeshManager reads keep_chunks()/is_chunk_kept() and builds.

const WG := preload("res://scripts/worldgen/wg.gd")

const VISUAL_MARGIN_CHUNKS := 2
const VISUAL_UNLOAD_GRACE_MS := 2000
const MAX_VISUAL_CHUNKS := 420   # budget cap on the kept visual set (tune)
# The streamed DATA ring (chunks) the world feeds; the visual coverage lives inside it.
const TERRAIN_RING_MIN := 3
const TERRAIN_RING_MAX := 10           # slider's max FLOOR (~160 tiles)
const TERRAIN_RING_HARD_MAX := 14      # absolute cap incl. zoom-out coverage (~224 tiles)

var world: Node2D

var visual_visible_chunks: Dictionary = {}   # key -> true: inside the current camera footprint
var visual_margin_chunks: Dictionary = {}    # key -> true: footprint grown by VISUAL_MARGIN_CHUNKS
var visual_keep_chunks: Dictionary = {}      # key -> true: margin + hysteresis-retained
var chunk_last_needed_ms: Dictionary = {}    # key -> last ms it was visible/margin (grace clock)

var _player_chunk := Vector2i.ZERO
var _data_ring := TERRAIN_RING_MIN
var editor_radius_cap := 0      # world editor: raise the visual hard cap (chunks); 0 = gameplay default


func setup(w: Node2D) -> void:
	world = w


func update(camera_rig: WorldCameraRig3D) -> void:
	var now := Time.get_ticks_msec()
	_player_chunk = WG.world_to_chunk(world.player.position)
	visual_visible_chunks = camera_rig.get_ground_footprint_chunk_set(0)
	visual_margin_chunks = camera_rig.get_ground_footprint_chunk_set(VISUAL_MARGIN_CHUNKS)
	# Budget: if a wide zoom-out blows the cap, drop the margin chunks farthest from the camera
	# target first (never the directly-visible footprint chunks).
	if visual_margin_chunks.size() > _visual_budget():
		_clamp_to_budget(camera_rig.get_target_grid())
	# Mark everything needed this frame, then keep = anything needed within the grace window.
	for key: String in visual_margin_chunks:
		chunk_last_needed_ms[key] = now
	for key: String in visual_visible_chunks:
		chunk_last_needed_ms[key] = now
	visual_keep_chunks = {}
	for key: String in chunk_last_needed_ms.keys():
		if now - int(chunk_last_needed_ms[key]) <= VISUAL_UNLOAD_GRACE_MS:
			visual_keep_chunks[key] = true
		else:
			chunk_last_needed_ms.erase(key)   # bound memory: drop expired grace clocks
	_data_ring = _compute_data_ring()


## Drop margin-only chunks (never directly-visible ones) farthest from the camera target until
## the kept set is back within MAX_VISUAL_CHUNKS.
func _clamp_to_budget(target_grid: Vector2) -> void:
	var ranked: Array = []
	for key: String in visual_margin_chunks.keys():
		if visual_visible_chunks.has(key):
			continue   # never trim a directly-visible chunk
		ranked.append([_chunk_center_dist2(key, target_grid), key])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])   # farthest first
	var over := visual_margin_chunks.size() - _visual_budget()
	for i: int in mini(over, ranked.size()):
		visual_margin_chunks.erase(ranked[i][1])


## Kept-chunk budget. Gameplay uses MAX_VISUAL_CHUNKS; the editor raises it to cover its larger
## footprint (so a far-zoom aerial view isn't trimmed back to a jagged ring).
func _visual_budget() -> int:
	if editor_radius_cap > 0:
		var span := editor_radius_cap * 2 + 1
		return maxi(MAX_VISUAL_CHUNKS, span * span)
	return MAX_VISUAL_CHUNKS


func _chunk_center_dist2(key: String, target_grid: Vector2) -> float:
	var parts := key.split(":")
	if parts.size() < 3:
		return 0.0
	var ct := WG.CHUNK_TILES
	var c := Vector2(float(int(parts[1]) * ct + ct / 2), float(int(parts[2]) * ct + ct / 2))
	return c.distance_squared_to(target_grid)


## DATA ring (chunks) that must be streamed so the visual coverage has loaded data + a neighbour
## margin for seamless meshing. Derived from how far the margin set actually reaches from the
## player (camera-footprint aware), floored by the view-distance slider, capped for perf.
func _compute_data_ring() -> int:
	var reach := 0
	for key: String in visual_margin_chunks.keys():
		var parts := key.split(":")
		if parts.size() < 3:
			continue
		var d := maxi(absi(int(parts[1]) - _player_chunk.x), absi(int(parts[2]) - _player_chunk.y))
		reach = maxi(reach, d)
	# The world editor raises the visual hard cap so the aerial view meshes all the way out to the
	# loaded data edge (no cut-off band) — gameplay keeps the perf-tuned TERRAIN_RING_HARD_MAX.
	var hard := editor_radius_cap if editor_radius_cap > 0 else TERRAIN_RING_HARD_MAX
	return clampi(maxi(required_visual_radius_floor(), reach + 1), TERRAIN_RING_MIN, hard)


# ---------------------------------------------------------------------- queries ----

func visible_chunks() -> Dictionary:
	return visual_visible_chunks


func margin_chunks() -> Dictionary:
	return visual_margin_chunks


func keep_chunks() -> Dictionary:
	return visual_keep_chunks


func is_chunk_visible(key: String) -> bool:
	return visual_visible_chunks.has(key)


func is_chunk_kept(key: String) -> bool:
	return visual_keep_chunks.has(key)


## Build priority: 0 footprint, 1 margin, 2 near the player active area, 3 hysteresis-only.
func priority_for_chunk(key: String) -> int:
	if visual_visible_chunks.has(key):
		return 0
	if visual_margin_chunks.has(key):
		return 1
	var parts := key.split(":")
	if parts.size() >= 3:
		var d := maxi(absi(int(parts[1]) - _player_chunk.x), absi(int(parts[2]) - _player_chunk.y))
		if d <= WG.ACTIVE_RADIUS:
			return 2
	return 3


## Slider-driven minimum visual radius (chunks): the floor the live footprint ring grows above.
func required_visual_radius_floor() -> int:
	return int(round(lerpf(float(TERRAIN_RING_MIN), float(TERRAIN_RING_MAX),
		clampf(GameSettings.view_distance, 0.0, 1.0))))


## The data/visual extent in TILES (== world units, TILE_S = 1): how far the loaded+meshed
## terrain reaches. The atmosphere pushes the fog ramp out relative to this.
func approx_visual_extent_tiles() -> float:
	return float(_data_ring * WG.CHUNK_TILES)


## DATA streaming ring (chunks) the coordinator exposes as terrain_ring for world.gd.
func terrain_data_ring() -> int:
	return _data_ring
