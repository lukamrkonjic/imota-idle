shader_type spatial;
// Illustrated calm-ocean water (A Short Hike feel). A deep-blue surface with a FEW
// large, widely-spaced contour loops — like calm topographic lines — and a clean
// turquoise shallow-water band along the coast.
//
// The contour pattern is built purely from WORLD-SPACE xz (one dominant domain-warped
// noise -> contour thresholds -> thin isolines), so it is glued to the world and never
// moves with the camera. The shallow band is a SEPARATE channel: a per-vertex
// distance-to-land value (UV.x, in tiles, baked from the terrain grid) -> a smooth
// shore mask. The two are computed independently — the shoreline never distorts the
// contours and the contours never leak into the shore.
//
// No geometry displacement, no depth sampling, no screen-space tricks, no neon lines.

render_mode unshaded, cull_back, blend_mix, depth_prepass_alpha;

// --- palette (restrained: one deep blue, one muted blue-cyan line, turquoise shallow) -
uniform vec4 base_color : source_color = vec4(0.078, 0.353, 0.471, 1.0);       // #145A78
uniform vec4 secondary_color : source_color = vec4(0.106, 0.400, 0.518, 1.0);  // #1B6684
uniform vec4 line_color : source_color = vec4(0.239, 0.506, 0.604, 1.0);       // #3D819A
uniform vec4 shoreline_color : source_color = vec4(0.384, 0.757, 0.741, 1.0);  // #62C1BD

// --- contour pattern ----------------------------------------------------------
uniform float pattern_scale = 0.032;            // world->noise freq (small = big, calm loops)
uniform float contour_count = 2.0;              // number of isolines across the noise range
uniform float line_width : hint_range(0.0, 0.5) = 0.035;     // half line thickness (contour units)
uniform float line_opacity : hint_range(0.0, 1.0) = 0.6;     // how strongly lines tint the water
uniform float domain_warp_strength = 0.5;       // bends the loops into organic shapes
uniform float secondary_strength : hint_range(0.0, 1.0) = 0.3;  // weak 2nd detail (never an equal net)
uniform float secondary_scale = 1.7;            // 2nd-layer relative frequency
uniform vec2 primary_speed = vec2(0.006, 0.003);    // slow warp drift A (normalized coords)
uniform vec2 secondary_speed = vec2(-0.003, 0.005); // slow warp drift B (different vector)

// --- shallow-water band (from the terrain distance field, not depth) ----------
uniform float shallow_start = 0.06;   // tiles from land where the band is full turquoise
uniform float shallow_end = 0.42;     // tiles from land where it has faded to deep water
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D warp_tex : repeat_enable, filter_linear;

varying vec3 v_world;
varying float v_dist;   // distance to nearest land, in tiles (baked into UV.x)

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = UV.x;
}

// 0..1 noise -> thin isolines. Slice into `count` levels, light up the narrow band at
// each crossing. fwidth keeps the line ~1px on screen at any zoom (no fixed-AA flicker).
float contour(float n, float count) {
	float v = n * count;
	float d = min(fract(v), 1.0 - fract(v));
	float aa = fwidth(v) * 0.8 + 0.0008;
	return 1.0 - smoothstep(line_width, line_width + aa, d);
}

void fragment() {
	vec2 wp = v_world.xz;

	// Animated DOMAIN WARP only: two slow, near-perpendicular vectors move the warp
	// sample (not the whole pattern), so the big loops keep their identity and just
	// gently breathe — no wholesale scrolling, no boiling.
	vec2 w1 = wp * (pattern_scale * 0.5) + primary_speed * TIME;
	vec2 w2 = wp * (pattern_scale * 0.5) + secondary_speed * TIME + vec2(0.4, 0.2);
	vec2 warp = (vec2(texture(warp_tex, w1).r, texture(warp_tex, w2).r) - 0.5) * domain_warp_strength;

	// One DOMINANT contour layer.
	vec2 uv1 = wp * pattern_scale + warp;
	float lines = contour(texture(noise_tex, uv1).r, contour_count);
	// Optional WEAK secondary detail at a different scale (kept subdued so it never
	// becomes a second equal network of lines).
	if (secondary_strength > 0.001) {
		float n2 = texture(noise_tex, uv1 * secondary_scale + vec2(3.7, 1.9)).r;
		lines = max(lines, contour(n2, contour_count) * secondary_strength);
	}

	// Deep base with a very subtle low-frequency blue variation (no big pale patches).
	float varn = texture(warp_tex, wp * (pattern_scale * 0.32)).r;
	vec3 deep = mix(base_color.rgb, secondary_color.rgb, smoothstep(0.45, 0.62, varn) * 0.5);

	// Shallow band straight from the terrain distance field: full near land, fading to
	// deep water by `shallow_end`. Continuous and camera-independent.
	float shore = 1.0 - smoothstep(shallow_start, shallow_end, v_dist);

	// Contours fade out inside the shallows so the band stays a clean flat colour.
	float line_mask = lines * (1.0 - shore) * line_opacity;
	vec3 col = mix(deep, line_color.rgb, line_mask);
	col = mix(col, shoreline_color.rgb, shore);

	ALBEDO = col;
	ALPHA = alpha;
}
