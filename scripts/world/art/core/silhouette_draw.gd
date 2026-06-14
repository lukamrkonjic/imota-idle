extends RefCounted
class_name SilhouetteDraw
## Re-colour hook for procedural art. When `active`, shapes draw flat white (the
## Alt-key interaction outline). When `shadow`, shapes draw in the global shadow
## colour (so an object's own draw routine can be re-run to project its
## silhouette — see ShadowProjector). Either mode suppresses self-shadows so a
## silhouette/outline pass doesn't recurse into drawing its own ground shadow.

const WorldLighting := preload("res://scripts/world/art/core/world_lighting.gd")

static var active := false   ## outline pass (white)
static var shadow := false   ## shadow projection pass (dark, desaturated)


static func ink(color: Color, alpha: float = 1.0) -> Color:
	if shadow:
		return WorldLighting.tint(0.5 * alpha)
	if active:
		return Color(1.0, 1.0, 1.0, 0.94 * alpha)
	var c := color
	c.a *= alpha
	return c


static func skip_shadows() -> bool:
	return active or shadow
