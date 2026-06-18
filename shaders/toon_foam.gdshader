shader_type spatial;
// Shoreline ribbon: a flat turquoise shallow band with animated, BROKEN white foam
// lapping at the waterline. Foam is keyed off world-space noise (so it's camera-stable
// and never a moving blob) and concentrated at the land edge of the ribbon (UV.x -> 0).
// A per-vertex "openness" value (COLOR.r, bigger for larger open seas) widens and
// thickens the foam so oceans froth more than little ponds. Flat & graphic; no gloss.

render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 shallow_color : source_color = vec4(0.439, 0.753, 0.737, 1.0);  // #70C0BC
uniform vec4 foam_color : source_color = vec4(0.90, 0.965, 0.97, 1.0);       // off-white crest
uniform float foam_scale = 1.0;       // world frequency of the foam breakup
uniform float foam_speed = 0.5;       // lapping speed
uniform float foam_coverage : hint_range(0.0, 1.0) = 0.45;  // base foam density at the lip
uniform sampler2D foam_noise : repeat_enable, filter_linear;

varying vec3 v_world;
varying float v_edge;   // 0 at the waterline (land edge) -> 1 at the inner (open-water) edge
varying float v_open;   // local sea openness, 0 (pond) .. 1 (open ocean)

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_edge = UV.x;
	v_open = COLOR.r;
}

void fragment() {
	vec3 col = shallow_color.rgb;
	// Foam reaches further in on bigger seas.
	float band = 0.45 + v_open * 0.5;
	float near = 1.0 - smoothstep(0.0, band, v_edge);
	// Two scrolling noise taps -> broken, lapping foam (world-space => stable).
	vec2 wp = v_world.xz;
	float n1 = texture(foam_noise, wp * (0.18 * foam_scale) + vec2(0.03, -0.02) * foam_speed * TIME).r;
	float n2 = texture(foam_noise, wp * (0.36 * foam_scale) - vec2(0.02, 0.025) * foam_speed * TIME).r;
	float fn = n1 * 0.6 + n2 * 0.4;
	// Higher coverage (and bigger seas) -> lower threshold -> more foam cells light up.
	float cover = clamp(foam_coverage + v_open * 0.35, 0.0, 0.95);
	float thresh = mix(0.66, 0.18, cover);
	float broken = smoothstep(thresh, thresh + 0.10, fn);
	float foam = near * broken;
	// A near-solid foam lip right at the waterline so the coast always reads as foamy.
	float lip = (1.0 - smoothstep(0.0, 0.30, v_edge)) * (0.9 + v_open * 0.1);
	foam = clamp(max(foam, lip), 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam);
	ALBEDO = col;
	ALPHA = 1.0;
}
