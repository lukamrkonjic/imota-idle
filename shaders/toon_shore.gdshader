shader_type spatial;
// Render-only coastal overlay. Drapes a thin sheet slightly ABOVE the terrain+water along
// the coast and paints the wet-sand + two-tone shallow bands, hiding the ground mesh's
// per-tile triangulation. Opaque (writes depth) so nothing shows through it.
//
// Everything keys off ONE shared smoothed field — the low-passed water fraction baked per
// vertex into UV.x (v_wf: 0 land .. 1 open water, 0.5 = smoothed coastline). We convert it
// to a signed distance to the coast (cells) and slice flat zones out of it:
//   dry beach (transparent) | wet sand | inner aqua | outer turquoise | deep (fade out)
// The outer boundary gets gentle low-frequency world-space width variation so it reads as
// a filled shallow region, not a constant-width vector stroke. The coastline itself
// (sd = 0) is NOT wobbled, so the large silhouette stays smooth.

render_mode unshaded, cull_back, blend_mix;

uniform vec4 wet_sand_color : source_color = vec4(0.788, 0.678, 0.451, 1.0);  // #C9AD73 wet sand
uniform vec4 inner_color : source_color = vec4(0.510, 0.820, 0.796, 1.0);     // #82D1CB light aqua
uniform vec4 outer_color : source_color = vec4(0.263, 0.682, 0.698, 1.0);     // #43AEB2 turquoise
uniform float sd_scale = 4.0;        // (wf-0.5) -> signed cells (matches the smoothing kernel)
uniform float wet_cells = 0.26;      // wet-sand band on the LAND side of the coast
uniform float inner_cells = 0.30;    // light-aqua inner band width (cells)
uniform float outer_cells = 0.50;    // turquoise outer band width (cells)
uniform float fade_cells = 0.22;     // soft fade into deep water at the band's outer edge
uniform float width_var = 0.22;      // +/- fraction of low-freq variation on the seaward bands
uniform float var_scale = 0.05;      // world frequency of the width variation
uniform float edge_aa = 0.04;        // small AA on the colour/alpha edges (cells)
uniform sampler2D var_noise : repeat_enable, filter_linear;

varying float v_wf;
varying vec3 v_world;

void vertex() {
	v_wf = UV.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float sd = (v_wf - 0.5) * sd_scale;   // + into water, - into land; 0 = smoothed coast
	// Low-frequency width variation applied only to the SEAWARD band edges (not the
	// coastline), so the shallow region swells/narrows organically while the coast stays
	// smooth. One noise tap, world-space -> stable.
	float n = texture(var_noise, v_world.xz * var_scale).r - 0.5;
	float inner_end = inner_cells * (1.0 + n * width_var * 0.6);
	float outer_end = inner_end + outer_cells * (1.0 + n * width_var);

	// Alpha zones: dry beach (transparent) -> wet sand -> aqua bands -> fade to deep.
	float a_in = smoothstep(-wet_cells - edge_aa, -wet_cells + edge_aa, sd);
	float a_out = 1.0 - smoothstep(outer_end, outer_end + fade_cells, sd);
	float alpha = a_in * a_out;

	// Colour: wet sand below the waterline (sd<0), then light aqua, then turquoise.
	float tw = smoothstep(-edge_aa, edge_aa, sd);                  // wet sand -> aqua at the coast
	float ta = smoothstep(inner_end - edge_aa, inner_end + edge_aa, sd);  // inner -> outer aqua
	vec3 col = mix(wet_sand_color.rgb, inner_color.rgb, tw);
	col = mix(col, outer_color.rgb, ta);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
