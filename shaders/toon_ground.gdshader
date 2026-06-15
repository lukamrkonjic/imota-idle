shader_type spatial;
// Toon terrain for the 3D pixel-art port: per-vertex COLOR carries the tile's
// palette color (sharp authored transitions between tiles, no blend/noise); the
// shadow/light bands are derived by blending toward palette tints. Matches the
// toon_world banding model so terrain and props read as one style.

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert;

uniform vec4 shadow_tint : source_color = vec4(0.27, 0.34, 0.22, 1.0);
uniform vec4 light_tint : source_color  = vec4(0.42, 0.47, 0.28, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.25;
uniform float light_threshold : hint_range(0.0, 1.0)  = 0.62;
uniform float softness : hint_range(0.0, 0.4) = 0.10;
uniform float ambient : hint_range(0.0, 1.0) = 0.30;

varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	lit = ambient + (1.0 - ambient) * lit;
	vec3 base = v_col;
	vec3 shad = mix(base, shadow_tint.rgb, 0.45);
	vec3 lite = mix(base, light_tint.rgb, 0.35);
	float s = smoothstep(shadow_threshold - softness, shadow_threshold + softness, lit);
	float l = smoothstep(light_threshold - softness, light_threshold + softness, lit);
	vec3 ramp = mix(shad, base, s);
	ramp = mix(ramp, lite, l);
	DIFFUSE_LIGHT += ramp;
}
