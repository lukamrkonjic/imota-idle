shader_type spatial;
// Illustrated stylized water (A Short Hike feel). A mostly-uniform deep-blue surface
// covered in thin, irregular, INTERCONNECTED wave LINES — like animated topographic
// contours / hand-drawn loops. The lines come from CONTOUR THRESHOLDS over two layers
// of domain-warped noise, NOT from sine waves (those read as regular rings/stripes).
//
// Everything is sampled from WORLD-SPACE xz + a slow TIME term, so the pattern is glued
// to the world and never slides when the camera moves/zooms. Flat & graphic: a tiny
// limited palette, hard edges, just enough AA to stop the low-res buffer flickering.
// No reflections, normals, gloss or geometry displacement. A narrow depth-based
// turquoise rim marks the shallow shoreline.

render_mode unshaded, cull_back, blend_mix, depth_prepass_alpha;

// --- palette (4 flat colours) -------------------------------------------------
uniform vec4 base_color : source_color = vec4(0.094, 0.345, 0.471, 1.0);       // #185878 deep water
uniform vec4 secondary_color : source_color = vec4(0.149, 0.435, 0.557, 1.0);  // slightly lighter blue
uniform vec4 line_color : source_color = vec4(0.235, 0.471, 0.596, 1.0);       // #3C7898 contour lines
uniform vec4 shoreline_color : source_color = vec4(0.439, 0.753, 0.737, 1.0);  // #70C0BC shallow rim

// --- pattern ------------------------------------------------------------------
uniform float pattern_scale = 0.13;             // world->noise freq for layer 1 (bigger = denser)
uniform float secondary_pattern_scale = 0.072;  // layer 2 freq (different so it never tiles obviously)
uniform float contour_count = 5.0;              // isolines drawn across the 0..1 noise range
uniform float line_width : hint_range(0.0, 0.5) = 0.05;  // half-thickness of a line, in contour units
uniform float domain_warp_strength = 0.55;      // how much the warp layer bends the lines
uniform float animation_strength : hint_range(0.0, 2.0) = 1.0;  // global motion multiplier (0 = frozen)
uniform float primary_speed = 0.6;              // layer 1 + warp drift speed
uniform float secondary_speed = 0.45;           // layer 2 drift speed (different -> shape morphs)

uniform float alpha : hint_range(0.0, 1.0) = 1.0;  // 1 = solid (no glassy see-through)

// Seamless tiling noise (NoiseTexture2D, single channel). One drives the pattern, the
// other (lower frequency) bends the sample space and adds the slow colour variation.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D warp_tex : repeat_enable, filter_linear;

varying vec3 v_world;

void vertex() {
	// World-space position of this surface point (mesh is built in world coords, but go
	// through MODEL_MATRIX so it's correct regardless of mesh placement/scale).
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Turn a 0..1 noise field into thin isolines: slice it into `contour_count` levels and
// light up only the narrow band hugging each level crossing. Width is kept ~constant on
// screen via fwidth so lines stay 1-2 px at the game's low internal resolution.
float contour(float n) {
	float v = n * contour_count;
	float d = min(fract(v), 1.0 - fract(v));      // distance to nearest isoline (0 = on the line)
	float aa = fwidth(v) * 0.7 + 0.0008;          // just enough AA to stop low-res flicker
	return 1.0 - smoothstep(line_width, line_width + aa, d);
}

void fragment() {
	vec2 wp = v_world.xz;
	float t = TIME * animation_strength;

	// Domain warp: a slow low-frequency noise offsets the sample coords so the contour
	// lines wander into organic loops/bends instead of smooth blobs. Two decorrelated
	// taps give an x and y offset. Drifts gently along one diagonal.
	vec2 wuv = wp * (pattern_scale * 0.45) + vec2(0.013, 0.009) * primary_speed * t;
	float wx = texture(warp_tex, wuv).r;
	float wy = texture(warp_tex, wuv + vec2(0.37, 0.21)).r;
	vec2 warp = (vec2(wx, wy) - 0.5) * domain_warp_strength;

	// Layer 1: drifts one way. Layer 2: coarser, drifts a near-perpendicular way at a
	// different speed, so the combined pattern slowly morphs and never looks repetitive.
	vec2 uv1 = wp * pattern_scale + warp + vec2(0.006, -0.004) * primary_speed * t;
	vec2 uv2 = wp * secondary_pattern_scale - warp * 0.6 + vec2(-0.004, 0.007) * secondary_speed * t;
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex, uv2).r;
	float lines = max(contour(n1), contour(n2));

	// Base: deep blue, with a faint secondary-blue variation from a very low-freq noise
	// so the field isn't a dead-flat fill (kept subtle — no large gradients/patches).
	float varn = texture(warp_tex, wp * (pattern_scale * 0.3) + vec2(-0.01, 0.006) * t).r;
	vec3 col = mix(base_color.rgb, secondary_color.rgb, smoothstep(0.42, 0.66, varn) * 0.6);
	col = mix(col, line_color.rgb, lines);
	// Shoreline rim is a separate geometry ribbon (see world_render_3d.gd) using
	// shoreline_color — reliable narrow width that follows the coast from any angle.

	ALBEDO = col;
	ALPHA = alpha;
}
