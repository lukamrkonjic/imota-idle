shader_type canvas_item;
// Aldenfall-style baked terrain, evaluated live: chunky PX pixels, value-noise
// grass patches, Bayer dither, cobble plaza, dirt paths to each camp, and a
// lake in the fishing sector. Ported from aldenfall/src/world/terrainBake.ts.

uniform float half_size = 1700.0;
uniform float px = 4.0;

// Palette (pixelPalette.ts)
const vec3 GRASS_A = vec3(0.290, 0.486, 0.247);
const vec3 GRASS_B = vec3(0.337, 0.533, 0.282);
const vec3 GRASS_C = vec3(0.239, 0.408, 0.208);
const vec3 GRASS_DARK = vec3(0.176, 0.314, 0.188);
const vec3 DIRT_A = vec3(0.545, 0.388, 0.251);
const vec3 DIRT_B = vec3(0.435, 0.306, 0.196);
const vec3 COBBLE_A = vec3(0.541, 0.502, 0.471);
const vec3 COBBLE_B = vec3(0.416, 0.376, 0.345);
const vec3 SAND_A = vec3(0.769, 0.627, 0.376);
const vec3 SAND_B = vec3(0.627, 0.502, 0.282);
const vec3 WATER_A = vec3(0.227, 0.549, 0.659);
const vec3 WATER_B = vec3(0.165, 0.408, 0.502);
const vec3 WATER_DEEP_A = vec3(0.102, 0.282, 0.376);
const vec3 WATER_DEEP_B = vec3(0.071, 0.220, 0.282);

// Sector mids (must match world.gd SECTORS): enemies 0, foraging 1.255,
// woodcutting 2.51, mining 3.77, fishing 5.02.
const float FISH_MID = 5.02;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 wp) {
	vec2 cell = wp / 96.0; // 24 art px * PX
	vec2 i = floor(cell);
	vec2 f = fract(cell);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1, 0));
	float c = hash2(i + vec2(0, 1));
	float d = hash2(i + vec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float bayer4(vec2 ip) {
	int x = int(mod(ip.x, 4.0));
	int y = int(mod(ip.y, 4.0));
	int m[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
	return (float(m[y * 4 + x]) / 16.0 - 0.5) * 0.12;
}

float ang_dist(float a, float b) {
	float d = abs(mod(a - b + TAU * 1.5, TAU) - PI);
	return PI - d;
}

void fragment() {
	vec2 world = UV * half_size * 2.0 - half_size;
	vec2 wp = floor(world / px) * px;       // chunky pixel grid
	vec2 ip = floor(world / px);            // dither index

	float dist = length(wp);
	float angle = mod(atan(wp.y, wp.x) + TAU, TAU);
	float n = vnoise(wp);

	// Base grass patchwork.
	vec3 col = n > 0.66 ? GRASS_A : (n > 0.33 ? GRASS_B : GRASS_C);
	col = mix(col, GRASS_DARK, vnoise(wp + vec2(200.0, 100.0)) * 0.25);

	// Dirt paths from the plaza out to each camp (5 sector mids).
	float paths[5] = {0.0, 1.255, 2.51, 3.77, 5.02};
	float path_w = 0.0;
	for (int i = 0; i < 5; i++) {
		float ad = ang_dist(angle, paths[i]);
		float lateral = ad * max(dist, 1.0);
		float along = 1.0 - smoothstep(420.0, 560.0, dist);
		float across = 1.0 - smoothstep(26.0, 50.0, lateral);
		path_w = max(path_w, across * along * step(90.0, dist));
	}
	vec3 road = mix(DIRT_A, COBBLE_A, vnoise(wp + vec2(30.0, 0.0)));
	col = mix(col, road, min(1.0, path_w * 1.2));

	// Cobble plaza.
	float plaza = 1.0 - smoothstep(120.0, 185.0, dist);
	col = mix(col, mix(COBBLE_A, COBBLE_B, vnoise(wp + vec2(50.0, 0.0))), plaza);

	// Fishing-sector lake with sand shore.
	float ad_fish = ang_dist(angle, FISH_MID);
	float lake_ang = 1.0 - smoothstep(0.34, 0.55, ad_fish);
	float lake_rad = smoothstep(300.0, 420.0, dist);
	float lake = lake_ang * lake_rad + (vnoise(wp * 0.5) - 0.5) * 0.08;
	float sand_w = smoothstep(0.30, 0.46, lake) * (1.0 - smoothstep(0.46, 0.55, lake));
	col = mix(col, mix(SAND_A, SAND_B, n), sand_w);
	if (lake > 0.5) {
		vec3 shallow = mix(WATER_A, WATER_B, vnoise(wp * 0.5));
		vec3 deep = mix(WATER_DEEP_A, WATER_DEEP_B, n);
		col = mix(shallow, deep, smoothstep(0.55, 0.85, lake));
	}

	// Micro variation + ordered dither (terrainBake.ts).
	float micro = hash2(floor(wp / 32.0));
	if (micro > 0.72) { col *= 1.05; }
	else if (micro < 0.28) { col *= 0.95; }
	col *= 1.0 + bayer4(ip);

	COLOR = vec4(col, 1.0);
}
