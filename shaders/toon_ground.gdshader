shader_type spatial;
// Toon terrain for the 3D pixel-art port: per-vertex COLOR carries the tile's palette
// colour (sharp authored transitions, no blend/noise); shadow/light bands are derived by
// blending toward palette tints. Matches the toon_world banding model.
//
// BEACH: where the vertex is flagged as sand (UV.y), the base colour is replaced by a
// stylised sand treatment computed in WORLD SPACE — large quantised dry/highlight patches
// (macro variation), a darker+saturated WET band near the water (UV.x), and sparse 1px
// speckle. The sand/grass boundary is dithered with noise so it doesn't read as a hard
// tile line. All world-space + deterministic, so it's stable as the camera moves.

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert;

uniform vec4 shadow_tint : source_color = vec4(0.27, 0.34, 0.22, 1.0);
uniform vec4 light_tint : source_color  = vec4(0.42, 0.47, 0.28, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.30;
uniform float light_threshold : hint_range(0.0, 1.0)  = 0.58;
uniform float softness : hint_range(0.0, 0.4) = 0.04;
uniform float ambient : hint_range(0.0, 1.0) = 0.22;
uniform float posterize_steps : hint_range(2.0, 8.0) = 4.0;

// Sand palette + variation controls.
uniform vec4 sand_dry : source_color = vec4(0.902, 0.800, 0.471, 1.0);    // #E6CC78 main dry
uniform vec4 sand_hi : source_color  = vec4(0.941, 0.855, 0.541, 1.0);    // #F0DA8A highlight
uniform vec4 sand_wet : source_color = vec4(0.788, 0.678, 0.451, 1.0);    // #C9AD73 wet sand
uniform float sand_macro_scale = 0.04;   // big colour-patch frequency (world)
uniform float sand_detail_scale = 0.6;   // 1px speckle frequency (world)
uniform float sand_speckle : hint_range(0.0, 0.2) = 0.06;
uniform sampler2D sand_noise : repeat_enable, filter_linear;

varying vec3 v_col;
varying vec3 v_world;
varying float v_beach;   // 1 = sand tile (UV.y)
varying float v_wet;     // 0 dry .. 1 wet, near the waterline (UV.x)

void vertex() {
	v_col = COLOR.rgb;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_beach = UV.y;
	v_wet = UV.x;
}

vec3 beach_color(vec2 wp) {
	float macro = texture(sand_noise, wp * sand_macro_scale).r;
	// Three flat sand levels (quantised, not a smooth gradient).
	vec3 sand = sand_dry.rgb;
	sand = mix(sand, sand_dry.rgb * 0.95, step(macro, 0.34));   // slightly darker dry patch
	sand = mix(sand, sand_hi.rgb, step(0.72, macro));           // pale highlight patch
	// Wet band near the water: darker, more saturated sand.
	sand = mix(sand, sand_wet.rgb, clamp(v_wet, 0.0, 1.0));
	// Sparse 1px speckle (low contrast).
	float sp = texture(sand_noise, wp * sand_detail_scale + vec2(11.3, 7.1)).r;
	sand *= 1.0 - step(0.87, sp) * sand_speckle;
	sand += step(0.95, sp) * sand_speckle * 0.7;
	return sand;
}

void fragment() {
	vec3 base = v_col;
	if (v_beach > 0.001) {
		vec3 sand = beach_color(v_world.xz);
		// Dithered sand/grass boundary: a noise-jittered threshold on the beach factor so
		// the edge breaks into flat patches instead of a clean tile line.
		float edge_n = texture(sand_noise, v_world.xz * 0.45 + vec2(3.0, 9.0)).r;
		float bfac = smoothstep(edge_n * 0.5 + 0.12, edge_n * 0.5 + 0.30, v_beach);
		base = mix(base, sand, bfac);
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	lit = ambient + (1.0 - ambient) * lit;
	lit = floor(lit * posterize_steps + 0.5) / posterize_steps;
	vec3 base = ALBEDO;
	vec3 shad = mix(base, shadow_tint.rgb, 0.62);
	vec3 lite = mix(base, light_tint.rgb, 0.42);
	float s = smoothstep(shadow_threshold - softness, shadow_threshold + softness, lit);
	float l = smoothstep(light_threshold - softness, light_threshold + softness, lit);
	vec3 ramp = mix(shad, base, s);
	ramp = mix(ramp, lite, l);
	DIFFUSE_LIGHT += ramp * mix(vec3(1.0), LIGHT_COLOR.rgb, 0.18);
}
