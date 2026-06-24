shader_type canvas_item;
// Soft drifting dawn mist: low-frequency fbm haze, denser low on screen (ground fog), fading up.
// Strength comes from the global `dawn_mist` (0 = none .. 1 = thick sunrise fog), driven each frame
// from the DayNight cycle. Rendered on a full-screen ColorRect above the 3D present.

global uniform float dawn_mist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	if (dawn_mist < 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = SCREEN_UV;
		// Two layers drifting at different speeds give the fog depth + slow churn.
		float drift = TIME * 0.012;
		float n = fbm(uv * vec2(3.2, 2.1) + vec2(drift, drift * 0.4));
		n = mix(n, fbm(uv * vec2(6.0, 4.0) - vec2(drift * 0.6, 0.0)), 0.35);
		float ground = smoothstep(0.15, 1.0, uv.y);   // denser toward the bottom (ground mist)
		float a = dawn_mist * ground * (0.22 + 0.6 * n);
		COLOR = vec4(vec3(0.87, 0.91, 0.96), clamp(a, 0.0, 0.72));
	}
}
