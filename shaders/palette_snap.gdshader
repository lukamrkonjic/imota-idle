shader_type canvas_item;
// Final colour-treatment pass for the pixel-art world (Stage 3/8). Three modes:
//
//   mode 0  passthrough  — only the colour grade (contrast/saturation/brightness).
//   mode 1  palette snap  — map each pixel to the nearest palette colour (LINEAR space).
//                           CRISP but FLICKERS over smooth gradients: a near-boundary pixel
//                           can jump to a totally different hue, which reads as speckle.
//   mode 2  posterize     — quantize colour into stepped bands. Monotonic, so a smooth
//                           biome-blend gradient becomes clean adjacent bands (crisp, NO
//                           speckle, never muddy). Quantization is done on HSV so hue is
//                           preserved and only value/saturation step — the cel-shaded /
//                           A Short Hike look. This is the default.
//
// Alpha preserved. Grade always applies; `strength` blends the quantized result over it.

uniform sampler2D palette_tex : filter_nearest;
uniform int palette_count = 32;
uniform float mode = 2.0;                // 0 passthrough, 1 palette snap, 2 posterize
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.8) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float value_steps : hint_range(2.0, 24.0) = 9.0;   // brightness bands (posterize)
uniform float sat_steps : hint_range(2.0, 16.0) = 7.0;     // saturation bands (posterize)

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// RGB<->HSV so we can quantize value/saturation while leaving hue continuous.
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	src.rgb = mix(vec3(luma), src.rgb, saturation);
	src.rgb = (src.rgb - vec3(0.5)) * contrast + vec3(0.5);
	src.rgb *= brightness;
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));

	if (mode < 0.5) {
		COLOR = src;
	} else if (mode < 1.5) {
		// Palette snap (nearest colour in linear space).
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
	} else {
		// Posterize in HSV: keep hue, step value + saturation into flat bands.
		vec3 hsv = rgb2hsv(src.rgb);
		hsv.z = floor(hsv.z * value_steps + 0.5) / value_steps;
		hsv.y = floor(hsv.y * sat_steps + 0.5) / sat_steps;
		vec3 q = hsv2rgb(hsv);
		COLOR = vec4(mix(src.rgb, q, strength), src.a);
	}
}
