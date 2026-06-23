extends Node2D
## Debug overlay: parent biome (tinted) + sub-biome borders. Toggle with F6.

const WG := preload("res://scripts/worldgen/wg.gd")

var enabled := false
var show_sub := true

const PARENT_COLORS := {
	"ocean": Color(0.15, 0.22, 0.55, 0.55),
	"beach": Color(0.85, 0.78, 0.45, 0.55),
	"plains": Color(0.45, 0.72, 0.35, 0.50),
	"forest": Color(0.18, 0.52, 0.22, 0.55),
	"swamp": Color(0.22, 0.42, 0.28, 0.55),
	"desert": Color(0.82, 0.68, 0.28, 0.55),
	"tundra": Color(0.78, 0.86, 0.92, 0.55),
	"rocky_hills": Color(0.48, 0.50, 0.54, 0.55),
	"volcanic": Color(0.52, 0.22, 0.16, 0.55),
	"alpine": Color(0.72, 0.78, 0.88, 0.55),
	"jungle": Color(0.12, 0.42, 0.18, 0.55),
	"boreal_forest": Color(0.28, 0.48, 0.32, 0.55),
	"savanna": Color(0.72, 0.62, 0.28, 0.55),
	"badlands": Color(0.62, 0.42, 0.28, 0.55),
}

const SUB_COLORS := {
	"dense_forest": Color(0.05, 0.18, 0.08, 0.75),
	"oasis": Color(0.20, 0.55, 0.70, 0.75),
	"flower_meadow": Color(0.85, 0.75, 0.35, 0.70),
	"marsh_pool": Color(0.18, 0.38, 0.55, 0.72),
	"rocky_clearing": Color(0.55, 0.55, 0.58, 0.72),
	"grove": Color(0.55, 0.78, 0.35, 0.72),
	"bamboo_thicket": Color(0.15, 0.55, 0.22, 0.75),
	"snowdrift": Color(0.92, 0.95, 0.98, 0.75),
	"cactus_plain": Color(0.88, 0.72, 0.25, 0.72),
	"salt_marsh": Color(0.90, 0.88, 0.82, 0.72),
	"heather_moor": Color(0.62, 0.48, 0.62, 0.72),
	"bog": Color(0.22, 0.32, 0.18, 0.75),
	"tide_flats": Color(0.75, 0.68, 0.42, 0.72),
	"geyser_field": Color(0.72, 0.35, 0.22, 0.75),
	"savanna_scrub": Color(0.68, 0.55, 0.22, 0.72),
	"thorn_waste": Color(0.52, 0.32, 0.18, 0.75),
	"lichen_field": Color(0.78, 0.82, 0.72, 0.72),
}


func toggle() -> void:
	enabled = not enabled
	visible = enabled
	queue_redraw()


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var world: Node2D = get_parent()
	if world == null or world.get("chunk_manager") == null:
		return
	var cm: Node2D = world.chunk_manager
	for chunk: RefCounted in cm.loaded_chunks():
		_draw_chunk(chunk)


func _draw_chunk(chunk: RefCounted) -> void:
	var reg: RefCounted = WorldGen.reg
	var n := WG.CHUNK_TILES
	var px := WG.TILE * 0.45
	for ty: int in n:
		for tx: int in n:
			var p_idx: int = chunk.parent_biome_at(tx, ty)
			if p_idx == 255:
				continue
			var parent_id := str(reg.biomes[p_idx]["id"])
			var col: Color = PARENT_COLORS.get(parent_id, Color(1, 0, 1, 0.4))
			var pos: Vector2 = chunk.tile_world(tx, ty)
			draw_rect(Rect2(pos - Vector2(px, px), Vector2(px * 2, px * 2)), col)
			if show_sub:
				var s_idx: int = chunk.sub_biome_at(tx, ty)
				if s_idx != 255:
					var sub_id := str(reg.biomes[s_idx]["id"])
					var sc: Color = SUB_COLORS.get(sub_id, Color(1, 1, 1, 0.6))
					draw_rect(Rect2(pos - Vector2(px * 0.6, px * 0.6), Vector2(px * 1.2, px * 1.2)), sc)
					draw_arc(pos, px * 0.85, 0, TAU, 8, Color(1, 1, 1, 0.85), 1.5)
