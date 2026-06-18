shader_type spatial;
// Stylized toon ocean. Modern approach: sum several directional travelling waves and
// derive the surface SLOPE analytically, building a smooth PER-PIXEL normal. The toon
// light ramp then shades real rolling crests and troughs (lit faces toward the sun,
// shaded faces away), and a height-based foam picks out the wave caps. Everything is
// world-space + sun-relative — no screen depth, fresnel or view vector — so it reads
// the SAME from any camera pitch/zoom. Coarse water mesh is fine: the wave detail
// lives in the fragment normal, not the geometry. Shore foam is separate ribbon mesh.

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert, cull_back, blend_mix, depth_prepass_alpha;

uniform vec4 base_color : source_color = vec4(0.31, 0.37, 0.47, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.23, 0.27, 0.35, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.48, 0.57, 1.0);
uniform float ambient : hint_range(0.0, 1.0) = 0.34;
uniform float alpha : hint_range(0.0, 1.0) = 0.92;
uniform float posterize_steps : hint_range(2.0, 8.0) = 4.0;
uniform float wave_scale = 1.0;    // overall ripple size (bigger = smaller waves)
uniform float wave_speed = 1.0;
uniform float choppiness : hint_range(0.0, 2.0) = 1.0;   // normal tilt / wave steepness
uniform float foam : hint_range(0.0, 1.0) = 0.35;        // white wave-cap strength

varying vec3 v_world;

// One travelling wave: accumulates height into h and slope (d height / d world.xz)
// into g. Slope of amp*sin(dot(p,dir)*freq + t) is amp*freq*dir*cos(...).
void add_wave(vec2 p, vec2 dir, float freq, float amp, float spd, float t, inout float h, inout vec2 g) {
	float ph = dot(p, dir) * freq + t * spd;
	h += amp * sin(ph);
	g += amp * freq * dir * cos(ph);
}

// Sum of waves -> total height + slope. Big slow swells carry the motion; finer,
// faster, cross-cutting ripples add detail. Returns height; writes slope to g.
float ocean(vec2 p, float t, out vec2 g) {
	// Domain warp: bend the sample space with a slow cross-flow so the wave crests
	// become long, organic, wandering fronts instead of regular rings or straight
	// stripes (the "weird lines" look).
	vec2 q = p + vec2(sin(p.y * 0.13 + t * 0.5), sin(p.x * 0.11 - t * 0.4)) * 1.7;
	g = vec2(0.0);
	float h = 0.0;
	// Dominant swells in SIMILAR directions -> long rolling crests that march across.
	add_wave(q, normalize(vec2(1.0,  0.32)), 0.34, 0.60, 1.0, t, h, g);   // ~18u swell
	add_wave(q, normalize(vec2(0.82, 0.58)), 0.52, 0.40, 1.3, t, h, g);   // ~12u swell
	// Cross chop + fine ripple for surface life.
	add_wave(q, normalize(vec2(-0.45, 1.0)), 0.95, 0.18, 1.9, t, h, g);   // ~6.6u chop
	add_wave(q, normalize(vec2( 0.25, 1.0)), 1.60, 0.09, 2.5, t, h, g);   // ~3.9u ripple
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g;
	float h = ocean(v_world.xz * wave_scale, TIME * wave_speed, g);
	VERTEX.y += h * 0.06;   // gentle gross bob (the look comes from the fragment normal)
}

// Toward the (fixed) sun — a world-space constant, so shading never depends on the
// camera. Matches the scene's directional light bearing.
const vec3 SUN = vec3(0.55, 0.66, 0.51);

void fragment() {
	ALPHA = alpha;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec2 g;
	float h = ocean(v_world.xz * wave_scale, TIME * wave_speed, g);
	// Surface normal from the wave slope (world space).
	vec3 wn = normalize(vec3(-g.x * choppiness, 1.0, -g.y * choppiness));
	// Cell-shaded toon water: posterise a blend of the wave HEIGHT (so crests read
	// light, troughs dark — flowing filled bands, not thin lines) and a gentle sun
	// lift off the wave normal. Both world-space -> identical from any camera angle.
	float v = clamp(h * 0.5 + 0.5, 0.0, 1.0) * 0.65 + clamp(dot(wn, normalize(SUN)), 0.0, 1.0) * 0.35;
	v = floor(v * posterize_steps + 0.5) / posterize_steps;
	vec3 col = mix(shadow_color.rgb, base_color.rgb, smoothstep(0.26, 0.46, v));
	col = mix(col, light_color.rgb, smoothstep(0.62, 0.84, v));
	// Thin foam crest LINES along the leading face of the tallest waves (height near a
	// peak AND sloping down-sun) plus soft white caps right at the peaks.
	float hn = h * 0.5 + 0.5;
	float crest_line = smoothstep(0.7, 0.78, hn) * (1.0 - smoothstep(0.86, 0.93, hn));
	float caps = smoothstep(0.9, 0.99, hn);
	col = mix(col, vec3(0.95, 0.98, 1.0), clamp(crest_line + caps, 0.0, 1.0) * foam);
	// Unlit: drive the colour entirely through EMISSION so it's fully controlled and
	// view-independent (no scene light/ambient term creeping in).
	ALBEDO = vec3(0.0);
	EMISSION = col;
}
