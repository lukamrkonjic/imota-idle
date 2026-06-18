shader_type spatial;
// Calm stylized toon water (A Short Hike-ish): flat palette water with broad
// bands, a gentle vertex wave, slight transparency, and a crisp depth-based FOAM
// line where the water meets land/shallow geometry. No specular/rim.

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert, cull_back, blend_mix, depth_prepass_alpha;

uniform vec4 base_color : source_color = vec4(0.31, 0.37, 0.47, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.23, 0.27, 0.35, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.48, 0.57, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.83, 0.88, 1.0);
uniform float ambient : hint_range(0.0, 1.0) = 0.34;
uniform float wave_amp = 0.035;
uniform float wave_speed = 0.7;
uniform float alpha : hint_range(0.0, 1.0) = 0.92;
uniform float foam_dist = 0.7;     // view-depth gap (world units) the foam spans
uniform float foam_strength : hint_range(0.0, 1.0) = 0.18;
uniform float posterize_steps : hint_range(2.0, 8.0) = 4.0;
uniform float line_strength : hint_range(0.0, 1.0) = 0.4;  // flowing contour lines
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

// World-space position handed to the fragment so the surface pattern is anchored to
// the WORLD, not the screen — it looks identical from any camera pitch/zoom (no more
// "one flat colour when you tilt the camera up", which was the view-dependent foam).
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin((VERTEX.x + VERTEX.z) * 1.3 + TIME * wave_speed) * wave_amp;
}

// A Short Hike-style water: a big, slow, organic "depth" field built from drifting
// sine waves, drawn as NESTED TOPOGRAPHIC CONTOUR LINES (a thin bright line at every
// level of the field). Because the field animates, the whole ring pattern morphs and
// flows like rolling waves. All from world position + time -> camera-independent.
float water_field(vec2 wp) {
	return sin(wp.x * 0.085 + TIME * 0.16)
		+ sin(wp.y * 0.072 - TIME * 0.12)
		+ sin((wp.x + wp.y) * 0.05 + TIME * 0.10) * 0.85
		+ sin((wp.x - wp.y) * 0.09 - TIME * 0.18) * 0.55
		+ sin(length(wp) * 0.04 - TIME * 0.22) * 0.4;   // a slow radial swell
}

// Two contour sets at slightly different spacings, offset in time, blended — the
// extra layer gives the busy, overlapping-ripple richness of the reference.
float water_lines(vec2 wp) {
	float f = water_field(wp);
	float a = abs(fract(f * 1.35) - 0.5) * 2.0;          // contour set A
	float b = abs(fract(f * 0.78 + 0.37) - 0.5) * 2.0;   // contour set B (wider rings)
	float la = smoothstep(0.80, 0.95, a);
	float lb = smoothstep(0.86, 0.97, b) * 0.7;
	return clamp(la + lb, 0.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alpha;
	// Foam: reconstruct the scene depth behind the water and compare to this
	// fragment's view depth — small gap = shore/shallow = foam. (Kept only as a thin
	// shore edge; the surface PATTERN below is world-space, not depth-based.)
	float d = texture(depth_tex, SCREEN_UV).x;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_depth = -(up.z / up.w);
	float surf_depth = -VERTEX.z;
	float gap = scene_depth - surf_depth;
	float foam = (1.0 - smoothstep(0.0, foam_dist, gap)) * foam_strength;
	// Flowing contour lines, anchored to world XZ -> camera-independent.
	float lines = water_lines(v_world.xz) * line_strength;
	EMISSION = foam_color.rgb * foam + light_color.rgb * lines;
}

void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	lit = ambient + (1.0 - ambient) * lit;
	lit = floor(lit * posterize_steps + 0.5) / posterize_steps;
	vec3 ramp = mix(shadow_color.rgb, base_color.rgb, smoothstep(0.32, 0.44, lit));
	ramp = mix(ramp, light_color.rgb, smoothstep(0.68, 0.82, lit));
	DIFFUSE_LIGHT += ramp;
}
