shader_type spatial;
// Render-only coastal overlay. Drapes a thin sheet slightly ABOVE the terrain+water
// along the coast and paints a two-tone aqua shallow band whose land-side edge is a
// SMOOTH curve — hiding the ground mesh's per-tile triangular "teeth" at the waterline.
//
// The smoothness comes from a low-passed water-occupancy field baked per vertex into
// UV.x (v_wf in 0..1: 0 = solid land, 1 = open water, ~0.5 = the smoothed coastline).
// We turn that into a signed distance to the coast (in terrain cells) and slice flat
// colour bands out of it. World-space + baked field => stable under the orthographic
// camera and when the camera moves. No white foam, no outlines, no gradients.

render_mode unshaded, cull_back, blend_mix;

uniform vec4 inner_color : source_color = vec4(0.482, 0.796, 0.773, 1.0);  // #7BCBC5 light aqua
uniform vec4 outer_color : source_color = vec4(0.275, 0.686, 0.686, 1.0);  // #46AFAF turquoise
uniform float sd_scale = 4.0;        // maps (wf-0.5) -> signed cells (matches the smoothing kernel)
uniform float inland_cells = 0.34;   // how far inland of the smooth coast the band reaches (covers teeth)
uniform float inner_cells = 0.30;    // light-aqua inner band width (cells)
uniform float outer_cells = 0.42;    // turquoise outer band width (cells)
uniform float fade_cells = 0.20;     // soft fade into deep water at the band's outer edge
uniform float edge_aa = 0.045;       // small AA on the colour/alpha edges (cells)

varying float v_wf;

void vertex() {
	v_wf = UV.x;
}

void fragment() {
	float sd = (v_wf - 0.5) * sd_scale;   // signed distance to coast, cells: + into water, - into land
	// Alpha: opaque from a bit inland of the smooth coast, out across both bands, then
	// fading to nothing so the deep-water mesh shows through (no hard ring).
	float a_in = smoothstep(-inland_cells - edge_aa, -inland_cells + edge_aa, sd);
	float band_end = inner_cells + outer_cells;
	float a_out = 1.0 - smoothstep(band_end, band_end + fade_cells, sd);
	float alpha = a_in * a_out;
	// Two flat colours: light aqua near the coast, turquoise further out.
	float t = smoothstep(inner_cells - edge_aa, inner_cells + edge_aa, sd);
	ALBEDO = mix(inner_color.rgb, outer_color.rgb, t);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
