shader_type spatial;
// Illustrated calm-ocean water (A Short Hike feel) with a PIXEL-SMOOTH coastline.
//
// The shoreline, shallows and foam are driven by ONE smoothed water-fraction field baked
// per vertex into UV.x (v_wf: 0 land .. 1 open water, 0.5 = the smoothed coastline). The
// field is sampled BICUBICALLY onto a finely-tessellated water plane, so the 0.5 contour
// is a smooth curve at sub-tile resolution — no per-tile triangulation teeth, decoupled
// from the coarse terrain mesh. The shader discards the land side of the contour (the dry
// beach terrain shows there), ramps shallow -> deep with the signed coast distance, lays
// an animated lacy foam line on the waterline, and keeps the illustrated contour loops in
// the open water. Transparent (blend_mix) only for a 1px anti-aliased waterline.

// NOTE: NO fog_disabled — the water must fade into the SAME depth fog as the terrain, or the
// distant river/sea pops as a vivid cyan streak against the hazed-out land. Godot applies the
// environment depth fog to this (unshaded, transparent) material automatically.
render_mode unshaded, cull_back, blend_mix;

// --- palette ------------------------------------------------------------------
uniform vec4 deep_color : source_color = vec4(0.094, 0.392, 0.612, 1.0);     // #18649C rich deep blue
uniform vec4 shallow_color : source_color = vec4(0.376, 0.690, 0.875, 1.0);  // #60B0DF light shallow blue
uniform vec4 mid_color : source_color = vec4(0.227, 0.549, 0.769, 1.0);      // #3A8CC4 medium transition water
uniform vec4 deepest_color : source_color = vec4(0.043, 0.247, 0.404, 1.0);  // #0A3F67 deepest basin
uniform vec4 line_color : source_color = vec4(0.659, 0.835, 0.945, 1.0);     // #A8D5F1 pale contour ring
uniform vec4 foam_color : source_color = vec4(0.918, 0.969, 0.980, 1.0);     // #EAF7FA sea foam

// --- DEPTH (A Short Hike: a CONTINUOUS seabed, shore shallow -> open deep -> offshore basins) ---
// Depth is driven first by distance-to-coast (a continuous coastal SLOPE), then deepened further by
// a smooth, connected, low-frequency field — but only OUT in open water — so the deepest basins read
// as broad seabed topography, never dark decals glued to the shoreline.
uniform sampler2D depth_tex : repeat_enable, filter_linear;
uniform float deep_reach = 2.2;      // cells: coastal slope length (shore shallow -> open deep). sd maxes ~2.6
uniform float depth_scale = 0.005;   // world scale of the seabed field (SMALL = big, connected basins)
uniform float depth_warp : hint_range(0.0, 1.0) = 0.30;  // gentle organic basin edges (too high = stampy)
uniform float basin_lo : hint_range(0.0, 1.0) = 0.48;    // field below this = no extra basin (open water stays deep_color)
uniform float basin_hi : hint_range(0.0, 1.0) = 0.82;    // field at/above = deepest basin core (smooth falloff between)
uniform float basin_open : hint_range(0.5, 1.0) = 0.58;  // v_wf where basins may begin -> gates them to OPEN water (higher = further offshore)
uniform float basin_strength : hint_range(0.0, 1.0) = 0.9; // weight of the deepest tier
// Contour PRESENCE: a slow field makes the line network come and go across broad stretches.
uniform float line_presence_scale = 0.008;
uniform float line_presence_min : hint_range(0.0, 1.0) = 0.12;  // lowest line strength in a "clean" stretch

// --- shared coast field (v_wf) ------------------------------------------------
uniform float sd_scale = 5.2;          // (wf-0.5)*sd_scale -> signed distance to coast, in cells
uniform float shore_aa = 0.10;         // cells: anti-aliased width of the waterline
uniform float brim_fill = 0.05;        // world-height AA band for the submersion fill (UV.y)
uniform float shallow_cells = 0.9;     // cells: shallow band width before it ramps to deep

// --- contour pattern (illustrated loops, open water only) ---------------------
uniform float pattern_scale = 0.072;
uniform float contour_count = 3.5;
uniform float line_width : hint_range(0.0, 0.5) = 0.038;
uniform float line_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float domain_warp_strength = 0.6;
uniform float secondary_strength : hint_range(0.0, 1.0) = 0.28;
uniform float secondary_scale = 1.7;
uniform vec2 primary_speed = vec2(0.006, 0.003);
uniform vec2 secondary_speed = vec2(-0.003, 0.005);
uniform float contour_fade_in = 0.7;   // cells: contours start returning past the shallows
uniform float contour_fade_out = 1.6;  // cells: contours fully back in open water
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D warp_tex : repeat_enable, filter_linear;

// --- animated foam ------------------------------------------------------------
uniform float foam_cells = 0.55;       // cells: how far the foam can wash off the waterline
uniform float foam_depth = 0.24;       // world-height band of submersion the foam rides (hugs the true edge)
uniform float foam_width = 0.30;       // world units: EVEN ribbon width along the waterline (slope/zoom independent)
uniform float foam_scale = 0.17;
uniform float foam_speed = 0.05;
uniform float foam_aa = 0.08;          // extra anti-aliasing width in world units
uniform float foam_sdf_bias = 0.02;    // nudge foam slightly if it sits on land
uniform sampler2D foam_tex : repeat_enable, filter_linear;

// --- distance detail LOD ------------------------------------------------------
uniform vec4 distant_color : source_color = vec4(0.165, 0.345, 0.500, 1.0);  // muted deep blue (far LOD)
uniform float detail_fade_begin = 16.0;
uniform float detail_fade_end = 34.0;

uniform float aa_strength = 1.1;
uniform float min_aa = 0.0015;

varying vec3 v_world;
varying float v_wf;
varying float v_sub;       // submersion depth (water surface - terrain) baked per vertex; >0 = under water
varying float v_is_water;  // 1.0 on a real water tile, 0.0 on the dry coastal margin (UV2.x)

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wf = UV.x;
	v_sub = UV.y;
	v_is_water = UV2.x;
}

float contour(float n, float count) {
	float v = n * count;
	float d = min(fract(v), 1.0 - fract(v));
	float w = fwidth(v);
	float aa = max(w * aa_strength, min_aa);
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, d);
	float tiny = 1.0 - smoothstep(0.45, 0.95, w);
	return line * tiny;
}

void fragment() {
	float sd = (v_wf - 0.5) * sd_scale;   // + into water, - onto land; 0 = smoothed coast
	// Base water = the smoothed coast contour (v_wf past the shoreline).
	float water_a = smoothstep(-shore_aa, shore_aa, sd);
	// Then fill any DOWNSLOPED terrain that dips below the sheet (v_sub > 0) so water always
	// reaches the shore with no dry gap — but GATE it by coastal proximity (v_wf): only near a
	// real water body. Far from water v_wf -> 0, so an isolated dip / margin trough / despeckled
	// pond never fills (that was the square-pond bug); approaching the shoreline the gate opens
	// and the submerged beach is covered up to the waterline.
	float coastal = smoothstep(0.12, 0.40, v_wf);
	water_a = max(water_a, coastal * smoothstep(0.0, brim_fill, v_sub));
	if (water_a <= 0.001) {
		discard;
	}
	vec2 wp = v_world.xz;

	// --- DEPTH: a CONTINUOUS seabed (shore shallow -> open deep -> offshore basins) --------------
	// REVERT NOTE — restoring the OLD (pre-depth) water:
	//   The original look was a flat 2-tone shallow->deep ramp, no depth tiers:
	//       vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, shallow_cells, sd));
	//   To revert: replace this whole DEPTH block with that one line, delete the `mid_color`/
	//   `deepest_color` + depth/basin uniforms above, and remove the "// DEPTH:" set_shader_parameter
	//   calls in world_render_3d.gd. (History: v1 = openness*field all-over; v2 = thresholded mass
	//   decals — both read procedural; THIS version is a continuous distance-to-coast slope + smooth
	//   offshore basins, i.e. a seabed.)
	//
	// 1) COASTAL SLOPE — the primary, continuous structure: depth grows smoothly with distance from
	//    the coast (sd), so every shore reads shallow -> transition -> deep. No instant dark at shore.
	float seabed = smoothstep(0.0, deep_reach, sd);           // 0 at the waterline .. ~1 toward open water
	// 2) OFFSHORE BASINS — the deepest tier. A smooth, connected, low-frequency field (gentle warp),
	//    GATED to open water by v_wf so basins never glue to the shoreline, with a smooth falloff so
	//    they read as broad connected seabed basins, not stamps. Where the field is low, open water
	//    just stays `deep_color` (clean). Basins only ride in where the body is genuinely open.
	vec2 dw = (vec2(texture(warp_tex, wp * depth_scale * 0.6).r,
	                texture(warp_tex, wp * depth_scale * 0.6 + vec2(8.3, 2.9)).r) - 0.5) * depth_warp;
	float field = texture(depth_tex, wp * depth_scale + dw).r;
	float open_w = smoothstep(basin_open, 0.94, v_wf);        // 0 near shore .. 1 in open water
	float basin = smoothstep(basin_lo, basin_hi, field) * open_w;
	// Combine: the coastal slope fills shallow->mid->deep (up to ~0.66); basins add the deepest tier.
	float depth01 = clamp(seabed * 0.66 + basin * basin_strength * 0.34, 0.0, 1.0);
	// 3) 4-TIER smooth ramp — shallow -> mid transition -> deep -> deepest. Overlapping smoothsteps
	//    give a gentle gradient (never a pale->very-dark jump); the presenter posterizes it into a
	//    few clean depth zones. Foam/shallows sit on top of this near the waterline.
	vec3 col = shallow_color.rgb;
	col = mix(col, mid_color.rgb,     smoothstep(0.05, 0.38, depth01));
	col = mix(col, deep_color.rgb,    smoothstep(0.34, 0.68, depth01));
	col = mix(col, deepest_color.rgb, smoothstep(0.66, 1.00, depth01));

	// --- CONTOUR CURRENTS: long flowing iso-lines (the STAR, ~70%) -------------------------------
	// Iso-contours of a big smooth field: low frequency + few levels = long, sweeping, varied-spacing
	// lines that read like ocean currents, not procedural cells.
	vec2 w1 = wp * (pattern_scale * 0.5) + primary_speed * TIME;
	vec2 w2 = wp * (pattern_scale * 0.5) + secondary_speed * TIME + vec2(0.4, 0.2);
	vec2 warp = (vec2(texture(warp_tex, w1).r, texture(warp_tex, w2).r) - 0.5) * domain_warp_strength;
	vec2 uv1 = wp * pattern_scale + warp;
	float lines = contour(texture(noise_tex, uv1).r, contour_count);
	if (secondary_strength > 0.001) {
		float n2 = texture(noise_tex, uv1 * secondary_scale + vec2(3.7, 1.9)).r;
		lines = max(lines, contour(n2, contour_count) * secondary_strength);
	}
	// PRESENCE: a slow low-frequency field makes the current network DISAPPEAR + REAPPEAR across
	// broad stretches (never a uniform grid) — clean water in the gaps, denser currents elsewhere.
	float presence = smoothstep(0.30, 0.62, texture(depth_tex, wp * line_presence_scale + vec2(31.0, 7.0)).r);
	lines *= mix(line_presence_min, 1.0, presence);
	float contour_vis = smoothstep(contour_fade_in, contour_fade_out, sd);
	col = mix(col, line_color.rgb, lines * contour_vis * line_opacity);

	// --- animated sea-foam (improved smooth hugging) ---
	vec2 fp = wp * foam_scale;
	float fa = texture(foam_tex, fp + vec2(TIME * foam_speed, TIME * foam_speed * 0.4)).r;
	float fb = texture(foam_tex, fp * 1.7 - vec2(TIME * foam_speed * 0.7, 0.0)).r;
	float wash = (fa + fb) * 0.5;

	// SDF distance (smooth coast from v_wf) + derivative distance (geometry)
	float sdf_dist = sd / sd_scale;
	vec2 g_scr = vec2(dFdx(v_sub), dFdy(v_sub));
	vec2 wxd = vec2(dFdx(wp.x), dFdy(wp.x));
	vec2 wzd = vec2(dFdx(wp.y), dFdy(wp.y));
	float det = wxd.x * wzd.y - wzd.x * wxd.y;
	vec2 grad = abs(det) > 1e-9
		? vec2(g_scr.x * wzd.y - g_scr.y * wzd.x, wxd.x * g_scr.y - wxd.y * g_scr.x) / det
		: vec2(0.0);
	float deriv_dist = v_sub / max(length(grad), 1e-4);

	// Blend: prefer smooth SDF near coast for clean curves
	float dist = mix(sdf_dist, deriv_dist, smoothstep(0.0, 0.8, abs(sdf_dist)));

	// Lapping animation: the band breathes with the scrolling foam noise (wash) plus a slow
	// shore-wave pulse, so the thin ribbon visibly washes in and out instead of sitting static.
	float lap = 0.82 + 0.18 * sin(TIME * 1.3 + (wp.x + wp.y) * 0.18);
	float band = (foam_width * (0.55 + wash * 0.9) + foam_aa) * lap;
	float foam = (1.0 - smoothstep(0.0, band, dist + foam_sdf_bias))
	           * smoothstep(-foam_width * 0.4 - foam_aa, foam_width * 0.15, dist + foam_sdf_bias);
	foam *= 0.72 + wash * 0.5;
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));

	// Distance LOD
	float view_depth = -VERTEX.z;
	float detail = 1.0 - smoothstep(detail_fade_begin, detail_fade_end, view_depth);
	col = mix(distant_color.rgb, col, detail);

	ALBEDO = col;
	ALPHA = water_a;
}