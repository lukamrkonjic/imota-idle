shader_type spatial;
// Calm stylized toon water for the 3D pixel-art world (A Short Hike-ish): flat
// palette water with broad bands, a gentle vertex wave, slight transparency.
// No specular/rim, ambient-disabled so the band colors stay exact palette.

render_mode specular_disabled, ambient_light_disabled, diffuse_lambert, cull_back;

uniform vec4 base_color : source_color = vec4(0.31, 0.37, 0.47, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.23, 0.27, 0.35, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.48, 0.57, 1.0);
uniform float ambient : hint_range(0.0, 1.0) = 0.42;
uniform float wave_amp = 0.035;
uniform float wave_speed = 0.7;
uniform float alpha : hint_range(0.0, 1.0) = 0.92;

void vertex() {
	VERTEX.y += sin((VERTEX.x + VERTEX.z) * 1.3 + TIME * wave_speed) * wave_amp;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alpha;
}

void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	lit = ambient + (1.0 - ambient) * lit;
	vec3 ramp = mix(shadow_color.rgb, base_color.rgb, smoothstep(0.28, 0.42, lit));
	ramp = mix(ramp, light_color.rgb, smoothstep(0.72, 0.86, lit));
	DIFFUSE_LIGHT += ramp;
}
