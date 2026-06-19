shader_type spatial;
// Illustrated calm-ocean water (A Short Hike feel) with a PIXEL-SMOOTH coastline.
//
// The shoreline, shallows and foam are driven by ONE smoothed water-fraction field baked
// per vertex into UV.x (v_wf: 0 land .. 1 open water, 0.5 = the smoothed coastline). The
// field is sampled BICUBICALLY onto a finely-tessellated water plane, so the 0.5 contour
// is a smooth curve at sub-tile resolution — no per-tile triangulation teeth, decoupled
// from the coarse terrain mesh. The shader discards the land side of the contour (the dry
// beach terrain shows there), ramps shallow -> deep with the signed coast distance, lays
// an animated lacy foam line on the waterline, and keeps the illustrated contour loops in
// the open water. Transparent (blend_mix) only for a 1px anti-aliased waterline.

render_mode unshaded, cull_back, fog_disabled, blend_mix;

// --- palette ------------------------------------------------------------------
uniform vec4 deep_color : source_color = vec4(0.067, 0.380, 0.498, 1.0);     // #11617F deep ocean
uniform vec4 shallow_color : source_color = vec4(0.420, 0.780, 0.760, 1.0);  // #6BC7C2 lit shallow
uniform vec4 line_color : source_color = vec4(0.290, 0.588, 0.655, 1.0);     // #4A96A7 contour
uniform vec4 foam_color : source_color = vec4(0.886, 0.953, 0.965, 1.0);     // #E2F3F6 sea foam

// --- shared coast field (v_wf) ------------------------------------------------
uniform float sd_scale = 5.2;          // (wf-0.5)*sd_scale -> signed distance to coast, in cells
uniform float shore_aa = 0.10;         // cells: anti-aliased width of the waterline
uniform float shallow_cells = 0.9;     // cells: shallow band width before it ramps to deep

// --- contour pattern (illustrated loops, open water only) ---------------------
uniform float pattern_scale = 0.072;
uniform float contour_count = 3.5;
uniform float line_width : hint_range(0.0, 0.5) = 0.038;
uniform float line_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float domain_warp_strength = 0.6;
uniform float secondary_strength : hint_range(0.0, 1.0) = 0.28;
uniform float secondary_scale = 1.7;
uniform vec2 primary_speed = vec2(0.006, 0.003);
uniform vec2 secondary_speed = vec2(-0.003, 0.005);
uniform float contour_fade_in = 0.7;   // cells: contours start returning past the shallows
uniform float contour_fade_out = 1.6;  // cells: contours fully back in open water
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D warp_tex : repeat_enable, filter_linear;

// --- animated foam ------------------------------------------------------------
uniform float foam_cells = 0.55;       // cells: how far the foam can wash off the waterline
uniform float foam_scale = 0.17;
uniform float foam_speed = 0.05;
uniform sampler2D foam_tex : repeat_enable, filter_linear;

uniform float aa_strength = 1.1;
uniform float min_aa = 0.0015;

varying vec3 v_world;
varying float v_wf;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wf = UV.x;
}

float contour(float n, float count) {
	float v = n * count;
	float d = min(fract(v), 1.0 - fract(v));
	float w = fwidth(v);
	float aa = max(w * aa_strength, min_aa);
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, d);
	float tiny = 1.0 - smoothstep(0.45, 0.95, w);
	return line * tiny;
}

void fragment() {
	float sd = (v_wf - 0.5) * sd_scale;   // + into water, - onto land; 0 = smoothed coast
	// Anti-aliased waterline: fully transparent a touch onto the land, full water a touch
	// into the sea. The dry beach terrain shows through on the land side.
	float water_a = smoothstep(-shore_aa, shore_aa, sd);
	if (water_a <= 0.001) {
		discard;
	}
	vec2 wp = v_world.xz;

	// --- shallow -> deep colour ramp by signed coast distance ---
	float deep_t = smoothstep(0.0, shallow_cells, sd);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, deep_t);

	// --- illustrated contour loops (fade in past the shallows) ---
	vec2 w1 = wp * (pattern_scale * 0.5) + primary_speed * TIME;
	vec2 w2 = wp * (pattern_scale * 0.5) + secondary_speed * TIME + vec2(0.4, 0.2);
	vec2 warp = (vec2(texture(warp_tex, w1).r, texture(warp_tex, w2).r) - 0.5) * domain_warp_strength;
	vec2 uv1 = wp * pattern_scale + warp;
	float lines = contour(texture(noise_tex, uv1).r, contour_count);
	if (secondary_strength > 0.001) {
		float n2 = texture(noise_tex, uv1 * secondary_scale + vec2(3.7, 1.9)).r;
		lines = max(lines, contour(n2, contour_count) * secondary_strength);
	}
	float contour_vis = smoothstep(contour_fade_in, contour_fade_out, sd);
	col = mix(col, line_color.rgb, lines * contour_vis * line_opacity);

	// --- animated lacy sea-foam hugging the waterline ---
	vec2 fp = wp * foam_scale;
	float fa = texture(foam_tex, fp + vec2(TIME * foam_speed, TIME * foam_speed * 0.4)).r;
	float fb = texture(foam_tex, fp * 1.7 - vec2(TIME * foam_speed * 0.7, 0.0)).r;
	float wash = (fa + fb) * 0.5;
	float foam = 1.0 - smoothstep(0.0, foam_cells * (0.55 + wash * 0.7), sd);
	foam *= smoothstep(0.40, 0.74, wash);                    // break into lace, not a solid sheet
	float rim = 1.0 - smoothstep(0.0, foam_cells * 0.5, abs(sd - foam_cells * 0.18));
	foam = max(foam, rim * 0.5);
	foam *= smoothstep(-shore_aa, shore_aa * 0.5, sd);       // never onto dry sand
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	ALPHA = water_a;
}
