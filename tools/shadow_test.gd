extends Node2D
## Shadow validation scene (spec §Validation). Lays out one of each caster on a
## neutral ground band so all shadows can be compared side by side: a player, a
## tree, a tent, a small prop, a large building, a wall, and two overlapping
## casters. Run windowed and optionally screenshot:
##   godot --path . res://tools/shadow_test.tscn -- --out=C:/path/shots/
## Saves shadow_test.png if --out is given, otherwise just displays.

const IsoSprites    := preload("res://scripts/world/art/iso_sprites.gd")
const PixelPalette  := preload("res://scripts/world/art/core/pixel_palette.gd")
const PixelDraw     := preload("res://scripts/world/art/core/pixel_draw.gd")
const WorldLighting := preload("res://scripts/world/art/core/world_lighting.gd")

var _t := 0.0
var _out_dir := ""


class Caster extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	RenderingServer.set_default_clear_color(Color(0.16, 0.18, 0.15))
	_build()
	if not _out_dir.is_empty():
		await _shoot()


func _build() -> void:
	# Ground band so shadows land on something readable.
	var ground := Caster.new()
	ground.fn = func(c: CanvasItem) -> void:
		var g := PixelPalette.hex(0x6A7A52)
		for ty: int in 18:
			for tx: int in 30:
				var cx := float(tx - ty) * 16.0
				var cy := float(tx + ty) * 8.0
				var shade := g.lightened(0.02) if (tx + ty) % 2 == 0 else g
				PixelDraw.px_diamond(c, cx, cy, 16.5, 8.5, shade)
	ground.z_index = -100
	add_child(ground)

	# Each entry: label, screen pos, draw callable.
	var entries: Array = [
		["player",   Vector2(-360, 40),  func(c: CanvasItem) -> void:
			IsoSprites.draw_player(c, PixelPalette.pal("skin_a"), PixelPalette.pal("outfit_a"),
				PixelPalette.pal("hair"), "idle", _t, 2)],
		["tree",     Vector2(-220, 0),   func(c: CanvasItem) -> void:
			IsoSprites.draw_prop(c, "tree", 104.0, PixelPalette.pal("foliage_a"), 1, false, _t, "oak")],
		["tent",     Vector2(-70, 60),   func(c: CanvasItem) -> void:
			IsoSprites.draw_tent(c, 40.0, PixelPalette.pal("outfit_a"))],
		["barrel",   Vector2(40, 80),    func(c: CanvasItem) -> void:
			IsoSprites.draw_city_prop(c, "barrel", 0, _t)],
		["lamp",     Vector2(110, 40),   func(c: CanvasItem) -> void:
			IsoSprites.draw_city_prop(c, "lamp", 0, _t)],
		["building", Vector2(320, -40),  func(c: CanvasItem) -> void:
			IsoSprites.draw_building_body(c, 7.0, 1, PixelPalette.pal("outfit_a"))
			IsoSprites.draw_building_roof(c, 7.0, 1, Color(0.5, 0.3, 0.3), 1.0)],
		["wall",     Vector2(120, 150),  func(c: CanvasItem) -> void:
			IsoSprites.draw_city_wall(c, 0)],
		# Two overlapping casters (check overlap does not go black):
		["overlap_a", Vector2(-150, 200), func(c: CanvasItem) -> void:
			IsoSprites.draw_city_prop(c, "crate", 0, _t)],
		["overlap_b", Vector2(-120, 205), func(c: CanvasItem) -> void:
			IsoSprites.draw_city_prop(c, "barrel", 1, _t)],
	]
	for e: Array in entries:
		var node := Caster.new()
		node.fn = e[2]
		node.position = e[1]
		node.y_sort_enabled = false
		add_child(node)


func _process(delta: float) -> void:
	_t += delta
	for ch: Node in get_children():
		ch.queue_redraw()


func _shoot() -> void:
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.4, 1.4)
	add_child(cam)
	for i: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := _out_dir.path_join("shadow_test.png")
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
