shader_type canvas_item;
// Optional final palette-matching pass for the pixel-art world (Stage 3/8).
// Maps each rendered pixel to the nearest color in a palette texture, compared in
// LINEAR space. No dithering, no noise, no ordered pattern. Alpha preserved.
// Disabled by default (enabled = 0); ramp up `strength` gradually.

uniform sampler2D palette_tex : filter_nearest;
uniform int palette_count = 32;
uniform float enabled = 0.0;            // 0 = passthrough, 1 = snap
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.8) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	src.rgb = mix(vec3(luma), src.rgb, saturation);
	src.rgb = (src.rgb - vec3(0.5)) * contrast + vec3(0.5);
	src.rgb *= brightness;
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));
	if (enabled < 0.5) {
		COLOR = src;
	} else {
		vec3 src_l = to_linear(src.rgb);
		float best = 1e9;
		vec3 best_c = src.rgb;
		for (int i = 0; i < 256; i++) {
			if (i >= palette_count) { break; }
			vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
			vec3 d = src_l - to_linear(p);
			float dist = dot(d, d);
			if (dist < best) { best = dist; best_c = p; }
		}
		COLOR = vec4(mix(src.rgb, best_c, strength), src.a);
	}
}
