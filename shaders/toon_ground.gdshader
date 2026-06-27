shader_type spatial;
// Toon terrain for the 3D pixel-art port. STABLE, ARTIST-AUTHORED ground (A Short Hike): the terrain
// colour is the baked per-vertex palette colour, shaped by a FIXED stylized form shade and a single
// uniform global MOOD multiplier. It is deliberately UNSHADED — it does NOT read the scene sun's
// direction/colour/energy and does NOT receive the directional shadow map, so the ground never
// recolours or shows jagged shadow crawl as the day/weather changes. (Props/characters/water keep
// their normal stylized lighting; only the terrain ground is decoupled.)
//
//   final = base_terrain_colour * fixed_form_shade * terrain_mood
//
// BEACH: where the vertex is flagged as sand (UV.y), the base colour is replaced by a stylised sand
// treatment computed in WORLD SPACE (stable as the camera moves). See beach_color().

render_mode unshaded, cull_back;

// Fixed form-shade banding tints (toward these on lit / shadowed faces). Cold variants for snow.
uniform vec4 shadow_tint : source_color = vec4(0.27, 0.34, 0.22, 1.0);
uniform vec4 light_tint : source_color  = vec4(0.42, 0.47, 0.28, 1.0);
uniform vec4 cold_shadow_tint : source_color = vec4(0.66, 0.71, 0.78, 1.0);
uniform vec4 cold_light_tint : source_color  = vec4(0.94, 0.96, 0.99, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.30;
uniform float light_threshold : hint_range(0.0, 1.0)  = 0.58;
uniform float softness : hint_range(0.0, 0.4) = 0.04;
uniform float ambient : hint_range(0.0, 1.0) = 0.22;
uniform float posterize_steps : hint_range(2.0, 8.0) = 4.0;
// How much the terrain's OWN surface normal shades it. Low = flat, even ground (A Short Hike): gentle
// undulation no longer bands into fake "shadows". This is a FIXED form shade (see fixed_light_dir).
uniform float slope_shading : hint_range(0.0, 1.0) = 0.16;
// How strongly the lit / shadowed form-shade bands tint the base colour. Subtle = painted, stable.
uniform float form_light_amt : hint_range(0.0, 1.0) = 0.42;
uniform float form_shadow_amt : hint_range(0.0, 1.0) = 0.30;

// FIXED fake light direction (WORLD space) for the stylized form shade. This is a constant — NOT the
// scene sun — so the shading never moves with the day/night cycle or recolours with weather. Points
// from a high afternoon side so gentle hills read with soft, stable form.
uniform vec3 fixed_light_dir = vec3(0.35, 0.86, 0.37);

// Global day/night/weather MOOD: ONE uniform multiplier applied evenly to all terrain (set from
// GDScript by WorldAtmosphere from DayNight/Weather). Directionless, white = neutral day. This is the
// ONLY way time/weather may touch the terrain — uniform, never per-tile, never the sun's colour.
uniform vec4 terrain_mood : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Sand palette + variation controls.
uniform vec4 sand_dry : source_color = vec4(0.902, 0.800, 0.471, 1.0);    // #E6CC78 main dry
uniform vec4 sand_hi : source_color  = vec4(0.941, 0.855, 0.541, 1.0);    // #F0DA8A highlight
uniform vec4 sand_wet : source_color = vec4(0.788, 0.678, 0.451, 1.0);    // #C9AD73 wet sand
uniform float sand_macro_scale = 0.04;   // big colour-patch frequency (world)
uniform float sand_detail_scale = 0.6;   // 1px speckle frequency (world)
uniform float sand_speckle : hint_range(0.0, 0.2) = 0.06;
uniform sampler2D sand_noise : repeat_enable, filter_linear;

varying vec3 v_col;
varying vec3 v_world;
varying vec3 v_wnormal;   // world-space normal -> STABLE fixed-direction form shade
varying float v_beach;    // 1 = sand tile (UV.y)
varying float v_wet;      // 0 dry .. 1 wet, near the waterline (UV.x)
varying float v_cold;     // snow/frozen surface fraction at this shared corner (UV2.x)

void vertex() {
	v_col = COLOR.rgb;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_beach = UV.y;
	v_wet = UV.x;
	v_cold = UV2.x;
}

vec3 beach_color(vec2 wp) {
	float macro = texture(sand_noise, wp * sand_macro_scale).r;
	// Three flat sand levels (quantised, not a smooth gradient).
	vec3 sand = sand_dry.rgb;
	sand = mix(sand, sand_dry.rgb * 0.95, step(macro, 0.34));   // slightly darker dry patch
	sand = mix(sand, sand_hi.rgb, step(0.72, macro));           // pale highlight patch
	// Wet band near the water: darker, more saturated sand.
	sand = mix(sand, sand_wet.rgb, clamp(v_wet, 0.0, 1.0));
	// Sparse 1px speckle (low contrast).
	float sp = texture(sand_noise, wp * sand_detail_scale + vec2(11.3, 7.1)).r;
	sand *= 1.0 - step(0.87, sp) * sand_speckle;
	sand += step(0.95, sp) * sand_speckle * 0.7;
	return sand;
}

void fragment() {
	vec3 base = v_col;
	if (v_beach > 0.001) {
		vec3 sand = beach_color(v_world.xz);
		// Dithered sand/grass boundary: a noise-jittered threshold on the beach factor so
		// the edge breaks into flat patches instead of a clean tile line.
		float edge_n = texture(sand_noise, v_world.xz * 0.45 + vec2(3.0, 9.0)).r;
		float bfac = smoothstep(edge_n * 0.5 + 0.12, edge_n * 0.5 + 0.30, v_beach);
		base = mix(base, sand, bfac);
	}

	// FIXED stylized FORM SHADE — same banding model as before, but driven by a CONSTANT fake light
	// direction + the world normal, so it is identical at every time of day and in all weather. No
	// scene sun, no LIGHT_COLOR, no shadow map. On near-flat ground slope_shading keeps it ~one even
	// tone; real hillsides get a subtle stable lit/shadow read.
	vec3 surface_shadow = mix(shadow_tint.rgb, cold_shadow_tint.rgb, v_cold);
	vec3 surface_light  = mix(light_tint.rgb,  cold_light_tint.rgb,  v_cold);
	float ndl = clamp(dot(normalize(v_wnormal), normalize(fixed_light_dir)), 0.0, 1.0);
	float shade = ambient + (1.0 - ambient) * mix(1.0, ndl, slope_shading);
	shade = floor(shade * posterize_steps + 0.5) / posterize_steps;
	float lit = smoothstep(light_threshold - softness, light_threshold + softness, shade);
	float shd = 1.0 - smoothstep(shadow_threshold - softness, shadow_threshold + softness, shade);
	vec3 col = base;
	col = mix(col, surface_light, lit * form_light_amt);
	col = mix(col, surface_shadow, shd * form_shadow_amt);

	// GLOBAL MOOD — uniform day/night/weather multiplier, applied evenly. Unshaded: ALBEDO is output.
	ALBEDO = col * terrain_mood.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
