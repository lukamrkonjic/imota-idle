extends Node2D
## Low-detail deterministic terrain shown behind generated chunks.
##
## This is not a real chunk and it does not spawn entities. It is a soft
## "world continues over there" wash that hides the engine clear colour when
## the camera sees beyond loaded chunks. Real explored chunks are still drawn
## on top by ChunkRenderer.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

const SAMPLE_STEP := WG.TILE * 4.0
const PAD := WG.TILE * 6.0
const REDRAW_INTERVAL := 0.55
const MOVE_THRESHOLD := WG.CHUNK_SIZE * WG.CHUNK_SIZE * 0.9

var camera: Camera2D
var fade_alpha := 0.34
var _last_center := Vector2.INF
var _last_zoom := 0.0
var _redraw_cooldown := 0.0


func _ready() -> void:
	z_index = -1000


func _process(delta: float) -> void:
	if camera == null:
		return
	_redraw_cooldown = maxf(_redraw_cooldown - delta, 0.0)
	var center := camera.global_position
	var zoom := camera.zoom.x
	var moved := center.distance_squared_to(_last_center) > MOVE_THRESHOLD
	var zoom_changed := absf(zoom - _last_zoom) > 0.12
	if (moved or zoom_changed) and _redraw_cooldown <= 0.0:
		_last_center = center
		_last_zoom = zoom
		_redraw_cooldown = REDRAW_INTERVAL
		queue_redraw()


func _draw() -> void:
	if camera == null or WorldGen.reg == null or WorldGen.generator == null:
		return
	var map_gen = WorldGen.generator.classifier.map_gen
	var vp := get_viewport_rect().size / maxf(camera.zoom.x, 0.001)
	var start := camera.global_position - vp * 0.5 - Vector2(PAD, PAD)
	var end := camera.global_position + vp * 0.5 + Vector2(PAD, PAD)
	var x0 := floorf(start.x / SAMPLE_STEP) * SAMPLE_STEP
	var y0 := floorf(start.y / SAMPLE_STEP) * SAMPLE_STEP
	var x := x0
	while x < end.x:
		var y := y0
		while y < end.y:
			var tile := WG.world_to_tile(Vector2(x, y))
			var parent_idx: int = map_gen.parent_idx_at(float(tile.x), float(tile.y))
			if parent_idx < 0 or parent_idx >= WorldGen.reg.biomes.size():
				y += SAMPLE_STEP
				continue
			var biome: Dictionary = WorldGen.reg.biomes[parent_idx]
			var weights: Array = biome.get("_tile_weights", [[0, 1.0]])
			var tile_id: int = int(weights[0][0])
			var col := ChunkRenderer.tile_color(WorldGen.reg, tile_id)
			var is_ocean := str(biome.get("id", "")) == "ocean"
			col = col.lerp(Color(0.22, 0.27, 0.23) if not is_ocean else Color(0.18, 0.20, 0.28), 0.72)
			col.a = fade_alpha
			var hw := WG.ISO_HW * 0.45
			var hh := WG.ISO_HH * 0.45
			var center := WG.tile_to_world(tile.x, tile.y)
			var pts := PackedVector2Array([
				Vector2(center.x, center.y - hh),
				Vector2(center.x + hw, center.y),
				Vector2(center.x, center.y + hh),
				Vector2(center.x - hw, center.y),
			])
			draw_colored_polygon(pts, col)
			y += SAMPLE_STEP
		x += SAMPLE_STEP
