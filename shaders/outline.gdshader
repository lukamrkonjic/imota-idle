shader_type spatial;
// Inverted-hull silhouette outline: grow the mesh a hair along its normals and draw only the
// back faces (cull_front), unshaded, so a thin white stroke peeks out around the object's
// contour while the real (un-grown) mesh covers the front. Used as a material_overlay on
// mover rigs and as the material on parts-built outline nodes for static interactables.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width : hint_range(0.0, 0.2) = 0.045;   // world-units the hull grows outward

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
