extends Node
## placeable_preview_shoot — renders a grid of PlaceablePreview panels (the world
## editor's showcase turntable) to a PNG so the art can be eyeballed without
## opening the interactive editor. Not headless: SubViewports need a real renderer.
##   godot --path . res://tools/placeable_preview_shoot.tscn -- --out=C:/path/

const PlaceablePreview := preload("res://tools/placeable_preview.gd")
const StampLibrary := preload("res://scripts/worldgen/stamp_library.gd")

var _out := "user://shots/"


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)

	var reg: RefCounted = WorldGen.reg
	DisplayServer.window_set_size(Vector2i(1140, 1040))
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.size = Vector2(1140, 1040)
	layer.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(8, 8)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	layer.add_child(grid)

	var sub := WorldGen.list_sub_biomes()
	var sub_id: String = str(sub[0]["id"]) if not sub.is_empty() else "forest"
	var enemy_name: String = "Chickens"
	if not DataRegistry.enemies.has(enemy_name) and not DataRegistry.enemies.is_empty():
		enemy_name = DataRegistry.enemies.keys()[0]

	var jobs: Array = [
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "house"}, "House"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "building", "foot": 7}, "Hall"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "fountain", "label": "Fountain"}, "Fountain"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "obelisk"}, "Obelisk"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "altar", "label": "Altar"}, "Altar"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "anvil"}, "Anvil"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "chest"}, "Chest"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "stall"}, "Stall"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "tent"}, "Tent"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "burrow", "label": "Animal Burrow"}, "Burrow"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "sign"}, "Sign"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "lantern"}, "Lantern"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "campfire"}, "Campfire"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "bridge"}, "Bridge"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_wall", "piece": 0}, "Wall"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_wall", "piece": 1}, "Gate"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_wall", "piece": 2}, "Tower"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "mammoth", "label": "Mammoth"}, "Mammoth"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "lamp"}, "Lamp post"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "well"}, "Well"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "crate"}, "Crate"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "barrel"}, "Barrel"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "flowerbox"}, "Flowerbox"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "city_prop", "prop": "cart"}, "Cart"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "ruin_arch", "label": "Ruins"}, "Broken arch"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "broken_statue", "label": "Statue"}, "Statue"),
		func(p: PlaceablePreview) -> void: p.show_structure({"kind": "ruin_pillar", "label": "Pillar"}, "Pillar"),
		func(p: PlaceablePreview) -> void: p.show_biome("forest"),
		func(p: PlaceablePreview) -> void: p.show_biome("desert"),
		func(p: PlaceablePreview) -> void: p.show_biome(sub_id),
		func(p: PlaceablePreview) -> void: p.show_terrain("water", "Water"),
		func(p: PlaceablePreview) -> void: p.show_creature(enemy_name),
		func(p: PlaceablePreview) -> void:
			var stamps: Array = StampLibrary.all()
			if not stamps.is_empty():
				p.show_stamp(stamps[0], str(stamps[0]["name"]))
			else:
				p.show_empty("no stamps"),
	]
	for j: Callable in jobs:
		var p := PlaceablePreview.new()
		p.reg = reg
		grid.add_child(p)
		j.call(p)

	for i: int in 30:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _out.path_join("placeable_preview.png")
	img.save_png(path)
	print("\n=== PREVIEW RESULT ===")
	print(JSON.stringify({"saved": ProjectSettings.globalize_path(path)}))
	get_tree().quit(0)
