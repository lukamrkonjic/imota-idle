shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
// Full-screen post-process outline (3D-pixel-art technique): detects silhouette
// + crease edges from the DEPTH and NORMAL buffers and tints them, then passes
// the rest of the scene through. Runs as a quad parented to the camera.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

uniform vec3 outline_color : source_color = vec3(0.13, 0.10, 0.12);
uniform float depth_threshold = 0.06;
uniform float normal_threshold = 0.85;
uniform float thickness = 1.0;
uniform float outline_opacity = 0.9;

void vertex() {
	// Cover the whole screen regardless of the quad's transform.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
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

	// Depth discontinuity (silhouettes + overlapping props).
	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv - vec2(ts.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(ts.x, 0.0), INV_PROJECTION_MATRIX);
	float du = lin_depth(uv - vec2(0.0, ts.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, ts.y), INV_PROJECTION_MATRIX);
	float depth_diff = max(max(abs(dc - dl), abs(dc - dr)), max(abs(dc - du), abs(dc - dd)));
	float depth_edge = step(depth_threshold, depth_diff);

	// Normal discontinuity (creases on the same surface).
	vec3 nc = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 nl = texture(normal_tex, uv - vec2(ts.x, 0.0)).rgb * 2.0 - 1.0;
	vec3 nr = texture(normal_tex, uv + vec2(ts.x, 0.0)).rgb * 2.0 - 1.0;
	vec3 nu = texture(normal_tex, uv - vec2(0.0, ts.y)).rgb * 2.0 - 1.0;
	vec3 nd = texture(normal_tex, uv + vec2(0.0, ts.y)).rgb * 2.0 - 1.0;
	float ne = (1.0 - dot(nc, nl)) + (1.0 - dot(nc, nr)) + (1.0 - dot(nc, nu)) + (1.0 - dot(nc, nd));
	float normal_edge = step(normal_threshold, ne);

	float edge = max(depth_edge, normal_edge) * outline_opacity;
	ALBEDO = mix(base, outline_color, edge);
}
