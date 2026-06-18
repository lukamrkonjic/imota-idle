shader_type spatial;
// Illustrated calm-ocean water (A Short Hike feel). A deep-blue surface with medium/large
// domain-warped contour loops — calm topographic lines — over plenty of open blue.
//
// The contour pattern is world-space xz noise -> contour thresholds -> thin isolines, so
// it is glued to the world and camera-stable, and is computed INDEPENDENTLY of the coast.
//
// The coast is driven by ONE shared smoothed field: a low-passed water fraction baked per
// vertex into UV.x (v_wf: 0 land .. 1 open water, 0.5 = the smoothed coastline). The SAME
// field feeds the shore overlay, so the two layers can never disagree and open a seam.
// Here we use it only to (a) DISCARD the deep mesh on the land side (the opaque overlay
// paints that zone), with slight overlap so there is never a bare-ground sliver, and (b)
// fade the contours out under the shallows, returning them gradually in the outer water.

render_mode unshaded, cull_back;   // OPAQUE: writes depth so the lifted overlay layers cleanly

// --- palette (restrained: one deep blue, one muted blue-cyan line) ------------
uniform vec4 base_color : source_color = vec4(0.067, 0.380, 0.498, 1.0);       // #11617F
uniform vec4 secondary_color : source_color = vec4(0.090, 0.431, 0.537, 1.0);  // #176E89
uniform vec4 line_color : source_color = vec4(0.290, 0.588, 0.655, 1.0);       // #4A96A7

// --- contour pattern ----------------------------------------------------------
uniform float pattern_scale = 0.072;            // world->noise freq (small = big, calm loops)
uniform float contour_count = 3.5;              // number of isolines across the noise range
uniform float line_width : hint_range(0.0, 0.5) = 0.038;     // half line thickness (contour units)
uniform float line_opacity : hint_range(0.0, 1.0) = 0.6;     // how strongly lines tint the water
uniform float domain_warp_strength = 0.6;       // bends the loops into organic shapes
uniform float secondary_strength : hint_range(0.0, 1.0) = 0.28;  // weak 2nd detail (never an equal net)
uniform float secondary_scale = 1.7;            // 2nd-layer relative frequency
uniform vec2 primary_speed = vec2(0.006, 0.003);    // slow warp drift A (normalized coords)
uniform vec2 secondary_speed = vec2(-0.003, 0.005); // slow warp drift B (different vector)

// --- shared coastline field (v_wf) --------------------------------------------
uniform float sd_scale = 4.0;          // (wf-0.5)*sd_scale -> signed distance to coast, in cells
uniform float coast_cut = -0.1;        // discard deep water inside this signed dist (cells); negative
                                        // => deep water extends slightly UNDER the overlay (overlap)
uniform float contour_fade_in = 0.55;  // cells: contours start returning past the shallows
uniform float contour_fade_out = 1.15; // cells: contours fully back in open water

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D warp_tex : repeat_enable, filter_linear;

varying vec3 v_world;
varying float v_wf;   // shared smoothed water fraction (baked into UV.x)

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wf = UV.x;
}

// 0..1 noise -> thin isolines. Slice into `count` levels and light up the narrow band at
// each crossing. The AA half-width is derived from the per-pixel footprint of the contour
// value (fwidth) and applied SYMMETRICALLY around line_width, so a line ramps smoothly in/
// out as it crosses an internal pixel instead of popping between 0 and 1 (the crawl/shimmer
// source). Sub-pixel loops — where the field sweeps a full contour period in under ~1px
// (w large) — are faded out, since they can only alias, never resolve.
uniform float aa_strength = 1.1;
uniform float min_aa = 0.0015;
float contour(float n, float count) {
	float v = n * count;
	float d = min(fract(v), 1.0 - fract(v));
	float w = fwidth(v);
	float aa = max(w * aa_strength, min_aa);
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, d);
	float tiny = 1.0 - smoothstep(0.45, 0.95, w);   // suppress < ~2px loops (pure aliasing)
	return line * tiny;
}

void fragment() {
	float sd = (v_wf - 0.5) * sd_scale;   // signed distance to the smoothed coast, in cells
	// Drop the deep-water ring on the land side of the coast (the opaque overlay paints
	// it). coast_cut < 0 keeps a little deep water UNDER the overlay so there is no seam.
	if (sd < coast_cut) {
		discard;
	}
	vec2 wp = v_world.xz;

	// Animated DOMAIN WARP only: two slow, near-perpendicular vectors move the warp
	// sample (not the whole pattern), so the big loops keep their identity and just
	// gently breathe — no wholesale scrolling, no boiling.
	vec2 w1 = wp * (pattern_scale * 0.5) + primary_speed * TIME;
	vec2 w2 = wp * (pattern_scale * 0.5) + secondary_speed * TIME + vec2(0.4, 0.2);
	vec2 warp = (vec2(texture(warp_tex, w1).r, texture(warp_tex, w2).r) - 0.5) * domain_warp_strength;

	// One DOMINANT contour layer + a WEAK secondary detail at a different scale.
	vec2 uv1 = wp * pattern_scale + warp;
	float lines = contour(texture(noise_tex, uv1).r, contour_count);
	if (secondary_strength > 0.001) {
		float n2 = texture(noise_tex, uv1 * secondary_scale + vec2(3.7, 1.9)).r;
		lines = max(lines, contour(n2, contour_count) * secondary_strength);
	}

	// Deep base with a very subtle low-frequency blue variation (no big pale patches).
	float varn = texture(warp_tex, wp * (pattern_scale * 0.32)).r;
	vec3 deep = mix(base_color.rgb, secondary_color.rgb, smoothstep(0.45, 0.62, varn) * 0.5);

	// Contours fade out under the shallows and return gradually through the outer water.
	float contour_vis = smoothstep(contour_fade_in, contour_fade_out, sd);
	vec3 col = mix(deep, line_color.rgb, lines * contour_vis * line_opacity);

	ALBEDO = col;
	ALPHA = 1.0;
}
