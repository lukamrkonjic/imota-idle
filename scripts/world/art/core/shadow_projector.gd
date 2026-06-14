extends RefCounted
class_name ShadowProjector
## The one and only shadow caster for the procedural draw pipeline (the draw-based
## equivalent of a ShadowCaster2D). Reads the shared WorldLighting sun and draws
## every shadow as a SMALL NUMBER OF SOLID, PIXEL-SNAPPED POLYGONS at a single
## flat alpha — never as a stack of translucent blobs or a swept convex hull.
##
## That single design choice fixes the previous artifacts:
##   * segmented "chain of blocks" smears  -> one continuous tapering quad
##   * diagonal banding under buildings     -> one solid silhouette + foundation
##   * giant black ovals                     -> a compact contact patch only
##   * stretched-down-screen shadows         -> direction comes from ground_dir()
##
## Casting kinds (all share direction/length/colour from WorldLighting):
##   contact()          compact patch right under the ground point.
##   cast_blade()       one tapering quad foot->tip (props, characters, walls).
##   cast_tree()        trunk blade + canopy disc + contact (trees/bushes).
##   cast_silhouette()  building: footprint + a smaller, offset roof diamond,
##                      hulled into a single leaning house-shaped polygon.
##
## Everything is anchored at the caster's foot (local 0,0) and drawn FIRST in the
## caster's _draw so it sits beneath the body. See docs/SHADOWS.md.

const PixelPalette  := preload("res://scripts/world/art/core/pixel_palette.gd")
const SilhouetteDraw := preload("res://scripts/world/art/core/silhouette_draw.gd")
const WorldLighting := preload("res://scripts/world/art/core/world_lighting.gd")


# ───────────────────────────────── helpers ───────────────────────────────────

static func _snap(p: Vector2) -> Vector2:
	if WorldLighting.pixel_snap_enabled:
		return Vector2(PixelPalette.snap(p.x), PixelPalette.snap(p.y))
	return p


## A flat, pixel-snapped ellipse as a single polygon (no stacked rects).
static func _ellipse_poly(center: Vector2, rx: float, ry: float, segments: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(_snap(center + Vector2(cos(a) * rx, sin(a) * ry)))
	return pts


# ───────────────────────────────── contact ───────────────────────────────────

## Compact darker patch right under the ground point. Deliberately small — this
## is the only near-round shadow we keep, and it is what grounds the object.
static func contact(canvas: CanvasItem, half_w: float, alpha_scale: float = 1.0) -> void:
	if SilhouetteDraw.skip_shadows() or half_w <= 0.0:
		return
	var a := WorldLighting.contact_shadow_opacity * alpha_scale
	canvas.draw_colored_polygon(
		_ellipse_poly(Vector2(0.0, 1.0), maxf(half_w * 0.8, 2.0), maxf(half_w * 0.4, 1.0)),
		WorldLighting.tint(a))


# ───────────────────────────────── blade ─────────────────────────────────────

## One continuous tapering quad from the foot out to the projected top, plus a
## contact patch. `foot_half` is the half-width at the ground; `tip_half` at the
## projected end; `height` drives length. Used by props, characters and walls.
static func cast_blade(canvas: CanvasItem, foot_half: float, tip_half: float,
		height: float, alpha_scale: float = 1.0) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var g := WorldLighting.ground_dir()
	var tip := g * WorldLighting.project(height)
	var perp := Vector2(-g.y, g.x)
	var fa := _snap(perp * foot_half)
	var fb := _snap(perp * -foot_half)
	var ta := _snap(tip + perp * tip_half)
	var tb := _snap(tip - perp * tip_half)
	# Single solid fill — flat alpha, crisp pixel-snapped edges, no banding.
	canvas.draw_colored_polygon(PackedVector2Array([fa, ta, tb, fb]),
		WorldLighting.tint(WorldLighting.shadow_opacity * alpha_scale))
	contact(canvas, foot_half, alpha_scale)


# ───────────────────────────────── tree ──────────────────────────────────────

## A readable tree shadow: a narrow trunk blade, a broad canopy disc projected
## out along the light, and a small contact patch at the trunk base.
static func cast_tree(canvas: CanvasItem, trunk_half: float, canopy_r: float,
		height: float, alpha_scale: float = 1.0) -> void:
	if SilhouetteDraw.skip_shadows():
		return
	var g := WorldLighting.ground_dir()
	var col := WorldLighting.tint(WorldLighting.shadow_opacity * alpha_scale)
	var perp := Vector2(-g.y, g.x)
	# trunk blade: foot -> ~70% of the way to the canopy centre
	var trunk_tip := g * WorldLighting.project(height) * 0.7
	canvas.draw_colored_polygon(PackedVector2Array([
		_snap(perp * trunk_half), _snap(trunk_tip + perp * trunk_half * 0.8),
		_snap(trunk_tip - perp * trunk_half * 0.8), _snap(perp * -trunk_half)]), col)
	# canopy disc at the projected top (one solid ellipse polygon)
	var canopy_c := g * WorldLighting.project(height)
	canvas.draw_colored_polygon(_ellipse_poly(canopy_c, canopy_r, canopy_r * 0.62), col)
	contact(canvas, trunk_half * 1.6, alpha_scale)


# ───────────────────────────────── building ──────────────────────────────────

## Building / large-structure shadow. Takes the ground footprint corners and a
## roof apex height; projects a SMALLER copy of the footprint to the roofline and
## convex-hulls the two diamonds into ONE leaning house-shaped silhouette. Adds a
## slightly darker foundation patch. Two solid fills total — no swept slab, no
## stripes, length already clamped by WorldLighting.project().
static func cast_silhouette(canvas: CanvasItem, footprint: PackedVector2Array,
		roof_height: float, roof_scale: float = 0.66, alpha_scale: float = 1.0) -> void:
	if SilhouetteDraw.skip_shadows() or footprint.size() < 3:
		return
	var off := WorldLighting.ground_dir() * WorldLighting.project(roof_height)
	var pts := PackedVector2Array()
	for c: Vector2 in footprint:
		pts.append(c)                                   # foundation corner
		pts.append(_snap(c * roof_scale + off))         # projected roof corner
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() >= 3:
		canvas.draw_colored_polygon(hull,
			WorldLighting.tint(WorldLighting.shadow_opacity * alpha_scale))
	# darker foundation contact exactly on the footprint
	canvas.draw_colored_polygon(footprint,
		WorldLighting.tint(WorldLighting.contact_shadow_opacity * alpha_scale))


# ───────────────────────────────── custom silhouette ─────────────────────────

## Lay an object's own simplified shapes onto the ground: subsequent procedural
## draws are sheared along the light and inked in shadow colour. Call end() after.
static func begin(canvas: CanvasItem, length_scale: float = 1.0) -> void:
	SilhouetteDraw.shadow = true
	canvas.draw_set_transform_matrix(WorldLighting.projection_xform(length_scale))


static func end(canvas: CanvasItem) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	SilhouetteDraw.shadow = false
