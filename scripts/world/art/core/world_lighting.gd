extends RefCounted
class_name WorldLighting
## WorldLightingSettings — the single, shared directional sun for the whole
## isometric world. EVERY shadow in the game reads these values, so the entire
## scene agrees on sun direction, elevation, projection angle, colour, opacity
## and edge style. No object is allowed to invent its own direction; casters
## only contribute their footprint and height.
##
## Plain static config so it is trivially animatable at runtime (a day/night
## controller can tween any field and every shadow follows on the next redraw).
## See docs/SHADOWS.md.

# ───────────────────────────────── inspector-style settings ──────────────────
# (named per the spec; the legacy aliases below keep older call-sites working)

## Compass bearing of the sun in the WORLD ground plane, degrees.
## Shadows fall in the opposite direction. 0° = +X (east), 90° = +Y (south).
## 245° puts the sun in the upper-right (NE on the iso ground) to match the
## building/prop art, which already lights its NE faces brightest — so shadows
## fall toward the lower-left, in front of objects and onto visible ground.
static var sun_azimuth_deg := 245.0

## Sun height above the horizon, degrees. LOWER => LONGER shadows.
static var sun_elevation_degrees := 52.0

## Base shadow colour — dark and desaturated, NEVER pure black, so overlaps
## read as "darker ground" rather than ink. A cool blue-grey neutral.
static var shadow_color := Color(0.10, 0.11, 0.16)

## Master opacity for a single (non-contact) projected shadow. Kept low so two
## or three overlapping shadows never accumulate to a solid black region.
static var shadow_opacity := 0.22

## Global length multiplier applied on top of the elevation-derived length.
static var shadow_length_multiplier := 0.85

## Opacity of the compact contact shadow right under a caster's ground point.
static var contact_shadow_opacity := 0.34

## Hard ceiling on projected shadow length in screen px, so tall structures
## cannot blanket half the map regardless of height/elevation.
static var maximum_shadow_length := 150.0

## Snap shadow geometry to the art pixel grid (matches the pixel-art world).
static var pixel_snap_enabled := true

## Screen y:x foreshortening of the isometric ground (matches WG.ISO_HH/ISO_HW).
const ISO_RATIO := 0.5


# ─────────────────────────────── world → iso conversion ──────────────────────

## The world-space sun direction on the flat ground plane (unit vector).
static func sun_world_direction() -> Vector2:
	var a := deg_to_rad(sun_azimuth_deg)
	return Vector2(cos(a), sin(a))


## Screen-space unit vector pointing the way shadows FALL (away from the sun),
## projected onto the isometric ground plane.
##
## CONVERSION (documented): the camera is isometric, so a world-ground vector
## (wx, wy) maps to screen as:
##     screen.x = (wx - wy)
##     screen.y = (wx + wy) * ISO_RATIO
## We therefore must NOT treat "screen-down" as a valid ground direction — we
## take the sun bearing in WORLD ground space, flip it (shadows oppose the sun),
## run it through the iso map above, then normalise. This guarantees a shadow
## lies flat on the ground plane instead of being sheared straight down screen.
static func ground_dir() -> Vector2:
	var shadow := -sun_world_direction()        # shadows fall opposite the sun
	var s := Vector2(shadow.x - shadow.y, (shadow.x + shadow.y) * ISO_RATIO)
	return s.normalized() if s.length() > 0.001 else Vector2(0.5, 0.5)


## Screen px of shadow throw per px of caster height (before clamping). A low
## sun (small elevation) stretches shadows out; a high sun shortens them.
static func length_factor() -> float:
	var e := clampf(sun_elevation_degrees, 6.0, 85.0)
	return shadow_length_multiplier * 1.5 / tan(deg_to_rad(e))


## Final projected length in screen px for a caster of the given height,
## clamped to maximum_shadow_length so big structures stay readable.
static func project(height: float) -> float:
	return clampf(maxf(0.0, height) * length_factor(), 0.0, maximum_shadow_length)


## The shadow tint at a base alpha (× the global opacity), capped below opaque.
static func tint(alpha: float) -> Color:
	var c := shadow_color
	c.a = clampf(alpha, 0.0, 0.9)
	return c


## Whether a given receiving surface should take a ground shadow at all.
## Keeps shadows off surfaces where they would read wrong. `surface` is one of:
## "ground" | "road" | "water" | "elevated" | "cliff" | "hidden".
static func receives_shadow(surface: String) -> bool:
	match surface:
		"hidden", "cliff":
			return false
		_:
			return true


## Opacity scale for a shadow landing on a given surface (water takes a fainter,
## cooler shadow; roads/ground take it full).
static func surface_opacity_scale(surface: String) -> float:
	match surface:
		"water":
			return 0.5
		_:
			return 1.0


## Transform that lays an upright local silhouette flat onto the ground as a
## projected shadow: the foot (local y = 0) stays put while height (negative y)
## is sheared along the light direction. Used by ShadowProjector.begin/end.
static func projection_xform(length_scale: float = 1.0) -> Transform2D:
	var g := ground_dir() * length_factor() * length_scale
	return Transform2D(Vector2(1.0, 0.0), -g, Vector2.ZERO)
