extends Node2D
## Aldreth World Editor (v2) — the production designer for the FIXED finite world.
##
## Top-down 1px-per-tile view of the baked world with hand-authoring tools:
##   • Biome brush   — paint a parent/micro-biome (sets biome + ground tile; the
##                     game auto-spawns that biome's decals/clutter at runtime).
##   • Terrain brush — paint a specific tile (grass/road/wall/water/…).
##   • Structure     — drop houses, halls, fountains, walls, lamps, ruins…
##   • Erase         — brush that removes placed content (structures + monsters),
##                     and, with "Erase biomes" on, restores the generated terrain.
##   • Set Spawn     — click a walkable tile to set the player spawn.
##
## Editing is undoable (compact per-stroke command records; a continuous drag is
## one undo step). Generate World rebuilds the whole continent via the shared
## FiniteWorldGenerator. Save writes data/world/baked/<id>.world (+ map + spawn).
##
## Controls: right-drag pan · wheel zoom (over map only) · [ ] brush size ·
## Ctrl+Z undo · Ctrl+Y / Ctrl+Shift+Z redo · Ctrl+S save · 1-6 tools.
##
## Live 3D view: the "🧊 3D View" toolbar button docks the REAL game renderer
## (world.tscn) in a panel. Because the editor edits the same WorldGen chunk objects
## the renderer reads, painting terrain/biome/water and then re-meshing the touched
## chunks shows the true in-game 3D look. Press F to aim the 3D camera at the cursor;
## arrow keys orbit it. The panel's "⛶ Maximize" button (or M) blows it up to a large
## authoring view: with a Structure/Stamp tool selected, CLICK in the 3D view to place
## the picked object at the cursor (trees, rocks, houses…), live; with Pan selected a
## click re-aims the camera. Arrows keep orbiting. (Self-test: run with `-- --we-selftest`.)
##
## Run:  godot --path . res://tools/world_editor.tscn

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")
const BakedWorldStore := preload("res://scripts/worldgen/baked_world_store.gd")
const FiniteWorldGenerator := preload("res://scripts/worldgen/finite_world_generator.gd")
const RoadBrush := preload("res://scripts/worldgen/road_brush.gd")
const TerrainStyle := preload("res://scripts/render/terrain_style.gd")
const StampLibrary := preload("res://scripts/worldgen/stamp_library.gd")
const PropMeshes := preload("res://scripts/render/prop_meshes.gd")
const WorldEntity := preload("res://scripts/world/world_entity.gd")
const PlaceablePreview := preload("res://tools/placeable_preview.gd")
const MountainField := preload("res://scripts/worldgen/mountain_field.gd")

const OUT_DIR := "res://data/world/baked/"

enum Tool { PAN, BIOME, TERRAIN, STAMP, STRUCTURE, ERASE, SPAWN, CREATURE, ROAD, SETTLEMENT, SMOOTHEN, ELEVATE, FOREST, CLUTTER, SKILL, GRASS, SELECT }

# Display name per tool, shown as the floating options-panel title.
const TOOL_NAMES := {
	Tool.PAN: "Pan / View", Tool.BIOME: "Biome", Tool.TERRAIN: "Terrain",
	Tool.STAMP: "Stamp", Tool.STRUCTURE: "Structure", Tool.ERASE: "Erase",
	Tool.SPAWN: "Set Spawn", Tool.CREATURE: "Creatures", Tool.ROAD: "Roads",
	Tool.SETTLEMENT: "Settlement", Tool.SMOOTHEN: "Smoothen", Tool.ELEVATE: "Elevate",
	Tool.FOREST: "Trees", Tool.CLUTTER: "Clutter", Tool.SKILL: "Skills",
	Tool.GRASS: "Grass", Tool.SELECT: "Select / Move",
}

# Structures rotate freely in fine steps (settlements/stamps stay on the 90° tile grid since they're
# multi-tile). STRUCT_ROT_STEPS=24 → 15° per scroll/R press; pick from many more sides.
const STRUCT_ROT_STEPS := 24

# Gather skills exposed by the Skills tool, in palette order. Combat (monster spawns) is shown
# first as its own accordion section. Each places a FUNCTIONAL resource: a harvestable gather site
# (trees/rocks/fish/herbs/...) or a wandering monster pack.
const SKILL_PLACE_ORDER := ["woodcutting", "mining", "fishing", "foraging", "hunter", "thieving"]
const SKILL_DISPLAY := {
	"woodcutting": "Woodcutting", "mining": "Mining", "fishing": "Fishing",
	"foraging": "Foraging", "hunter": "Hunter", "thieving": "Thieving",
}

const TERRAIN := [
	["grass", "Grass"], ["grass_dark", "Dark grass"], ["dirt", "Dirt path"],
	["cobble", "Cobble road"], ["gravel", "Gravel"], ["sand", "Sand"],
	["shallow", "Shallows"], ["water", "Water"], ["deep_water", "Deep water"],
	["rock", "Rock"], ["snow", "Snow"], ["marsh", "Marsh"], ["mud", "Mud"],
	["wheat_ripe", "Wheat"], ["plaza", "Plaza"], ["plank_floor", "Plank floor"],
	["building_wall", "Building wall"], ["lava_rock", "Lava rock"], ["ash", "Ash"],
]

const STRUCTURES := [
	["House", {"kind": "house"}], ["Hall (large)", {"kind": "building", "foot": 7}],
	["Fountain", {"kind": "fountain", "label": "Fountain"}],
	["Well", {"kind": "city_prop", "prop": "well"}], ["Lamp post", {"kind": "city_prop", "prop": "lamp"}],
	["Crate", {"kind": "city_prop", "prop": "crate"}], ["Barrel", {"kind": "city_prop", "prop": "barrel"}],
	["Cart", {"kind": "city_prop", "prop": "cart"}], ["Hay", {"kind": "city_prop", "prop": "hay"}],
	["Flower box", {"kind": "city_prop", "prop": "flowerbox"}],
	["Wall segment", {"kind": "city_wall", "piece": 0}], ["Wall gate", {"kind": "city_wall", "piece": 1}],
	["Wall tower", {"kind": "city_wall", "piece": 2}], ["Tent", {"kind": "tent"}],
	["Campfire", {"kind": "campfire"}], ["Sign", {"kind": "sign", "label": "Sign"}],
	["Anvil", {"kind": "anvil", "station": "anvil"}], ["Altar", {"kind": "altar", "label": "Altar"}],
	["Obelisk", {"kind": "obelisk", "label": "Obelisk"}], ["Chest", {"kind": "chest"}],
	["Broken arch", {"kind": "ruin_arch", "label": "Ruins"}], ["Broken pillar", {"kind": "ruin_pillar"}],
	["Broken wall", {"kind": "broken_wall"}], ["Rubble", {"kind": "rubble_pile"}],
	["Broken statue", {"kind": "broken_statue", "label": "Statue"}],
	# Props/scenery models (each renders as its own 3D entity in-game).
	["Stall", {"kind": "stall", "label": "Stall"}], ["Lantern", {"kind": "lantern"}],
	["Bridge", {"kind": "bridge"}], ["Mammoth", {"kind": "mammoth", "label": "Mammoth"}],
	["Meteor", {"kind": "meteor", "label": "Meteor"}],
	# Nature models (decorative — tree label picks the species).
	["Tree (oak)", {"kind": "tree", "label": "Oak Tree"}], ["Tree (pine)", {"kind": "tree", "label": "Pine Tree"}],
	["Tree (fir)", {"kind": "tree", "label": "Fir Tree"}], ["Tree (maple)", {"kind": "tree", "label": "Maple Tree"}],
	["Rock", {"kind": "rock"}], ["Bush", {"kind": "bush"}],
	# Ground-clutter decor placed as standalone models.
	["Mushroom", {"kind": "decor", "prop": "mushroom"}], ["Flowers", {"kind": "decor", "prop": "flower"}],
	["Fern", {"kind": "decor", "prop": "fern"}], ["Reeds", {"kind": "decor", "prop": "reed"}],
	["Shrub", {"kind": "decor", "prop": "shrub"}], ["Grass tuft", {"kind": "decor", "prop": "grass"}],
	["Pebbles", {"kind": "decor", "prop": "pebble"}],
	# ── added clutter (assign to biomes as you like) ──
	["Boulder", {"kind": "decor", "prop": "boulder"}], ["Rock pile", {"kind": "decor", "prop": "rock_pile"}],
	["Cairn", {"kind": "decor", "prop": "cairn"}], ["Standing stone", {"kind": "decor", "prop": "standing_stone"}],
	["Crystal", {"kind": "decor", "prop": "crystal"}], ["Geode", {"kind": "decor", "prop": "geode"}],
	["Log", {"kind": "decor", "prop": "log"}], ["Log pile", {"kind": "decor", "prop": "log_pile"}],
	["Branch", {"kind": "decor", "prop": "branch"}], ["Tree roots", {"kind": "decor", "prop": "tree_roots"}],
	["Mossy log", {"kind": "decor", "prop": "mossy_log"}], ["Cattails", {"kind": "decor", "prop": "cattail"}],
	["Thistle", {"kind": "decor", "prop": "thistle"}], ["Berry bush", {"kind": "decor", "prop": "berry_bush"}],
	["Clover", {"kind": "decor", "prop": "clover"}], ["Lily pad", {"kind": "decor", "prop": "lily_pad"}],
	["Dandelion", {"kind": "decor", "prop": "dandelion"}], ["Agave", {"kind": "decor", "prop": "agave"}],
	["Tumbleweed", {"kind": "decor", "prop": "tumbleweed"}], ["Sagebrush", {"kind": "decor", "prop": "sagebrush"}],
	["Animal skull", {"kind": "decor", "prop": "animal_skull"}], ["Toadstool", {"kind": "decor", "prop": "toadstool"}],
	["Mushroom cluster", {"kind": "decor", "prop": "mushroom_cluster"}], ["Bracket fungus", {"kind": "decor", "prop": "bracket_fungus"}],
	["Snow patch", {"kind": "decor", "prop": "snow_patch"}], ["Ice shard", {"kind": "decor", "prop": "ice_shard"}],
	["Frozen shrub", {"kind": "decor", "prop": "frozen_shrub"}], ["Seashell", {"kind": "decor", "prop": "seashell"}],
	["Starfish", {"kind": "decor", "prop": "starfish"}], ["Coral", {"kind": "decor", "prop": "coral"}],
	["Barrel", {"kind": "decor", "prop": "barrel"}], ["Crate", {"kind": "decor", "prop": "crate"}],
	["Sack", {"kind": "decor", "prop": "sack"}], ["Hay bale", {"kind": "decor", "prop": "hay_bale"}],
	["Bucket", {"kind": "decor", "prop": "bucket"}], ["Signpost", {"kind": "decor", "prop": "signpost"}],
	["Fence post", {"kind": "decor", "prop": "fence_post"}], ["Anthill", {"kind": "decor", "prop": "anthill"}],
	# ── Graveyard structures ──
	["Gravestone", {"kind": "city_prop", "prop": "gravestone"}],
	["Cross headstone", {"kind": "city_prop", "prop": "gravestone_cross"}],
	["Tomb", {"kind": "city_prop", "prop": "tomb"}], ["Crypt", {"kind": "city_prop", "prop": "crypt"}],
	["Grave mound", {"kind": "city_prop", "prop": "grave_mound"}],
	["Coffin", {"kind": "city_prop", "prop": "coffin"}], ["Bone pile", {"kind": "city_prop", "prop": "bone_pile"}],
	["Grave urn", {"kind": "city_prop", "prop": "grave_urn"}],
	["Mourning statue", {"kind": "city_prop", "prop": "mourning_statue"}],
	["Iron railing", {"kind": "city_prop", "prop": "iron_fence"}],
	["Grave candle", {"kind": "city_prop", "prop": "grave_candle"}],
	# ── Dark moor ──
	["Dead tree", {"kind": "city_prop", "prop": "dead_tree"}],
	["Gnarled stump", {"kind": "city_prop", "prop": "gnarled_stump"}],
	["Gallows", {"kind": "city_prop", "prop": "gallows"}],
	["Standing stone (dark)", {"kind": "city_prop", "prop": "standing_stone_dark"}],
	["Crooked post", {"kind": "city_prop", "prop": "crooked_post"}],
	["Raven perch", {"kind": "city_prop", "prop": "raven_perch"}],
	["Withered bush", {"kind": "city_prop", "prop": "withered_bush"}],
	["Wisp lantern", {"kind": "city_prop", "prop": "wisp_lantern"}],
	["Peat stack", {"kind": "city_prop", "prop": "peat_stack"}],
	# ── Fairy ──
	["Fairy ring", {"kind": "city_prop", "prop": "fairy_ring"}],
	["Giant toadstool", {"kind": "city_prop", "prop": "giant_toadstool"}],
	["Glow mushroom", {"kind": "city_prop", "prop": "glow_mushroom"}],
	["Glow crystal", {"kind": "city_prop", "prop": "glow_crystal"}],
	["Flower arch", {"kind": "city_prop", "prop": "flower_arch"}],
	["Toadstool house", {"kind": "city_prop", "prop": "toadstool_house"}],
	["Fairy lantern", {"kind": "city_prop", "prop": "fairy_lantern"}],
	["Bluebells", {"kind": "city_prop", "prop": "bluebells"}],
	# ── Medieval props ──
	["Crossroads sign", {"kind": "city_prop", "prop": "signpost"}],
	["Banner", {"kind": "city_prop", "prop": "banner"}], ["Torch", {"kind": "city_prop", "prop": "torch"}],
	["Brazier", {"kind": "city_prop", "prop": "brazier"}],
	["Water trough", {"kind": "city_prop", "prop": "water_trough"}],
	["Market awning", {"kind": "city_prop", "prop": "market_awning"}],
	["Grindstone", {"kind": "city_prop", "prop": "grindstone"}],
	["Archery target", {"kind": "city_prop", "prop": "archery_target"}],
	["Training dummy", {"kind": "city_prop", "prop": "training_dummy"}],
	["Stocks", {"kind": "city_prop", "prop": "stocks"}],
	["Hanging sign", {"kind": "city_prop", "prop": "hanging_sign"}],
	["Forge", {"kind": "city_prop", "prop": "forge"}],
	# ── Stable & farm ──
	["Stable", {"kind": "city_prop", "prop": "stable"}],
	["Hay bale (round)", {"kind": "city_prop", "prop": "hay_bale"}],
	["Hitching post", {"kind": "city_prop", "prop": "hitching_post"}],
	["Feed trough", {"kind": "city_prop", "prop": "feed_trough"}],
	["Saddle rack", {"kind": "city_prop", "prop": "saddle_rack"}],
	["Paddock fence", {"kind": "city_prop", "prop": "paddock_fence"}],
	# ── Furniture & fittings ──
	["Weapon rack", {"kind": "city_prop", "prop": "weapon_rack"}],
	["Bookcase", {"kind": "city_prop", "prop": "bookcase"}],
	["Shelf", {"kind": "city_prop", "prop": "shelf"}], ["Table", {"kind": "city_prop", "prop": "table"}],
	["Chair", {"kind": "city_prop", "prop": "chair"}], ["Bench", {"kind": "city_prop", "prop": "bench"}],
	["Bed", {"kind": "city_prop", "prop": "bed"}],
	["Candelabra", {"kind": "city_prop", "prop": "candelabra"}],
	["Cauldron", {"kind": "city_prop", "prop": "cauldron"}],
	["Fireplace", {"kind": "city_prop", "prop": "fireplace"}],
	["Barrel rack", {"kind": "city_prop", "prop": "barrel_rack"}],
	["Crate stack", {"kind": "city_prop", "prop": "crate_stack"}],
	["Alchemy table", {"kind": "city_prop", "prop": "alchemy_table"}],
	["Throne", {"kind": "city_prop", "prop": "throne"}],
	["Lectern", {"kind": "city_prop", "prop": "lectern"}],
]

const ROOF_COLORS := ["7a3b3b", "3b5a7a", "4a6b3a", "6b5a3a", "5a3b6b", "7a6b3a"]
const SIDEBAR_W := 240    # fixed sidebar width (items fill it)
const HUD_SCALE := 1.25   # editor chrome (tool panels / preview / minimap) is drawn 1.25× larger
const STRUCT_MARK := Color(0.95, 0.85, 0.4)
const SPAWN_MARK := Color(0.3, 1.0, 0.45)
const TEST_SPAWN_MARK := Color(1.0, 0.6, 0.15)   # orange beacon for the (ephemeral) Test Level spawn
const TREE_MARK := Color(0.16, 0.42, 0.18, 0.92)   # ambient canopy dot on the 2D map
const TREE_DRAW_ZOOM := 1.2   # px/tile below which canopy dots are sub-pixel — skip (perf)

var _reg: RefCounted
var _spec: RefCounted
var _bounds := Rect2i()
var _min_tx := 0
var _min_ty := 0
var _w := 1
var _h := 1

var _chunks: Dictionary = {}
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _cam: Camera2D
var _overlay: Node2D
var _img_dirty := false

var _tool := Tool.PAN
var _brush := 2
var _erase_keep_terrain := false   # Erase opt-out: keep painted terrain/biome/elevation (remove placed objects only)
var _sel_biome := ""
var _sel_terrain := "grass"
var _sel_struct := 0
var _place_off := Vector2.ZERO   # sub-tile iso offset for free (non-grid) structure placement
var _struct_open: Dictionary = {}   # structure-accordion: category name → expanded?
var _sel_stamp := 0
var _sel_creature := ""
# Skills tool: which skill ("combat" or a gather-skill key) + the chosen node/creature. Each skill
# is its own sidebar button (all select Tool.SKILL); the options panel lists that skill's objects.
var _sel_skill := ""
var _sel_skill_item := ""
var _skill_tool_buttons: Dictionary = {}   # skill key → sidebar Button
var _creature_count := 3          # pack size dropped per click (scattered across the spawn area)
var _creature_wander := 4         # roam radius, tiles
var _creature_aggro := 0          # engage distance, tiles (0 = global default)
var _creature_leash := 0          # give-up/leave distance, tiles (0 = global default)
var _creature_aggressive := true
var _stamp_variant := 0
var _stamp_rot := 0
var _struct_rot := 0              # STRUCTURE yaw step (0..STRUCT_ROT_STEPS-1), 15° each — granular
# Select/Move tool: the placed object currently grabbed (chunk + index into chunk.structures).
var _sel_chunk: RefCounted = null
var _sel_index := -1
var _sel_moving := false          # true after "Move" pressed: next click relocates the selection
var _stamp_flip := false
var _sel_road_style := "road"
var _road_width := 3              # road width in tiles (diameter); the Road tool's slider sets it
var _road_width_label: Label
var _decor_density := 0.25        # Trees/Clutter brush: per-tile place chance (the Density slider)
var _density_slider: HSlider
var _decor_placed := {}           # tiles painted this stroke, so a drag doesn't double-place
var _place_scale := 1.0           # uniform size for placed structures/trees/clutter (the Scale slider)
var _road_pts: Array[Vector2i] = []
var _road_drawing := false
var _road_styles_cache: Dictionary = {}
var _sel_settlement := "village"
var _settlement_rot := 0
var _settlement_cache: Dictionary = {}
var _spawn_tile := Vector2i.ZERO
var _show_structs := true
var _show_spawn := true
var _show_collision := false
var _show_biomes := false
var _show_danger := false
var _show_walk := false
var _show_elevation := false
var _elev_check: CheckBox      # the Elevation overlay toggle, auto-ticked by the Smoothen tool
var _show_trees := true   # draw the procedural ambient canopy as dots (and what the eraser cut)
# Per-chunk canopy cache: chunk key -> PackedInt32Array of local tile indices that grow an
# ambient tree (deterministic, so computed once). Cuts are filtered at draw; a chunk's entry
# is invalidated only when its terrain/biome is edited (see _apply_state). This keeps the
# every-frame map redraw cheap instead of re-running the canopy gate over every tile.
var _canopy_cache: Dictionary = {}

var _panning := false
var _painting := false
var _hover_tile := Vector2i.ZERO
var _ui_hover := false

# undo/redo — each entry is a "stroke" dict (see _begin_stroke).
var _history: Array = []
var _redo: Array = []
var _stroke: Dictionary = {}
var _stroke_active := false

# UI
var _hud: CanvasLayer
var _status: Label
var _coords: Label
var _palette_box: VBoxContainer
var _tool_buttons: Dictionary = {}
var _brush_label: Label
var _erase_biomes_check: CheckBox
var _undo_btn: Button
var _redo_btn: Button
var _busy := false
var _preview: PlaceablePreview
var _preview_panel: PanelContainer
var _selected_choice_btn: Button
# Reworked HUD: grouped collapsible sidebar, a floating per-tool options panel, and a
# dedicated editor menu modal (ESC) — separate from the embedded game's pause menu.
var _sidebar: PanelContainer
var _tool_group_bodies: Array = []        # [{btn, body, open}] collapsible tool categories
var _opts_panel: PanelContainer           # floating panel: active tool's options + brush sliders
var _opts_title: Label
var _editor_menu: PopupPanel              # the ESC menu modal
var _gen_menu: PopupMenu                  # Generate ▸ submenu inside the editor menu
var _reroll_btn: Button

# Live 3D view — embeds the real game world (world.tscn) in a SubViewport so you can
# see the actual 3D result (elevation, water, models) of what you paint on the 2D map.
# Lazy: the heavy game scene is only instanced when you toggle the panel on.
const _GAME_SCENE := preload("res://scenes/world.tscn")
var _v3d_panel: PanelContainer
var _v3d_container: SubViewportContainer
var _v3d_vp: SubViewport
var _v3d_world: Node2D            # the embedded world.tscn instance (its render_3d does the 3D)
var _ehud: CanvasLayer            # the embedded world's HUD (hidden in editing, shown in Test Level)
var _v3d_on := false
# Test Level — flips the embedded world from view-only to fully playable at a chosen spawn, hands it
# input + the follow camera + its HUD, and hides the editor chrome. Esc / the Back button returns.
var _testing := false
var _back_btn: Button
var _chrome_prev_vis: Dictionary = {}   # editor HUD child -> visibility saved while testing
# Set Test Spawn: pick the tile Test Level drops the player on (else it uses the camera focus).
var _picking_test_spawn := false
var _test_spawn_tile := Vector2i(-2147483648, 0)   # unset sentinel
var _test_spawn_marker3d: Node3D
var _v3d_max := false             # large/navigable mode vs the small docked corner panel
var _v3d_btn: Button
var _v3d_focus_tile := Vector2i(-2147483648, 0)   # last tile the 3D camera was sent to
const _V3D_SIZE := Vector2i(540, 380)
const _V3D_LEFT := 192      # 3D canvas starts right of the tool column
const _V3D_TOP := 44        # …and below the top bar
# Maximized = aerial "satellite" camera: steep top-down-ish pitch, zoomed out, free
# pan (right-drag) + wheel zoom across the map; left-click places with a paint tool.
const _V3D_SAT_PITCH := 1.16      # near top-down aerial (CAM_PITCH_MAX is 1.40)
var _v3d_zoom := 0.45             # lower = wider aerial view (cam ortho size grows)
var _v3d_panning := false
var _v3d_pan_prev := Vector2.ZERO
var _v3d_painting := false      # brush/sculpt drag in progress over the maximized 3D view
var _gizmo_root: Node3D         # hover cursor in the 3D world (brush ring / placement footprint)
var _gizmo_disc: MeshInstance3D
var _gizmo_foot: MeshInstance3D
var _spawn_marker3d: Node3D     # persistent green beacon at the player spawn in the 3D view
var _last_instant_ms := 0       # throttle for live-drag chunk remeshes
var _ghost_root: Node3D         # translucent 3D model of the structure about to be placed
var _ghost_variant := 0         # reroll seed for the ghost's look (roof colour / model variant)
var _ghost_sig := ""            # rebuild key: rebuild ghost meshes only when selection/variant changes
var _ghost_mat_cache: Dictionary = {}   # source material id → cached translucent ghost material
var _v3d_focus_pos := Vector2.ZERO   # float world-space camera focus (WASD/pan move it)
const _V3D_VIEW_CAP := 40            # aerial terrain CEILING (chunks); data auto-follows the zoom up to this (world.gd mini)
# World minimap (bottom-right): whole-world baked map; click to jump the aerial camera.
var _minimap_panel: PanelContainer
var _minimap_tex: TextureRect
var _minimap_marker: ColorRect
var _map_overlay: Control       # draws placed content (spawn / creatures / buildings / pois / roads) over the map
var _minimap_check: CheckBox   # Overlays > "World map" — kept in sync with the M key
var _show_minimap := false   # Overlays > "World map" toggle — OFF by default (don't auto-open the bottom-right map; press M / tick the box to show it)


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true
	_reg = WorldGen.reg
	_spec = _reg.spec
	if not _spec.active or not _spec.finite:
		push_error("World editor needs a finite authored world (set bounds in worldspec).")
		get_tree().quit(1)
		return
	_bounds = _spec.bounds
	_min_tx = _bounds.position.x * WG.CHUNK_TILES
	_min_ty = _bounds.position.y * WG.CHUNK_TILES
	_w = _bounds.size.x * WG.CHUNK_TILES
	_h = _bounds.size.y * WG.CHUNK_TILES
	if _sel_biome.is_empty():
		_sel_biome = str(WorldGen.list_surface_biomes()[0]["id"])
	if _sel_creature.is_empty():
		_sel_creature = "Chickens" if DataRegistry.enemies.has("Chickens") \
			else (str(DataRegistry.enemies.keys()[0]) if not DataRegistry.enemies.is_empty() else "")
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.11))
	_load_world()
	_build_view()
	_build_ui()
	_build_3d_view_panel()
	_build_world_minimap()
	_set_tool(Tool.PAN)
	_refresh_palette()
	_refresh_history_buttons()
	var _selftest := false
	for _a: String in OS.get_cmdline_user_args():
		if _a.begins_with("--we-selftest"):
			_run_selftest.call_deferred()
			_selftest = true
			break
		if _a.begins_with("--we-sat"):
			_run_sat_shot.call_deferred()
			_selftest = true
			break
	# Open straight into the aerial 3D world-builder (the rendered map IS the canvas).
	if not _selftest:
		_toggle_3d_maximize.call_deferred()


## Dev verification: enter the aerial view over the heartland, zoom out wide, screenshot.
func _run_sat_shot() -> void:
	_toggle_3d_view()
	_focus_3d(Vector2i(0, 0))
	for _i: int in 8:
		_v3d_zoom_by(1.0 / 1.12)   # zoom out toward the wide limit (stress the streaming)
	await get_tree().create_timer(15.0).timeout
	if _v3d_vp != null:
		_v3d_vp.get_texture().get_image().save_png("user://we_sat.png")
		print("[we-sat] saved we_sat.png zoom=%.3f" % _v3d_zoom)
	get_tree().quit()


## Dev verification: find a scattered set-piece POI in the baked world, aim the 3D
## camera at it, and screenshot. Pass a POI type to target a specific one. Run:
##   godot --path . res://tools/world_editor.tscn -- --we-selftest=haunted_ruins
func _run_selftest() -> void:
	var want := "haunted_ruins"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--we-selftest="):
			want = a.trim_prefix("--we-selftest=")
	if want == "road":
		_run_road_selftest()
		return
	if want == "settlement":
		_run_settlement_selftest()
		return
	# biome:<id> — find a tile of that biome (away from the coast/spawn) and frame it.
	if want.begins_with("biome:"):
		var bid := want.trim_prefix("biome:")
		var bidx := int(_reg.biome_index.get(bid, -1))
		var spot := Vector2i(-2147483648, 0)
		# Prefer an INTERIOR tile (a 5x5 patch all the same biome) so we frame a dense
		# stand, not a sparse border. Fall back to any matching tile.
		var fallback := Vector2i(-2147483648, 0)
		for c: RefCounted in _chunks.values():
			if Vector2(c.cx, c.cy).length() < 6.0:
				continue  # skip the spawn hub
			for ly: int in range(3, WG.CHUNK_TILES - 3):
				for lx: int in range(3, WG.CHUNK_TILES - 3):
					if c.biome_at(lx, ly) != bidx:
						continue
					if fallback.x == -2147483648:
						fallback = Vector2i(c.cx * WG.CHUNK_TILES + lx, c.cy * WG.CHUNK_TILES + ly)
					var interior := true
					for oy: int in range(-2, 3):
						for ox: int in range(-2, 3):
							if c.biome_at(lx + ox, ly + oy) != bidx:
								interior = false
								break
						if not interior: break
					if interior:
						spot = Vector2i(c.cx * WG.CHUNK_TILES + lx, c.cy * WG.CHUNK_TILES + ly)
						break
				if spot.x != -2147483648: break
			if spot.x != -2147483648: break
		if spot.x == -2147483648:
			spot = fallback
		print("[we-selftest] biome '%s' (idx %d) at %s" % [bid, bidx, str(spot)])
		_toggle_3d_view()
		if spot.x != -2147483648:
			_focus_3d(spot)
		await get_tree().create_timer(9.0).timeout
		if _v3d_world != null:
			var nodes: Array = _v3d_world.get("_decor_nodes")
			var canopy := 0
			var by_kind: Dictionary = {}
			for nd in nodes:
				var kk := str(nd.get("kind"))
				if kk.begins_with("canopy_"):
					canopy += 1
					by_kind[kk] = int(by_kind.get(kk, 0)) + 1
			print("[we-selftest] decor nodes=%d  canopy=%d  by_kind=%s" % [nodes.size(), canopy, str(by_kind)])
		if _v3d_vp != null:
			_v3d_vp.get_texture().get_image().save_png("user://we3d_biome.png")
		print("[we-selftest] saved we3d_biome.png (%s)" % bid)
		get_tree().quit()
		return
	var order: Array = [want, "haunted_ruins", "cursed_keep", "old_watchtower", "abandoned_farmstead", "wayfarers_wreck"]
	var found := Vector2i(-2147483648, 0)
	var found_type := ""
	for poi_type: String in order:
		for c: RefCounted in _chunks.values():
			for poi: Dictionary in c.pois:
				if str(poi.get("type", "")) == poi_type:
					var anc: Vector2i = poi["anchor"]
					found = Vector2i(c.cx * WG.CHUNK_TILES + anc.x, c.cy * WG.CHUNK_TILES + anc.y)
					found_type = poi_type
					break
			if found_type != "": break
		if found_type != "": break
	print("[we-selftest] target '%s' found=%s at %s" % [want, found_type, str(found)])
	var dumped := false
	for c: RefCounted in _chunks.values():
		if dumped:
			break
		for poi: Dictionary in c.pois:
			if str(poi.get("type", "")) == found_type:
				var summ: Array = []
				for pt: Dictionary in poi["parts"]:
					var tag := str(pt.get("kind"))
					if pt.has("enemy_name"): tag += "=" + str(pt["enemy_name"])
					elif pt.has("prop"): tag += "=" + str(pt["prop"])
					summ.append(tag)
				print("[we-selftest] parts: ", summ)
				dumped = true
				break
	_toggle_3d_view()
	if found_type != "":
		_focus_3d(found)
	await get_tree().create_timer(9.0).timeout
	if _v3d_vp != null:
		_v3d_vp.get_texture().get_image().save_png("user://we3d_poi.png")
	print("[we-selftest] saved we3d_poi.png (%s)" % found_type)
	get_tree().quit()


# ─────────────────────────────── load / view ────────────────────────────────

func _load_world() -> void:
	_img = Image.create_empty(_w, _h, false, Image.FORMAT_RGB8)
	for cy: int in range(_bounds.position.y, _bounds.end.y):
		for cx: int in range(_bounds.position.x, _bounds.end.x):
			var chunk: RefCounted = WorldGen.get_chunk(0, cx, cy)
			_chunks["%d:%d" % [cx, cy]] = chunk
			_blit_chunk(chunk)
	_tex = ImageTexture.create_from_image(_img)
	if WorldGen.baked.loaded and WorldGen.baked.has_spawn:
		_spawn_tile = WorldGen.baked.spawn_tile
	else:
		_spawn_tile = Vector2i(_min_tx + _w / 2, _min_ty + _h / 2)


func _blit_chunk(chunk: RefCounted) -> void:
	var bx: int = chunk.cx * WG.CHUNK_TILES - _min_tx
	var by: int = chunk.cy * WG.CHUNK_TILES - _min_ty
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			var tid: int = chunk.tile_id(lx, ly)
			var col: Color = _tile_color(tid)
			if not bool(_reg.tile_def(tid).get("water", false)):
				col = TerrainStyle.biome_tinted(col, str(_reg.tile_order[tid]), _reg.biome_tint(chunk.biome_at(lx, ly)), 0.55)
			_img.set_pixel(bx + lx, by + ly, col)


func _tile_color(tid: int) -> Color:
	var cols: Array = _reg.tile_def(tid)["colors"]
	return cols[0]


func _build_view() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = _tex
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_overlay = Node2D.new()
	_overlay.z_index = 5
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay.bind(_overlay))
	_cam = Camera2D.new()
	_cam.position = Vector2(_w, _h) * 0.5
	_cam.zoom = Vector2(3.0, 3.0)
	add_child(_cam)
	_cam.make_current()


# ─────────────────────────────── input ──────────────────────────────────────

## Esc is caught at the very top (before the docked 3D-view world's SubViewport) and consumed, so
## the editor opens ITS OWN menu instead of leaking the game's pause menu.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _testing:
			_exit_test_mode()     # while playtesting, Esc returns to the editor (not the editor menu)
		else:
			_toggle_editor_menu()


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _testing:
		return   # playtesting: the embedded world owns input; the editor stops intercepting
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and not _ui_hover:
			if _is_rotatable_tool(): _rotate_placement(1)
			else: _zoom_at(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _ui_hover:
			if _is_rotatable_tool(): _rotate_placement(-1)
			else: _zoom_at(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and not _ui_hover:
			_painting = event.pressed
			if event.pressed:
				_begin_stroke()
				_apply_tool(true)
			else:
				_commit_stroke()
	elif event is InputEventMouseMotion and _panning:
		_cam.position -= event.relative / _cam.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


## App shortcuts live here (not _handle_key) so undo/redo/save fire even when a
## toolbar button or the docked 3D view currently holds keyboard focus.
func _shortcut_input(event: InputEvent) -> void:
	if _busy or _testing or not (event is InputEventKey) or not event.pressed or event.echo or not event.ctrl_pressed:
		return
	match event.keycode:
		KEY_Z:
			if event.shift_pressed: _do_redo()
			else: _do_undo()
			get_viewport().set_input_as_handled()
		KEY_Y:
			_do_redo()
			get_viewport().set_input_as_handled()
		KEY_S:
			_save()
			get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		return   # Ctrl shortcuts (undo/redo/save) are handled in _shortcut_input
	match event.keycode:
		KEY_BRACKETLEFT: _set_brush(_brush - 1)
		KEY_BRACKETRIGHT: _set_brush(_brush + 1)
		KEY_R:
			if _is_rotatable_tool():
				_rotate_placement(1)   # one 90° step — Stamp / Settlement / Structure
		KEY_F:
			if _tool == Tool.STAMP:
				_stamp_flip = not _stamp_flip
				_status.text = "Stamp flip: %s" % ("on" if _stamp_flip else "off")
			elif _v3d_on:
				_focus_3d(_hover_tile)
				_status.text = "3D camera → tile (%d, %d)" % [_hover_tile.x, _hover_tile.y]
		KEY_M: _toggle_minimap()
		KEY_1: _set_tool(Tool.PAN)
		KEY_2: _set_tool(Tool.BIOME)
		KEY_3: _set_tool(Tool.TERRAIN)
		KEY_4: _set_tool(Tool.STAMP)
		KEY_5: _set_tool(Tool.STRUCTURE)
		KEY_6: _set_tool(Tool.ERASE)
		KEY_7: _set_tool(Tool.SPAWN)
		KEY_8: _set_tool(Tool.CREATURE)
		KEY_9: _set_tool(Tool.ROAD)
		KEY_0: _set_tool(Tool.SETTLEMENT)
		KEY_H: _set_tool(Tool.SMOOTHEN)   # smootHen / flatten elevation
		KEY_E: _set_tool(Tool.ELEVATE)    # Elevate / raise into hills & mountains
		KEY_T: _set_tool(Tool.FOREST)     # Trees brush (biome-aware species)
		KEY_C: _set_tool(Tool.CLUTTER)    # Clutter brush (biome-aware ground detail)
		KEY_V: _set_tool(Tool.GRASS)      # Grass brush (lush short meadow grass)
		KEY_Q: _set_tool(Tool.SELECT)     # Select / move / rescale / delete a placed object
		KEY_G: _select_skill_tool("combat" if _sel_skill.is_empty() else _sel_skill)   # Skills placement


func _zoom_at(factor: float) -> void:
	var before := get_global_mouse_position()
	_cam.zoom = (_cam.zoom * factor).clamp(Vector2(0.4, 0.4), Vector2(24.0, 24.0))
	var after := get_global_mouse_position()
	_cam.position += before - after


func _process(_delta: float) -> void:
	if _testing:
		return   # playtesting: the embedded world drives itself; the editor does nothing
	# 3D world canvas: WASD flies the aerial camera over the map.
	if _v3d_on:
		_v3d_wasd(_delta)
		_update_minimap_marker()
		_update_hover_gizmo()
		_update_spawn_marker3d()
		_update_test_spawn_marker3d()
	elif _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.visible = false
	# Pointer is "over UI" whenever any editor Control is under the cursor — used
	# to keep the mouse wheel scrolling lists instead of zooming the map.
	_ui_hover = get_viewport().gui_get_hovered_control() != null
	# In the docked 3D view the cursor sits over the 3D panel, so read the tile under the 3D
	# cursor (not the hidden 2D map) — otherwise the coords/biome readout is wrong in 3D.
	var t := _v3d_tile_under_mouse() if _v3d_on else _tile_under_mouse()
	if t.x != -2147483648 and t != _hover_tile:
		_hover_tile = t
		_update_coords()
	if _painting and not _ui_hover and _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE, Tool.SMOOTHEN, Tool.ELEVATE, Tool.FOREST, Tool.CLUTTER, Tool.GRASS]:
		_apply_tool(false)
	if _painting and not _ui_hover and _tool == Tool.ROAD and _road_drawing:
		if _road_pts.is_empty() or _road_pts[_road_pts.size() - 1] != _hover_tile:
			_road_pts.append(_hover_tile)
	if _img_dirty:
		_img_dirty = false
		_tex.update(_img)
	_overlay.queue_redraw()
	_position_preview_panel()


## Float the preview panel just to the right of the currently selected sidebar
## item, tracking it as the palette scrolls. Falls back beside the sidebar top
## for tools with no list selection (Pan / Erase / Set Spawn).
func _position_preview_panel() -> void:
	if _preview_panel == null:
		return
	# FIXED spot just right of the floating options panel (which itself sits right of the 1.25×
	# sidebar) — never tracks the selected row. Always in the same place so it's easy to glance at.
	var opts_w := (_opts_panel.size.x * HUD_SCALE) if _opts_panel != null else 0.0
	_preview_panel.position = Vector2(8.0 + SIDEBAR_W * HUD_SCALE + 8.0 + opts_w + 10.0, 58)


func _tile_under_mouse() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x) + _min_tx, floori(p.y) + _min_ty)


# ─────────────────────────────── tools / brush ──────────────────────────────

func _apply_tool(just_pressed: bool) -> void:
	match _tool:
		Tool.BIOME: _paint(_paint_biome_tile)
		Tool.TERRAIN: _paint(_paint_terrain_tile)
		Tool.ERASE: _paint(_erase_tile)
		Tool.SMOOTHEN: _smoothen_brush()
		Tool.ELEVATE: _elevate_brush()
		Tool.FOREST: _paint(func(x: int, y: int) -> void: _place_decor(x, y, true))
		Tool.CLUTTER: _paint(func(x: int, y: int) -> void: _place_decor(x, y, false))
		Tool.GRASS: _paint(_place_grass)
		Tool.SELECT:
			if just_pressed:
				if _sel_moving:
					_move_selection_to(_hover_tile)
				else:
					_select_object_at(_hover_tile)
		Tool.STAMP:
			if just_pressed:
				_place_stamp(_hover_tile)
				_commit_stroke()
		Tool.STRUCTURE:
			if just_pressed:
				_place_off = Vector2.ZERO   # 2D map clicks snap to the tile centre
				_place_structure(_hover_tile)
				_commit_stroke()
		Tool.SPAWN:
			if just_pressed:
				_set_spawn(_hover_tile)
				_commit_stroke()
		Tool.ROAD:
			if just_pressed:
				_road_pts.clear()
				_road_pts.append(_hover_tile)
				_road_drawing = true
				_status.text = "Drawing road… drag across the map, release to finish."
		Tool.SETTLEMENT:
			if just_pressed:
				_place_settlement(_hover_tile)
				_commit_stroke()
		Tool.CREATURE:
			if just_pressed:
				_place_creature(_hover_tile)
				_commit_stroke()
		Tool.SKILL:
			if just_pressed:
				_place_skill(_hover_tile)
				_commit_stroke()


func _paint(fn: Callable) -> void:
	var r := _brush - 1
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue
			fn.call(_hover_tile.x + dx, _hover_tile.y + dy)


## Trees / Clutter brush: at each brushed tile (gated by the Density slider) drop a BIOME-RESOLVED
## decoration — a tree species from that biome's canopy palette, or a ground-clutter kind from its
## groundDecor palette. Biomes with no canopy (desert/ocean) simply grow no trees, so the brush is
## biome-appropriate by construction. Placed as a `decor` structure → persists in chunk.structures
## (saved to the .world, carried through re-bakes by the authored overlay) and renders via the 3D
## prop batcher, exactly like a hand-placed Structure.
func _place_decor(gtx: int, gty: int, is_tree: bool) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var tkey := "%d:%d" % [gtx, gty]
	if _decor_placed.has(tkey):
		return                                   # already visited this tile this stroke
	_decor_placed[tkey] = true
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var bidx: int = chunk.biome_at(lx, ly)
	if bidx == 255:
		return                                   # no biome on this tile (off-map / ocean gap)
	var tname: String = str(_reg.tile_order[chunk.tile_id(lx, ly)])
	# Keep flora off water, roads/paths and settlement floors (matches the auto-canopy rules).
	if bool(_reg.tile_def(chunk.tile_id(lx, ly)).get("water", false)) \
			or TerrainStyle.is_path(tname) or tname in ["plaza", "plank_floor", "building_wall"]:
		return
	# Trees are sparser than clutter at the same Density setting.
	if randf() > _decor_density * (0.55 if is_tree else 1.0):
		return
	var kinds := _decor_kinds(bidx, is_tree)
	if kinds.is_empty():
		return                                   # this biome grows no trees/clutter
	if is_tree and _tree_at(chunk, lx, ly):
		return                                   # don't stack a second tree on a tile that has one
	# Trees render as `tree` entities (full size, species from prop_kind); clutter as `decor`.
	var part := {
		"kind": ("tree" if is_tree else "decor"), "prop": _weighted_kind(kinds),
		"tx": lx, "ty": ly, "label": "",
		"yaw": randf() * TAU, "variant": randi() % 9973,
		"ox": randf_range(-9.0, 9.0), "oy": randf_range(-9.0, 9.0),   # sub-tile jitter so they don't grid-align
	}
	if not is_equal_approx(_place_scale, 1.0):
		part["scale"] = _place_scale
	chunk.structures.append(part)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "structures", "item": part})


## Biome canopy/groundDecor palette for an effective biome index, falling back to the PARENT biome's
## palette when a sub-biome defines none — so the brush still grows the region's trees/clutter there.
func _decor_kinds(bidx: int, is_tree: bool) -> Array:
	var bid := str(_reg.biomes[bidx]["id"])
	var kinds: Array = (_reg.canopy(bid) if is_tree else _reg.ground_decor(bid)).get("kinds", [])
	if kinds.is_empty():
		var pid: String = _reg.parent_biome_id(bidx)
		if pid != bid and not pid.is_empty():
			kinds = (_reg.canopy(pid) if is_tree else _reg.ground_decor(pid)).get("kinds", [])
	return kinds


## True if a tree is already placed on this chunk-local tile (so the brush doesn't stack trees).
func _tree_at(chunk: RefCounted, lx: int, ly: int) -> bool:
	for s: Dictionary in chunk.structures:
		if str(s.get("kind", "")) == "tree" and int(s.get("tx", -1)) == lx and int(s.get("ty", -1)) == ly:
			return true
	return false


## Weighted random pick of a `kind` string from a [{kind, weight}] palette (biome canopy/groundDecor).
func _weighted_kind(kinds: Array) -> String:
	var total := 0.0
	for k: Dictionary in kinds:
		total += float(k.get("weight", 1.0))
	var roll := randf() * maxf(total, 0.0001)
	for k: Dictionary in kinds:
		roll -= float(k.get("weight", 1.0))
		if roll <= 0.0:
			return str(k["kind"])
	return str(kinds[0]["kind"])


## Grass brush: paint a LUSH meadow by dropping several short wind-swayed grass tufts per tile. Uses
## the `hike_grass` decor (short blades; its foliage material already sways in the wind) and is batched
## by StaticPropBatcher into one MultiMesh per chunk, so dense grass stays cheap. Biome-agnostic so you
## can carpet anywhere; skips water/paths/floors. Records to chunk.structures (saved + undoable).
const GRASS_PROP := "hike_grass"
const GRASS_SCALE := 0.7          # short — meadow grass, not tall reeds

func _place_grass(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var tkey := "%d:%d" % [gtx, gty]
	if _decor_placed.has(tkey):
		return                                   # one tuft-cluster per tile per stroke
	_decor_placed[tkey] = true
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var tname: String = str(_reg.tile_order[chunk.tile_id(lx, ly)])
	if bool(_reg.tile_def(chunk.tile_id(lx, ly)).get("water", false)) \
			or TerrainStyle.is_path(tname) or tname in ["plaza", "plank_floor", "building_wall"]:
		return
	# 2..3 tufts per tile (Density nudges the third) for a lush carpet, jittered off-grid.
	var tufts := 2 + (1 if randf() < _decor_density else 0)
	for _i: int in tufts:
		var part := {
			"kind": "decor", "prop": GRASS_PROP, "tx": lx, "ty": ly, "label": "",
			"yaw": randf() * TAU, "variant": randi() % 9973,
			"ox": randf_range(-11.0, 11.0), "oy": randf_range(-11.0, 11.0),
			"scale": GRASS_SCALE * _place_scale * randf_range(0.85, 1.12),
		}
		chunk.structures.append(part)
		_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "structures", "item": part})


# ───────────────────────── Select / Move tool (edit placed objects) ─────────────────────────

## Grab the placed object nearest the clicked tile (searches the tile + its 8 neighbours across
## chunks, by sub-tile world position). Decor/structures/trees/grass all live in chunk.structures, so
## all are selectable; the palette then offers move / rescale / rotate (R) / delete.
func _select_object_at(tile: Vector2i) -> void:
	var target := WG.tile_to_world(tile.x, tile.y)
	var best_chunk: RefCounted = null
	var best_i := -1
	var best_d := INF
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			var ch: RefCounted = _chunk_at_tile(tile.x + dx, tile.y + dy)
			if ch == null:
				continue
			var lx: int = (tile.x + dx) - ch.cx * WG.CHUNK_TILES
			var ly: int = (tile.y + dy) - ch.cy * WG.CHUNK_TILES
			for i: int in ch.structures.size():
				var s: Dictionary = ch.structures[i]
				if int(s.get("tx", -999)) != lx or int(s.get("ty", -999)) != ly:
					continue
				var wp: Vector2 = ch.tile_world(lx, ly) + Vector2(float(s.get("ox", 0.0)), float(s.get("oy", 0.0)))
				var d := wp.distance_squared_to(target)
				if d < best_d:
					best_d = d
					best_chunk = ch
					best_i = i
	_sel_chunk = best_chunk
	_sel_index = best_i
	_sel_moving = false
	if best_chunk == null:
		_status.text = "Select: nothing here — click a tree / building / decor / grass to grab it."
	else:
		var s: Dictionary = best_chunk.structures[best_i]
		_status.text = "Selected %s — use the panel to Move / rescale / rotate (R) / delete." % str(s.get("prop", s.get("label", s.get("kind", "object"))))
	_refresh_palette()


## Relocate the grabbed object to a new tile (snaps to the tile centre, clears sub-tile jitter; moves
## it between chunks if needed). Armed by the "Move" button; the next click is the destination.
func _move_selection_to(tile: Vector2i) -> void:
	if _sel_chunk == null or _sel_index < 0 or _sel_index >= _sel_chunk.structures.size():
		_sel_moving = false
		return
	var dst: RefCounted = _chunk_at_tile(tile.x, tile.y)
	if dst == null:
		return
	var src := _sel_chunk
	var old_item: Dictionary = src.structures[_sel_index]
	var part: Dictionary = old_item.duplicate(true)
	part["tx"] = tile.x - dst.cx * WG.CHUNK_TILES
	part["ty"] = tile.y - dst.cy * WG.CHUNK_TILES
	part["ox"] = 0.0
	part["oy"] = 0.0
	_begin_stroke()
	_stroke["removed"].append({"key": "%d:%d" % [src.cx, src.cy], "arr": "structures", "item": old_item})
	src.structures.remove_at(_sel_index)
	dst.structures.append(part)
	_stroke["added"].append({"key": "%d:%d" % [dst.cx, dst.cy], "arr": "structures", "item": part})
	_sel_chunk = dst
	_sel_index = dst.structures.size() - 1
	_sel_moving = false
	_commit_stroke()
	_refresh_struct_chunks([{"key": "%d:%d" % [src.cx, src.cy]}, {"key": "%d:%d" % [dst.cx, dst.cy]}])
	_status.text = "Moved to (%d, %d)." % [tile.x, tile.y]
	_refresh_palette()


## Delete the grabbed object (undoable via the stroke history).
func _delete_selection() -> void:
	if _sel_chunk == null or _sel_index < 0 or _sel_index >= _sel_chunk.structures.size():
		return
	var ch := _sel_chunk
	var key := "%d:%d" % [ch.cx, ch.cy]
	_begin_stroke()
	_stroke["removed"].append({"key": key, "arr": "structures", "item": ch.structures[_sel_index]})
	ch.structures.remove_at(_sel_index)
	_commit_stroke()
	_sel_chunk = null
	_sel_index = -1
	_sel_moving = false
	_refresh_struct_chunks([{"key": key}])
	_status.text = "Deleted."
	_refresh_palette()


## Live-rescale the grabbed object (not pushed to undo — re-select to adjust).
func _rescale_selection(scale: float) -> void:
	if _sel_chunk == null or _sel_index < 0 or _sel_index >= _sel_chunk.structures.size():
		return
	var part: Dictionary = _sel_chunk.structures[_sel_index]
	part["scale"] = scale
	_sel_chunk.structures[_sel_index] = part
	_refresh_struct_chunks([{"key": "%d:%d" % [_sel_chunk.cx, _sel_chunk.cy]}])


# ─────────────────────────────── smoothen tool ──────────────────────────────
# Brush that REMOVES elevation: every brushed tile is pulled toward the average of
# its 3×3 neighbourhood and eroded a notch, never raised. Repeated strokes melt a
# raised bump back to ground level and feather its edges. Elevation is part of the
# baked chunk (chunk.elev) — Save writes it straight back, no re-bake needed.

func _elev_at(gtx: int, gty: int) -> int:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null or chunk.elev.size() == 0:
		return 0
	var ci: int = Chunk.idx(gtx - chunk.cx * WG.CHUNK_TILES, gty - chunk.cy * WG.CHUNK_TILES)
	return int(chunk.elev[ci]) if chunk.elev.size() > ci else 0


# Compute the smoothed/lowered elevation for one tile from the CURRENT terrain (all
# neighbour reads happen before any write, so a stroke is order-independent).
# Returns -1 to leave the tile alone (off-map, already flat).
func _smoothen_value(gtx: int, gty: int) -> int:
	var e := _elev_at(gtx, gty)
	if e <= 0:
		return -1   # already ground — nothing to remove
	var sum := 0
	var cnt := 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			sum += _elev_at(gtx + dx, gty + dy)
			cnt += 1
	var avg := float(sum) / float(cnt)
	# Feather toward the neighbourhood (never above current height) and then take a firm
	# step DOWN. A broad uniform plateau or mountain has avg ≈ e, so a pure blend would
	# stall — the explicit −1 floor guarantees every pass actually removes elevation, so
	# the brush bites into mountains too, not just isolated spikes.
	var lowered := lerpf(float(e), minf(float(e), avg), 0.5) - 1.0
	var ne := clampi(int(round(lowered)), 0, e)
	if ne >= e:
		ne = e - 1   # always make progress while there is height to remove
	return ne


func _smoothen_brush() -> void:
	var r := _brush - 1
	var edits: Array = []
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue
			var gx := _hover_tile.x + dx
			var gy := _hover_tile.y + dy
			var ne := _smoothen_value(gx, gy)
			if ne >= 0 and ne != _elev_at(gx, gy):
				edits.append([gx, gy, ne])
	for e: Array in edits:
		_record_elev(int(e[0]), int(e[1]), int(e[2]))


func _record_elev(gtx: int, gty: int, new_elev: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	if chunk.elev.size() == 0:
		# A fully-flat baked chunk may ship with no elevation array — allocate a zeroed
		# one so the Elevate brush can raise mountains out of previously flat ground.
		chunk.elev.resize(WG.CHUNK_TILES * WG.CHUNK_TILES)
	var ci: int = Chunk.idx(gtx - chunk.cx * WG.CHUNK_TILES, gty - chunk.cy * WG.CHUNK_TILES)
	if ci >= chunk.elev.size():
		return
	var new_state: Array = _tile_state(chunk, ci)
	new_state[4] = new_elev
	_record_and_set(gtx, gty, new_state)


# ─────────────────────────────── elevate tool ───────────────────────────────
# Brush that RAISES terrain into hills and mountains. A dome falloff makes the brush
# centre rise fastest and the rim feather to nothing, so repeated passes build a smooth
# natural peak (with grass→rock→snow shading driven by height) rather than a flat mesa.
# Elevation is the single source of truth for mountains, so raising it is all we need —
# the mesher, colouring and in-game climb/cliff rules follow from chunk.elev.

func _elevate_brush() -> void:
	var r := _brush - 1
	var edits: Array = []
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 > r * r + r:
				continue
			var gx := _hover_tile.x + dx
			var gy := _hover_tile.y + dy
			var ne := _elevate_value(gx, gy, d2, r)
			if ne >= 0 and ne != _elev_at(gx, gy):
				edits.append([gx, gy, ne])
	for e: Array in edits:
		_record_elev(int(e[0]), int(e[1]), int(e[2]))


func _elevate_value(gtx: int, gty: int, d2: int, r: int) -> int:
	var falloff := 1.0 - sqrt(float(d2)) / float(maxi(r, 1) + 1)   # 1 centre .. ~0 rim
	if falloff <= 0.0:
		return -1
	var cur := _elev_at(gtx, gty)
	var rise := 1 + int(round(falloff * 2.0))   # +1 at the rim .. +3 at the centre per pass
	return clampi(cur + rise, 0, MountainField.ELEV_MAX_STEPS)


func _chunk_at_tile(gtx: int, gty: int) -> RefCounted:
	var c := WG.tile_to_chunk(Vector2i(gtx, gty))
	return _chunks.get("%d:%d" % [c.x, c.y], null)


func _tile_def_at(gtx: int, gty: int) -> Dictionary:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return {}
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	return _reg.tile_def(chunk.tile_id(lx, ly))


func _is_walkable_tile(gtx: int, gty: int) -> bool:
	var td := _tile_def_at(gtx, gty)
	if td.is_empty():
		return false
	return bool(td.get("walkable", false)) and not bool(td.get("water", false)) and not bool(td.get("hazard", false))


func _tile_state(chunk: RefCounted, ci: int) -> Array:
	# 5th element is elevation so the Smoothen tool's lowering is captured for undo.
	# Terrain/biome paints pass 4-element states and leave elevation untouched.
	return [chunk.tiles[ci], chunk.biomes_t[ci], chunk.parent_biomes_t[ci], chunk.sub_biomes_t[ci],
		(int(chunk.elev[ci]) if chunk.elev.size() > ci else 0)]


func _apply_state(gtx: int, gty: int, state: Array) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var ci: int = Chunk.idx(lx, ly)
	chunk.tiles[ci] = int(state[0])
	chunk.biomes_t[ci] = int(state[1])
	chunk.parent_biomes_t[ci] = int(state[2])
	chunk.sub_biomes_t[ci] = int(state[3])
	if state.size() > 4 and chunk.elev.size() > ci:
		chunk.elev[ci] = int(state[4])   # Smoothen tool edits elevation; flattening can free a canopy tile
	_canopy_cache.erase(chunk.key())   # tile/biome/elevation change can add/remove this chunk's trees
	_set_px(gtx, gty, _tile_color(int(state[0])))


## Capture the before-state once per tile in the active stroke, apply new state,
## and record after-state — so the whole drag collapses into one undo step.
func _record_and_set(gtx: int, gty: int, new_state: Array) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var ci: int = Chunk.idx(lx, ly)
	var key := Vector2i(gtx, gty)
	if not _stroke["tiles"].has(key):
		_stroke["tiles"][key] = [_tile_state(chunk, ci), null]
	_apply_state(gtx, gty, new_state)
	_stroke["tiles"][key][1] = new_state.duplicate()


func _paint_terrain_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var tid := int(_reg.tile_index.get(_sel_terrain, -1))
	if tid < 0:
		return
	var ci: int = Chunk.idx(gtx - chunk.cx * WG.CHUNK_TILES, gty - chunk.cy * WG.CHUNK_TILES)
	_record_and_set(gtx, gty, [tid, chunk.biomes_t[ci], chunk.parent_biomes_t[ci], chunk.sub_biomes_t[ci]])


func _paint_biome_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var idx := int(_reg.biome_index.get(_sel_biome, -1))
	if idx < 0:
		return
	# Soft, noisy brush edge: paint solidly in the core, then dither out across the outer ring so
	# the new biome MIXES into whatever is already there rather than stamping a hard circle. Uses
	# two hash scales for a less regular, more organic falloff.
	var br := float(_brush - 1)
	if br >= 2.0:
		var dist := Vector2(gtx - _hover_tile.x, gty - _hover_tile.y).length()
		var edge := (dist / br - 0.45) / 0.55      # 0 at ~45% radius .. 1 at the rim
		if edge > 0.0:
			var sd: int = WorldGen.store.world_seed
			var n := 0.6 * WG.r01(sd, gtx, gty, 9311) + 0.4 * WG.r01(sd, gtx >> 1, gty >> 1, 9319)
			if n < clampf(edge, 0.0, 1.0):
				return   # leave this tile's existing biome (dithered falloff = blend with surroundings)
	var is_sub: bool = bool(_reg.biomes[idx].get("isSubBiome", false))
	var parent := idx
	var sub := 255
	if is_sub:
		parent = int(_reg.biome_index.get(str(_reg.biomes[idx].get("parentBiome", "")), idx))
		sub = idx
	_record_and_set(gtx, gty, [_biome_primary_tile(idx), idx, parent, sub])


func _biome_primary_tile(idx: int) -> int:
	var weights: Array = _reg.biomes[idx].get("_tile_weights", [])
	if weights.is_empty():
		return int(_reg.tile_index.get("grass", 0))
	return int(weights[0][0])


func _erase_tile(gtx: int, gty: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var lx: int = gtx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gty - chunk.cy * WG.CHUNK_TILES
	var key := "%d:%d" % [chunk.cx, chunk.cy]
	_erase_from(chunk, "structures", lx, ly, key)
	_erase_from(chunk, "monsters", lx, ly, key)
	_cut_tree(chunk, lx, ly, key)
	FiniteWorldGenerator.apply_structure_collision(chunk)
	if _erase_keep_terrain:
		return   # opt-out: only the placed objects above were removed; leave the terrain as-is
	# Revert the tile to its ORIGINAL generated state — this wipes painted roads/terrain/biome AND
	# any smoothen/elevate edits, restoring the procedural surface tile, biome, and authored
	# elevation (from the elevation mask where one exists, else the procedural mountain field).
	var cls: RefCounted = WorldGen.generator.classifier
	var gtid: int = WorldGen.surface_tile_id(gtx, gty)
	var gb: int = cls.biome_idx(float(gtx), float(gty))
	var gp: int = cls.parent_biome_idx(float(gtx), float(gty))
	var ge: int = cls.mask_elev_steps(float(gtx), float(gty)) if cls.has_elev_mask() else cls.elevation_steps(float(gtx), float(gty))
	_record_and_set(gtx, gty, [gtid, gb, gp, 255, ge])


func _erase_from(chunk: RefCounted, arr_name: String, lx: int, ly: int, key: String) -> void:
	var arr: Array = _chunk_array(chunk, arr_name)
	for i: int in range(arr.size() - 1, -1, -1):
		var item: Dictionary = arr[i]
		if int(item.get("tx", -999)) == lx and int(item.get("ty", -999)) == ly:
			_stroke["removed"].append({"key": key, "arr": arr_name, "item": item})
			arr.remove_at(i)


## True when the procedural ambient-canopy pass would grow a tree on this local tile —
## the SAME gate as world_entity_spawner._spawn_canopy_tile, so the map matches the game.
## Ignores cuts (those are filtered by the caller); this is the cacheable, pure part.
func _canopy_raw(chunk: RefCounted, lx: int, ly: int) -> bool:
	var ci := ly * WG.CHUNK_TILES + lx
	if chunk.elev.size() > 0 and int(chunk.elev[ci]) > 0:
		return false
	var tid: int = chunk.tile_id(lx, ly)
	var tile: Dictionary = _reg.tile_def(tid)
	if bool(tile.get("water", false)) or not bool(tile.get("walkable", true)) or bool(tile.get("hazard", false)):
		return false
	if _reg.tile_order[tid] in ["dirt", "cobble", "mud", "gravel", "badland_clay", "plaza", "plank_floor", "building_wall"]:
		return false
	var b_idx: int = chunk.biome_at(lx, ly)
	if b_idx == 255:
		return false
	var cfg: Dictionary = _reg.canopy(str(_reg.biomes[b_idx]["id"]))
	var density := float(cfg.get("density", 0.0))
	if density <= 0.0:
		return false
	var seed: int = WorldGen.store.world_seed
	var eff := density * WG.canopy_density_mul(seed, chunk.cx * WG.CHUNK_TILES + lx, chunk.cy * WG.CHUNK_TILES + ly)
	return WG.r01(seed, chunk.cx * 271 + lx, chunk.cy * 283 + ly, 211) <= eff


## Cached list of a chunk's canopy tile indices (cuts NOT applied). Computed once per chunk
## and reused every redraw; invalidated by _apply_state when the chunk's terrain/biome edits.
func _chunk_canopy(chunk: RefCounted) -> PackedInt32Array:
	var k: String = chunk.key()
	var cached: Variant = _canopy_cache.get(k)
	if cached != null:
		return cached
	var out := PackedInt32Array()
	for ly: int in WG.CHUNK_TILES:
		for lx: int in WG.CHUNK_TILES:
			if _canopy_raw(chunk, lx, ly):
				out.append(ly * WG.CHUNK_TILES + lx)
	_canopy_cache[k] = out
	return out


## Eraser: cut the ambient tree on this tile (records for undo). No-op if the tile has
## no canopy or is already cut, so the cuts set stays sparse.
func _cut_tree(chunk: RefCounted, lx: int, ly: int, key: String) -> void:
	var ci := ly * WG.CHUNK_TILES + lx
	if chunk.tree_cuts.has(ci) or not _canopy_raw(chunk, lx, ly):
		return
	chunk.tree_cuts[ci] = true
	_stroke["cuts"].append({"key": key, "ci": ci})


func _chunk_array(chunk: RefCounted, arr_name: String) -> Array:
	match arr_name:
		"monsters": return chunk.monsters
		"sites": return chunk.sites
		_: return chunk.structures


# ─────────────────────────────── stamps ──────────────────────────────────────

## Paint a reusable natural stamp (pond, grove, outcrop…) at the cursor. Tiles +
## biomes go down as recorded tile edits; resource counts drop gather sites.
## Each placement bumps the variant so repeats vary; R rotates, F flips.
func _place_stamp(center: Vector2i) -> void:
	var stamps: Array = StampLibrary.all()
	if stamps.is_empty() or _sel_stamp >= stamps.size():
		return
	var stamp: Dictionary = stamps[_sel_stamp]
	var built: Dictionary = StampLibrary.build(stamp, _stamp_variant, _stamp_rot, _stamp_flip)
	for c: Dictionary in built["cells"]:
		var gx: int = center.x + int(c["dx"])
		var gy: int = center.y + int(c["dy"])
		var chunk: RefCounted = _chunk_at_tile(gx, gy)
		if chunk == null:
			continue
		var ci: int = Chunk.idx(gx - chunk.cx * WG.CHUNK_TILES, gy - chunk.cy * WG.CHUNK_TILES)
		var tile_name := str(c["tile"])
		var tid: int = int(chunk.tiles[ci])
		if not tile_name.is_empty() and _reg.tile_index.has(tile_name):
			tid = int(_reg.tile_index[tile_name])
		var biome_name := str(c.get("biome", ""))
		var b: int = int(chunk.biomes_t[ci])
		var p: int = int(chunk.parent_biomes_t[ci])
		var s: int = int(chunk.sub_biomes_t[ci])
		if not biome_name.is_empty() and _reg.biome_index.has(biome_name):
			b = int(_reg.biome_index[biome_name])
			p = b
			s = 255
		_record_and_set(gx, gy, [tid, b, p, s])
	for site: Dictionary in built["sites"]:
		_add_stamp_site(center.x + int(site["dx"]), center.y + int(site["dy"]), str(site["skill"]))
	_stamp_variant += 1
	_status.text = "Stamped %s (variant %d)" % [str(stamp["name"]), _stamp_variant]


## Add a natural gather site for a skill at a tile (editor stamp). Picks the
## lowest-level node of that skill so it's valid anywhere, builds the standard
## site dict, and records it for undo.
func _add_stamp_site(gx: int, gy: int, skill: String) -> void:
	var chunk: RefCounted = _chunk_at_tile(gx, gy)
	if chunk == null:
		return
	var entries: Array = _reg.node_table.get(skill, [])
	if entries.is_empty():
		return
	var best: Dictionary = entries[0]
	for e: Dictionary in entries:
		if int(e["level"]) < int(best["level"]):
			best = e
	var cfg: Dictionary = _reg.skill_cfg(skill)
	var lx: int = gx - chunk.cx * WG.CHUNK_TILES
	var ly: int = gy - chunk.cy * WG.CHUNK_TILES
	var site := {
		"skill": skill, "node": best["name"], "level": int(best["level"]),
		"kind": str(cfg.get("kind", "bush")), "tx": lx, "ty": ly,
		"resources": int(cfg.get("resources", 8)), "remaining": int(cfg.get("resources", 8)),
		"respawn_sec": float(cfg.get("respawnSec", 25.0)), "available": true, "respawn_at": 0.0,
	}
	chunk.sites.append(site)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "sites", "item": site})


func _place_structure(t: Vector2i) -> void:
	var chunk: RefCounted = _chunk_at_tile(t.x, t.y)
	if chunk == null:
		return
	var entry: Array = STRUCTURES[_sel_struct]
	var part: Dictionary = (entry[1] as Dictionary).duplicate(true)
	part["tx"] = t.x - chunk.cx * WG.CHUNK_TILES
	part["ty"] = t.y - chunk.cy * WG.CHUNK_TILES
	if not part.has("label"):
		part["label"] = ""
	# Match what the hover ghost showed: the rerolled roof colour and the scroll/R rotation.
	if part["kind"] in ["house", "building", "tent"]:
		part["color"] = ROOF_COLORS[_ghost_variant % ROOF_COLORS.size()]
	part["yaw"] = _struct_yaw()         # fine 15°-step rotation (scroll / R)
	part["variant"] = _ghost_variant   # spawn the exact model the ghost previewed
	if _place_off != Vector2.ZERO:
		part["ox"] = _place_off.x       # free placement: sub-tile iso offset from the tile centre
		part["oy"] = _place_off.y
	if not is_equal_approx(_place_scale, 1.0):
		part["scale"] = _place_scale
	chunk.structures.append(part)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "structures", "item": part})
	# Buildings/walls collide via non-walkable wall tiles (same as the baked city),
	# so editor-placed ones get real collision too. Lone props use the derived
	# collision layer. Footprint tile changes are recorded in the stroke (undoable).
	var kind: String = str(part["kind"])
	if kind in ["building", "house", "city_wall"]:
		var wall := int(_reg.tile_index.get("building_wall", -1))
		var floor_tile := int(_reg.tile_index.get("plank_floor", _reg.tile_index.get("cobble", -1)))
		var r := 1 if kind != "building" else maxi(1, int(part.get("foot", 6)) / 2)
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var gx: int = t.x + dx
				var gy: int = t.y + dy
				var ch2: RefCounted = _chunk_at_tile(gx, gy)
				if ch2 != null and wall >= 0:
					var tile_id := wall
					if kind in ["building", "house"]:
						var edge := dx == -r or dx == r or dy == -r or dy == r
						var in_door := false
						var door_x := -maxi(0, r / 2)
						var door_depth := 3 if kind == "building" else 2
						for i: int in range(-1, 2):
							in_door = in_door or (dx == door_x + i and dy == r)
							in_door = in_door or (dx == door_x + i and dy == r - 1)
						if kind == "building":
							in_door = in_door or (dx == door_x and dy == r - door_depth + 1)
						tile_id = floor_tile if (not edge or in_door) and floor_tile >= 0 else wall
					var ci2: int = Chunk.idx(gx - ch2.cx * WG.CHUNK_TILES, gy - ch2.cy * WG.CHUNK_TILES)
					_record_and_set(gx, gy, [tile_id, ch2.biomes_t[ci2], ch2.parent_biomes_t[ci2], ch2.sub_biomes_t[ci2]])
	FiniteWorldGenerator.apply_structure_collision(chunk)
	_status.text = "Placed %s at (%d, %d)" % [str(entry[0]), t.x, t.y]


func _set_spawn(t: Vector2i) -> void:
	if not _is_walkable_tile(t.x, t.y):
		_status.text = "Spawn must be on walkable land (not water/hazard)."
		return
	_stroke["spawn"] = [_spawn_tile, t]
	_spawn_tile = t
	_status.text = "Player spawn set to (%d, %d)" % [t.x, t.y]
	_update_spawn_marker3d()   # snap the 3D beacon to the new spot right away


func _set_px(gtx: int, gty: int, col: Color) -> void:
	var ix := gtx - _min_tx
	var iy := gty - _min_ty
	if ix < 0 or iy < 0 or ix >= _w or iy >= _h:
		return
	_img.set_pixel(ix, iy, col)
	_img_dirty = true


# ─────────────────────────────── undo / redo ────────────────────────────────

func _begin_stroke() -> void:
	_stroke = {"tiles": {}, "added": [], "removed": [], "cuts": [], "spawn": null, "road": null}
	_decor_placed.clear()
	_stroke_active = true


func _stroke_empty() -> bool:
	return _stroke["tiles"].is_empty() and _stroke["added"].is_empty() \
		and _stroke["removed"].is_empty() and _stroke["cuts"].is_empty() and _stroke["spawn"] == null


func _commit_stroke() -> void:
	if not _stroke_active:
		return
	if _road_drawing:
		_finalize_road()
		_road_drawing = false
	_stroke_active = false
	if _stroke_empty():
		return
	_history.append(_stroke)
	_redo.clear()
	if _history.size() > 200:
		_history.pop_front()
	_resync_3d_tiles(_stroke["tiles"].keys())
	# Biome/terrain edits change which NATIVE trees + clutter a tile grows, so respawn the touched
	# chunks' procedural decor to match the new biome. Editor-placed structures/trees/roads live in
	# chunk data and are re-emitted unchanged, so only the biome's own scatter is swapped.
	if _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE]:
		_refresh_painted_entities(_stroke["tiles"].keys())
	# Trees/Clutter brushes + the Creature tool add records to chunk data — respawn the touched
	# chunks so the new trees/clutter/enemies appear in the 3D view immediately.
	if _tool in [Tool.FOREST, Tool.CLUTTER, Tool.GRASS, Tool.CREATURE, Tool.SKILL]:
		_refresh_struct_chunks(_stroke["added"])
	if _map_overlay != null:
		_map_overlay.queue_redraw()   # keep the world-map markers in sync with the edit (no-op when hidden)
	_refresh_history_buttons()


func _do_undo() -> void:
	if _history.is_empty():
		return
	var s: Dictionary = _history.pop_back()
	for key: Vector2i in s["tiles"]:
		_apply_state(key.x, key.y, s["tiles"][key][0])
	for a: Dictionary in s["added"]:
		_chunk_array(_chunks[a["key"]], a["arr"]).erase(a["item"])
	for r: Dictionary in s["removed"]:
		_chunk_array(_chunks[r["key"]], r["arr"]).append(r["item"])
	for cut: Dictionary in s.get("cuts", []):
		_chunks[cut["key"]].tree_cuts.erase(int(cut["ci"]))   # undo: regrow the cut tree
	if s["spawn"] != null:
		_spawn_tile = s["spawn"][0]
	if s.get("road") != null:
		_spec.roads.erase(s["road"])
	_refresh_stroke_collision(s)
	_resync_3d_tiles(s["tiles"].keys())
	_refresh_struct_chunks(s["added"])     # show added/removed decor (trees, clutter, structures)
	_refresh_struct_chunks(s["removed"])
	_redo.append(s)
	_status.text = "Undid 1 action (%d left)" % _history.size()
	if _map_overlay != null:
		_map_overlay.queue_redraw()
	_refresh_history_buttons()


func _do_redo() -> void:
	if _redo.is_empty():
		return
	var s: Dictionary = _redo.pop_back()
	for key: Vector2i in s["tiles"]:
		_apply_state(key.x, key.y, s["tiles"][key][1])
	for a: Dictionary in s["added"]:
		_chunk_array(_chunks[a["key"]], a["arr"]).append(a["item"])
	for r: Dictionary in s["removed"]:
		_chunk_array(_chunks[r["key"]], r["arr"]).erase(r["item"])
	for cut: Dictionary in s.get("cuts", []):
		_chunks[cut["key"]].tree_cuts[int(cut["ci"])] = true   # redo: re-cut the tree
	if s["spawn"] != null:
		_spawn_tile = s["spawn"][1]
	if s.get("road") != null:
		_spec.roads.append(s["road"])
	_refresh_stroke_collision(s)
	_resync_3d_tiles(s["tiles"].keys())
	_refresh_struct_chunks(s["added"])
	_refresh_struct_chunks(s["removed"])
	_history.append(s)
	_status.text = "Redid 1 action"
	if _map_overlay != null:
		_map_overlay.queue_redraw()
	_refresh_history_buttons()


## Recompute collision for chunks touched by an undone/redone stroke's structures.
func _refresh_stroke_collision(s: Dictionary) -> void:
	var keys: Dictionary = {}
	for a: Dictionary in s["added"]:
		keys[a["key"]] = true
	for r: Dictionary in s["removed"]:
		keys[r["key"]] = true
	for key: String in keys:
		if _chunks.has(key):
			FiniteWorldGenerator.apply_structure_collision(_chunks[key])


# ─────────────────────────────── road tool ──────────────────────────────────
# Drawn strokes are simplified to coarse waypoints, then compiled through the SAME
# RoadBrush the bake uses (Catmull-Rom curve, variable width, feathered rim, auto
# bridges over water). The road is stored as an editable polyline in spec.roads and
# persisted to the worldspec on save — so material/wear/width stay swappable.

func _finalize_road() -> void:
	var pts := _simplify(_road_pts, 2.0)
	if pts.size() < 2:
		_status.text = "Road too short — drag to draw a longer path."
		return
	var road := {
		"id": "road_%d" % _spec.roads.size(),
		"kind": "minor",
		"style": _sel_road_style,
		"width": _road_width,
		"points": pts,
	}
	_spec.roads.append(road)
	_stroke["road"] = road
	var brush := RoadBrush.new()
	# Roads KEEP the terrain elevation and just repaint the surface tile, so they conform to the
	# existing hill surface (the mesher smooths the terraced steps into a curve) instead of cutting
	# their own graded channel. (Grading is left in RoadBrush behind an elevation sampler if ever
	# wanted, but is intentionally not used here.)
	brush.build_roads(_reg, WorldGen.store.world_seed, [road])
	for k: Vector2i in brush.road_tiles:
		_set_road_tile(k.x, k.y, int(brush.road_tiles[k]))
	for ckey: String in brush.structures:
		if _chunks.has(ckey):
			for part: Dictionary in brush.structures[ckey]:
				_chunks[ckey].structures.append(part)
				_stroke["added"].append({"key": ckey, "arr": "structures", "item": part})
	_status.text = "Road '%s' drawn (%s, %d pts) → %d tiles" % [
		road["id"], _sel_road_style, pts.size(), brush.road_tiles.size()]


## Repaint one tile as road/bridge surface, KEEPING the chunk's biome + elevation,
## recorded into the active stroke so the whole road is one undo step.
func _set_road_tile(gtx: int, gty: int, tile_id: int) -> void:
	var chunk: RefCounted = _chunk_at_tile(gtx, gty)
	if chunk == null:
		return
	var ci: int = Chunk.idx(gtx - chunk.cx * WG.CHUNK_TILES, gty - chunk.cy * WG.CHUNK_TILES)
	_record_and_set(gtx, gty, [tile_id, chunk.biomes_t[ci], chunk.parent_biomes_t[ci], chunk.sub_biomes_t[ci]])


func _road_styles() -> Dictionary:
	if _road_styles_cache.is_empty():
		var path := "res://data/world/road_styles.json"
		if FileAccess.file_exists(path):
			var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if p is Dictionary:
				_road_styles_cache = (p as Dictionary).get("styles", {})
	return _road_styles_cache


## Douglas-Peucker: drop the hand-jitter from a freehand stroke down to the few
## waypoints that define its shape; the brush re-smooths them into a flowing curve.
func _simplify(pts: Array, eps: float) -> Array:
	if pts.size() <= 2:
		return pts.duplicate()
	var a := Vector2(pts[0])
	var b := Vector2(pts[pts.size() - 1])
	var dmax := 0.0
	var idx := 0
	for i: int in range(1, pts.size() - 1):
		var d := _perp_dist(Vector2(pts[i]), a, b)
		if d > dmax:
			dmax = d
			idx = i
	if dmax > eps:
		var left := _simplify(pts.slice(0, idx + 1), eps)
		var right := _simplify(pts.slice(idx), eps)
		left.resize(left.size() - 1)   # drop the shared junction point
		return left + right
	return [pts[0], pts[pts.size() - 1]]


func _perp_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	if a.is_equal_approx(b):
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


## Write the live road polylines back into the worldspec JSON so they persist and
## stay re-styleable (the dirt is recomputed from road_styles.json on every bake).
func _persist_roads_to_worldspec() -> void:
	var path := "res://data/world/worldspec/%s.json" % str(_spec.id)
	if not FileAccess.file_exists(path):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (p is Dictionary):
		return
	var doc: Dictionary = p
	var arr: Array = []
	for r: Dictionary in _spec.roads:
		var jpts: Array = []
		for pt: Vector2i in r.get("points", []):
			jpts.append([pt.x, pt.y])
		arr.append({
			"id": str(r.get("id", "")),
			"kind": str(r.get("kind", "minor")),
			"style": str(r.get("style", "")),
			"width": int(r.get("width", 0)),
			"points": jpts,
		})
	doc["roads"] = arr
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()


## Headless smoke-test of the whole road draw path: synthesize a wavy stroke,
## run it through commit (which finalizes via RoadBrush), then undo it.
func _run_road_selftest() -> void:
	var pts: Array[Vector2i] = []
	for i: int in range(0, 66, 3):
		pts.append(Vector2i(-32 + i, 6 + int(round(3.0 * sin(i * 0.18)))))
	_road_pts = pts
	_begin_stroke()
	_road_drawing = true
	var before: int = _spec.roads.size()
	_commit_stroke()
	var tiles := 0
	if not _history.is_empty():
		tiles = int((_history[_history.size() - 1] as Dictionary)["tiles"].size())
	var added: bool = _spec.roads.size() == before + 1
	print("[we-selftest:road] roads %d->%d  tiles_painted=%d" % [before, _spec.roads.size(), tiles])
	_do_undo()
	var undone: bool = _spec.roads.size() == before
	print("[we-selftest:road] after undo roads=%d  RESULT=%s" % [
		_spec.roads.size(), ("PASS" if (added and tiles > 0 and undone) else "FAIL")])
	get_tree().quit()


# ─────────────────────────── settlement templates ───────────────────────────
# Stamp a placeholder settlement (camp/hamlet/village/town/city) as a cluster of
# NORMAL structures, so each placement stays hand-editable afterwards. Sizes come
# from data/world/settlement_templates.json (radius + building counts + wall).

func _settlement_templates() -> Dictionary:
	if _settlement_cache.is_empty():
		var path := "res://data/world/settlement_templates.json"
		if FileAccess.file_exists(path):
			var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if p is Dictionary:
				_settlement_cache = p
	return _settlement_cache


func _place_settlement(center: Vector2i) -> void:
	var doc := _settlement_templates()
	var def: Dictionary = (doc.get("templates", {}) as Dictionary).get(_sel_settlement, {})
	if def.is_empty():
		_status.text = "No settlement template '%s'." % _sel_settlement
		return
	var occupied: Dictionary = {}
	var touched: Dictionary = {}
	var placed := 0
	for part: Dictionary in _build_settlement(def, center, _settlement_rot):
		var tx: int = int(part["tx"])
		var ty: int = int(part["ty"])
		var cell := Vector2i(tx, ty)
		if occupied.has(cell):
			continue
		var chunk: RefCounted = _chunk_at_tile(tx, ty)
		if chunk == null:
			continue
		var td := _tile_def_at(tx, ty)
		if td.is_empty() or not bool(td.get("walkable", false)) or bool(td.get("water", false)) or bool(td.get("hazard", false)):
			continue   # skip parts that would land in water / off the map / on a cliff
		occupied[cell] = true
		var lp := part.duplicate()
		lp["tx"] = tx - chunk.cx * WG.CHUNK_TILES
		lp["ty"] = ty - chunk.cy * WG.CHUNK_TILES
		lp["variant"] = _part_variant(tx, ty)   # match the model the settlement ghost previewed
		chunk.structures.append(lp)
		var ckey := "%d:%d" % [chunk.cx, chunk.cy]
		touched[ckey] = true
		_stroke["added"].append({"key": ckey, "arr": "structures", "item": lp})
		placed += 1
	for ck: String in touched:
		if _chunks.has(ck):
			FiniteWorldGenerator.apply_structure_collision(_chunks[ck])
	_status.text = "Placed %s (%d parts) at (%d, %d) - edit buildings with the Structure/Erase tools." % [
		str(def.get("label", _sel_settlement)), placed, center.x, center.y]


## Expand a template into structure parts (relative dx/dy), then rotate + resolve
## to absolute world tiles. Layout is deterministic per placement position.
func _build_settlement(def: Dictionary, center: Vector2i, rot: int) -> Array:
	var parts: Array = []
	var R: int = int(def.get("radius", 5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(center)
	# centre feature
	if bool(def.get("fountain", false)):
		parts.append({"kind": "fountain", "label": str(def.get("label", "")), "dx": 0, "dy": 0})
	elif bool(def.get("well", false)):
		parts.append({"kind": "city_prop", "prop": "well", "dx": 0, "dy": 0})
	elif bool(def.get("campfire", false)):
		parts.append({"kind": "campfire", "dx": 0, "dy": 0})
	# houses in concentric rings
	var houses: int = int(def.get("houses", 0))
	var placed := 0
	var ring := 3
	while placed < houses and ring <= R + 1:
		var circ: int = maxi(4, int(floor(TAU * float(ring) / 3.5)))
		for k: int in circ:
			if placed >= houses:
				break
			var ang := (float(k) / float(circ)) * TAU + rng.randf_range(-0.15, 0.15)
			var rr := float(ring) + rng.randf_range(-1.0, 1.0)
			parts.append({"kind": "house", "color": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()],
				"dx": int(round(cos(ang) * rr)), "dy": int(round(sin(ang) * rr))})
			placed += 1
		ring += 3
	# great halls
	var halls: int = int(def.get("halls", 0))
	for i: int in halls:
		var a := (float(i) / float(maxi(1, halls))) * TAU + 0.4
		parts.append({"kind": "building", "foot": 7, "color": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()],
			"dx": int(round(cos(a) * float(R - 2))), "dy": int(round(sin(a) * float(R - 2)))})
	# tents (camp)
	for i: int in int(def.get("tents", 0)):
		var a := rng.randf() * TAU
		parts.append({"kind": "tent", "dx": int(round(cos(a) * 2.0)), "dy": int(round(sin(a) * 2.0)) + 1})
	# market stalls + services near the centre
	for i: int in int(def.get("stalls", 0)):
		parts.append({"kind": "stall", "label": "Stall",
			"dx": rng.randi_range(-2, 2), "dy": rng.randi_range(-2, 2)})
	if bool(def.get("anvil", false)):
		parts.append({"kind": "anvil", "station": "anvil", "label": "Anvil", "dx": 2, "dy": -2})
	if bool(def.get("chest", false)):
		parts.append({"kind": "chest", "station": "bank", "label": "Bank", "dx": -2, "dy": -2})
	# lamps on a mid ring
	var lamps: int = int(def.get("lamps", 0))
	for i: int in lamps:
		var a := (float(i) / float(maxi(1, lamps))) * TAU
		parts.append({"kind": "city_prop", "prop": "lamp",
			"dx": int(round(cos(a) * float(R) * 0.6)), "dy": int(round(sin(a) * float(R) * 0.6))})
	# wall ring
	match str(def.get("wall", "")):
		"full": _ring_wall(parts, R, true)
		"partial": _ring_wall(parts, R, false)
	# entrance signpost
	if bool(def.get("sign", false)):
		parts.append({"kind": "sign", "label": str(def.get("label", "Settlement")), "dx": 0, "dy": R})
	# rotate offsets, resolve to absolute world tiles
	var out: Array = []
	for p: Dictionary in parts:
		var v := _rot_offset(int(p.get("dx", 0)), int(p.get("dy", 0)), rot)
		var q := p.duplicate()
		q.erase("dx")
		q.erase("dy")
		q["tx"] = center.x + v.x
		q["ty"] = center.y + v.y
		out.append(q)
	return out


func _ring_wall(parts: Array, R: int, full: bool) -> void:
	var n: int = maxi(8, int(floor(TAU * float(R) / 1.3)))
	for k: int in n:
		var ang := (float(k) / float(n)) * TAU
		parts.append({"kind": "city_wall", "piece": 0,
			"dx": int(round(cos(ang) * float(R))), "dy": int(round(sin(ang) * float(R)))})
	if full:
		for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:            # cardinal gates
			parts.append({"kind": "city_wall", "piece": 1,
				"dx": int(round(cos(a) * float(R))), "dy": int(round(sin(a) * float(R)))})
		for a: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:   # corner towers
			parts.append({"kind": "city_wall", "piece": 2,
				"dx": int(round(cos(a) * float(R))), "dy": int(round(sin(a) * float(R)))})


func _rot_offset(dx: int, dy: int, rot: int) -> Vector2i:
	match posmod(rot, 4):
		1: return Vector2i(-dy, dx)
		2: return Vector2i(-dx, -dy)
		3: return Vector2i(dy, -dx)
		_: return Vector2i(dx, dy)


func _run_settlement_selftest() -> void:
	_sel_settlement = "village"
	_begin_stroke()
	_place_settlement(Vector2i(8, 8))
	var added: int = _stroke["added"].size()
	_commit_stroke()
	print("[we-selftest:settlement] placed parts=%d" % added)
	_do_undo()
	print("[we-selftest:settlement] RESULT=%s" % ("PASS" if added > 0 else "FAIL"))
	get_tree().quit()


func _refresh_history_buttons() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = _history.is_empty()
		_undo_btn.text = "↶ Undo (%d)" % _history.size()
	if _redo_btn != null:
		_redo_btn.disabled = _redo.is_empty()
		_redo_btn.text = "↷ Redo (%d)" % _redo.size()


# ─────────────────────────────── overlay ─────────────────────────────────────

func _draw_overlay(c: CanvasItem) -> void:
	var zoom: float = _cam.zoom.x
	# Live feedback while dragging a road: the raw stroke as a bright polyline.
	if _road_drawing and _road_pts.size() >= 2:
		var off := Vector2(_min_tx, _min_ty)
		var prev := Vector2(_road_pts[0]) - off + Vector2(0.5, 0.5)
		for i: int in range(1, _road_pts.size()):
			var cur := Vector2(_road_pts[i]) - off + Vector2(0.5, 0.5)
			c.draw_line(prev, cur, Color(0.95, 0.6, 0.2, 0.9), maxf(0.6, 2.0 / zoom))
			prev = cur
	# Brush / placement footprint cursor on the 2D map: a ring sized to the brush for the
	# sculpt/paint tools, a square for placement tools — so you see size + where it lands.
	if not _v3d_on and _hover_tile.x != -2147483648:
		var ctr := Vector2(_hover_tile) - Vector2(_min_tx, _min_ty) + Vector2(0.5, 0.5)
		var lw := maxf(0.5, 1.5 / zoom)
		if _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE, Tool.SMOOTHEN, Tool.ELEVATE, Tool.FOREST, Tool.CLUTTER, Tool.GRASS]:
			c.draw_arc(ctr, float(_brush), 0.0, TAU, 48, Color(1.0, 0.92, 0.3, 0.9), lw)
		elif _tool in [Tool.STAMP, Tool.STRUCTURE, Tool.SETTLEMENT]:
			var fr := _half_footprint_tiles()
			c.draw_rect(Rect2(ctr - Vector2(fr, fr), Vector2(fr, fr) * 2.0), Color(0.4, 0.85, 1.0, 0.9), false, lw)
	if _show_collision or _show_biomes or _show_danger or _show_walk or _show_elevation:
		var view := _view_rect_tiles()
		var classifier: RefCounted = WorldGen.generator.classifier
		for key: String in _chunks:
			var chunk: RefCounted = _chunks[key]
			var bx: int = chunk.cx * WG.CHUNK_TILES
			var by: int = chunk.cy * WG.CHUNK_TILES
			if bx + WG.CHUNK_TILES < view.position.x or bx > view.end.x \
					or by + WG.CHUNK_TILES < view.position.y or by > view.end.y:
				continue
			if _show_danger:
				# One translucent tint per chunk by distance-from-centre danger.
				var d: float = classifier.danger01(float(bx + 8), float(by + 8))
				c.draw_rect(Rect2(float(bx - _min_tx), float(by - _min_ty), WG.CHUNK_TILES, WG.CHUNK_TILES),
					Color(d, 1.0 - d, 0.15, 0.22))
			if _show_collision or _show_biomes or _show_walk or _show_elevation:
				for ly: int in WG.CHUNK_TILES:
					for lx: int in WG.CHUNK_TILES:
						var px := float(bx + lx - _min_tx)
						var py := float(by + ly - _min_ty)
						if _show_collision and chunk.is_blocked(lx, ly):
							c.draw_rect(Rect2(px, py, 1.0, 1.0), Color(0.9, 0.2, 0.2, 0.45))
						if _show_walk:
							var td: Dictionary = _reg.tile_def(chunk.tile_id(lx, ly))
							if not bool(td.get("walkable", false)) or bool(td.get("water", false)) or bool(td.get("hazard", false)):
								c.draw_rect(Rect2(px, py, 1.0, 1.0), Color(0.15, 0.25, 0.9, 0.35))
						if _show_biomes:
							var bidx: int = chunk.biome_at(lx, ly)
							if bidx != 255 and bidx < _reg.biomes.size():
								c.draw_rect(Rect2(px, py, 1.0, 1.0), _biome_tint(bidx))
						if _show_elevation and chunk.elev.size() > 0:
							var elev: int = chunk.elev[Chunk.idx(lx, ly)]
							if elev > 0:
								c.draw_rect(Rect2(px, py, 1.0, 1.0),
									_elev_tint(float(elev) / float(MountainField.ELEV_MAX_STEPS)))
	if _show_structs:
		var view := _view_rect_tiles()
		for key: String in _chunks:
			var chunk: RefCounted = _chunks[key]
			var bx: int = chunk.cx * WG.CHUNK_TILES
			var by: int = chunk.cy * WG.CHUNK_TILES
			if bx + WG.CHUNK_TILES < view.position.x or bx > view.end.x \
					or by + WG.CHUNK_TILES < view.position.y or by > view.end.y:
				continue
			for p: Dictionary in chunk.structures:
				var gx: float = float(bx + int(p.get("tx", 0)) - _min_tx) + 0.5
				var gy: float = float(by + int(p.get("ty", 0)) - _min_ty) + 0.5
				c.draw_rect(Rect2(gx - 0.5, gy - 0.5, 1.0, 1.0), STRUCT_MARK)
		# Procedural ambient canopy: the trees the live game scatters from each biome's
		# canopy block — the map matches the world. Cached per chunk (deterministic) so the
		# every-frame redraw just iterates a short index list per visible chunk instead of
		# re-running the gate over 256 tiles. Cut tiles (chunk.tree_cuts) are filtered out, so
		# erasing shows immediately. Skipped when zoomed out, where the dots are sub-pixel.
		if _show_trees and zoom >= TREE_DRAW_ZOOM:
			var tview := _view_rect_tiles()
			for tkey: String in _chunks:
				var tchunk: RefCounted = _chunks[tkey]
				var tbx: int = tchunk.cx * WG.CHUNK_TILES
				var tby: int = tchunk.cy * WG.CHUNK_TILES
				if tbx + WG.CHUNK_TILES < tview.position.x or tbx > tview.end.x \
						or tby + WG.CHUNK_TILES < tview.position.y or tby > tview.end.y:
					continue
				var cuts: Dictionary = tchunk.tree_cuts
				for ci: int in _chunk_canopy(tchunk):
					if cuts.has(ci):
						continue
					var ttx := float(tbx + (ci % WG.CHUNK_TILES) - _min_tx) + 0.5
					var tty := float(tby + (ci / WG.CHUNK_TILES) - _min_ty) + 0.5
					c.draw_rect(Rect2(ttx - 0.35, tty - 0.35, 0.7, 0.7), TREE_MARK)
	if _show_spawn:
		var sp := Vector2(float(_spawn_tile.x - _min_tx) + 0.5, float(_spawn_tile.y - _min_ty) + 0.5)
		var r := 2.5
		c.draw_colored_polygon(PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)]), SPAWN_MARK)
		c.draw_arc(sp, r + 1.5, 0.0, TAU, 16, Color(0, 0, 0, 0.7), 1.0 / zoom)
	var ct := Vector2(float(_hover_tile.x - _min_tx) + 0.5, float(_hover_tile.y - _min_ty) + 0.5)
	if _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE]:
		c.draw_arc(ct, float(maxi(_brush - 1, 0)) + 0.5, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.0 / zoom)
	elif _tool == Tool.STAMP:
		var stamps: Array = StampLibrary.all()
		if _sel_stamp < stamps.size():
			var sr := float(int(stamps[_sel_stamp].get("radius", 3)))
			c.draw_arc(ct, sr + 0.5, 0.0, TAU, 24, Color(0.5, 1.0, 0.6, 0.9), 1.0 / zoom)


## High-contrast height heat ramp for the elevation overlay: a vivid
## blue -> cyan -> green -> yellow -> orange -> red -> white gradient so each
## elevation band reads clearly (t is steps / max steps).
static var _ELEV_RAMP: Array[Color] = [
	Color(0.10, 0.20, 0.95),   # lowest  - deep blue
	Color(0.00, 0.80, 0.95),   # cyan
	Color(0.15, 0.90, 0.20),   # green
	Color(0.95, 0.95, 0.10),   # yellow
	Color(0.98, 0.55, 0.05),   # orange
	Color(0.95, 0.10, 0.10),   # red
	Color(1.00, 1.00, 1.00),   # highest - white peaks
]
func _elev_tint(t: float) -> Color:
	t = clampf(t, 0.0, 1.0) * float(_ELEV_RAMP.size() - 1)
	var i := int(t)
	var col: Color
	if i >= _ELEV_RAMP.size() - 1:
		col = _ELEV_RAMP[_ELEV_RAMP.size() - 1]
	else:
		col = _ELEV_RAMP[i].lerp(_ELEV_RAMP[i + 1], t - float(i))
	col.a = 0.85
	return col


## Deterministic translucent tint per biome index for the biome overlay.
func _biome_tint(bidx: int) -> Color:
	var h := float((bidx * 2654435761) % 360) / 360.0
	return Color.from_hsv(h, 0.6, 0.9, 0.33)


func _view_rect_tiles() -> Rect2i:
	var half := get_viewport_rect().size / _cam.zoom * 0.5
	var tl := _cam.position - half
	return Rect2i(
		Vector2i(floori(tl.x) + _min_tx - 2, floori(tl.y) + _min_ty - 2),
		Vector2i(int(half.x * 2.0) + 4, int(half.y * 2.0) + 4))


# ─────────────────────────────── UI ──────────────────────────────────────────

func _build_ui() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	top.position = Vector2(8, 8)
	top.scale = Vector2(HUD_SCALE, HUD_SCALE)
	_track_ui_hover(top)
	_hud.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 10)
	top.add_child(tb)
	var title := Label.new()
	title.text = "  %s — World Editor   " % str(_spec.spec_name)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	tb.add_child(title)
	_undo_btn = _toolbar_button(tb, "↶ Undo", _do_undo)
	_redo_btn = _toolbar_button(tb, "↷ Redo", _do_redo)
	_toolbar_button(tb, "💾 Save (Ctrl+S)", _save)
	_toolbar_button(tb, "✓ Validate", _validate)
	_toolbar_button(tb, "⟳ New World (Full)", _confirm_generate)
	_v3d_btn = _toolbar_button(tb, "🧊 3D View", _toggle_3d_view)
	_v3d_btn.toggle_mode = true
	_toolbar_button(tb, "📍 Set Test Spawn", _begin_pick_test_spawn)
	_toolbar_button(tb, "▶ Test Level", _enter_test_mode)
	_toolbar_button(tb, "🗑 Wipe Save", _confirm_wipe_save)
	_status = Label.new()
	_status.text = "Loaded %d chunks" % _chunks.size()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	tb.add_child(_status)
	var hspacer := Control.new()
	hspacer.custom_minimum_size = Vector2(12, 0)
	tb.add_child(hspacer)
	_toolbar_button(tb, "☰ Menu (Esc)", _toggle_editor_menu)

	# Left sidebar: the 14 tools grouped into collapsible categories (replaces the old flat list).
	_sidebar = PanelContainer.new()
	_sidebar.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	_sidebar.position = Vector2(8, 58)   # clears the taller (1.25×) top bar
	_sidebar.scale = Vector2(HUD_SCALE, HUD_SCALE)
	_sidebar.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_track_ui_hover(_sidebar)
	_hud.add_child(_sidebar)
	var lb := VBoxContainer.new()
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.add_theme_constant_override("separation", 2)
	_sidebar.add_child(lb)

	_tool_group(lb, "Paint", [[Tool.BIOME, "2  Biome"], [Tool.TERRAIN, "3  Terrain"]], true)
	_tool_group(lb, "Sculpt", [[Tool.ELEVATE, "E  Elevate"], [Tool.SMOOTHEN, "H  Smoothen"]], true)
	_tool_group(lb, "Nature", [[Tool.FOREST, "T  Trees"], [Tool.CLUTTER, "C  Clutter"], [Tool.GRASS, "V  Grass"], [Tool.STAMP, "4  Stamp"]], false)
	_tool_group(lb, "Build", [[Tool.STRUCTURE, "5  Structure"], [Tool.SETTLEMENT, "0  Settlement"], [Tool.ROAD, "9  Roads"]], false)
	_build_skill_tool_group(lb)
	_tool_group(lb, "Live", [[Tool.CREATURE, "8  Creatures"], [Tool.SPAWN, "7  Set Spawn"]], false)
	_tool_group(lb, "Edit", [[Tool.SELECT, "Q  Select / Move"], [Tool.PAN, "1  Pan / View"], [Tool.ERASE, "6  Erase"]], false)

	# Overlays — its own collapsible section so it never crowds the tools.
	var ov := _collapsible(lb, "Overlays", false)
	_overlay_check(ov, "Structures", _show_structs, func(on: bool) -> void: _show_structs = on)
	_overlay_check(ov, "Trees", _show_trees, func(on: bool) -> void: _show_trees = on)
	_overlay_check(ov, "Player spawn", _show_spawn, func(on: bool) -> void: _show_spawn = on)
	_overlay_check(ov, "Collision/water", _show_collision, func(on: bool) -> void: _show_collision = on)
	_overlay_check(ov, "Biome tint", _show_biomes, func(on: bool) -> void: _show_biomes = on)
	_overlay_check(ov, "Danger/level", _show_danger, func(on: bool) -> void: _show_danger = on)
	_overlay_check(ov, "Walkability", _show_walk, func(on: bool) -> void: _show_walk = on)
	_elev_check = _overlay_check(ov, "Elevation", _show_elevation, func(on: bool) -> void: _show_elevation = on)
	_minimap_check = _overlay_check(ov, "World map (M)", _show_minimap, _set_show_minimap)

	_coords = Label.new()
	_coords.add_theme_font_size_override("font_size", 16)
	_coords.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	lb.add_child(_coords)
	var hint := Label.new()
	hint.text = "RMB pan · wheel zoom · [ ] size · Ctrl+Z/Y · Esc menu"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lb.add_child(hint)

	_build_opts_panel()
	_build_editor_menu()
	_build_preview_panel()


## A collapsible section: a header button that toggles a body VBox. Returns the body to fill.
func _collapsible(parent: Control, title: String, open: bool) -> VBoxContainer:
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.focus_mode = Control.FOCUS_NONE
	head.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	head.custom_minimum_size = Vector2(SIDEBAR_W - 12, 0)
	parent.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.visible = open
	parent.add_child(body)
	head.text = ("▾  " if open else "▸  ") + title
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		head.text = ("▾  " if body.visible else "▸  ") + title)
	return body


## One collapsible tool category. `tools` = [[Tool.X, "label"], ...]; buttons register in _tool_buttons.
func _tool_group(parent: Control, title: String, tools: Array, open: bool) -> void:
	var body := _collapsible(parent, title, open)
	for ts: Array in tools:
		var b := Button.new()
		b.text = "    " + str(ts[1])
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(SIDEBAR_W - 16, 0)
		var tl: int = ts[0]
		b.pressed.connect(func() -> void: _set_tool(tl))
		body.add_child(b)
		_tool_buttons[tl] = b


## The "Skills" sidebar group: one button per skill (Combat + each gather skill). All select the
## Skills tool, but each pins a different skill so its OBJECTS show in the options panel — one click
## to a skill instead of selecting "Skills" then expanding it.
func _build_skill_tool_group(parent: Control) -> void:
	var body := _collapsible(parent, "Skills", false)
	_add_skill_button(body, "combat", "Combat")
	for skill: String in SKILL_PLACE_ORDER:
		_add_skill_button(body, skill, str(SKILL_DISPLAY.get(skill, skill.capitalize())))


func _add_skill_button(body: Control, skill: String, label: String) -> void:
	var b := Button.new()
	b.text = "    " + label
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(SIDEBAR_W - 16, 0)
	b.pressed.connect(func() -> void: _select_skill_tool(skill))
	body.add_child(b)
	_skill_tool_buttons[skill] = b


## Pick a skill: activate the Skills tool with this skill, defaulting the selection to its first
## object so the options panel and ghost are ready to place immediately.
func _select_skill_tool(skill: String) -> void:
	_sel_skill = skill
	_sel_skill_item = _first_skill_item(skill)
	if skill == "combat":
		_sel_creature = _sel_skill_item
	_set_tool(Tool.SKILL)


## The default object for a skill: the first creature (Combat) or the lowest-level node (gather).
func _first_skill_item(skill: String) -> String:
	if skill == "combat":
		var lst := _creature_list()
		return str(lst[0]["name"]) if not lst.is_empty() else ""
	var best := ""
	var best_lv := 1 << 30
	for e: Dictionary in _reg.node_table.get(skill, []):
		if int(e["level"]) < best_lv:
			best_lv = int(e["level"])
			best = str(e["name"])
	return best


## Floating panel pinned right of the sidebar: the ACTIVE tool's options + the brush controls,
## so nothing stacks endlessly in the sidebar. _palette_box is repopulated by _refresh_palette().
func _build_opts_panel() -> void:
	_opts_panel = PanelContainer.new()
	_opts_panel.add_theme_stylebox_override("panel", _panel(Color(0.12, 0.13, 0.17)))
	_opts_panel.top_level = true
	_opts_panel.position = Vector2(8.0 + SIDEBAR_W * HUD_SCALE + 8.0, 58)
	_opts_panel.scale = Vector2(HUD_SCALE, HUD_SCALE)
	_opts_panel.custom_minimum_size = Vector2(212, 0)
	_opts_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_track_ui_hover(_opts_panel)
	_hud.add_child(_opts_panel)
	var ob := VBoxContainer.new()
	ob.add_theme_constant_override("separation", 3)
	_opts_panel.add_child(ob)
	_opts_title = Label.new()
	_opts_title.add_theme_font_size_override("font_size", 16)
	_opts_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	ob.add_child(_opts_title)
	ob.add_child(HSeparator.new())

	_brush_label = Label.new()
	_brush_label.text = "Brush size: %d" % _brush
	ob.add_child(_brush_label)
	var slider := HSlider.new()
	slider.min_value = 1; slider.max_value = 24; slider.value = _brush
	slider.custom_minimum_size = Vector2(198, 0)
	slider.value_changed.connect(func(v: float) -> void: _set_brush(int(v)))
	ob.add_child(slider)

	var dlabel := Label.new()
	dlabel.text = "Density: %d%%" % int(_decor_density * 100.0)
	ob.add_child(dlabel)
	_density_slider = HSlider.new()
	_density_slider.min_value = 2; _density_slider.max_value = 100; _density_slider.value = _decor_density * 100.0
	_density_slider.custom_minimum_size = Vector2(198, 0)
	_density_slider.value_changed.connect(func(v: float) -> void:
		_decor_density = v / 100.0
		dlabel.text = "Density: %d%%" % int(v))
	ob.add_child(_density_slider)

	var slabel := Label.new()
	slabel.text = "Scale: %d%%" % int(_place_scale * 100.0)
	ob.add_child(slabel)
	var sscale := HSlider.new()
	sscale.min_value = 25; sscale.max_value = 300; sscale.value = _place_scale * 100.0
	sscale.custom_minimum_size = Vector2(198, 0)
	sscale.value_changed.connect(func(v: float) -> void:
		_place_scale = v / 100.0
		slabel.text = "Scale: %d%%" % int(v))
	ob.add_child(sscale)

	_erase_biomes_check = CheckBox.new()
	_erase_biomes_check.text = "Keep painted terrain"
	_erase_biomes_check.toggled.connect(func(on: bool) -> void: _erase_keep_terrain = on)
	ob.add_child(_erase_biomes_check)

	ob.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	# Fill the height available below the panel so long lists (creatures, terrain, biomes) show many
	# rows at once instead of a short 330px window.
	var avail := (get_viewport().get_visible_rect().size.y - 58.0) / HUD_SCALE - 240.0
	scroll.custom_minimum_size = Vector2(198, maxf(360.0, avail))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ob.add_child(scroll)
	_palette_box = VBoxContainer.new()
	_palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_palette_box)


## The editor's OWN menu modal (Esc) — replaces the game pause menu that used to leak in from the
## embedded 3D-view world. File + generate + quit live here so the header stays slim.
func _build_editor_menu() -> void:
	_editor_menu = PopupPanel.new()
	_editor_menu.add_theme_stylebox_override("panel", _panel(Color(0.11, 0.11, 0.14)))
	_track_ui_hover(_editor_menu)
	_hud.add_child(_editor_menu)
	var mb := VBoxContainer.new()
	mb.add_theme_constant_override("separation", 4)
	mb.custom_minimum_size = Vector2(248, 0)
	_editor_menu.add_child(mb)
	var t := Label.new()
	t.text = "  World Editor"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	mb.add_child(t)
	mb.add_child(HSeparator.new())
	_menu_item(mb, "💾   Save   (Ctrl+S)", func() -> void: _editor_menu.hide(); _save())
	_menu_item(mb, "✓   Validate", func() -> void: _editor_menu.hide(); _validate())
	_menu_item(mb, "⟳   New World (Full)", func() -> void: _editor_menu.hide(); _confirm_generate())
	_menu_item(mb, "🗑   Wipe Save", func() -> void: _editor_menu.hide(); _confirm_wipe_save())
	_menu_item(mb, "⌨   Keyboard Shortcuts", _show_shortcuts)
	mb.add_child(HSeparator.new())
	_menu_item(mb, "✕   Quit Editor", func() -> void: get_tree().quit())
	mb.add_child(HSeparator.new())
	var resume := Button.new()
	resume.text = "Resume Editing"
	resume.custom_minimum_size = Vector2(248, 36)
	resume.pressed.connect(func() -> void: _editor_menu.hide())
	mb.add_child(resume)


func _menu_item(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(248, 34)
	b.pressed.connect(cb)
	parent.add_child(b)


func _toggle_editor_menu() -> void:
	if _editor_menu == null:
		return
	if _editor_menu.visible:
		_editor_menu.hide()
	else:
		_editor_menu.popup_centered()


# ───────────────────────────── Test Level (play the world) ──────────────────
# Spawn the player where the aerial camera is looking and hand the embedded world FULL gameplay: it
# becomes the real game (sim-players, enemy AI, movement, HUD) running on the SAME world you're
# editing — no second instance, no save changes. Esc or the Back button returns to the editor.

func _enter_test_mode() -> void:
	if _testing:
		return
	if not _v3d_on or _v3d_world == null:
		_toggle_3d_view()        # ensure the embedded world exists + is shown
	if _v3d_world == null:
		return
	_testing = true
	_picking_test_spawn = false   # cancel any half-started spawn pick
	if _editor_menu != null:
		_editor_menu.hide()
	# Sandbox: a fresh throwaway character each time (full HP + the starter kit), with no stale
	# activity carried over from a previous test. The real save is never loaded (SaveManager.suppress)
	# nor written (save_game() respects suppress), so this whole session is temporary — edit the world,
	# test pathing, leave; nothing persists.
	GameState.reset_state()
	_v3d_world.call("halt_player")
	# Spawn at the picked Test Spawn tile if set, else where the aerial camera is looking — both
	# snapped to walkable ground.
	var spawn_src: Vector2 = WG.tile_to_world(_test_spawn_tile.x, _test_spawn_tile.y) if _test_spawn_tile.x != -2147483648 else _v3d_focus_pos
	var spawn: Vector2 = WorldGen.nearest_walkable_world(spawn_src)
	if _test_spawn_marker3d != null and is_instance_valid(_test_spawn_marker3d):
		_test_spawn_marker3d.visible = false
	var pl: Node2D = _v3d_world.get("player")
	if pl != null:
		pl.position = spawn
	var cm: Node = _v3d_world.get("chunk_manager")
	if cm != null:
		cm.call("update_center", spawn)
	# Hand the world full gameplay + the follow camera + normal (uncapped) streaming.
	_v3d_world.set("gameplay_active", true)
	_v3d_world.set("editor_stream_cap", 0)
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("editor_cam_target", null)    # follow the player, not the pinned aerial focus
		rend.set("editor_hide_player", false)
		rend.set("editor_no_fog", false)
		rend.set("editor_view_radius", 0)
		rend.set("_cam_pitch", 0.413)          # drop the aerial satellite tilt back to the gameplay angle
	# Restore the normal gameplay zoom (the 3D ortho mirrors the 2D camera) — the editor left it wide.
	var cam2d: Node = _v3d_world.get("_camera")
	if cam2d != null:
		cam2d.set("zoom", Vector2(1.65, 1.65))
	if _ehud != null:
		_ehud.visible = true
	# The embedded world now OWNS input (clicks → walk/attack); the editor stops intercepting.
	if _v3d_vp != null:
		_v3d_vp.handle_input_locally = true
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.visible = false
	if _spawn_marker3d != null and is_instance_valid(_spawn_marker3d):
		_spawn_marker3d.visible = false
	# Fill the screen with the game view and hide the editor chrome (keep only the Back button).
	_set_editor_chrome_visible(false)
	_v3d_panel.position = Vector2.ZERO
	_v3d_container.custom_minimum_size = get_viewport().get_visible_rect().size
	_ensure_back_button()
	_back_btn.visible = true
	_back_btn.move_to_front()
	_status.text = "Testing level — Esc to return to the editor"


func _exit_test_mode() -> void:
	if not _testing:
		return
	_testing = false
	# Freeze the world again and return to the pinned aerial editor camera.
	_v3d_world.set("gameplay_active", false)
	_v3d_world.set("editor_stream_cap", _V3D_VIEW_CAP)
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("editor_hide_player", true)
		rend.set("editor_no_fog", true)
		rend.set("editor_view_radius", _V3D_VIEW_CAP)
		rend.set("editor_cam_target", _v3d_focus_pos)
	if _ehud != null:
		_ehud.visible = false
	if _v3d_vp != null:
		_v3d_vp.handle_input_locally = false
	if _back_btn != null:
		_back_btn.visible = false
	_set_editor_chrome_visible(true)
	_apply_v3d_layout()      # restore the editor's docked/maximized 3D layout + re-pin the camera


## Hide every editor HUD panel (keeping the 3D world view + the Back button) so Test Level fills the
## screen like the real game; on return, restore exactly what was visible before.
func _set_editor_chrome_visible(vis: bool) -> void:
	if vis:
		for c: Node in _chrome_prev_vis:
			if is_instance_valid(c):
				(c as CanvasItem).visible = _chrome_prev_vis[c]
		_chrome_prev_vis.clear()
		return
	_chrome_prev_vis.clear()
	for c: Node in _hud.get_children():
		if c == _v3d_panel or c == _back_btn or c == _editor_menu:
			continue
		if c is CanvasItem:
			_chrome_prev_vis[c] = (c as CanvasItem).visible
			(c as CanvasItem).visible = false


func _ensure_back_button() -> void:
	if _back_btn != null:
		return
	_back_btn = Button.new()
	_back_btn.text = "◀ Back to Editor (Esc)"
	_back_btn.top_level = true
	_back_btn.position = Vector2(12, 10)
	_back_btn.add_theme_font_size_override("font_size", 16)
	_back_btn.add_theme_stylebox_override("normal", _panel(Color(0.13, 0.13, 0.16)))
	_back_btn.pressed.connect(_exit_test_mode)
	_track_ui_hover(_back_btn)
	_hud.add_child(_back_btn)


## Arm the Test Spawn picker: the next left-click in the 3D view sets where Test Level drops the player.
func _begin_pick_test_spawn() -> void:
	if not _v3d_on:
		_toggle_3d_view()
	_picking_test_spawn = true
	_status.text = "Click in the 3D view to set the Test Level spawn point."


func _show_shortcuts() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Keyboard Shortcuts"
	dlg.dialog_text = ("Tools  1 Pan · 2 Biome · 3 Terrain · 4 Stamp · 5 Structure · 6 Erase\n"
		+ "       7 Set Spawn · 8 Creatures · 9 Roads · 0 Settlements\n"
		+ "       E Elevate · H Smoothen · T Trees · C Clutter\n\n"
		+ "Canvas  RMB drag pan · wheel zoom · LMB place/paint\n"
		+ "        [ ] brush size · R rotate · F flip placement · M world map\n\n"
		+ "File    Ctrl+S save · Ctrl+Z undo · Ctrl+Y / Ctrl+Shift+Z redo · Esc menu")
	_hud.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


## Showcase panel that floats just to the right of the selected sidebar item
## (positioned each frame in _process). Shows the currently selected biome / tile
## / structure / creature with the real game art on a static iso tile. Updated by
## _update_preview() on every selection.
func _build_preview_panel() -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.add_theme_stylebox_override("panel", _panel(Color(0.13, 0.13, 0.16)))
	_preview_panel.position = Vector2(200, 60)
	_preview_panel.scale = Vector2(HUD_SCALE, HUD_SCALE)
	_preview_panel.top_level = true   # position is in screen space, not the HUD layout
	_track_ui_hover(_preview_panel)
	_hud.add_child(_preview_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_preview_panel.add_child(box)
	_header(box, "Preview")
	_preview = PlaceablePreview.new()
	_preview.reg = _reg
	box.add_child(_preview)
	_reroll_btn = Button.new()
	_reroll_btn.text = "🎲 Re-roll variant"
	_reroll_btn.pressed.connect(_reroll_variant)
	box.add_child(_reroll_btn)


# ───────────────────────────── live 3D view ─────────────────────────────────
# Embeds the real game (world.tscn) in a SubViewport. Because the editor edits the
# SAME WorldGen chunk objects the embedded renderer reads, painting on the 2D map and
# then re-meshing the touched chunks shows the true in-game 3D result.

## Build the (initially hidden) docked 3D panel shell. The heavy game scene inside is
## created lazily the first time the panel is shown (see _toggle_3d_view).
func _build_3d_view_panel() -> void:
	_v3d_panel = PanelContainer.new()
	_v3d_panel.add_theme_stylebox_override("panel", _panel(Color(0.06, 0.07, 0.09)))
	_v3d_panel.top_level = true
	_v3d_panel.visible = false
	_track_ui_hover(_v3d_panel)
	_hud.add_child(_v3d_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_v3d_panel.add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_header(bar, "3D View")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hint := Label.new()
	hint.text = "WASD / R-drag move · wheel / pinch zoom · L-click place"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	bar.add_child(hint)
	_v3d_container = SubViewportContainer.new()
	_v3d_container.custom_minimum_size = _V3D_SIZE
	_v3d_container.stretch = true
	# Docked = view-only (mouse passes to the 2D map). Maximized flips to STOP so the
	# editor receives clicks here for 3D placement / camera re-aim (see _apply_v3d_layout).
	_v3d_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_v3d_container.gui_input.connect(_on_v3d_gui_input)
	box.add_child(_v3d_container)
	_v3d_panel.position = Vector2(get_viewport().get_visible_rect().size) - Vector2(_V3D_SIZE) - Vector2(24, 24)


## Bottom-right world minimap: the whole baked map; click anywhere to jump the aerial
## camera there. A marker shows where the 3D view is currently centred.
func _build_world_minimap() -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.add_theme_stylebox_override("panel", _panel(Color(0.06, 0.07, 0.09)))
	_minimap_panel.top_level = true
	_minimap_panel.scale = Vector2(HUD_SCALE, HUD_SCALE)
	_minimap_panel.visible = false
	_hud.add_child(_minimap_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_minimap_panel.add_child(box)
	var lbl := Label.new()
	lbl.text = "World map — click to go"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.7))
	box.add_child(lbl)
	_minimap_tex = TextureRect.new()
	# Load the freshly-baked map straight from disk (bypass Godot's import cache, which can
	# serve a stale pre-rebake texture — that makes the map show the wrong world and sends
	# click-to-go to the wrong place).
	_minimap_tex.texture = _load_baked_map_texture()
	var mw := 300.0
	_minimap_tex.custom_minimum_size = Vector2(mw, mw * float(_h) / float(_w))
	_minimap_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap_tex.gui_input.connect(_on_minimap_input)
	box.add_child(_minimap_tex)
	# Content overlay: player spawn, creature spawns, buildings, POIs/cities, roads — a world overview.
	_map_overlay = Control.new()
	_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_overlay.draw.connect(_draw_map_markers.bind(_map_overlay))
	_minimap_tex.add_child(_map_overlay)
	_minimap_marker = ColorRect.new()
	_minimap_marker.color = Color(1.0, 1.0, 1.0, 0.95)
	_minimap_marker.size = Vector2(8, 8)
	_minimap_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_tex.add_child(_minimap_marker)


## Overview markers drawn over the world map: roads, buildings/POIs (with city names), creature
## spawns and the player spawn — so the map reads as a real world overview. NPCs/shops will anchor
## to their POI here too once placed. Coordinates: global tile -> map fraction -> overlay pixel.
func _draw_map_markers(c: CanvasItem) -> void:
	if _minimap_tex == null or _w <= 0 or _h <= 0:
		return
	var sz := _minimap_tex.size
	var sx := sz.x / float(_w)
	var sy := sz.y / float(_h)
	var px := func(gtx: float, gty: float) -> Vector2:
		return Vector2((gtx - float(_min_tx)) * sx, (gty - float(_min_ty)) * sy)

	# Roads (the future network) — tan polylines.
	for road: Dictionary in _spec.roads:
		var rpts: Array = road.get("points", [])
		if rpts.size() >= 2:
			var line := PackedVector2Array()
			for p: Variant in rpts:
				line.append(px.call(float(p.x), float(p.y)))
			c.draw_polyline(line, Color(0.85, 0.72, 0.45, 0.85), 1.5)

	var font := ThemeDB.fallback_font
	for ch: RefCounted in _chunks.values():
		var bx: int = ch.cx * WG.CHUNK_TILES
		var by: int = ch.cy * WG.CHUNK_TILES
		# Buildings & structures only — skip ambient trees + clutter decor (both are just FX scenery).
		for s: Dictionary in ch.structures:
			var skind := str(s.get("kind", ""))
			if skind == "tree" or skind == "decor":
				continue
			var sp := px.call(float(bx + int(s.get("tx", 0))), float(by + int(s.get("ty", 0))))
			c.draw_rect(Rect2(sp - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.95, 0.78, 0.32, 0.95))
		# Creature spawns — red dots.
		for m: Dictionary in ch.monsters:
			c.draw_circle(px.call(float(bx + int(m.get("tx", 0))), float(by + int(m.get("ty", 0)))), 2.6, Color(0.92, 0.26, 0.22, 0.95))
		# POIs / settlements / cities — hollow gold square + name (future NPCs/shops anchor here too).
		for poi: Dictionary in ch.pois:
			var anc = poi.get("anchor", Vector2i.ZERO)
			var pp := px.call(float(bx + anc.x), float(by + anc.y))
			c.draw_rect(Rect2(pp - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.88, 0.4, 1.0), false, 1.5)
			var nm := str(poi.get("name", poi.get("label", "")))
			if not nm.is_empty() and font != null:
				c.draw_string(font, pp + Vector2(6, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.97, 0.78))

	# Player spawn — green beacon, drawn last (on top).
	var spx := px.call(float(_spawn_tile.x), float(_spawn_tile.y))
	c.draw_circle(spx, 5.0, Color(0.18, 0.85, 0.32, 0.95))
	c.draw_arc(spx, 6.5, 0.0, TAU, 20, Color(1, 1, 1, 0.95), 1.5)


## Read the baked overview PNG straight off disk so we never display a stale import-cached
## texture (which mismatches the live bounds and breaks click-to-go).
func _load_baked_map_texture() -> Texture2D:
	var path := "res://data/world/baked/" + str(_spec.id) + "_map.png"
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			return ImageTexture.create_from_image(img)
	return load(path)   # fall back to the imported resource if the raw read fails


## Overlays > "World map" checkbox.
func _set_show_minimap(on: bool) -> void:
	_show_minimap = on
	_apply_minimap_visibility()


## M key — show/hide the world-map overlay (mirrors the Overlays > "World map" checkbox).
func _toggle_minimap() -> void:
	_show_minimap = not _show_minimap
	if _minimap_check != null:
		_minimap_check.set_pressed_no_signal(_show_minimap)
	_apply_minimap_visibility()
	_status.text = "World map: %s" % ("on" if _show_minimap else "off")


## The minimap shows only in 3D view AND when the user hasn't toggled it off.
func _apply_minimap_visibility() -> void:
	if _minimap_panel == null:
		return
	_minimap_panel.visible = _v3d_on and _show_minimap
	if _minimap_panel.visible:
		_position_minimap.call_deferred()
		if _map_overlay != null:
			_map_overlay.queue_redraw()   # refresh the placed-content markers each time the map opens


## Park the minimap in the bottom-right corner.
func _position_minimap() -> void:
	if _minimap_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_minimap_panel.reset_size()
	# size is the logical (unscaled) size; the panel renders at HUD_SCALE, so anchor by the scaled size.
	_minimap_panel.position = vp - _minimap_panel.size * HUD_SCALE - Vector2(16, 16)


## Click on the minimap -> jump the aerial camera to that world position.
func _on_minimap_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var sz := _minimap_tex.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var pos: Vector2 = (event as InputEventMouseButton).position
	var frac := pos / sz
	var tx := _min_tx + int(frac.x * float(_w))
	var ty := _min_ty + int(frac.y * float(_h))
	if not _v3d_on:
		_toggle_3d_view()
	_v3d_set_focus_world(WG.tile_to_world(tx, ty))
	_minimap_tex.accept_event()


## Keep the minimap marker over the current aerial focus.
func _update_minimap_marker() -> void:
	if _minimap_marker == null or _minimap_tex == null or _w <= 0 or _h <= 0:
		return
	var frac := Vector2(
		float(_v3d_focus_tile.x - _min_tx) / float(_w),
		float(_v3d_focus_tile.y - _min_ty) / float(_h))
	_minimap_marker.position = frac * _minimap_tex.size - _minimap_marker.size * 0.5


## Toggle between the 2D map editor and the full-screen 3D world canvas. When ON, the
## rendered world REPLACES the 2D map (the 2D sprite + overlay hide) and the 3D view
## fills the editor area behind the tool panels — an aerial world-builder you pan
## (right-drag), zoom (wheel) and place on (left-click with a Structure/Stamp tool).
func _toggle_3d_view() -> void:
	_v3d_on = not _v3d_on
	_v3d_panel.visible = _v3d_on
	if _v3d_btn != null:
		_v3d_btn.button_pressed = _v3d_on
	# The 3D canvas REPLACES the 2D map — hide the flat map + its overlay while on.
	if _sprite != null:
		_sprite.visible = not _v3d_on
	if _overlay != null:
		_overlay.visible = not _v3d_on
	if _minimap_panel != null:
		_apply_minimap_visibility()
	if _v3d_on:
		if _v3d_world == null:
			_spawn_embedded_world()
		_hud.move_child(_v3d_panel, 0)   # behind the tool panels so they stay on top
		_apply_v3d_layout()


## M / the panel button — same 2D<->3D toggle.
func _toggle_3d_maximize() -> void:
	_toggle_3d_view()


## Full-screen layout for the 3D canvas: fill the editor area right of the tool column
## and below the top bar, hand the editor the clicks, and frame the aerial camera.
func _apply_v3d_layout() -> void:
	if _v3d_panel == null or not _v3d_on:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := Vector2i(maxi(360, int(vp.x) - _V3D_LEFT), maxi(280, int(vp.y) - _V3D_TOP))
	_v3d_container.custom_minimum_size = Vector2(sz)
	# NOTE: do NOT set _v3d_vp.size — `stretch = true` makes the container drive the
	# SubViewport size. Setting it manually is ignored (and left the viewport stuck at
	# 540x380, which broke the streaming-radius math and the View slider).
	if _v3d_vp != null:
		_v3d_vp.handle_input_locally = false       # the EDITOR owns clicks (place / pan)
	_v3d_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_v3d_panel.position = Vector2(_V3D_LEFT, _V3D_TOP)
	var ft := _v3d_focus_tile if _in_bounds_tile(_v3d_focus_tile) else _spawn_tile
	_focus_3d(ft)
	_v3d_focus_pos = WG.tile_to_world(ft.x, ft.y)
	_apply_v3d_satellite_camera()
	_v3d_panel.reset_size.call_deferred()


func _spawn_embedded_world() -> void:
	_status.text = "Booting 3D view…"
	_v3d_vp = SubViewport.new()
	_v3d_vp.size = _V3D_SIZE
	_v3d_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_v3d_vp.handle_input_locally = false   # editor owns input; this is a viewer
	_v3d_container.add_child(_v3d_vp)
	_v3d_world = _GAME_SCENE.instantiate()
	# DECOUPLE: the editor's embedded world is a VIEW-ONLY instance — it streams + renders the real
	# world (so you see the 3D result of your edits) but runs NONE of the gameplay simulation (no
	# sim-players, no enemy AI, no collision). "Test Level" flips gameplay_active true to play it.
	_v3d_world.set("gameplay_active", false)
	_v3d_world.set("sims_enabled", false)   # the editor never wants the sim-player crowd, not even in Test Level
	_v3d_vp.add_child(_v3d_world)
	# Hide the embedded game's own HUD — we only want the 3D world image (it returns in Test Level).
	_ehud = _v3d_world.get_node_or_null("HUD") as CanvasLayer
	if _ehud != null:
		_ehud.visible = false
	# World-building canvas: no player avatar, just the rendered world.
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("editor_hide_player", true)
		rend.set("editor_no_fog", true)                 # no distance fog in the editor
		rend.set("editor_view_radius", _V3D_VIEW_CAP)   # footprint/visual ceiling; the actual view auto-fills under it
		rend.set("editor_plain_player", true)           # Test Level character wears plain clothes, not showcase armour
	# Terrain auto-follows the zoom (world.gd loads min(zoom-radius, ceiling)) — no manual view-distance
	# control; the ceiling just bounds an extreme zoom-out so it can't try to mesh the whole continent.
	_v3d_world.set("editor_stream_cap", _V3D_VIEW_CAP)


## Aim the 3D camera at a world tile by teleporting the embedded player there (the
## renderer's camera eases to follow it) and re-centring its chunk streaming.
func _focus_3d(tile: Vector2i) -> void:
	if not _v3d_on or _v3d_world == null:
		return
	_v3d_focus_tile = tile
	var pos := WG.tile_to_world(tile.x, tile.y)
	var pl: Node2D = _v3d_world.get("player")
	if pl != null:
		pl.position = pos
	var cm: Node = _v3d_world.get("chunk_manager")
	if cm != null:
		cm.call("update_center", pos)
	# Pin the 3D camera to this authoring point so the live player never drifts the view.
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("editor_cam_target", pos)


## Re-mesh the chunks a stroke (or undo/redo) touched so terrain/biome/water edits show
## up in the 3D view. (Structure entities placed via the 3D view are refreshed separately
## by _refresh_3d_entities.)
## Live-drag remesh: re-mesh ONLY the hovered chunk in place (fast, no flicker). Neighbour
## seams are reconciled by _resync_3d_tiles() on stroke commit.
func _resync_3d_instant(tile: Vector2i) -> void:
	if not _v3d_on or _v3d_world == null:
		return
	# Throttle the live remesh: the brush still EDITS every motion event, but rebuilding the
	# chunk mesh ~30×/s instead of on every motion keeps a fast drag smooth. The final state is
	# always correct — _commit_stroke does a full neighbour-seam rebuild on release.
	var now := Time.get_ticks_msec()
	if now - _last_instant_ms < 33:
		return
	_last_instant_ms = now
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("rebuild_chunk_instant"):
		return
	rend.call("rebuild_chunk_instant", floori(float(tile.x) / float(WG.CHUNK_TILES)),
		floori(float(tile.y) / float(WG.CHUNK_TILES)))
	# Live-drop the clutter onto the sculpted ground as you drag the brush (commit does the rest).
	if rend.has_method("reset_prop_transforms_in_rect"):
		rend.call("reset_prop_transforms_in_rect", _tiles_world_rect(
			[Vector2i(tile.x - _brush, tile.y - _brush), Vector2i(tile.x + _brush, tile.y + _brush)]))


## Padded world-space AABB covering a set of edited tiles. tile_to_world is isometric, so a tile
## range is a diamond in world space — we bound its corners and grow by a tile so props standing on
## any edited tile fall inside (over-inclusion just re-samples a few extra props, which is harmless).
func _tiles_world_rect(tiles: Array) -> Rect2:
	var tmin := Vector2i(2147483647, 2147483647)
	var tmax := Vector2i(-2147483648, -2147483648)
	for t: Vector2i in tiles:
		tmin.x = mini(tmin.x, t.x); tmin.y = mini(tmin.y, t.y)
		tmax.x = maxi(tmax.x, t.x); tmax.y = maxi(tmax.y, t.y)
	var r := Rect2(WG.tile_to_world(tmin.x, tmin.y), Vector2.ZERO)
	for c: Vector2i in [Vector2i(tmax.x, tmin.y), Vector2i(tmin.x, tmax.y), tmax]:
		r = r.expand(WG.tile_to_world(c.x, c.y))
	return r.grow(WG.TILE * 1.5)


# ───────────────────────────── hover cursor (3D) ────────────────────────────
# A ground-hugging gizmo under the 3D cursor: a translucent disc sized to the brush for
# the sculpt/paint tools, or a square footprint for placement tools — so you can see the
# brush size and exactly where the next stroke / drop lands before committing.

func _half_footprint_tiles() -> float:
	match _tool:
		Tool.STAMP:
			var stamps: Array = StampLibrary.all()
			if _sel_stamp < stamps.size():
				return maxf(1.0, float(int(stamps[_sel_stamp].get("radius", 3))))
			return 3.0
		Tool.SETTLEMENT:
			return 6.0
		_:
			return 1.0


func _update_hover_gizmo() -> void:
	if _v3d_world == null:
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("iso_to_3d"):
		return
	var ring: bool = _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE, Tool.SMOOTHEN, Tool.ELEVATE, Tool.FOREST, Tool.CLUTTER, Tool.GRASS]
	var ghost_struct: bool = _tool == Tool.STRUCTURE   # single model at the cursor
	var ghost_settle: bool = _tool == Tool.SETTLEMENT  # whole building cluster
	var square: bool = _tool == Tool.STAMP             # terrain stamp: just a footprint
	var road_disc: bool = _tool == Tool.ROAD           # show the road thickness as a disc
	var spawn_cursor: bool = _tool == Tool.SPAWN       # single-tile target where the click sets spawn
	# Show only while hovering the 3D view itself. In the maximized view that container is the
	# hovered control; over the sidebar it isn't — so this hides the cursor over the panels
	# (the blanket _ui_hover check was wrong here: the 3D container always counts as "UI").
	if not (ring or ghost_struct or ghost_settle or square or road_disc or spawn_cursor) or get_viewport().gui_get_hovered_control() != _v3d_container:
		_hide_hover_gizmo()
		return
	var iso := _v3d_screen_iso(_v3d_container.get_local_mouse_position())
	if iso == Vector2.INF:
		_hide_hover_gizmo()
		return
	var h: float = rend.call("height_at", iso)
	var center: Vector3 = rend.call("iso_to_3d", iso, h)
	if ghost_struct:
		# A translucent copy of the structure, rotated by the current placement yaw, so you
		# preview exactly what (and which way) the next click drops.
		_hide_flat_gizmo()
		_ensure_ghost(rend)
		if _ghost_root != null and is_instance_valid(_ghost_root):
			# Follow the exact cursor point (free placement drops it there, no grid snap).
			_ghost_root.visible = true
			_ghost_root.global_transform = Transform3D(Basis(Vector3.UP, _struct_yaw()).scaled(Vector3.ONE * _place_scale), center)
		return
	if ghost_settle:
		# The whole settlement cluster at the hovered tile (buildings are placed absolutely, so
		# the root stays at the origin). Rebuilds as you cross tiles / rotate the layout.
		_hide_flat_gizmo()
		_ensure_settlement_ghost(rend, WG.world_to_tile(iso))
		if _ghost_root != null and is_instance_valid(_ghost_root):
			_ghost_root.visible = true
			_ghost_root.global_transform = Transform3D.IDENTITY
		return
	_hide_ghost()
	_ensure_hover_gizmo(rend)
	if _gizmo_root == null:
		return
	var disc_tiles := float(_brush) if ring else (float(_road_width) * 0.5 if road_disc else 0.6)
	var tiles: float = disc_tiles if (ring or road_disc or spawn_cursor) else _half_footprint_tiles()
	var edge: Vector3 = rend.call("iso_to_3d", iso + Vector2(tiles * WG.TILE, 0.0), h)
	var radius := maxf(0.4, center.distance_to(edge))
	_gizmo_root.visible = true
	_gizmo_root.global_position = center + Vector3(0.0, 0.08, 0.0)
	_gizmo_disc.visible = ring or road_disc or spawn_cursor
	_gizmo_foot.visible = square
	if ring or road_disc or spawn_cursor:
		_gizmo_disc.scale = Vector3(radius, 1.0, radius)
	else:
		_gizmo_foot.scale = Vector3(radius, 1.0, radius)


## STRUCTURE ghost: a single translucent model, rebuilt only when the selection / rerolled
## look changes (its world position + yaw are a cheap per-frame transform on the root).
func _ensure_ghost(rend: Node) -> void:
	var sig := "T|%d|%d" % [_sel_struct, _ghost_variant]
	if sig == _ghost_sig and _ghost_root != null and is_instance_valid(_ghost_root):
		return
	var root := _new_ghost_root(rend)
	if root == null:
		_ghost_sig = ""
		return
	_ghost_sig = sig
	if _sel_struct >= 0 and _sel_struct < STRUCTURES.size():
		_add_ghost_building(STRUCTURES[_sel_struct][1], Transform3D.IDENTITY, root, _ghost_variant)


## SETTLEMENT ghost: the whole building cluster, each model at its absolute tile. Rebuilt when
## the template / rotation / hovered tile changes (the layout is seeded by the centre tile, so
## it must match the tile the click will use). Buildings carry the layout's baked positions.
func _ensure_settlement_ghost(rend: Node, tile: Vector2i) -> void:
	var sig := "S|%s|%d|%d,%d" % [_sel_settlement, _settlement_rot, tile.x, tile.y]
	if sig == _ghost_sig and _ghost_root != null and is_instance_valid(_ghost_root):
		return
	var root := _new_ghost_root(rend)
	if root == null:
		_ghost_sig = ""
		return
	_ghost_sig = sig
	var def: Dictionary = (_settlement_templates().get("templates", {}) as Dictionary).get(_sel_settlement, {})
	if def.is_empty():
		return
	for part: Dictionary in _build_settlement(def, tile, _settlement_rot):
		var tx := int(part["tx"])
		var ty := int(part["ty"])
		var tiso := WG.tile_to_world(tx, ty)
		var wp: Vector3 = rend.call("iso_to_3d", tiso, rend.call("height_at", tiso))
		_add_ghost_building(part, Transform3D(Basis.IDENTITY, wp), root, _part_variant(tx, ty))


func _new_ghost_root(rend: Node) -> Node3D:
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	var root: Node = rend.get("terrain_root")
	if root == null:
		return null
	_ghost_root = Node3D.new()
	_ghost_root.top_level = true
	root.add_child(_ghost_root)
	return _ghost_root


## Add one structure's translucent model to the ghost root at `local` (root-space).
func _add_ghost_building(part: Dictionary, local: Transform3D, root: Node3D, variant: int) -> void:
	var ent := _ghost_entity_for(part, variant)
	if ent == null:
		return
	var parts: Array = PropMeshes.entity_parts(ent)
	ent.free()
	if parts.is_empty():
		return
	var bnode := Node3D.new()
	bnode.transform = local
	root.add_child(bnode)
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)).scaled(p["scl"]), p["off"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _ghost_material(p["mat"])
		bnode.add_child(mi)


## A translucent copy of a part's material (cached per source so big settlements don't
## re-duplicate the same handful of shared materials on every rebuild).
func _ghost_material(src: Variant) -> Material:
	if src == null or not (src is StandardMaterial3D):
		return src
	var id := (src as Resource).get_instance_id()
	if _ghost_mat_cache.has(id):
		return _ghost_mat_cache[id]
	var gm: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var col: Color = gm.albedo_color
	col.a = 0.6
	gm.albedo_color = col
	_ghost_mat_cache[id] = gm
	return gm


## A throwaway WorldEntity for a structure part, so PropMeshes.entity_parts() yields the same
## model the placed structure will use. Mirrors the spawner's part→entity mapping.
func _ghost_entity_for(part: Dictionary, variant: int) -> Node2D:
	var kind := str(part.get("kind", ""))
	var e := WorldEntity.new()
	e.kind = kind
	e.label = str(part.get("label", ""))
	e.variant = variant
	e.display_size = 40.0
	e.roof_alpha = 1.0
	var roof := _roof_color_for(part, variant)
	match kind:
		"tent":
			e.display_size = 54.0
			e.tent_color = roof
			e.glow_color = roof
		"house":
			e.roof_color = roof
		"building":
			e.display_size = float(part.get("foot", 6))
			e.roof_color = roof
		"mountain":
			e.display_size = float(part.get("foot", 3))
			e.mountain_snow = float(part.get("snow", 0.4))
		"city_wall":
			e.variant = int(part.get("piece", 0))
		"city_prop":
			e.prop_kind = str(part.get("prop", "crate"))
		"decor":
			e.prop_kind = str(part.get("prop", "grass"))
		"obelisk":
			e.attuned = true
	return e


func _roof_color_for(part: Dictionary, variant: int) -> Color:
	if part.has("color"):
		return Color.from_string("#" + str(part["color"]), Color(0.5, 0.3, 0.3))
	return Color.from_string("#" + str(ROOF_COLORS[variant % ROOF_COLORS.size()]), Color(0.5, 0.3, 0.3))


## Deterministic per-tile model variant — used for both the settlement ghost and the placed
## parts (stored on each), so the spawned cluster matches what the ghost showed.
func _part_variant(tx: int, ty: int) -> int:
	return absi(hash(str(tx) + ":" + str(ty))) % 1000


## Re-roll the look of both the sidebar preview and the in-world ghost (and so the next
## structure placed, which adopts the ghost's variant/roof).
func _reroll_variant() -> void:
	_ghost_variant = (_ghost_variant + 1) % 9973
	_ghost_sig = ""   # force the ghost meshes to rebuild with the new look
	if _preview != null:
		_preview.reroll()


func _ensure_hover_gizmo(rend: Node) -> void:
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		return
	var root: Node = rend.get("terrain_root")
	if root == null:
		return
	_gizmo_root = Node3D.new()
	_gizmo_root.top_level = true   # we drive global_position directly
	root.add_child(_gizmo_root)
	_gizmo_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.06
	cyl.radial_segments = 40
	_gizmo_disc.mesh = cyl
	_gizmo_disc.material_override = _gizmo_mat(Color(1.0, 0.92, 0.3, 0.22))
	_gizmo_root.add_child(_gizmo_disc)
	_gizmo_foot = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.06, 2.0)   # ±1 unit square → ±radius once scaled
	_gizmo_foot.mesh = box
	_gizmo_foot.material_override = _gizmo_mat(Color(0.4, 0.85, 1.0, 0.28))
	_gizmo_root.add_child(_gizmo_foot)


func _gizmo_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true              # always visible over the terrain
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Persistent green beacon marking the player spawn in the 3D view: a ground ring, a vertical
## beam and a floating diamond head, built once per embedded world (child of the terrain root)
## and sized in tile-units so it scales with the iso→3D mapping. Repositioned each frame so it
## stays glued to the spawn tile as you elevate terrain or move the spawn point.
func _ensure_spawn_marker3d(rend: Node) -> void:
	if _spawn_marker3d != null and is_instance_valid(_spawn_marker3d):
		return
	var root: Node = rend.get("terrain_root")
	if root == null:
		return
	_spawn_marker3d = Node3D.new()
	_spawn_marker3d.top_level = true   # we drive global_position + scale directly
	root.add_child(_spawn_marker3d)
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.05
	rc.bottom_radius = 1.05
	rc.height = 0.05
	rc.radial_segments = 40
	ring.mesh = rc
	ring.material_override = _gizmo_mat(SPAWN_MARK * Color(1, 1, 1, 0.30))
	_spawn_marker3d.add_child(ring)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.09
	pc.bottom_radius = 0.09
	pc.height = 3.2
	pole.mesh = pc
	pole.position = Vector3(0.0, 1.6, 0.0)
	pole.material_override = _gizmo_mat(SPAWN_MARK * Color(1, 1, 1, 0.55))
	_spawn_marker3d.add_child(pole)
	var head := MeshInstance3D.new()
	var hc := SphereMesh.new()           # low-segment sphere reads as a faceted gem from the air
	hc.radius = 0.5
	hc.height = 1.1
	hc.radial_segments = 6
	hc.rings = 3
	head.mesh = hc
	head.position = Vector3(0.0, 3.5, 0.0)
	head.material_override = _gizmo_mat(SPAWN_MARK)
	_spawn_marker3d.add_child(head)


## Orange beacon at the picked Test Level spawn (mirrors the green game-spawn beacon, distinct colour).
func _update_test_spawn_marker3d() -> void:
	var unset := _test_spawn_tile.x == -2147483648
	if not _v3d_on or _v3d_world == null or unset:
		if _test_spawn_marker3d != null and is_instance_valid(_test_spawn_marker3d):
			_test_spawn_marker3d.visible = false
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("iso_to_3d"):
		return
	_ensure_test_marker3d(rend)
	if _test_spawn_marker3d == null:
		return
	_test_spawn_marker3d.visible = true
	var iso := WG.tile_to_world(_test_spawn_tile.x, _test_spawn_tile.y)
	var h: float = rend.call("height_at", iso)
	var center: Vector3 = rend.call("iso_to_3d", iso, h)
	var edge: Vector3 = rend.call("iso_to_3d", iso + Vector2(WG.TILE, 0.0), h)
	var s := maxf(0.4, center.distance_to(edge))
	_test_spawn_marker3d.scale = Vector3(s, s, s)
	_test_spawn_marker3d.global_position = center


func _ensure_test_marker3d(rend: Node) -> void:
	if _test_spawn_marker3d != null and is_instance_valid(_test_spawn_marker3d):
		return
	var root: Node = rend.get("terrain_root")
	if root == null:
		return
	_test_spawn_marker3d = Node3D.new()
	_test_spawn_marker3d.top_level = true
	root.add_child(_test_spawn_marker3d)
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.05
	rc.bottom_radius = 1.05
	rc.height = 0.05
	rc.radial_segments = 40
	ring.mesh = rc
	ring.material_override = _gizmo_mat(TEST_SPAWN_MARK * Color(1, 1, 1, 0.35))
	_test_spawn_marker3d.add_child(ring)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.08
	pc.bottom_radius = 0.08
	pc.height = 2.6
	pole.mesh = pc
	pole.position = Vector3(0.0, 1.3, 0.0)
	pole.material_override = _gizmo_mat(TEST_SPAWN_MARK * Color(1, 1, 1, 0.7))
	_test_spawn_marker3d.add_child(pole)
	var head := MeshInstance3D.new()
	var hc := SphereMesh.new()
	hc.radius = 0.42
	hc.height = 0.9
	hc.radial_segments = 6
	hc.rings = 3
	head.mesh = hc
	head.position = Vector3(0.0, 2.7, 0.0)
	head.material_override = _gizmo_mat(TEST_SPAWN_MARK)
	_test_spawn_marker3d.add_child(head)


## Reposition + show/hide the 3D spawn beacon. Cheap enough to run every frame in 3D; also
## called right after _set_spawn so the marker snaps to a freshly-placed spawn immediately.
func _update_spawn_marker3d() -> void:
	if not _v3d_on or _v3d_world == null:
		if _spawn_marker3d != null and is_instance_valid(_spawn_marker3d):
			_spawn_marker3d.visible = false
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("iso_to_3d"):
		return
	_ensure_spawn_marker3d(rend)
	if _spawn_marker3d == null:
		return
	_spawn_marker3d.visible = _show_spawn
	if not _show_spawn:
		return
	var iso := WG.tile_to_world(_spawn_tile.x, _spawn_tile.y)
	var h: float = rend.call("height_at", iso)
	var center: Vector3 = rend.call("iso_to_3d", iso, h)
	var edge: Vector3 = rend.call("iso_to_3d", iso + Vector2(WG.TILE, 0.0), h)
	var s := maxf(0.4, center.distance_to(edge))   # one tile → world units, keeps the beacon scaled
	_spawn_marker3d.scale = Vector3(s, s, s)
	_spawn_marker3d.global_position = center


func _hide_hover_gizmo() -> void:
	_hide_flat_gizmo()
	_hide_ghost()


func _hide_flat_gizmo() -> void:
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.visible = false


func _hide_ghost() -> void:
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.visible = false


func _resync_3d_tiles(tiles: Array) -> void:
	if not _v3d_on or _v3d_world == null:
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("rebuild_chunk"):
		return
	var seen := {}
	for t: Vector2i in tiles:
		var cx := floori(float(t.x) / float(WG.CHUNK_TILES))
		var cy := floori(float(t.y) / float(WG.CHUNK_TILES))
		var k := Vector2i(cx, cy)
		if seen.has(k):
			continue
		seen[k] = true
		rend.call("rebuild_chunk", cx, cy)
	# Elevation/terrain edits move the ground under static clutter — drop those props' cached height
	# so the batch re-samples them (otherwise trees/rocks float above the lowered/raised surface).
	if rend.has_method("reset_prop_transforms_in_rect") and not tiles.is_empty():
		rend.call("reset_prop_transforms_in_rect", _tiles_world_rect(tiles))


## Put the embedded camera into the aerial "satellite" framing: steep top-down-ish
## pitch + a wide zoom-out so you survey the region, not a player's-eye iso shot.
func _apply_v3d_satellite_camera() -> void:
	if _v3d_world == null:
		return
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("_cam_pitch", _V3D_SAT_PITCH)
	var cam2d: Node = _v3d_world.get("_camera")
	if cam2d != null:
		cam2d.set("zoom", Vector2(_v3d_zoom, _v3d_zoom))


## Input inside the maximized aerial view (mouse_filter STOP routes it here):
##   left-click  -> place the selected structure/stamp at the cursor (or set spawn)
##   right-drag  -> pan the aerial camera across the map
##   wheel       -> zoom the aerial view in/out
func _on_v3d_gui_input(event: InputEvent) -> void:
	if _testing:
		return   # don't accept_event() — let clicks fall through to the embedded (playing) world
	if not _v3d_on or _busy:
		return
	# Set Test Spawn: the next left-click in the 3D view picks the Test Level spawn tile.
	if _picking_test_spawn and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var st := _v3d_tile_under_mouse()
		if st.x != -2147483648 and _in_bounds_tile(st):
			_test_spawn_tile = st
			_status.text = "Test Level spawn set to (%d, %d)." % [st.x, st.y]
		_picking_test_spawn = false
		_v3d_container.accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _is_rotatable_tool(): _rotate_placement(1)
			else: _v3d_zoom_by(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _is_rotatable_tool(): _rotate_placement(-1)
			else: _v3d_zoom_by(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_v3d_panning = event.pressed
			_v3d_pan_prev = _v3d_container.get_local_mouse_position()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _tool == Tool.ROAD:
				if event.pressed: _v3d_road_begin()
				else: _v3d_road_end()
			elif _tool in [Tool.BIOME, Tool.TERRAIN, Tool.ERASE, Tool.SMOOTHEN, Tool.ELEVATE, Tool.FOREST, Tool.CLUTTER, Tool.GRASS]:
				# Brush + terrain-sculpt tools paint directly in the 3D view where the
				# height is visible. _process keeps _hover_tile under the 3D cursor.
				_v3d_painting = event.pressed
				if event.pressed:
					_begin_stroke()
					_apply_tool(true)
					_resync_3d_instant(_hover_tile)   # live, flicker-free feedback as you sculpt
				else:
					_commit_stroke()                  # full neighbour-seam reconcile (also in-place)
			elif event.pressed:
				_v3d_place_at_cursor()
		_v3d_container.accept_event()
	elif event is InputEventMagnifyGesture:
		_v3d_zoom_by(event.factor)            # trackpad pinch
		_v3d_container.accept_event()
	elif event is InputEventMouseMotion and _v3d_panning:
		_v3d_pan_drag()
		_v3d_container.accept_event()
	elif event is InputEventMouseMotion and _v3d_painting:
		var pt := _v3d_tile_under_mouse()
		if pt.x != -2147483648:
			_hover_tile = pt
			_apply_tool(false)
			_resync_3d_instant(_hover_tile)    # remesh just the touched chunk live (no flicker)
		_v3d_container.accept_event()
	elif event is InputEventMouseMotion and _road_drawing:
		var tl := _v3d_tile_under_mouse()
		if tl.x != -2147483648 and (_road_pts.is_empty() or _road_pts[_road_pts.size() - 1] != tl):
			_road_pts.append(tl)
		_v3d_container.accept_event()


func _v3d_road_begin() -> void:
	var tile := _v3d_tile_under_mouse()
	if tile.x == -2147483648:
		return
	_begin_stroke()
	_road_pts.clear()
	_road_pts.append(tile)
	_road_drawing = true
	_status.text = "Drawing road in 3D… drag, release to finish."


func _v3d_road_end() -> void:
	if not _road_drawing:
		return
	var mid: Vector2i = _road_pts[_road_pts.size() / 2] if not _road_pts.is_empty() else Vector2i.ZERO
	_commit_stroke()   # finalizes the road (paints tiles, builds bridges) + resyncs 3D
	_refresh_3d_entities(mid)


func _v3d_place_at_cursor() -> void:
	var iso := _v3d_screen_iso(_v3d_container.get_local_mouse_position())
	var tile := _v3d_tile_under_mouse()
	if tile.x == -2147483648 or not _in_bounds_tile(tile):
		return
	# Free placement: drop the structure at the EXACT cursor point, not the tile centre, so you
	# can nudge several decor pieces together without the grid snapping them into rows.
	_place_off = (iso - WG.tile_to_world(tile.x, tile.y)) if iso != Vector2.INF else Vector2.ZERO
	match _tool:
		Tool.STRUCTURE:
			_begin_stroke(); _place_structure(tile); _commit_stroke()
			_refresh_3d_entities(tile)
		Tool.STAMP:
			_begin_stroke(); _place_stamp(tile); _commit_stroke()
			_refresh_3d_entities(tile)
		Tool.SPAWN:
			_begin_stroke(); _set_spawn(tile); _commit_stroke()
		Tool.SETTLEMENT:
			_begin_stroke(); _place_settlement(tile); _commit_stroke()
			_refresh_3d_entities(tile)
		Tool.CREATURE:
			_begin_stroke(); _place_creature(tile); _commit_stroke()
		Tool.SKILL:
			_begin_stroke(); _place_skill(tile); _commit_stroke()
			_refresh_3d_entities(tile)
		Tool.SELECT:
			if _sel_moving:
				_move_selection_to(tile)
			else:
				_select_object_at(tile)
		_:
			_status.text = "Pick a Structure/Stamp/Road/Settlement/Creature/Skills/Select tool, then click. (%d, %d)" % [tile.x, tile.y]


func _v3d_zoom_by(factor: float) -> void:
	# Wide range: ~0.06 surveys a big stretch of the world (terrain cap fogs the far
	# edge), 1.8 is close-in placement. Pinch + wheel both route here.
	_v3d_zoom = clampf(_v3d_zoom * factor, 0.06, 1.8)
	var cam2d: Node = _v3d_world.get("_camera") if _v3d_world != null else null
	if cam2d != null:
		cam2d.set("zoom", Vector2(_v3d_zoom, _v3d_zoom))


## Grab-the-map pan: move the camera focus by the world delta the cursor dragged.
func _v3d_pan_drag() -> void:
	var cur := _v3d_container.get_local_mouse_position()
	var prev_iso := _v3d_screen_iso(_v3d_pan_prev)
	var cur_iso := _v3d_screen_iso(cur)
	_v3d_pan_prev = cur
	if prev_iso == Vector2.INF or cur_iso == Vector2.INF:
		return
	_v3d_set_focus_world(_v3d_focus_pos + (prev_iso - cur_iso))


## Move the aerial camera to a float world position (keeps sub-tile precision for
## smooth WASD / drag panning; the embedded world re-centres on the rounded tile).
func _v3d_set_focus_world(pos: Vector2) -> void:
	_v3d_focus_pos = pos
	_focus_3d(WG.world_to_tile(pos))


## WASD fly-over: pan the aerial camera in screen-relative directions (W = toward the
## top of the view), at a constant screen speed regardless of zoom. Called each frame.
func _v3d_wasd(delta: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1.0
	if mv == Vector2.ZERO:
		return
	var c := _v3d_container.size * 0.5
	var o := _v3d_screen_iso(c)
	var rx := _v3d_screen_iso(c + Vector2(60.0, 0.0))
	var ry := _v3d_screen_iso(c + Vector2(0.0, 60.0))
	if o == Vector2.INF or rx == Vector2.INF or ry == Vector2.INF:
		return
	var world_delta := ((rx - o) * mv.x + (ry - o) * mv.y) / 60.0 * 900.0 * delta
	_v3d_set_focus_world(_v3d_focus_pos + world_delta)


## Container-local mouse -> world iso position via the embedded camera ground raycast.
func _v3d_screen_iso(local: Vector2) -> Vector2:
	if _v3d_world == null or _v3d_vp == null:
		return Vector2.INF
	var rend: Node = _v3d_world.get("render_3d")
	if rend == null or not rend.has_method("screen_to_iso"):
		return Vector2.INF
	var csize := _v3d_container.size
	if csize.x <= 0.0 or csize.y <= 0.0:
		return Vector2.INF
	var sub_px := Vector2(local.x / csize.x, local.y / csize.y) * Vector2(_v3d_vp.size)
	return rend.call("screen_to_iso", sub_px)


## World tile under the 3D-view cursor (or sentinel x when off-map / no view).
func _v3d_tile_under_mouse() -> Vector2i:
	var iso := _v3d_screen_iso(_v3d_container.get_local_mouse_position())
	if iso == Vector2.INF:
		return Vector2i(-2147483648, 0)
	return WG.world_to_tile(iso)


## Respawn the embedded world's entities for the placed tile's chunk (+ neighbours, so
## footprints that cross a chunk border show), then force a static-batch rebuild so the
## new structure appears in the 3D view without a reload.
## Respawn native decor/canopy for every chunk a paint stroke touched (deduped), so repainting a
## biome swaps its scatter. Editor-placed structures persist (they're stored on the chunk).
func _refresh_painted_entities(tiles: Array) -> void:
	var seen := {}
	for t: Vector2i in tiles:
		var c := WG.tile_to_chunk(t)
		var k := "%d:%d" % [c.x, c.y]
		if seen.has(k):
			continue
		seen[k] = true
		_refresh_3d_entities(t, true)   # biome/terrain edits → regrow native canopy for the new biome


## Respawn 3D entities for every chunk named in a list of structure records ({key:"cx:cy",...}), so
## brush-placed trees/clutter — and undo/redo of them — show up in the 3D view immediately.
func _refresh_struct_chunks(items: Array) -> void:
	var seen := {}
	for a: Dictionary in items:
		var k: String = a["key"]
		if seen.has(k):
			continue
		seen[k] = true
		var p := k.split(":")
		_refresh_3d_entities(Vector2i(int(p[0]) * WG.CHUNK_TILES + 8, int(p[1]) * WG.CHUNK_TILES + 8), false)


func _refresh_3d_entities(tile: Vector2i, regen_canopy := false) -> void:
	if _v3d_world == null:
		return
	var sp: Object = _v3d_world.get("_entity_spawner")
	var containers: Dictionary = _v3d_world.get("_chunk_containers")
	if sp == null or containers == null:
		return
	var c0 := WG.tile_to_chunk(tile)
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var chunk: RefCounted = _chunks.get("%d:%d" % [c0.x + dx, c0.y + dy])
			if chunk == null or not containers.has(chunk.key()):
				continue
			sp.call("on_chunk_unloaded", chunk)
			if regen_canopy and sp.has_method("clear_ambient_canopy"):
				sp.call("clear_ambient_canopy", chunk)   # drop old biome's trees so new ones grow
			sp.call("on_chunk_loaded", chunk, true)
	var rend: Node = _v3d_world.get("render_3d")
	if rend != null:
		rend.set("_static_sig", "")   # force the static prop batch to rebuild


func _in_bounds_tile(t: Vector2i) -> bool:
	return t.x >= _min_tx and t.x < _min_tx + _w and t.y >= _min_ty and t.y < _min_ty + _h


func _toolbar_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _overlay_check(parent: Control, text: String, on: bool, cb: Callable) -> CheckBox:
	var cb_box := CheckBox.new()
	cb_box.text = text
	cb_box.button_pressed = on
	cb_box.toggled.connect(cb)
	parent.add_child(cb_box)
	return cb_box


func _track_ui_hover(_ctrl: Node) -> void:
	# No-op: _ui_hover is derived each frame from gui_get_hovered_control() in
	# _process (per-control enter/exit wrongly flips false when moving onto a
	# child button). Kept as a hook in case per-panel handling is wanted later.
	pass


func _set_tool(t: int) -> void:
	_tool = t
	for k: int in _tool_buttons:
		(_tool_buttons[k] as Button).button_pressed = (k == t)
	# The Skills group has one button per skill (all map to Tool.SKILL); highlight the active skill.
	for sk: String in _skill_tool_buttons:
		(_skill_tool_buttons[sk] as Button).button_pressed = (t == Tool.SKILL and sk == _sel_skill)
	if t == Tool.SMOOTHEN or t == Tool.ELEVATE:
		_show_elevation = true   # so you can see height change live as you brush
		if _elev_check != null:
			_elev_check.button_pressed = true
	_refresh_palette()


func _set_brush(v: int) -> void:
	_brush = clampi(v, 1, 24)
	if _brush_label != null:
		_brush_label.text = "Brush size: %d" % _brush


## Stamps and settlements rotate in 90° steps; the scroll wheel turns them (when one of
## those tools is selected) instead of zooming. Structures have no rotation field yet.
func _is_rotatable_tool() -> bool:
	return _tool == Tool.STAMP or _tool == Tool.SETTLEMENT or _tool == Tool.STRUCTURE or _tool == Tool.SELECT


func _rotate_placement(dir: int) -> void:
	if _tool == Tool.SETTLEMENT:
		_settlement_rot = (_settlement_rot + dir + 4) % 4
		_status.text = "Settlement rotation: %d° (scroll / R to turn)" % (_settlement_rot * 90)
	elif _tool == Tool.SELECT:
		# Rotate the GRABBED object in fine steps and write it straight back.
		if _sel_chunk != null and _sel_index >= 0 and _sel_index < _sel_chunk.structures.size():
			var part: Dictionary = _sel_chunk.structures[_sel_index]
			part["yaw"] = wrapf(float(part.get("yaw", 0.0)) + dir * (TAU / float(STRUCT_ROT_STEPS)), 0.0, TAU)
			_sel_chunk.structures[_sel_index] = part
			_refresh_struct_chunks([{"key": "%d:%d" % [_sel_chunk.cx, _sel_chunk.cy]}])
			_status.text = "Rotated %s to %d°" % [str(part.get("prop", part.get("kind", "object"))), int(round(rad_to_deg(float(part["yaw"]))))]
	elif _tool == Tool.STRUCTURE:
		_struct_rot = (_struct_rot + dir + STRUCT_ROT_STEPS) % STRUCT_ROT_STEPS
		_status.text = "Structure rotation: %d° (scroll / R to turn, 15° steps)" % int(round(_struct_rot * 360.0 / STRUCT_ROT_STEPS))
	else:
		_stamp_rot = (_stamp_rot + dir + 4) % 4
		_status.text = "Stamp rotation: %d° (scroll / R to turn)" % (_stamp_rot * 90)


## Yaw (radians) for the STRUCTURE ghost/placement from the fine rotation step.
func _struct_yaw() -> float:
	return float(_struct_rot) * (TAU / float(STRUCT_ROT_STEPS))


func _refresh_palette() -> void:
	if _palette_box == null:
		return
	if _opts_title != null:
		_opts_title.text = str(TOOL_NAMES.get(_tool, "Options"))
	_selected_choice_btn = null
	for c: Node in _palette_box.get_children():
		c.queue_free()
	match _tool:
		Tool.BIOME:
			_header(_palette_box, "Parent biomes")
			for e: Dictionary in WorldGen.list_surface_biomes():
				_choice(str(e["name"]), str(e["id"]), _sel_biome == str(e["id"]),
					func(id: String) -> void: _sel_biome = id)
			_header(_palette_box, "Micro-biomes")
			for e: Dictionary in WorldGen.list_sub_biomes():
				_choice("  " + str(e["name"]), str(e["id"]), _sel_biome == str(e["id"]),
					func(id: String) -> void: _sel_biome = id)
		Tool.TERRAIN:
			_header(_palette_box, "Terrain / roads / walls")
			for e: Array in TERRAIN:
				_choice(str(e[1]), str(e[0]), _sel_terrain == str(e[0]),
					func(id: String) -> void: _sel_terrain = id)
		Tool.STAMP:
			_header(_palette_box, "Natural stamps")
			var stamps: Array = StampLibrary.all()
			for i: int in stamps.size():
				var ii := i
				_choice(str(stamps[i]["name"]), str(i), _sel_stamp == i,
					func(_id: String) -> void:
						_sel_stamp = ii
						_stamp_variant = 0)
			if _sel_stamp < stamps.size():
				_add_stamp_preview(stamps[_sel_stamp])
			_note("Click to place. R rotate, F flip. Each placement varies.")
		Tool.STRUCTURE:
			_build_structure_accordion()
		Tool.SKILL:
			_build_skill_nodes()
		Tool.CREATURE:
			_header(_palette_box, "Enemy spawn")
			_note("Click a walkable tile to drop a spawn of the selected creature. The pack scatters\nacross the spawn area and wanders it; set how far it roams, how close you must get to\nbe attacked, and how far you can drag it before it gives up.")
			_param_slider("Pack size: %d", _creature_count, 1, 12, func(v: int) -> void: _creature_count = v)
			_param_slider("Wander radius: %d", _creature_wander, 1, 24, func(v: int) -> void: _creature_wander = v)
			_param_slider("Aggro dist (0=auto): %d", _creature_aggro, 0, 24, func(v: int) -> void: _creature_aggro = v)
			_param_slider("Leave dist (0=auto): %d", _creature_leash, 0, 40, func(v: int) -> void: _creature_leash = v)
			var ck := CheckBox.new()
			ck.text = "Aggressive (auto-attacks)"
			ck.button_pressed = _creature_aggressive
			ck.toggled.connect(func(on: bool) -> void: _creature_aggressive = on)
			_palette_box.add_child(ck)
			_header(_palette_box, "Creature")
			for e: Dictionary in _creature_list():
				var nm := str(e["name"])
				_choice("%s  ·  Lv%d" % [nm, int(e["level"])], nm, _sel_creature == nm,
					func(id: String) -> void: _sel_creature = id)
		Tool.SPAWN:
			_note("Click a walkable tile to set the player spawn. Current: (%d, %d)" % [_spawn_tile.x, _spawn_tile.y])
		Tool.ERASE:
			_note("Brush to remove placed structures, monsters, ambient trees AND painted roads/terrain — reverting each tile to its original generated biome + elevation (undoes smoothen/elevate too). Tick 'Keep painted terrain' to remove only placed objects and leave the terrain as-is.")
		Tool.ROAD:
			_header(_palette_box, "Road style")
			for sname: String in _road_styles().keys():
				_choice(str(sname).capitalize(), str(sname), _sel_road_style == str(sname),
					func(id: String) -> void: _sel_road_style = id)
			_road_width_label = Label.new()
			_road_width_label.text = "Road width: %d" % _road_width
			_palette_box.add_child(_road_width_label)
			var rwslider := HSlider.new()
			rwslider.min_value = 1
			rwslider.max_value = 12
			rwslider.step = 1
			rwslider.value = _road_width
			rwslider.custom_minimum_size = Vector2(210, 0)
			rwslider.value_changed.connect(func(v: float) -> void:
				_road_width = int(v)
				if _road_width_label != null:
					_road_width_label.text = "Road width: %d" % _road_width)
			_palette_box.add_child(rwslider)
			_note("Drag to draw a road - it auto-curves and bridges any water it crosses. The width slider sets its thickness (shown as a disc on the cursor). Ctrl+Z undoes the whole road; Ctrl+S saves the polylines to the worldspec.")
		Tool.SETTLEMENT:
			_header(_palette_box, "Settlements")
			var sdoc := _settlement_templates()
			var stmpls: Dictionary = sdoc.get("templates", {})
			var sorder: Array = sdoc.get("order", stmpls.keys())
			for sid: Variant in sorder:
				var lbl := str((stmpls.get(str(sid), {}) as Dictionary).get("label", str(sid).capitalize()))
				_choice(lbl, str(sid), _sel_settlement == str(sid),
					func(id: String) -> void: _sel_settlement = id)
			_note("Click to stamp a placeholder settlement (R rotates). Buildings drop as normal structures - edit each placement with the Structure/Erase tools.")
		Tool.SMOOTHEN:
			_header(_palette_box, "Smoothen / flatten")
			_note("Drag the brush over raised ground to lower and smooth it back toward the surroundings. Each pass steps the height down, so sweep (or hold) to melt a bump — or a whole mountain — down to flat. Never raises terrain. Works in both the 2D map and the 3D view. The 'Elevation' overlay turns on automatically so you can watch height drop. Ctrl+S saves directly to the world (no re-bake).")
		Tool.ELEVATE:
			_header(_palette_box, "Elevate / raise")
			_note("Drag (or hold) the brush to raise terrain into hills and mountains. A soft dome falloff means the brush centre rises fastest and the edges feather, building natural peaks — height shades grass→rock→snow on its own. Bigger brush = broader massif. Caps at the alpine summit height. Works in the 2D map and the 3D view. Ctrl+S saves directly (no re-bake).")
		Tool.GRASS:
			_header(_palette_box, "Grass (lush meadow)")
			_note("Drag / hold to carpet the ground in short, wind-swayed meadow grass. Brush size sets the swathe; Density sets how thick; Scale sets blade height. Works in the 2D map and 3D view; skips water, paths and floors. Grass is batched (one MultiMesh per chunk) so big meadows stay cheap. Use the Select tool to pick a tuft back up, or Erase to clear. Ctrl+S saves.")
		Tool.SELECT:
			_header(_palette_box, "Select / Move")
			if _sel_chunk == null or _sel_index < 0 or _sel_index >= _sel_chunk.structures.size():
				_note("Click a PLACED object (tree, building, decor, grass…) to grab it. Then Move it, rescale it, rotate it (scroll / R), or delete it. Roads aren't grabbed here — their look is data-driven: edit data/world/road_styles.json to restyle every road, or use Erase + Road to redraw.")
			else:
				var s: Dictionary = _sel_chunk.structures[_sel_index]
				_note("Grabbed: %s  (chunk %d:%d)" % [str(s.get("prop", s.get("label", s.get("kind", "object")))), _sel_chunk.cx, _sel_chunk.cy])
				var move_btn := Button.new()
				move_btn.text = "Move (then click a tile)" if not _sel_moving else "Click a tile to drop it…"
				move_btn.pressed.connect(func() -> void:
					_sel_moving = true
					_status.text = "Move: click the destination tile."
					_refresh_palette())
				_palette_box.add_child(move_btn)
				var del_btn := Button.new()
				del_btn.text = "Delete"
				del_btn.add_theme_color_override("font_color", Color(0.95, 0.5, 0.45))
				del_btn.pressed.connect(_delete_selection)
				_palette_box.add_child(del_btn)
				var rlabel := Label.new()
				var cur_scale := float(s.get("scale", 1.0))
				rlabel.text = "Rescale: %d%%" % int(round(cur_scale * 100.0))
				_palette_box.add_child(rlabel)
				var rs := HSlider.new()
				rs.min_value = 25; rs.max_value = 400; rs.step = 5; rs.value = cur_scale * 100.0
				rs.custom_minimum_size = Vector2(198, 0)
				rs.value_changed.connect(func(v: float) -> void:
					rlabel.text = "Rescale: %d%%" % int(v)
					_rescale_selection(v / 100.0))
				_palette_box.add_child(rs)
				_note("Scroll / R rotates the grabbed object in 15° steps. Move snaps it to a tile. Delete is undoable (Ctrl+Z); rescale/rotate are live — re-select to tweak. Ctrl+S saves.")
		_:
			_note("Right-drag to pan, wheel to zoom. Pick a tool to edit.")
	_update_preview()


## Skills palette: the OBJECTS for the skill picked in the sidebar. Combat shows the spawn controls
## + the bestiary; each gather skill lists its nodes by level. Clicking a tile places the selection.
func _build_skill_nodes() -> void:
	if _sel_skill.is_empty():
		_note("Pick a skill from the sidebar (Combat / Woodcutting / Mining / …).")
		return
	if _sel_skill == "combat":
		if _opts_title != null:
			_opts_title.text = "Skills · Combat"
		_note("Click a walkable tile to drop a pack of the selected creature.")
		_param_slider("Pack size: %d", _creature_count, 1, 12, func(v: int) -> void: _creature_count = v)
		_param_slider("Wander radius: %d", _creature_wander, 1, 24, func(v: int) -> void: _creature_wander = v)
		_param_slider("Aggro dist (0=auto): %d", _creature_aggro, 0, 24, func(v: int) -> void: _creature_aggro = v)
		_param_slider("Leave dist (0=auto): %d", _creature_leash, 0, 40, func(v: int) -> void: _creature_leash = v)
		var ck := CheckBox.new()
		ck.text = "Aggressive (auto-attacks)"
		ck.button_pressed = _creature_aggressive
		ck.toggled.connect(func(on: bool) -> void: _creature_aggressive = on)
		_palette_box.add_child(ck)
		_header(_palette_box, "Creature")
		for e: Dictionary in _creature_list():
			var nm := str(e["name"])
			_choice("%s  ·  Lv%d" % [nm, int(e["level"])], nm, _sel_skill_item == nm,
				func(id: String) -> void:
					_sel_skill_item = id
					_sel_creature = id
					_update_preview())
		return
	# Gather skill: list its nodes by level.
	var disp := str(SKILL_DISPLAY.get(_sel_skill, _sel_skill.capitalize()))
	if _opts_title != null:
		_opts_title.text = "Skills · " + disp
	if _sel_skill == "fishing":
		_note("Click a SHORE tile next to water to place a fishing spot (it auto-binds the water).")
	else:
		_note("Click a tile to place a working %s node." % disp.to_lower())
	var sorted: Array = _reg.node_table.get(_sel_skill, []).duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) < int(b["level"]))
	for e: Dictionary in sorted:
		var nm := str(e["name"])
		_choice("%s  ·  Lv%d" % [nm, int(e["level"])], nm, _sel_skill_item == nm,
			func(id: String) -> void:
				_sel_skill_item = id
				_update_preview())


## Place the selected skill resource at a tile: a monster pack (Combat) or a functional gather site.
func _place_skill(t: Vector2i) -> void:
	if _sel_skill == "combat":
		_place_creature(t)
		return
	if _sel_skill_item.is_empty():
		_status.text = "Pick a skill node first."
		return
	_place_skill_site(t, _sel_skill, _sel_skill_item)


## Append a working gather site (the same dict the runtime spawner builds) for a specific node, so
## it's immediately harvestable in Test Level and persists on save. Fishing binds an adjacent water
## tile so its school + cast have somewhere to go.
func _place_skill_site(t: Vector2i, skill: String, node_name: String) -> void:
	var chunk: RefCounted = _chunk_at_tile(t.x, t.y)
	if chunk == null:
		return
	var def: Dictionary = {}
	for e: Dictionary in _reg.node_table.get(skill, []):
		if str(e["name"]) == node_name:
			def = e
			break
	if def.is_empty():
		_status.text = "Unknown node '%s'." % node_name
		return
	var cfg: Dictionary = _reg.skill_cfg(skill)
	var lx: int = t.x - chunk.cx * WG.CHUNK_TILES
	var ly: int = t.y - chunk.cy * WG.CHUNK_TILES
	var site := {
		"skill": skill, "node": node_name, "level": int(def["level"]),
		"kind": str(cfg.get("kind", "bush")), "tx": lx, "ty": ly,
		"resources": int(cfg.get("resources", 8)), "remaining": int(cfg.get("resources", 8)),
		"respawn_sec": float(cfg.get("respawnSec", 25.0)), "available": true, "respawn_at": 0.0,
	}
	if skill == "fishing":
		var w := _adjacent_water_tile(chunk, lx, ly)
		if w.x < 0:
			_status.text = "Fishing spots need water beside them — click a shore tile next to water."
			return
		site["fish_tx"] = w.x
		site["fish_ty"] = w.y
	chunk.sites.append(site)
	_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "sites", "item": site})
	_status.text = "Placed %s — %s Lv%d" % [node_name, SKILL_DISPLAY.get(skill, skill.capitalize()), int(def["level"])]


## Nearest 4-neighbour water tile (local coords) beside (lx,ly), or (-1,-1). Used to anchor a
## fishing spot's school/cast to real water.
func _adjacent_water_tile(chunk: RefCounted, lx: int, ly: int) -> Vector2i:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = lx + off.x
		var ny: int = ly + off.y
		if nx < 0 or ny < 0 or nx >= WG.CHUNK_TILES or ny >= WG.CHUNK_TILES:
			continue
		if bool(_reg.tile_def(chunk.tile_id(nx, ny)).get("water", false)):
			return Vector2i(nx, ny)
	return Vector2i(-1, -1)


## Bestiary entries sorted by level then name, for the creature preview browser.
func _creature_list() -> Array:
	var out: Array = []
	for nm: String in DataRegistry.enemies:
		out.append({"name": nm, "level": int(DataRegistry.enemies[nm].get("level", 1))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	return out


## A labelled integer slider in the palette (label_fmt has one %d). cb gets the new int value.
func _param_slider(label_fmt: String, value: int, mn: int, mx: int, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_fmt % value
	_palette_box.add_child(lbl)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.value = value
	s.custom_minimum_size = Vector2(176, 0)
	s.value_changed.connect(func(v: float) -> void:
		cb.call(int(v))
		lbl.text = label_fmt % int(v))
	_palette_box.add_child(s)


## Drop an enemy spawn (a pack of `_creature_count`) around the clicked tile, scattered within the
## wander radius. Each mob gets the per-spawn wander/aggro/leash from the palette and roams its own
## spawn point. Records go into chunk.monsters (saved + undoable + carried through re-bakes).
func _place_creature(t: Vector2i) -> void:
	if _sel_creature.is_empty():
		_status.text = "Pick a creature first."
		return
	var lvl := int(DataRegistry.enemies.get(_sel_creature, {}).get("level", 1))
	var placed := 0
	for i: int in _creature_count:
		var ang := randf() * TAU
		var rad := (0.0 if i == 0 else sqrt(randf()) * float(_creature_wander))
		var gx := t.x + int(round(cos(ang) * rad))
		var gy := t.y + int(round(sin(ang) * rad))
		var chunk: RefCounted = _chunk_at_tile(gx, gy)
		if chunk == null:
			continue
		var lx: int = gx - chunk.cx * WG.CHUNK_TILES
		var ly: int = gy - chunk.cy * WG.CHUNK_TILES
		if bool(_reg.tile_def(chunk.tile_id(lx, ly)).get("water", false)):
			continue
		var m := {
			"name": _sel_creature, "level": lvl, "tx": lx, "ty": ly,
			"aggressive": _creature_aggressive, "wander": float(_creature_wander),
			"aggro": float(_creature_aggro), "leash": float(_creature_leash),
		}
		chunk.monsters.append(m)
		_stroke["added"].append({"key": "%d:%d" % [chunk.cx, chunk.cy], "arr": "monsters", "item": m})
		placed += 1
	_status.text = "Placed %d × %s (Lv%d)" % [placed, _sel_creature, lvl]


## Drive the showcase turntable from the current tool + selection.
func _update_preview() -> void:
	if _preview == null:
		return
	match _tool:
		Tool.BIOME:
			_preview.show_biome(_sel_biome)
		Tool.TERRAIN:
			var label := _sel_terrain
			for e: Array in TERRAIN:
				if str(e[0]) == _sel_terrain:
					label = str(e[1])
			_preview.show_terrain(_sel_terrain, label)
		Tool.STRUCTURE:
			var entry: Array = STRUCTURES[_sel_struct]
			_preview.show_structure((entry[1] as Dictionary), str(entry[0]))
		Tool.STAMP:
			var stamps: Array = StampLibrary.all()
			if _sel_stamp < stamps.size():
				_preview.show_stamp(stamps[_sel_stamp], str(stamps[_sel_stamp]["name"]))
		Tool.SETTLEMENT:
			var sdoc := _settlement_templates()
			var sdef: Dictionary = (sdoc.get("templates", {}) as Dictionary).get(_sel_settlement, {})
			var slbl := str(sdef.get("label", _sel_settlement.capitalize()))
			# Side panel shows a representative dwelling; the in-world ghost shows the full cluster.
			_preview.show_structure({"kind": "house", "label": slbl}, slbl)
		Tool.CREATURE:
			if _sel_creature.is_empty():
				_preview.show_empty("No creatures in the bestiary")
			else:
				_preview.show_creature(_sel_creature)
		Tool.SKILL:
			if _sel_skill == "combat":
				if _sel_skill_item.is_empty():
					_preview.show_empty("Pick a creature to spawn")
				else:
					_preview.show_creature(_sel_skill_item)
			elif _sel_skill_item.is_empty():
				_preview.show_empty("Pick a skill node to place")
			else:
				var skind := str(_reg.skill_cfg(_sel_skill).get("kind", "bush"))
				if skind in ["tree", "rock", "bush"]:
					_preview.show_structure({"kind": skind, "label": _sel_skill_item}, _sel_skill_item)
				else:
					_preview.show_empty(_sel_skill_item)
		_:
			_preview.show_empty("Pick a paint/place tool to preview")


# ───────────────────────── structure accordion ──────────────────────────────
# Ordered category list. Each structure is bucketed by _struct_category(); categories render
# as collapsible headers so the long list is browsable instead of one flat scroll.
const STRUCT_CATEGORY_ORDER := [
	"Buildings", "Walls & fences", "Town props", "Medieval props", "Camp & light",
	"Stable & farm", "Furniture & fittings", "Graveyard", "Dark moor", "Fairy",
	"Ruins & monuments", "Landmarks", "Trees & nature", "Decor · plants", "Decor · fungi",
	"Decor · rocks", "Decor · wood", "Decor · desert", "Decor · snow & ice", "Decor · coastal",
	"Decor · camp props", "Other"]


func _build_structure_accordion() -> void:
	# Bucket every structure index by category (preserving list order within a bucket).
	var buckets: Dictionary = {}
	for i: int in STRUCTURES.size():
		var cat := _struct_category(STRUCTURES[i][1] as Dictionary)
		if not buckets.has(cat):
			buckets[cat] = []
		buckets[cat].append(i)
	# Auto-open the category holding the current selection so it's always visible.
	var sel_cat := _struct_category(STRUCTURES[_sel_struct][1] as Dictionary)
	for cat: String in STRUCT_CATEGORY_ORDER:
		if not buckets.has(cat):
			continue
		var open := bool(_struct_open.get(cat, cat == sel_cat))
		_accordion_header(cat, open, buckets[cat].size())
		if not open:
			continue
		for i: int in buckets[cat]:
			var ii := i
			_choice("  " + str(STRUCTURES[i][0]), str(i), _sel_struct == i,
				func(_id: String) -> void: _sel_struct = ii)


func _accordion_header(cat: String, open: bool, count: int) -> void:
	var b := Button.new()
	b.text = ("▾ " if open else "▸ ") + cat + "  (%d)" % count
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(176, 0)
	b.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	b.pressed.connect(func() -> void:
		_struct_open[cat] = not open
		_refresh_palette())
	_palette_box.add_child(b)


func _struct_category(part: Dictionary) -> String:
	var kind := str(part.get("kind", ""))
	var prop := str(part.get("prop", ""))
	match kind:
		"house", "building", "tent": return "Buildings"
		"city_wall": return "Walls & fences"
		"fountain", "sign", "anvil", "chest", "altar", "stall": return "Town props"
		"campfire", "lantern": return "Camp & light"
		"obelisk", "ruin_arch", "ruin_pillar", "broken_wall", "rubble_pile", "broken_statue": return "Ruins & monuments"
		"mammoth", "meteor", "bridge": return "Landmarks"
		"tree", "bush", "rock": return "Trees & nature"
		"city_prop":
			return _city_prop_category(prop)
		"decor":
			return _decor_category(prop)
	return "Other"


func _city_prop_category(prop: String) -> String:
	if prop == "lamp" or prop == "lantern": return "Camp & light"
	if prop in ["gravestone", "gravestone_cross", "tomb", "crypt", "grave_mound", "coffin",
			"bone_pile", "grave_urn", "mourning_statue", "iron_fence", "grave_candle"]:
		return "Graveyard"
	if prop in ["dead_tree", "gnarled_stump", "gallows", "standing_stone_dark", "crooked_post",
			"raven_perch", "withered_bush", "wisp_lantern", "peat_stack"]:
		return "Dark moor"
	if prop in ["fairy_ring", "giant_toadstool", "glow_mushroom", "glow_crystal", "flower_arch",
			"toadstool_house", "fairy_lantern", "bluebells"]:
		return "Fairy"
	if prop in ["stable", "hay_bale", "hitching_post", "feed_trough", "saddle_rack", "paddock_fence"]:
		return "Stable & farm"
	if prop in ["weapon_rack", "bookcase", "shelf", "table", "chair", "bench", "bed", "candelabra",
			"cauldron", "fireplace", "barrel_rack", "crate_stack", "alchemy_table", "throne", "lectern"]:
		return "Furniture & fittings"
	if prop in ["signpost", "banner", "torch", "brazier", "water_trough", "market_awning",
			"grindstone", "archery_target", "training_dummy", "stocks", "hanging_sign", "forge"]:
		return "Medieval props"
	return "Town props"   # well, crate, barrel, cart, hay, flowerbox


func _decor_category(prop: String) -> String:
	if prop == "fence_post": return "Walls & fences"
	if prop in ["boulder", "rock_pile", "cairn", "standing_stone", "crystal", "geode", "pebble"]: return "Decor · rocks"
	if prop in ["log", "log_pile", "branch", "tree_roots", "mossy_log"]: return "Decor · wood"
	if prop in ["agave", "tumbleweed", "sagebrush", "animal_skull"]: return "Decor · desert"
	if prop in ["snow_patch", "ice_shard", "frozen_shrub"]: return "Decor · snow & ice"
	if prop in ["seashell", "starfish", "coral"]: return "Decor · coastal"
	if prop in ["toadstool", "mushroom_cluster", "bracket_fungus", "mushroom"]: return "Decor · fungi"
	if prop in ["barrel", "crate", "sack", "hay_bale", "bucket", "signpost", "anthill"]: return "Decor · camp props"
	return "Decor · plants"   # flowers, fern, reed, shrub, grass, cattail, thistle, berry, clover, lily pad, dandelion


func _header(parent: Control, text: String) -> void:
	var h := Label.new()
	h.text = text
	h.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	parent.add_child(h)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 11)
	_palette_box.add_child(l)


## Small swatch preview of the selected stamp (tile colours) under the palette.
func _add_stamp_preview(stamp: Dictionary) -> void:
	var built: Dictionary = StampLibrary.build(stamp, 0, 0, false)
	var cells: Array = built["cells"]
	if cells.is_empty():
		return
	var mn := Vector2i(9999, 9999)
	var mx := Vector2i(-9999, -9999)
	for c: Dictionary in cells:
		mn = Vector2i(mini(mn.x, int(c["dx"])), mini(mn.y, int(c["dy"])))
		mx = Vector2i(maxi(mx.x, int(c["dx"])), maxi(mx.y, int(c["dy"])))
	var w: int = mx.x - mn.x + 1
	var h: int = mx.y - mn.y + 1
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for c: Dictionary in cells:
		var tname := str(c["tile"])
		if tname.is_empty() or not _reg.tile_index.has(tname):
			continue
		var cols: Array = _reg.tile_def(int(_reg.tile_index[tname]))["colors"]
		img.set_pixel(int(c["dx"]) - mn.x, int(c["dy"]) - mn.y, cols[0])
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(160, 120)
	_palette_box.add_child(tr)


func _choice(label: String, id: String, selected: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = selected
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(170, 0)
	b.pressed.connect(func() -> void:
		cb.call(id)
		_refresh_palette())
	if selected:
		_selected_choice_btn = b
	_palette_box.add_child(b)


func _update_coords() -> void:
	if _coords == null:
		return
	var info := "(%d, %d)" % [_hover_tile.x, _hover_tile.y]
	var chunk: RefCounted = _chunk_at_tile(_hover_tile.x, _hover_tile.y)
	if chunk != null:
		var lx: int = _hover_tile.x - chunk.cx * WG.CHUNK_TILES
		var ly: int = _hover_tile.y - chunk.cy * WG.CHUNK_TILES
		var bidx: int = chunk.biome_at(lx, ly)
		if bidx != 255 and bidx < _reg.biomes.size():
			info += "  " + str(_reg.biomes[bidx].get("id", ""))
	_coords.text = info


func _panel(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	return s


# ─────────────────────────────── generate ───────────────────────────────────

func _confirm_generate() -> void:
	_confirm_generate_mode(false, "Regenerate the whole world?",
		"This rebuilds the ENTIRE finite world (terrain + cities, ruins, roads…)\n"
		+ "and REPLACES all current edits. Unsaved work is lost (Save first).\n"
		+ "This clears the undo history.\n\nProceed?")


## Wipe the player's game save so the next launch is a fresh new game at the authored world spawn.
## (The world you edit here lives in res://data — it is NOT touched.)
func _confirm_wipe_save() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Wipe player save?"
	dlg.dialog_text = "Deletes your character save (skills, inventory) and explored-world state, so the\ngame starts a fresh new game at the world spawn you set here.\n\nThe world you're editing is NOT affected. This cannot be undone."
	dlg.ok_button_text = "Wipe save"
	_track_ui_hover(dlg)
	_hud.add_child(dlg)
	dlg.confirmed.connect(_wipe_save)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


## Delete the save files under user:// — platform-independent (DirAccess resolves user:// on every OS,
## so no hard-coded macOS/Windows/Linux paths). save.json = character; world.json = explored/placed state.
func _wipe_save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		_status.text = "Wipe failed: cannot open the user data directory."
		return
	var removed: Array = []
	for fname: String in ["save.json", "world.json"]:
		if dir.file_exists(fname) and dir.remove(fname) == OK:
			removed.append(fname)
	_status.text = ("Wiped %s — next game launch starts fresh at the world spawn." % ", ".join(removed)) \
		if not removed.is_empty() else "No save found to wipe (already a clean slate)."


func _confirm_generate_mode(natural: bool, title: String, body: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.dialog_text = body
	dlg.ok_button_text = "Generate"
	_track_ui_hover(dlg)
	_hud.add_child(dlg)
	dlg.confirmed.connect(func() -> void: _generate_world(natural))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _generate_world(natural_only: bool = false) -> void:
	_busy = true
	_status.text = "Generating world… (this can take ~30s)"
	await get_tree().process_frame
	var svc: RefCounted = FiniteWorldGenerator.new()
	# Fresh random seed → a whole new natural continent each time (not the same
	# fixed layout). The result is baked straight into the editor's chunks.
	svc.setup(_reg, randi())
	svc.natural_only = natural_only
	var chunks: Dictionary = await svc.generate_region(self,
		func(done: int, total: int) -> void:
			_status.text = "Generating… %d/%d chunks" % [done, total])
	_chunks = chunks
	_img = Image.create_empty(_w, _h, false, Image.FORMAT_RGB8)
	for key: String in _chunks:
		_blit_chunk(_chunks[key])
	_tex.update(_img)
	_spawn_tile = svc.default_spawn_tile()
	_history.clear()
	_redo.clear()
	_refresh_history_buttons()
	_busy = false
	_status.text = "Regenerated %d chunks. Undo history cleared. Save to keep." % _chunks.size()


# ─────────────────────────────── validate ───────────────────────────────────

func _validate() -> void:
	var issues: Array = []
	if not _is_walkable_tile(_spawn_tile.x, _spawn_tile.y):
		issues.append("Player spawn (%d,%d) is not walkable land." % [_spawn_tile.x, _spawn_tile.y])
	if not _bounds.has_point(WG.tile_to_chunk(_spawn_tile)):
		issues.append("Player spawn is outside the world bounds.")
	# Structures referencing unknown station ids.
	var stations: Dictionary = {}
	for key: String in _chunks:
		for p: Dictionary in _chunks[key].structures:
			if p.has("station"):
				stations[str(p["station"])] = true
	# Bank reachable near spawn (within a few chunks)?
	var bank_near := false
	var sc := WG.tile_to_chunk(_spawn_tile)
	for key: String in _chunks:
		var chunk: RefCounted = _chunks[key]
		if absi(chunk.cx - sc.x) > 3 or absi(chunk.cy - sc.y) > 3:
			continue
		for p: Dictionary in chunk.structures:
			if str(p.get("station", "")) == "bank":
				bank_near = true
		for poi: Dictionary in chunk.pois:
			for part: Dictionary in poi.get("parts", []):
				if str(part.get("station", "")) == "bank":
					bank_near = true
	if not bank_near:
		issues.append("No bank within ~3 chunks of spawn (starter area should have one).")

	var dlg := AcceptDialog.new()
	dlg.title = "Validation — %d issue(s)" % issues.size()
	dlg.dialog_text = "✓ No issues found." if issues.is_empty() else "• " + "\n• ".join(PackedStringArray(issues))
	_track_ui_hover(dlg)
	_hud.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	_status.text = "Validation: %d issue(s)" % issues.size()


# ─────────────────────────────── save ───────────────────────────────────────

func _save() -> void:
	_status.text = "Saving…"
	var chunks_doc: Dictionary = {}
	for key: String in _chunks:
		var chunk: RefCounted = _chunks[key]
		FiniteWorldGenerator.apply_structure_collision(chunk)   # derive fresh collision
		chunks_doc[key] = {
			"t": BakedWorldStore.encode(chunk.tiles),
			"b": BakedWorldStore.encode(chunk.biomes_t),
			"p": BakedWorldStore.encode(chunk.parent_biomes_t),
			"s": BakedWorldStore.encode(chunk.sub_biomes_t),
			"k": BakedWorldStore.encode(chunk.collision),
			"e": BakedWorldStore.encode(chunk.elev),
			"zone": chunk.zone.duplicate(true),
			"safe": chunk.safe,
			"sites": chunk.sites.duplicate(true),
			"pois": chunk.pois.duplicate(true),
			"monsters": chunk.monsters.duplicate(true),
			"structures": chunk.structures.duplicate(true),
			"cuts": chunk.tree_cuts.keys(),
		}
	var doc := {
		"version": 1,
		"id": _spec.id,
		"bounds": {"min": [_bounds.position.x, _bounds.position.y],
			"max": [_bounds.end.x - 1, _bounds.end.y - 1]},
		"spawn": [_spawn_tile.x, _spawn_tile.y],
		"chunks": chunks_doc,
	}
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world_path: String = OUT_DIR + str(_spec.id) + ".world"
	var f := FileAccess.open(world_path, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s" % world_path
		return
	f.store_string(var_to_str(doc))
	f.close()
	_img.save_png(OUT_DIR + str(_spec.id) + "_map.png")
	_persist_roads_to_worldspec()
	_status.text = "Saved %d chunks, %d roads → %s" % [_chunks.size(), _spec.roads.size(), world_path]
	print("World editor saved: ", ProjectSettings.globalize_path(world_path))
