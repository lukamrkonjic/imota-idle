shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert;
// Continuous WORLD-SPACE terrain colouring with NO high-frequency speckle:
// broad grass regions from ONE low-frequency mask quantised into 4 palette
// bands, a subtle broad value mask, and a 3-region winding dirt path with
// CLEAN discrete edges (no smoothstep feather / glow).

uniform sampler2D noise_lo : repeat_enable, filter_linear;

uniform vec3 g0 : source_color;
uniform vec3 g1 : source_color;
uniform vec3 g2 : source_color;
uniform vec3 g3 : source_color;
uniform vec3 path_center : source_color;
uniform vec3 path_main : source_color;
uniform vec3 path_edge : source_color;

uniform float region_scale = 0.12;  // broad colour regions (~4-8 m)
uniform float value_scale = 0.32;   // broad value variation (~1.5-3 m)
uniform float fade = 0.10;

varying vec3 vw;

void vertex() {
	vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float path_z(float x) {
	return sin(x * 0.42) * 3.0 + cos(x * 0.21) * 1.4;
}

void fragment() {
	// Broad region mask -> 4 grass bands (no per-pixel / high-frequency noise).
	float nb = texture(noise_lo, vw.xz * region_scale).r;
	float nm = texture(noise_lo, vw.xz * value_scale + vec2(0.37)).r;
	float v = clamp((nb - 0.5) * 1.3 + 0.5, 0.0, 1.0);
	vec3 grass = (v < 0.28) ? g0 : ((v < 0.5) ? g1 : ((v < 0.74) ? g2 : g3));
	grass *= 1.0 + (nm - 0.5) * 0.06;  // gentle broad value variation only

	// Path: discrete regions, clean edges, width varied broadly along its length.
	float widthn = texture(noise_lo, vec2(vw.x * 0.06, 0.3)).r;
	float hw = 0.9 * (1.0 + (widthn - 0.5) * 0.6);
	float pd = abs(vw.z - path_z(vw.x));
	float edge = (nm - 0.5) * 0.22;  // irregular but clean boundary
	vec3 col = grass;
	if (pd < hw + edge) {
		if (pd < hw * 0.42 + edge) col = path_center;
		else if (pd < hw * 0.82 + edge) col = path_main;
		else col = path_edge;
		if (nm > 0.80 && pd > hw * 0.5) col = grass;  // sparse grass intrusions
	}

	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), fade);  // slightly faded
	ALBEDO = col;
}

void light() {
	float d = dot(normalize(NORMAL), normalize(LIGHT));
	float t = smoothstep(0.32, 0.44, d);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * ATTENUATION * (0.62 + 0.38 * t);
}
