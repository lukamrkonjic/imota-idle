extends RefCounted
class_name RenderViewportPresenter
## Pixel-art presentation layer (extracted from the WorldRender3D monolith). Owns the
## low-resolution SubViewport that the 3D world renders into, the 3D world root, and the
## TextureRect that presents that image to the window at an EXACT integer scale
## (nearest-neighbour, no fractional stretch — the stable pixel grid). Also owns the
## sub-pixel residual shift used by the camera rig for "Stable Pixel Motion", and the
## screen<->internal-pixel coordinate conversions picking needs.

const INTERNAL := Vector2i(640, 360)   # internal render res (higher = finer/less chunky pixels)
# How the low-res image is placed on the window: an exact integer scale + centred offset.
const PRESENT_OVERSCAN := 1   # internal-px margin per side, for the sub-pixel residual shift
# Discrete INTEGER pixel scales the slider snaps to. Godot recommends integer viewport
# scaling for pixel art — fractional scales give texels uneven displayed sizes, which is
# exactly what crawls during motion. Each level is an exact display:internal ratio.
const PIXEL_LEVELS := [1, 2, 3, 4, 5, 6, 8]
const PixelPalette := preload("res://scripts/world/art/core/pixel_palette.gd")
const PALETTE_SNAP := preload("res://shaders/palette_snap.gdshader")

var world: Node2D
var sub: SubViewport
var world3d: Node3D
var present: TextureRect
var _snap_mat: ShaderMaterial
var _pixel_scale := 3             # INTEGER display px per internal px (nearest-neighbour, no fractional stretch)
var _present_scale := 1.0
var _present_off := Vector2.ZERO
var _present_base_off := Vector2.ZERO


func setup(w: Node2D) -> void:
	world = w
	_setup_viewport()
	_setup_present()
	# Pixelation is controlled from the Settings menu (GameSettings.pixelation).
	_pixel_scale = _scale_from_setting(GameSettings.pixelation)
	GameSettings.changed.connect(_on_settings_changed)


func _setup_viewport() -> void:
	sub = SubViewport.new()
	sub.size = INTERNAL
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub.use_taa = false
	sub.use_debanding = false
	sub.positional_shadow_atlas_size = 0
	# The presenter is a RefCounted, not a Node — the SubViewport lives under the world's
	# present CanvasLayer (added in _setup_present) so it stays in the scene tree.
	world3d = Node3D.new()
	sub.add_child(world3d)


func _setup_present() -> void:
	# Present the low-res 3D world at nearest-neighbour, under the HUD (layer 1).
	var layer := CanvasLayer.new()
	layer.layer = 0
	world.add_child(layer)
	layer.add_child(sub)
	present = TextureRect.new()
	# Sized/positioned explicitly in update_pixelation to an EXACT integer scale (centred,
	# slight overscan) so every internal texel becomes a uniform block — no fractional
	# stretch (the root cause of pixel crawl). Nearest-neighbour, no mipmaps.
	present.set_anchors_preset(Control.PRESET_TOP_LEFT)
	present.texture = sub.get_texture()
	present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	present.stretch_mode = TextureRect.STRETCH_SCALE
	# Let clicks / scroll-wheel fall through to the 2D world (movement, picking,
	# zoom all still run on the hidden 2D substrate).
	present.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_mat = ShaderMaterial.new()
	_snap_mat.shader = PALETTE_SNAP
	_snap_mat.set_shader_parameter("palette_tex", _palette_texture())
	_snap_mat.set_shader_parameter("palette_count", PixelPalette.PAL.size())
	# Colour treatment = POSTERIZE (mode 2), not palette-snap. A hard per-pixel nearest-palette
	# snap flickers over the smooth biome blends (a near-boundary pixel jumps to a different hue ->
	# speckle); turning it off entirely leaves the ground muddy/washed-out. Posterizing in HSV
	# keeps hue continuous and steps value/saturation into flat bands, so a blend becomes clean
	# adjacent bands — crisp, no speckle. The grade (contrast/saturation/brightness) always applies.
	_snap_mat.set_shader_parameter("mode", 2.0)
	_snap_mat.set_shader_parameter("strength", 1.0)
	_snap_mat.set_shader_parameter("value_steps", 9.0)
	_snap_mat.set_shader_parameter("sat_steps", 7.0)
	_snap_mat.set_shader_parameter("contrast", 1.08)
	_snap_mat.set_shader_parameter("saturation", 1.03)   # muted, earthy — not punchy lime
	_snap_mat.set_shader_parameter("brightness", 0.92)   # moodier, slightly darker
	present.material = _snap_mat
	layer.add_child(present)


## React to the Settings-menu pixelation slider (0 = native, 1 = really crunchy),
## mapped to a 1x..8x render-pixel size relative to the window.
func _on_settings_changed(prop: StringName) -> void:
	if prop == &"pixelation":
		_pixel_scale = _scale_from_setting(GameSettings.pixelation)


func _scale_from_setting(v: float) -> int:
	# Verification override: `-- --crisp` renders near-native so detail is legible in shots.
	if "--crisp" in OS.get_cmdline_args() or "--crisp" in OS.get_cmdline_user_args():
		return 1
	var idx := int(round(clampf(v, 0.0, 1.0) * float(PIXEL_LEVELS.size() - 1)))
	return PIXEL_LEVELS[clampi(idx, 0, PIXEL_LEVELS.size() - 1)]


## Size the SubViewport to an INTEGER fraction of the window and present it at that exact
## integer scale (centred, slight overscan so the integer-scaled image always covers the
## window — no black bars, no fractional stretch). This is the stable pixel grid: every
## internal texel maps to a uniform `scale x scale` block of display pixels.
func update_pixelation() -> void:
	if sub == null or present == null:
		return
	var win: Vector2 = world.get_viewport().get_visible_rect().size
	if win.x < 1.0 or win.y < 1.0:
		return
	var scale: int = _pixel_scale
	# Overscan (ceil + a 1px margin on every side) so display = internal*scale comfortably
	# covers the window AND leaves room for the sub-pixel residual shift below to slide the
	# image without revealing an empty edge. Both dims are integers.
	var internal := Vector2i(
		maxi(8, int(ceil(win.x / float(scale))) + 2 * PRESENT_OVERSCAN),
		maxi(8, int(ceil(win.y / float(scale))) + 2 * PRESENT_OVERSCAN))
	if internal != sub.size:
		sub.size = internal
	var displayed := internal * scale
	_present_scale = float(scale)
	_present_base_off = Vector2(floor((win.x - float(displayed.x)) * 0.5), floor((win.y - float(displayed.y)) * 0.5))
	present.size = Vector2(displayed)
	# Base position now; the camera rig adds the sub-pixel residual shift after the follow.
	present.position = _present_base_off
	_present_off = _present_base_off


## Slide the presented image by the camera's pixel-snap residual (rounded to whole DISPLAY
## pixels), keeping every internal texel a clean block while the apparent motion stays smooth
## to display-pixel precision. Called by WorldCameraRig3D after it snaps the render camera.
func apply_residual_shift(shift: Vector2) -> void:
	if present == null:
		return
	present.position = _present_base_off + shift
	_present_off = present.position


## Window pixel -> SubViewport pixel. The present rect is an exact integer scale placed at
## `_present_off`, so invert that affine mapping (subtract offset, divide by scale).
func window_to_subviewport_px(screen: Vector2) -> Vector2:
	return (screen - _present_off) / _present_scale


## SubViewport (internal) pixel -> window pixel: the inverse of window_to_subviewport_px,
## so picking stays aligned with the presented image.
func subviewport_to_window_px(px: Vector2) -> Vector2:
	return px * _present_scale + _present_off


func get_subviewport() -> SubViewport:
	return sub


func get_world3d() -> Node3D:
	return world3d


func get_present_scale() -> float:
	return _present_scale


func get_present_off() -> Vector2:
	return _present_off


func _palette_texture() -> ImageTexture:
	var keys := PixelPalette.PAL.keys()
	var img := Image.create(keys.size(), 1, false, Image.FORMAT_RGBA8)
	for i: int in keys.size():
		img.set_pixel(i, 0, PixelPalette.pal(keys[i]))
	return ImageTexture.create_from_image(img)
