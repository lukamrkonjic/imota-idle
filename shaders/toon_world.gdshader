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

uniform vec4 shadow_color : source_color = vec4(0.27, 0.30, 0.24, 1.0);
uniform vec4 base_color : source_color   = vec4(0.35, 0.42, 0.29, 1.0);
uniform vec4 light_color : source_color  = vec4(0.42, 0.47, 0.28, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.34;
uniform float light_threshold : hint_range(0.0, 1.0)  = 0.62;
uniform float softness : hint_range(0.0, 0.4) = 0.045;
// Ambient fill lifts the floor so shadow-facing surfaces stay readable (soft,
// warm A Short Hike shadows rather than near-black).
uniform float ambient : hint_range(0.0, 1.0) = 0.16;
uniform float posterize_steps : hint_range(2.0, 8.0) = 4.0;
// Gentle canopy/grass sway. 0 = off (trunks, rocks, houses). Per-instance phase
// from the model origin; taller verts sway more.
uniform float wind : hint_range(0.0, 0.3) = 0.0;
uniform float wind_speed = 1.6;

void vertex() {
	if (wind > 0.0) {
		vec2 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
		// Two summed frequencies give a livelier, less mechanical gust than a
		// single sine; per-instance phase from world position decorrelates props.
		float phase = TIME * wind_speed + wp.x * 0.6 + wp.y * 0.4;
		float gust = sin(phase) * 0.75 + sin(phase * 2.3 + 1.1) * 0.25;
		float lift = max(VERTEX.y + 0.4, 0.0);
		VERTEX.x += gust * wind * lift;
		VERTEX.z += cos(phase * 0.8) * wind * 0.5 * lift;
	}
}

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
	lit = ambient + (1.0 - ambient) * lit;
	lit = floor(lit * posterize_steps + 0.5) / posterize_steps;
	float s = smoothstep(shadow_threshold - softness, shadow_threshold + softness, lit);
	float l = smoothstep(light_threshold - softness, light_threshold + softness, lit);
	vec3 ramp = mix(shadow_color.rgb, base_color.rgb, s);
	ramp = mix(ramp, light_color.rgb, l);
	// Subtle warm wash from the sun color — keeps palette identity, adds warmth.
	DIFFUSE_LIGHT += ramp * mix(vec3(1.0), LIGHT_COLOR.rgb, 0.18);
}
