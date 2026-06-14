extends Node
## prop_preview — renders the ruin/clutter props in a grid against a neutral iso
## ground so the art can be eyeballed without walking the world. Saves one PNG.
##   godot --path . res://tools/prop_preview.tscn -- --out=C:/path/

const IsoSprites := preload("res://scripts/world/art/iso_sprites.gd")
const PixelDraw := preload("res://scripts/world/art/core/pixel_draw.gd")
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")

var _out := "user://shots/"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var canvas := _Canvas.new()
	add_child(canvas)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path: String = _out.path_join("ruin_props.png")
	img.save_png(path)
	print("\n=== PROP RESULT ===")
	print(JSON.stringify({"saved": ProjectSettings.globalize_path(path)}))
	get_tree().quit(0)


class _Canvas:
	extends Node2D

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), PixelPalette.hex(0x6f7a66))
		var cells: Array = [
			["pillar v0", func(c: CanvasItem) -> void: IsoSprites.draw_ruin_pillar(c, 0)],
			["pillar v1", func(c: CanvasItem) -> void: IsoSprites.draw_ruin_pillar(c, 1)],
			["pillar v2", func(c: CanvasItem) -> void: IsoSprites.draw_ruin_pillar(c, 2)],
			["arch open", func(c: CanvasItem) -> void: IsoSprites.draw_ruin_arch(c, 1)],
			["arch closed", func(c: CanvasItem) -> void: IsoSprites.draw_ruin_arch(c, 0)],
			["wall", func(c: CanvasItem) -> void: IsoSprites.draw_broken_wall(c, 1)],
			["rubble", func(c: CanvasItem) -> void: IsoSprites.draw_rubble_pile(c, 1)],
			["statue", func(c: CanvasItem) -> void: IsoSprites.draw_broken_statue(c, 0)],
			["statue arm", func(c: CanvasItem) -> void: IsoSprites.draw_broken_statue(c, 2)],
		]
		var cols := 5
		for i: int in cells.size():
			var col := i % cols
			var row := i / cols
			var origin := Vector2(110.0 + float(col) * 180.0, 200.0 + float(row) * 230.0)
			# iso ground tile under the prop for context
			PixelDraw.px_diamond(self, origin.x, origin.y, 28.0, 14.0, PixelPalette.hex(0x86916f))
			draw_set_transform(origin, 0.0, Vector2.ONE)
			(cells[i][1] as Callable).call(self)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_string(ThemeDB.fallback_font, origin + Vector2(-40, 40), str(cells[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
