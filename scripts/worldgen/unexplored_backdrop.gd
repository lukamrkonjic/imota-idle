extends Node2D
## Low-detail deterministic terrain shown behind generated chunks.
##
## This is not a real chunk and it does not spawn entities. It is a soft
## "world continues over there" wash that hides the engine clear colour when
## the camera sees beyond loaded chunks. Real explored chunks are still drawn
## on top by ChunkRenderer.

const WG := preload("res://scripts/worldgen/wg.gd")
const ChunkRenderer := preload("res://scripts/worldgen/chunk_renderer.gd")

const SAMPLE_STEP := WG.TILE * 1.5
const PAD := WG.CHUNK_SIZE

var camera: Camera2D
var tint := Color(0.22, 0.27, 0.23)
var fade_alpha := 0.34
var _last_center := Vector2.INF
var _last_zoom := 0.0


func _ready() -> void:
	z_index = -1000


func _process(_delta: float) -> void:
	if camera == null:
		return
	var center := camera.global_position
	var zoom := camera.zoom.x
	if center.distance_squared_to(_last_center) > 24.0 * 24.0 or absf(zoom - _last_zoom) > 0.02:
		_last_center = center
		_last_zoom = zoom
		queue_redraw()


func _draw() -> void:
	if camera == null or WorldGen.reg == null:
		return
	var vp := get_viewport_rect().size / maxf(camera.zoom.x, 0.001)
	var start := camera.global_position - vp * 0.5 - Vector2(PAD, PAD)
	var end := camera.global_position + vp * 0.5 + Vector2(PAD, PAD)
	var x0 := floorf(start.x / SAMPLE_STEP) * SAMPLE_STEP
	var y0 := floorf(start.y / SAMPLE_STEP) * SAMPLE_STEP
	var x := x0
	while x < end.x:
		var y := y0
		while y < end.y:
			var tx := floori((x + SAMPLE_STEP * 0.5) / WG.TILE)
			var ty := floori((y + SAMPLE_STEP * 0.5) / WG.TILE)
			var f: Vector3 = WorldGen.generator.classifier.fields(float(tx), float(ty))
			var b: int = WorldGen.generator.classifier.biome_idx_jittered(float(tx), float(ty), 0.9)
			var tile_id: int = WorldGen.generator.classifier.tile_at(float(tx), float(ty), f, b)
			var col := ChunkRenderer.tile_color(WorldGen.reg, tile_id)
			var biome: Dictionary = WorldGen.reg.biomes[b]
			var is_ocean := str(biome.get("id", "")) == "ocean"
			col = col.lerp(Color(0.22, 0.27, 0.23) if not is_ocean else Color(0.18, 0.20, 0.28), 0.72)
			col.a = fade_alpha
			draw_rect(Rect2(Vector2(x, y), Vector2(SAMPLE_STEP + 1.0, SAMPLE_STEP + 1.0)), col)
			y += SAMPLE_STEP
		x += SAMPLE_STEP
