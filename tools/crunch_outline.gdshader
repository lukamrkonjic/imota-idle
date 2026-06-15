shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
// Restrained screen-space edge separation (NOT an ink contour). Edges are a
// dark, desaturated palette colour at low opacity, depth-driven with normal
// edges much subtler, faded with distance, and suppressed on near-flat ground.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

uniform vec3 outline_color : source_color = vec3(0.26, 0.21, 0.24);
uniform float depth_threshold = 0.9;
uniform float normal_threshold = 1.3;
uniform float depth_strength = 1.0;
uniform float normal_strength = 0.35;
uniform float outline_opacity = 0.38;
uniform float thickness = 1.0;
uniform float fade_start = 22.0;
uniform float fade_end = 46.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);  // fullscreen
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, raw), 1.0);
	return -(view.z / view.w);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ts = thickness / VIEWPORT_SIZE;
	vec3 base = texture(screen_tex, uv).rgb;

	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv - vec2(ts.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(ts.x, 0.0), INV_PROJECTION_MATRIX);
	float du = lin_depth(uv - vec2(0.0, ts.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, ts.y), INV_PROJECTION_MATRIX);
	float depth_diff = max(max(abs(dc - dl), abs(dc - dr)), max(abs(dc - du), abs(dc - dd)));
	float depth_edge = smoothstep(depth_threshold * 0.6, depth_threshold * 1.4, depth_diff) * depth_strength;

	vec3 nc = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 nl = texture(normal_tex, uv - vec2(ts.x, 0.0)).rgb * 2.0 - 1.0;
	vec3 nr = texture(normal_tex, uv + vec2(ts.x, 0.0)).rgb * 2.0 - 1.0;
	vec3 nu = texture(normal_tex, uv - vec2(0.0, ts.y)).rgb * 2.0 - 1.0;
	vec3 nd = texture(normal_tex, uv + vec2(0.0, ts.y)).rgb * 2.0 - 1.0;
	float ne = (1.0 - dot(nc, nl)) + (1.0 - dot(nc, nr)) + (1.0 - dot(nc, nu)) + (1.0 - dot(nc, nd));
	float normal_edge = smoothstep(normal_threshold * 0.7, normal_threshold * 1.3, ne) * normal_strength;

	// Suppress edges on near-flat, upward surfaces (the ground): the encoded
	// normal's green channel is high when the surface faces the camera-up.
	float upface = smoothstep(0.55, 0.85, texture(normal_tex, uv).g);
	normal_edge *= (1.0 - upface * 0.85);

	float fade = 1.0 - smoothstep(fade_start, fade_end, dc);
	float edge = clamp(max(depth_edge, normal_edge), 0.0, 1.0) * fade * outline_opacity;
	ALBEDO = mix(base, outline_color, edge);
}
