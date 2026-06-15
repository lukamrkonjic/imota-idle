shader_type spatial;
// Reusable toon lighting for the 3D pixel-art preview (A Short Hike-style
// rendering, our palette). Three BROAD bands whose colors are distinct palette
// colors (NOT base * brightness): shadow / base / light. Soft-but-narrow
// thresholds, no rim, no fresnel, no outline, no specular. Cast-shadow regions
// fall to the material's palette shadow color, so shadows are never pure black.
//
// ambient_light_disabled: we composite the band color directly into
// DIFFUSE_LIGHT so the output is exactly the chosen palette colors regardless of
// the environment's ambient term (one key directional light is expected).

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert;

uniform vec4 shadow_color : source_color = vec4(0.13, 0.13, 0.16, 1.0);
uniform vec4 base_color : source_color   = vec4(0.35, 0.42, 0.29, 1.0);
uniform vec4 light_color : source_color  = vec4(0.42, 0.47, 0.28, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float light_threshold : hint_range(0.0, 1.0)  = 0.72;
uniform float softness : hint_range(0.0, 0.4) = 0.07;

void fragment() {
	// White albedo: the engine multiplies DIFFUSE_LIGHT by ALBEDO, so we keep
	// ALBEDO neutral and put the exact palette band colors in DIFFUSE_LIGHT.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// ATTENUATION folds in the directional shadow, so shadowed pixels read 0.
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	float s = smoothstep(shadow_threshold - softness, shadow_threshold + softness, lit);
	float l = smoothstep(light_threshold - softness, light_threshold + softness, lit);
	vec3 ramp = mix(shadow_color.rgb, base_color.rgb, s);
	ramp = mix(ramp, light_color.rgb, l);
	DIFFUSE_LIGHT += ramp;
}
