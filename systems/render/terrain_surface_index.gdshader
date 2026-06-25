shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D surface_id_texture : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_albedo_texture : source_color, filter_linear, repeat_disable;
instance uniform vec2 control_origin_xz = vec2(0.0, 0.0);
instance uniform vec2 control_size_xz = vec2(100.0, 100.0);
uniform vec2 macro_albedo_origin_xz = vec2(0.0, 0.0);
uniform vec2 macro_albedo_size_xz = vec2(5500.0, 5700.0);
uniform bool use_albedo_array = false;
uniform bool use_normal_array = false;
uniform bool use_macro_albedo = false;
uniform float macro_albedo_strength = 0.35;
uniform float macro_albedo_chroma_strength = 0.0;
uniform float normal_array_strength = 0.36;
uniform vec4 surface_color_0 : source_color = vec4(0.50, 0.47, 0.38, 1.0);
uniform vec4 surface_color_1 : source_color = vec4(0.86, 0.86, 0.82, 1.0);
uniform vec4 surface_color_2 : source_color = vec4(0.92, 0.84, 0.72, 1.0);
uniform vec4 surface_color_3 : source_color = vec4(0.78, 0.96, 0.72, 1.0);
uniform vec4 surface_color_4 : source_color = vec4(0.72, 0.62, 0.50, 1.0);
uniform vec4 surface_color_5 : source_color = vec4(0.90, 0.86, 0.78, 1.0);
uniform vec4 surface_color_6 : source_color = vec4(0.62, 0.68, 0.64, 1.0);
uniform vec4 surface_color_7 : source_color = vec4(0.88, 0.78, 0.64, 1.0);
uniform vec2 surface_uv_scale_0 = vec2(2.5, 2.5);
uniform vec2 surface_uv_scale_1 = vec2(2.7, 2.7);
uniform vec2 surface_uv_scale_2 = vec2(2.5, 2.5);
uniform vec2 surface_uv_scale_3 = vec2(2.4, 2.4);
uniform vec2 surface_uv_scale_4 = vec2(2.3, 2.3);
uniform vec2 surface_uv_scale_5 = vec2(2.2, 2.2);
uniform vec2 surface_uv_scale_6 = vec2(2.0, 2.0);
uniform vec2 surface_uv_scale_7 = vec2(1.6, 1.6);
uniform float terrain_roughness = 0.88;
uniform float terrain_specular = 0.18;
// C2 PER-SURFACE ROUGHNESS/AO MATERIAL RESPONSE. The terrain used a single flat scalar
// roughness (terrain_roughness, the catalog-averaged value) for every surface, so wet
// stone, dry sand and loose scree all shaded with identical glossiness -- the literal
// "everything looks flat" read. These uniforms carry the catalog's OWN per-surface
// roughness (wet-adjusted) per surface-id layer so the surface-id map drives real material
// variation: glossier wet/mossy stone (low roughness), matte loose sand/scree (high).
// ALBEDO IS UNTOUCHED -- this adds only the roughness/AO light RESPONSE, not a restyle.
// The render builder sets surface_roughness_0..7 from each surface's SurfaceVisualDef in
// _apply_surface_index_palette(); defaults below mirror the legacy single scalar so the
// shader is golden-neutral if the builder never sets them (e.g. palette-only fallback).
uniform float surface_roughness_0 = 0.88;   // palette fallback / packed_dirt-like
uniform float surface_roughness_1 = 0.88;
uniform float surface_roughness_2 = 0.88;
uniform float surface_roughness_3 = 0.88;
uniform float surface_roughness_4 = 0.88;
uniform float surface_roughness_5 = 0.88;
uniform float surface_roughness_6 = 0.88;
uniform float surface_roughness_7 = 0.88;
// Cavity AO RESPONSE: a tunable contact-darkening driven off the per-pixel surface relief
// the shader already computes (the texture/micro normal's lean off the geometric normal --
// floor_pbr_bump on the floor, array-normal tilt on cliffs). Crevices read slightly
// occluded so raking golden-hour light reveals grain depth instead of a flat matte plate.
// No new texture fetch (a full per-surface AO map array from the unused ground_pbr scans is
// the larger refactor deliberately deferred per the audit note). Default subtle; 0 = no-op.
uniform float surface_ao_strength = 0.35;    // authority of the cavity-AO darkening
uniform float surface_ao_floor_bias = 0.6;   // extra AO weight on the drivable floor relief
uniform vec4 zion_sandstone_color : source_color = vec4(0.82, 0.42, 0.20, 1.0);
uniform vec4 zion_sand_color : source_color = vec4(0.78, 0.68, 0.52, 1.0);
uniform vec4 zion_strata_dark_color : source_color = vec4(0.36, 0.14, 0.08, 1.0);
uniform vec4 zion_navajo_vermilion_color : source_color = vec4(0.36, 0.10, 0.04, 1.0);
uniform vec4 zion_navajo_red_orange_color : source_color = vec4(0.49, 0.14, 0.05, 1.0);
uniform vec4 zion_navajo_salmon_color : source_color = vec4(0.62, 0.27, 0.13, 1.0);
uniform vec4 zion_navajo_apricot_color : source_color = vec4(0.71, 0.37, 0.18, 1.0);
uniform vec4 zion_navajo_cream_color : source_color = vec4(0.79, 0.58, 0.34, 1.0);
uniform vec4 zion_navajo_bleached_white_color : source_color = vec4(0.83, 0.74, 0.58, 1.0);
uniform float zion_navajo_height_start = 1250.0;
uniform float zion_navajo_height_end = 1700.0;
uniform float zion_navajo_palette_strength = 1.0;
// Navajo height-palette ALBEDO MODULATION reference. The cliff modulation tints the live
// base albedo toward the height palette WHILE preserving its texture/relief detail by
// applying a per-channel ratio palette/reference. This reference is the legacy mid-warm
// sandstone tone the modulation was calibrated against -- it is deliberately NOT
// zion_sandstone_color, which the render builder repurposes to the DARK Navajo base
// (0.49,0.14,0.05); driving the ratio off that dark value would under-tint (brighten) the
// modulation. Kept as its own uniform so the builder never sets it and the calibration holds.
uniform vec4 zion_navajo_modulation_reference : source_color = vec4(0.82, 0.42, 0.20, 1.0);
uniform float zion_navajo_modulation_blend = 0.38;     // final pull toward the flat palette tone
uniform float zion_sandstone_slope_start = 0.08;
uniform float zion_sandstone_slope_end = 0.38;
uniform float zion_sand_height_start = 1193.0;
uniform float zion_sand_height_end = 1202.0;
uniform float zion_strata_scale = 18.0;                                      // major cross-bed repeat in world meters
uniform float zion_strata_strength = 0.28;
uniform vec4 zion_strata_light_color : source_color = vec4(0.86, 0.62, 0.38, 1.0);  // lighter band tone (Navajo cross-bedding)
uniform vec2 zion_strata_dip = vec2(0.15, 0.15);                                    // legacy xz phase nudge; major dip comes from zion_crossbed_*
uniform vec2 zion_crossbed_dip_dir = vec2(0.84, 0.54);
uniform float zion_crossbed_dip_tangent = 0.58;
uniform float zion_crossbed_major_period_m = 18.0;
uniform float zion_crossbed_lamina_period_m = 1.5;
uniform float zion_crossbed_warp_m = 2.4;
uniform float zion_crossbed_set_turn = 0.72;            // per-set azimuth swing of the cross-bed dip (radians)
uniform float zion_crossbed_truncation_strength = 0.52; // weight of the truncation surface darkening at set boundaries
uniform float zion_detile_strength = 0.18;
uniform vec4 zion_floor_dark_color : source_color = vec4(0.20, 0.16, 0.13, 1.0);
uniform vec4 zion_floor_sediment_color : source_color = vec4(0.55, 0.34, 0.24, 1.0);  // reddish Kayenta sediment tint beneath the crust
uniform vec4 zion_floor_slickrock_color : source_color = vec4(0.60, 0.45, 0.32, 1.0);  // warm but desaturated (exposed Navajo, not glowing)
uniform vec4 zion_floor_wash_color : source_color = vec4(0.48, 0.42, 0.32, 1.0);
uniform vec4 zion_floor_sand_patch_color : source_color = vec4(0.74, 0.66, 0.52, 1.0);  // cooler tan patch (was saturated orange)
uniform float zion_floor_scatter_strength = 0.80;
uniform float zion_floor_detile_strength = 0.24;
uniform float zion_floor_patch_strength = 0.34;
uniform vec4 zion_riparian_tint_color : source_color = vec4(0.26, 0.49, 0.18, 1.0);
uniform float zion_riparian_tint_strength = 0.30;
uniform float zion_riparian_inner_m = 10.0;
uniform float zion_riparian_outer_m = 96.0;
uniform float zion_bank_wet_width_m = 16.0;
uniform float zion_bank_wet_darkness = 0.32;
uniform float zion_bank_wet_roughness = 0.18;
uniform vec4 zion_river_segment_0 = vec4(910.0, 500.0, 900.0, 700.0);
uniform vec4 zion_river_segment_1 = vec4(900.0, 700.0, 920.0, 900.0);
uniform vec4 zion_river_segment_2 = vec4(920.0, 900.0, 1000.0, 1000.0);
uniform vec4 zion_river_segment_3 = vec4(1000.0, 1000.0, 1070.0, 1200.0);
uniform vec4 zion_river_segment_4 = vec4(1070.0, 1200.0, 1130.0, 1300.0);
uniform vec4 zion_river_segment_5 = vec4(1130.0, 1300.0, 1180.0, 1350.0);
uniform vec4 zion_river_segment_6 = vec4(1180.0, 1350.0, 1330.0, 1400.0);
uniform vec4 zion_river_segment_7 = vec4(1330.0, 1400.0, 1410.0, 1450.0);
uniform vec4 zion_river_segment_8 = vec4(1410.0, 1450.0, 1500.0, 1550.0);
uniform vec4 zion_river_segment_9 = vec4(1500.0, 1550.0, 1530.0, 1600.0);
uniform vec4 zion_varnish_color : source_color = vec4(0.13, 0.08, 0.06, 1.0);  // warm charcoal
uniform vec4 zion_varnish_mn_color : source_color = vec4(0.025, 0.018, 0.013, 1.0);
uniform vec4 zion_varnish_fe_color : source_color = vec4(0.11, 0.035, 0.014, 1.0);
uniform float zion_varnish_strength = 0.5;
uniform float zion_varnish_lip_strength = 0.55;     // authority of cliff-lip varnish drapes (vs. the seep streaks)
uniform float zion_varnish_wall_threshold = 0.30;   // local_normal_y below this = near-vertical face
uniform float zion_varnish_height_start = 1300.0;   // varnish mostly on walls above the floor
uniform float zion_varnish_streak_scale = 0.12;     // horizontal streak frequency
uniform float zion_varnish_drop_m = 145.0;
// Kayenta Formation: warm-dark band at cliff base (~1200-1250 m) below the Navajo mass.
uniform vec4 zion_kayenta_color : source_color = vec4(0.38, 0.10, 0.06, 1.0);  // deep brick-red
uniform vec4 zion_kayenta_basal_color : source_color = vec4(0.27, 0.075, 0.045, 1.0);          // darker basal slope tone
uniform vec4 zion_kayenta_lavender_color : source_color = vec4(0.20, 0.13, 0.14, 1.0);
uniform vec4 zion_kayenta_ledge_shadow_color : source_color = vec4(0.105, 0.045, 0.035, 1.0);  // recessed-ledge shadow
uniform vec4 zion_kayenta_vegetation_shadow_color : source_color = vec4(0.055, 0.085, 0.036, 1.0); // ledge scrub shade
uniform float zion_kayenta_height_start = 1200.0;
uniform float zion_kayenta_height_end = 1250.0;
uniform float zion_kayenta_skirt_height_m = 120.0;
uniform float zion_kayenta_strength = 0.55;
uniform float zion_kayenta_contact_step_m = 4.5;    // vertical jitter of the Kayenta/Navajo contact step
uniform float zion_kayenta_ledge_period_m = 5.5;    // ledge-and-recess banding period in the Kayenta skirt
// FAR-WALL WARM GRADIENT: large-scale height-driven warm Navajo-red tint + mild contrast boost so
// the far canyon walls (HLOD, 5-8 km out) keep a warm stratified read when sub-pixel strata bands
// average to a flat mid-tone. Driven by world height (upper wall rims correlate with far geometry).
// Gated to cliff/wall pixels (cliff_mask) so the drivable floor is untouched. Near terrain walls
// already receive the full Navajo palette (navajo_mask * zion_navajo_palette_strength); this adds a
// broad-scale warm push that survives LOD flattening without altering the near look. Set to 0 = no-op.
uniform vec4 zion_far_wall_warm_color : source_color = vec4(0.52, 0.18, 0.07, 1.0);  // warm red-orange anchor
uniform float zion_far_wall_height_start = 1280.0;  // world Y where warm push begins (above canyon floor)
uniform float zion_far_wall_height_end = 1600.0;    // world Y of full warm push (upper rims)
uniform float zion_far_wall_warm_strength = 0.22;   // tint authority (0 = off, 0.22 = visible but conservative)
uniform float zion_far_wall_contrast = 0.26;        // luminance contrast lift (0 = off) — counters distance albedo-flattening the post-stack can't recover, restoring strata separation on the far walls

// Upper-wall bleach: pale buff cream tint driven by world height (Great White Throne reads near-white).
uniform vec4 zion_bleach_color : source_color = vec4(0.91, 0.84, 0.72, 1.0);  // pale buff cream
uniform float zion_bleach_height_start = 1550.0;   // lower edge of the bleached upper walls
uniform float zion_bleach_strength = 0.38;         // upper-rim pale-buff blend — eased from 0.55 so the most-distant rims keep warm Navajo identity instead of washing to near-white buff
uniform bool zion_wetrock_enabled = true;
uniform float zion_wetrock_height_start = 1230.0;
uniform float zion_wetrock_height_end = 1320.0;
uniform float zion_wetrock_darkness = 0.4;
uniform vec4 zion_wetrock_moss_color : source_color = vec4(0.164, 0.219, 0.125, 1.0);
uniform vec4 zion_hanging_garden_color : source_color = vec4(0.06, 0.16, 0.025, 1.0);  // seep-line hanging-garden green
uniform float zion_hanging_garden_strength = 0.34;
// W6-SURFACE-DETAIL: procedural micro-normal relief + ROUGHNESS wobble so raking
// golden-hour light catches fine (~1.4 m) sand/rock grain instead of bouncing off
// a flat-plastic geometric normal. Hash-only (no extra texture fetches); per-surface
// strength bumps sand/gravel/loose_rock and stays near-zero on pavement/wet_stone.
uniform float micro_normal_scale = 0.7;            // hash frequency (~1.4 m features)
uniform float surface_micro_strength_0 = 0.14;     // palette fallback / packed_dirt
uniform float surface_micro_strength_1 = 0.04;     // wet_stone (smooth)
uniform float surface_micro_strength_2 = 0.16;     // packed_gravel (bumpy)
uniform float surface_micro_strength_3 = 0.14;     // packed_dirt (desert floor)
uniform float surface_micro_strength_4 = 0.18;     // loose_rock (most relief)
uniform float surface_micro_strength_5 = 0.08;     // tall_grass (hidden by billboards)
uniform float surface_micro_strength_6 = 0.02;     // paved_road (near-flat)
uniform float surface_micro_strength_7 = 0.14;     // fallback (sand/dirt-like)
uniform float micro_roughness_variation = 0.06;    // +/- wobble around terrain_roughness
// FLOOR-FIDELITY (de-orange + micro-detail). Additive uniforms only: the render builder
// does not set any of these, so the defaults below take effect without touching
// terrain_visual_builder.gd / atmosphere / grass. Each defaults to a subtle, readable
// amount and can be dialed to zero to restore the prior flat-warm floor.
// De-orange the base sand: the builder hard-sets zion_sand_color to a warm tone, so we
// pull the flat-floor albedo toward a cooler desert-sand target (warm tan, not saturated
// orange). The hue-preserving macro-albedo blend downstream is untouched.
uniform vec4 zion_floor_cool_sand_color : source_color = vec4(0.72, 0.67, 0.58, 1.0);
uniform float zion_floor_deorange_strength = 0.55;
// Micro-detail: extra fine-grain octave + floor-aware roughness/albedo break-up so the
// immediate drivable floor reads as sand grain / slickrock / packed wash instead of a
// flat matte plane. Hash-only (no extra texture fetches).
uniform float micro_fine_scale = 2.6;              // ~0.38 m sand-grain frequency
uniform float micro_fine_strength = 0.45;          // relative amplitude of the fine octave
uniform float micro_roughness_floor_variation = 0.05;   // +/- extra floor roughness wobble
uniform float micro_albedo_grain_strength = 0.045;      // subtle fine albedo break-up on floor
// FLOOR-TONAL-DRIFT: broad (~tens-of-meters) warm/cool hue drift across the drivable canyon
// floor so the close-up ground reads as redder slickrock benches grading into paler sandy
// washes -- the real lower-Zion floor mosaic -- instead of one uniform de-oranged tint. The
// existing small-scale wash/slickrock/sand-patch masks break up ON TOP of this broad base.
// Hash-only (reuses the floor_macro/floor_mid octaves already computed below; no extra
// texture fetches), floor-gated by low_flat_mask so cliffs/strata/walls pay nothing and are
// untouched. Additive uniforms only -- the render builder never sets these, so the defaults
// take effect golden-neutrally and can be dialed to zero to restore the prior flat-tint floor.
uniform vec4 zion_floor_warm_bench_color : source_color = vec4(0.58, 0.36, 0.24, 1.0);  // redder iron-rich slickrock bench
uniform vec4 zion_floor_pale_wash_color : source_color = vec4(0.76, 0.69, 0.57, 1.0);   // paler bleached sandy wash
uniform float zion_floor_tonal_drift_strength = 0.22;   // authority of the broad warm/cool floor drift
uniform float zion_floor_tonal_drift_bias = 0.04;       // center shift (+ = warmer overall, - = paler)
// FLOOR-PBR: real CC0 ambientCG PBR textures (albedo + normal) sampled TRIPLANAR in world
// space and detail-blended onto the drivable floor, so the close-up reads as real Zion
// sand / slickrock / packed wash instead of a flat procedural tint. Cliffs/strata stay on
// the existing procedural path: a slope + height gate drives floor_pbr_gate to ~0 off the
// low drivable surface, so the Navajo/Kayenta/varnish cliff palette is untouched. Slope-safe
// via triplanar axis weighting off the world geometric normal (no stretching on slickrock
// bumps). Reuses the existing per-surface-id albedo_array + normal_array (already bound by
// terrain_visual_builder.gd), so the surface-id picks the texture (sand/dirt vs slickrock/
// rock vs gravel/wash) and the procedural floor masks keep supplying the de-orange TINT.
// No dedicated roughness map ships in the ambientCG set (albedo+normal only), so floor
// roughness is nudged by the triplanar NORMAL relief (bumpier grain -> slightly rougher).
uniform bool use_floor_pbr = true;
uniform float floor_pbr_blend = 0.55;               // detail-blend authority of the real albedo on the floor
uniform float floor_pbr_normal_strength = 0.50;     // world-space floor normal-map authority
uniform float floor_pbr_roughness_strength = 0.10;  // roughness lift driven by normal relief
uniform vec2 floor_pbr_uv_scale = vec2(0.45, 0.45); // world repeats/meter (sand-fine ~2.2 m/tile default)
uniform float floor_pbr_slickrock_scale_mul = 0.5;  // broader tiling where the floor reads as slickrock
uniform float floor_pbr_triplanar_blend = 6.0;      // axis-weight power (higher = harder triplanar seams)
uniform float floor_pbr_slope_flat_ny = 0.86;       // local_normal_y >= this = full floor texture (~30 deg)
uniform float floor_pbr_slope_steep_ny = 0.55;      // local_normal_y <= this = no floor texture (~57 deg, cliff)
uniform float floor_pbr_height_start_offset = 6.0;  // m above zion_sand_height_end where PBR begins to fade
uniform float floor_pbr_height_end_offset = 22.0;   // m above zion_sand_height_end where PBR is fully gone (floor + low slickrock only)
// PERF: when the top (Y) plane's triplanar weight is >= this threshold, sample ONLY the top
// plane (2 fetches) instead of all three (6 fetches). The flat floor -- the overwhelming
// majority of drivable pixels -- is near-horizontal so the side planes contribute <10% each
// there and are not worth 4 extra texture fetches. Real slopes (slickrock bumps), where the
// side planes are needed for slope-safety, fall below the threshold and pay for full triplanar.
uniform float floor_pbr_single_plane_threshold = 0.90;

// TILED-DETAIL-NORMAL micro-relief. The canyon slickrock/sand surface is the dominant pixel
// in every frame and previously read smooth/procedural away from the floor-PBR band -- the
// strata/floor-pbr/micro normals supply structure, but the broad slickrock benches and walls
// lacked fine, believable rock/sand grain. This blends a single tiled CC0 rock-grain normal
// scan (neutral, non-directional) into the surface normal in WORLD XZ at a tunable strength +
// world tiling scale, so raking golden-hour light catches micro rock/sand relief across the
// whole terrain (not only the floor-pbr region). To avoid an obvious tiled look it sums TWO
// octaves at different world scales (like the grass wind), and fades the strength out with
// camera distance so far tiles do not shimmer/alias. Combined via a reoriented tangent-frame
// tilt on top of the EXISTING surface normal (same T=+X/B=+Z convention as apply_array_normal),
// NOT a hard replace, so it composes with the strata/floor-pbr relief already computed.
// hint_normal => an UNBOUND sampler decodes to flat (0,0,1) = zero perturbation, so the path is
// safe even if the render builder never binds the texture. terrain_detail_normal_strength = 0
// is an exact no-op (early-out), preserving the golden-neutral default-safe path. ALBEDO, the
// warm gradient, roughness/AO and fog are all untouched -- this writes only NORMAL.
uniform sampler2D terrain_detail_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float terrain_detail_normal_strength = 0.35;     // tangent-tilt authority (0 = exact no-op)
uniform float terrain_detail_normal_scale = 0.45;        // world repeats/meter for octave A (~2.2 m/tile)
uniform float terrain_detail_normal_octave2_scale_mul = 0.30; // octave B world scale vs A (~7.4 m/tile)
uniform float terrain_detail_normal_octave_mix = 0.40;   // weight of the broader octave B (0 = A only)
uniform float terrain_detail_normal_fade_start_m = 120.0; // camera distance where detail begins to fade
uniform float terrain_detail_normal_fade_end_m = 340.0;   // camera distance where detail is fully faded out

varying vec2 world_xz;
varying float world_y;
varying float local_normal_y;

const float ZION_TAU = 6.28318530718;

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth (bilinear) hash: samples the four cell corners and mixes them by a smoothstep'd
// fract offset, so the result is C0-continuous across cell boundaries. Used to drive macro
// detile variation without producing a hard ~1/scale block grid of seams.
float hash21_smooth(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 blend = f * f * (3.0 - 2.0 * f);
	float h00 = hash21(cell + vec2(0.0, 0.0));
	float h10 = hash21(cell + vec2(1.0, 0.0));
	float h01 = hash21(cell + vec2(0.0, 1.0));
	float h11 = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(h00, h10, blend.x), mix(h01, h11, blend.x), blend.y);
}

float wrapped_line(float phase, float width) {
	float edge_distance = min(fract(phase), 1.0 - fract(phase));
	return 1.0 - smoothstep(0.0, width, edge_distance);
}

vec3 zion_navajo_palette(float height_t) {
	float t = clamp(height_t, 0.0, 1.0);
	if (t < 0.2) {
		return mix(zion_navajo_vermilion_color.rgb, zion_navajo_red_orange_color.rgb, smoothstep(0.0, 0.2, t));
	}
	if (t < 0.4) {
		return mix(zion_navajo_red_orange_color.rgb, zion_navajo_salmon_color.rgb, smoothstep(0.2, 0.4, t));
	}
	if (t < 0.6) {
		return mix(zion_navajo_salmon_color.rgb, zion_navajo_apricot_color.rgb, smoothstep(0.4, 0.6, t));
	}
	if (t < 0.8) {
		return mix(zion_navajo_apricot_color.rgb, zion_navajo_cream_color.rgb, smoothstep(0.6, 0.8, t));
	}
	return mix(zion_navajo_cream_color.rgb, zion_navajo_bleached_white_color.rgb, smoothstep(0.8, 1.0, t));
}

// Tint the live base albedo toward the height palette WHILE keeping its texture/relief
// break-up. A per-channel ratio (palette / reference) re-tones the base instead of flatly
// replacing it, then a luma correction + a small blend toward the flat palette tone keeps
// the result on-target. The reference is the LEGACY mid-warm sandstone tone this was tuned
// against (zion_navajo_modulation_reference), NOT the dark builder-set zion_sandstone_color,
// so the modulation does not double-darken against main's already-dark Navajo base.
vec3 zion_navajo_modulated_albedo(vec3 base_albedo, vec3 palette_color) {
	vec3 reference_color = max(zion_navajo_modulation_reference.rgb, vec3(0.035));
	vec3 height_ratio = clamp(palette_color / reference_color, vec3(0.22), vec3(3.25));
	vec3 modulated = clamp(base_albedo * height_ratio, vec3(0.0), vec3(1.0));
	float target_luma = max(luminance(palette_color), 0.025);
	float modulated_luma = max(luminance(modulated), 0.025);
	modulated = clamp(modulated * clamp(target_luma / modulated_luma, 0.45, 1.85), vec3(0.0), vec3(1.0));
	return mix(modulated, palette_color, clamp(zion_navajo_modulation_blend, 0.0, 1.0));
}

vec4 surface_color_for_id(float surface_id_value) {
	if (surface_id_value < 0.5) {
		return surface_color_0;
	}
	if (surface_id_value < 1.5) {
		return surface_color_1;
	}
	if (surface_id_value < 2.5) {
		return surface_color_2;
	}
	if (surface_id_value < 3.5) {
		return surface_color_3;
	}
	if (surface_id_value < 4.5) {
		return surface_color_4;
	}
	if (surface_id_value < 5.5) {
		return surface_color_5;
	}
	if (surface_id_value < 6.5) {
		return surface_color_6;
	}
	if (surface_id_value < 7.5) {
		return surface_color_7;
	}
	return surface_color_0;
}

vec2 surface_uv_scale_for_id(float surface_id_value) {
	if (surface_id_value < 0.5) {
		return surface_uv_scale_0;
	}
	if (surface_id_value < 1.5) {
		return surface_uv_scale_1;
	}
	if (surface_id_value < 2.5) {
		return surface_uv_scale_2;
	}
	if (surface_id_value < 3.5) {
		return surface_uv_scale_3;
	}
	if (surface_id_value < 4.5) {
		return surface_uv_scale_4;
	}
	if (surface_id_value < 5.5) {
		return surface_uv_scale_5;
	}
	if (surface_id_value < 6.5) {
		return surface_uv_scale_6;
	}
	if (surface_id_value < 7.5) {
		return surface_uv_scale_7;
	}
	return surface_uv_scale_0;
}

float surface_micro_strength_for_id(float surface_id_value) {
	if (surface_id_value < 0.5) {
		return surface_micro_strength_0;
	}
	if (surface_id_value < 1.5) {
		return surface_micro_strength_1;
	}
	if (surface_id_value < 2.5) {
		return surface_micro_strength_2;
	}
	if (surface_id_value < 3.5) {
		return surface_micro_strength_3;
	}
	if (surface_id_value < 4.5) {
		return surface_micro_strength_4;
	}
	if (surface_id_value < 5.5) {
		return surface_micro_strength_5;
	}
	if (surface_id_value < 6.5) {
		return surface_micro_strength_6;
	}
	if (surface_id_value < 7.5) {
		return surface_micro_strength_7;
	}
	return surface_micro_strength_0;
}

// C2: per-surface base roughness for the rounded surface-id layer. Same nearest-id ladder
// the other per-surface selectors use. Drives the ROUGHNESS base so each surface shades
// with its own glossiness (wet/mossy stone glossy, loose sand/scree matte) instead of one
// catalog-averaged scalar. Defaults mirror the legacy flat value so an unset builder is a
// no-op.
float surface_roughness_for_id(float surface_id_value) {
	if (surface_id_value < 0.5) {
		return surface_roughness_0;
	}
	if (surface_id_value < 1.5) {
		return surface_roughness_1;
	}
	if (surface_id_value < 2.5) {
		return surface_roughness_2;
	}
	if (surface_id_value < 3.5) {
		return surface_roughness_3;
	}
	if (surface_id_value < 4.5) {
		return surface_roughness_4;
	}
	if (surface_id_value < 5.5) {
		return surface_roughness_5;
	}
	if (surface_id_value < 6.5) {
		return surface_roughness_6;
	}
	if (surface_id_value < 7.5) {
		return surface_roughness_7;
	}
	return surface_roughness_0;
}

// Two-octave smooth-hash "micro-height" in world XZ. Each octave is a couple of
// hash21 corner samples; together they give subtle multi-scale grain rather than a
// single cellular look. Output is roughly in [-1, 1]. Used only as a heightfield
// for the surface-micro normal gradient below. (The floor's extra fine-grain relief
// is layered on separately by apply_floor_fine_normal, gated to the low flat floor
// so cliffs/walls pay nothing for it.)
float micro_height(vec2 world_xz_pos) {
	vec2 q1 = world_xz_pos * micro_normal_scale;
	vec2 q2 = world_xz_pos * (micro_normal_scale * 2.17) + vec2(11.7, 4.3);
	return (hash21_smooth(q1) * 2.0 - 1.0) * 0.68 + (hash21_smooth(q2) * 2.0 - 1.0) * 0.32;
}

float distance_to_segment(vec2 point, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float ab_len2 = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(point - a, ab) / ab_len2, 0.0, 1.0);
	return length(point - (a + ab * t));
}

float zion_river_distance(vec2 point) {
	float distance_m = distance_to_segment(point, zion_river_segment_0.xy, zion_river_segment_0.zw);
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_1.xy, zion_river_segment_1.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_2.xy, zion_river_segment_2.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_3.xy, zion_river_segment_3.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_4.xy, zion_river_segment_4.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_5.xy, zion_river_segment_5.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_6.xy, zion_river_segment_6.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_7.xy, zion_river_segment_7.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_8.xy, zion_river_segment_8.zw));
	distance_m = min(distance_m, distance_to_segment(point, zion_river_segment_9.xy, zion_river_segment_9.zw));
	return distance_m;
}

// Perturb a world-space geometric normal by the local micro-height gradient. The
// gradient is taken in world XZ and applied along the XZ tangent directions projected
// into the surface tangent plane. Either tangent is skipped if its projection is too
// short (axis-aligned wall) so we never normalize a zero vector. `strength` controls
// bump amplitude (tangent tilt per unit gradient) — kept subtle per surface.
vec3 apply_micro_normal(vec3 geo_world_normal, vec2 world_xz_pos, float strength) {
	if (strength <= 0.0) {
		return geo_world_normal;
	}
	float eps = 0.35;  // ~0.35 m finite-difference step (well below the ~1.4 m feature)
	float h_x_neg = micro_height(world_xz_pos + vec2(-eps, 0.0));
	float h_x_pos = micro_height(world_xz_pos + vec2( eps, 0.0));
	float h_z_neg = micro_height(world_xz_pos + vec2(0.0, -eps));
	float h_z_pos = micro_height(world_xz_pos + vec2(0.0,  eps));
	vec2 grad = vec2(h_x_neg - h_x_pos, h_z_neg - h_z_pos) * strength;
	vec3 perturbed = geo_world_normal;
	vec3 tx = vec3(1.0, 0.0, 0.0) - geo_world_normal * geo_world_normal.x;
	float tx_len2 = dot(tx, tx);
	if (tx_len2 > 1e-4) {
		perturbed -= tx * (grad.x / sqrt(tx_len2));
	}
	vec3 tz = vec3(0.0, 0.0, 1.0) - geo_world_normal * geo_world_normal.z;
	float tz_len2 = dot(tz, tz);
	if (tz_len2 > 1e-4) {
		perturbed -= tz * (grad.y / sqrt(tz_len2));
	}
	return normalize(perturbed);
}

// FLOOR-FIDELITY: floor-only fine sand-grain normal relief. Same isotropic 4-tap
// axis gradient as apply_micro_normal (so grain quality matches), but on a fine
// (~0.4 m) smooth hash and gated to the low flat floor by floor_gate. Non-floor
// pixels (cliffs, sky) early-out before any hash work, so the per-pixel cost is
// paid only where the camera actually drives. micro_fine_strength scales the fine
// octave relative to the per-surface micro amplitude.
vec3 apply_floor_fine_normal(vec3 geo_world_normal, vec2 world_xz_pos, float strength, float floor_gate) {
	if (floor_gate <= 0.0 || strength <= 0.0) {
		return geo_world_normal;
	}
	float eps = 0.22;  // ~0.22 m step (well below the ~0.4 m fine feature)
	vec2 fs = vec2(micro_fine_scale);
	vec2 off = vec2(4.1, 7.9);
	float h_x_neg = hash21_smooth((world_xz_pos + vec2(-eps, 0.0)) * fs + off);
	float h_x_pos = hash21_smooth((world_xz_pos + vec2( eps, 0.0)) * fs + off);
	float h_z_neg = hash21_smooth((world_xz_pos + vec2(0.0, -eps)) * fs + off);
	float h_z_pos = hash21_smooth((world_xz_pos + vec2(0.0,  eps)) * fs + off);
	float amp = strength * floor_gate * micro_fine_strength;
	vec2 grad = vec2(h_x_neg - h_x_pos, h_z_neg - h_z_pos) * amp;
	vec3 perturbed = geo_world_normal;
	vec3 tx = vec3(1.0, 0.0, 0.0) - geo_world_normal * geo_world_normal.x;
	float tx_len2 = dot(tx, tx);
	if (tx_len2 > 1e-4) {
		perturbed -= tx * (grad.x / sqrt(tx_len2));
	}
	vec3 tz = vec3(0.0, 0.0, 1.0) - geo_world_normal * geo_world_normal.z;
	float tz_len2 = dot(tz, tz);
	if (tz_len2 > 1e-4) {
		perturbed -= tz * (grad.y / sqrt(tz_len2));
	}
	return normalize(perturbed);
}

vec3 apply_array_normal(vec3 geo_world_normal, vec3 sampled_normal, float strength) {
	if (strength <= 0.0) {
		return geo_world_normal;
	}
	vec3 perturbed = geo_world_normal * max(sampled_normal.z, 0.15);
	vec3 tx = vec3(1.0, 0.0, 0.0) - geo_world_normal * geo_world_normal.x;
	float tx_len2 = dot(tx, tx);
	if (tx_len2 > 1e-4) {
		perturbed += tx * (sampled_normal.x * strength / sqrt(tx_len2));
	}
	vec3 tz = vec3(0.0, 0.0, 1.0) - geo_world_normal * geo_world_normal.z;
	float tz_len2 = dot(tz, tz);
	if (tz_len2 > 1e-4) {
		perturbed += tz * (sampled_normal.y * strength / sqrt(tz_len2));
	}
	return normalize(perturbed);
}

// TILED-DETAIL-NORMAL: blend a neutral tiled rock-grain normal scan into the surface normal in
// world XZ. Two octaves at different world scales (A fine, B broad, each with its own UV offset
// so the repeats do not correlate into a visible grid) are decoded to tangent space, summed
// into one detail tangent normal, then applied as a tangent-frame tilt on top of the incoming
// world normal -- the SAME T=+X / B=+Z projection convention apply_array_normal uses, so the
// relief leans the right way and composes with the strata/floor-pbr normal already baked into
// geo_world_normal. amp folds in strength * distance-fade (0 => exact no-op early-out). The
// per-octave tangent xy are summed (z left implicit via the tangent projection), giving a
// reoriented-style blend rather than a hard replace.
vec3 apply_detail_normal(vec3 geo_world_normal, vec2 world_xz_pos, float amp) {
	if (amp <= 0.0) {
		return geo_world_normal;
	}
	vec2 uv_a = world_xz_pos * terrain_detail_normal_scale;
	vec2 uv_b = world_xz_pos * (terrain_detail_normal_scale * max(terrain_detail_normal_octave2_scale_mul, 0.001)) + vec2(0.37, 0.61);
	vec3 n_a = texture(terrain_detail_normal_texture, uv_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(terrain_detail_normal_texture, uv_b).rgb * 2.0 - 1.0;
	float octave_mix = clamp(terrain_detail_normal_octave_mix, 0.0, 1.0);
	// Blend the two octaves' tangent xy (broader octave B weighted in by octave_mix), keep a
	// healthy z so the normalized detail normal stays near-up, then scale by amp downstream --
	// subtle micro-relief, not a busy bump. The differing octave scales + B's UV offset keep the
	// repeats from correlating into a visible tile grid.
	vec2 detail_xy = mix(n_a.xy, n_b.xy, octave_mix);
	vec3 detail_n = normalize(vec3(detail_xy, max(mix(n_a.z, n_b.z, octave_mix * 0.5), 0.20)));
	vec2 tilt = detail_n.xy * amp;
	vec3 perturbed = geo_world_normal;
	vec3 tx = vec3(1.0, 0.0, 0.0) - geo_world_normal * geo_world_normal.x;
	float tx_len2 = dot(tx, tx);
	if (tx_len2 > 1e-4) {
		perturbed += tx * (tilt.x / sqrt(tx_len2));
	}
	vec3 tz = vec3(0.0, 0.0, 1.0) - geo_world_normal * geo_world_normal.z;
	float tz_len2 = dot(tz, tz);
	if (tz_len2 > 1e-4) {
		perturbed += tz * (tilt.y / sqrt(tz_len2));
	}
	return normalize(perturbed);
}

// FLOOR-PBR triplanar sample. Projects the per-surface-id albedo_array + normal_array onto
// the three world planes and weight-blends them by the (powered) absolute geometric normal,
// so the drivable floor reads as real sand/slickrock/gravel up close without stretching on
// slickrock bumps. Each plane's tangent-space normal is rebuilt into world space on its own
// T/B/N basis (matching the top-projected convention apply_array_normal uses) before blending,
// so the relief points the right way regardless of which plane dominates. out_bump is how far
// the texture normal leans off the geo normal (0 = flat grain, 1 = strongly relief'd); it is
// reused to nudge ROUGHNESS because no dedicated roughness map ships in the ambientCG set.
void sample_floor_pbr_triplanar(
		vec3 geo_world_normal,
		vec2 world_xz_pos,
		float world_y_pos,
		float surface_id_value,
		float uv_scale,
		float triplanar_power,
		out vec3 out_albedo,
		out vec3 out_world_normal,
		out float out_bump
	) {
	float layer = clamp(surface_id_value, 0.0, 7.0);
	vec2 scale = vec2(max(uv_scale, 0.0001));
	vec3 w = pow(abs(geo_world_normal), vec3(max(triplanar_power, 0.0001)));
	float w_sum = max(dot(w, vec3(1.0)), 1e-4);
	w /= w_sum;
	vec2 uv_y = world_xz_pos * scale;                       // top plane (normal +Y): xz
	// PERF (single-plane on flats): the triplanar axis weights are cheap (no fetches), so
	// decide here. When the top plane dominates beyond floor_pbr_single_plane_threshold the
	// side planes would contribute <10% each -- not worth 4 extra fetches -- so sample only
	// the Y plane (2 fetches). Real slopes (slickrock bumps), where the side planes are
	// needed for slope-safety, fall below the threshold and run the full 3-plane blend.
	if (w.y >= floor_pbr_single_plane_threshold) {
		out_albedo = texture(albedo_array, vec3(uv_y, layer)).rgb;
		vec3 n_t = texture(normal_array, vec3(uv_y, layer)).rgb * 2.0 - 1.0;
		vec3 n_w = normalize(vec3(n_t.x, n_t.z, n_t.y));  // T=+X, B=+Z, N=+Y
		out_world_normal = n_w;
		out_bump = clamp(1.0 - max(dot(n_w, geo_world_normal), 0.0), 0.0, 1.0);
		return;
	}
	vec2 uv_x = vec2(world_y_pos, world_xz_pos.y) * scale;  // +X plane: yz
	vec2 uv_z = vec2(world_xz_pos.x, world_y_pos) * scale;  // +Z plane: xy
	vec3 a_y = texture(albedo_array, vec3(uv_y, layer)).rgb;
	vec3 a_x = texture(albedo_array, vec3(uv_x, layer)).rgb;
	vec3 a_z = texture(albedo_array, vec3(uv_z, layer)).rgb;
	out_albedo = a_y * w.y + a_x * w.x + a_z * w.z;
	vec3 n_y_t = texture(normal_array, vec3(uv_y, layer)).rgb * 2.0 - 1.0;
	vec3 n_x_t = texture(normal_array, vec3(uv_x, layer)).rgb * 2.0 - 1.0;
	vec3 n_z_t = texture(normal_array, vec3(uv_z, layer)).rgb * 2.0 - 1.0;
	vec3 n_y_w = normalize(vec3(n_y_t.x, n_y_t.z, n_y_t.y));  // T=+X, B=+Z, N=+Y
	vec3 n_x_w = normalize(vec3(n_x_t.z, n_x_t.x, n_x_t.y));  // T=+Y, B=+Z, N=+X
	vec3 n_z_w = normalize(vec3(n_z_t.x, n_z_t.y, n_z_t.z));  // T=+X, B=+Y, N=+Z
	vec3 blended = normalize(n_y_w * w.y + n_x_w * w.x + n_z_w * w.z);
	out_world_normal = blended;
	out_bump = clamp(1.0 - max(dot(blended, geo_world_normal), 0.0), 0.0, 1.0);
}

void vertex() {
	vec4 world_position = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = world_position.xz;
	world_y = world_position.y;
	local_normal_y = abs(normalize(NORMAL).y);
}

void fragment() {
	vec2 control_uv = clamp((world_xz - control_origin_xz) / control_size_xz, vec2(0.0), vec2(1.0));
	float surface_id_value = floor(texture(surface_id_texture, control_uv).r * 255.0 + 0.5);
	vec3 world_geo_normal_now = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 surface_color = surface_color_for_id(surface_id_value);
	// FLOOR-PBR eligibility, computed early so the planar array fetch below can be skipped on
	// floor pixels: there the triplanar inject later supplies the real texture, so the planar
	// fetch would be wasted work + texture-cache contention (a source of frame spikes). Gate
	// = slope * height and is ~= 0 off the low drivable floor, so cliffs/strata are untouched
	// and keep the planar array path. floor_pbr_uv broadens with slope (sand fine, slickrock
	// broader), derived from local_normal_y so it is available here without the late masks.
	float floor_pbr_slope_gate = smoothstep(floor_pbr_slope_steep_ny, floor_pbr_slope_flat_ny, local_normal_y);
	float floor_pbr_gate = clamp(floor_pbr_slope_gate * (1.0 - smoothstep(zion_sand_height_end + floor_pbr_height_start_offset, zion_sand_height_end + floor_pbr_height_end_offset, world_y)), 0.0, 1.0);
	bool floor_pbr_active = use_floor_pbr && use_albedo_array && use_normal_array && (floor_pbr_gate > 0.5);
	vec3 floor_pbr_normal_w = world_geo_normal_now;
	float floor_pbr_bump = 0.0;
	float floor_pbr_uv = floor_pbr_uv_scale.x * mix(1.0, floor_pbr_slickrock_scale_mul, 1.0 - floor_pbr_slope_gate);
	if (use_albedo_array && !floor_pbr_active) {
		float albedo_layer = clamp(surface_id_value, 0.0, 7.0);
		vec2 albedo_uv = world_xz * surface_uv_scale_for_id(surface_id_value);
		vec3 albedo_sample = texture(albedo_array, vec3(albedo_uv, albedo_layer)).rgb;
		ALBEDO = mix(albedo_sample, surface_color.rgb, 0.25);
	} else {
		ALBEDO = surface_color.rgb;
	}
	float slope_mask = 1.0 - clamp(local_normal_y, 0.0, 1.0);
	float sandstone_mask = smoothstep(zion_sandstone_slope_start, zion_sandstone_slope_end, slope_mask);
	float high_wall_mask = smoothstep(zion_sand_height_start + 4.0, zion_sand_height_end + 18.0, world_y);
	float low_flat_mask = (1.0 - sandstone_mask) * (1.0 - smoothstep(zion_sand_height_start, zion_sand_height_end, world_y));
	float cliff_mask = max(sandstone_mask, high_wall_mask * 0.86);
	float cliff_face_mask = smoothstep(0.32, 0.82, slope_mask);
	bool cliff_strata_active = (cliff_mask > 0.0) || (high_wall_mask > 0.0);
	float kayenta_mask = 0.0;
	float kayenta_contact_line = 0.0;
	float kayenta_contact_y = 0.0;
	vec3 navajo_color = ALBEDO;
	float navajo_height_t_out = 0.0;
	float major_sweep = 0.0;
	float major_line = 0.0;
	float lamina_wave = 0.0;
	float lamina_line = 0.0;
	float lamina_dark = 0.0;
	float truncation_line = 0.0;
	float strata_wave = 0.0;
	vec3 kayenta_base = ALBEDO;
	if (cliff_strata_active) {
		// Kayenta/Navajo contact: a stepped, slightly jittered surface (not a flat band edge)
		// so the basal skirt reads as the recessed ledge-and-step Kayenta, capped by a darker
		// contact line where the Navajo cliff springs from it.
		float kayenta_effective_end = max(zion_kayenta_height_end, zion_sand_height_start + zion_kayenta_skirt_height_m);
		float kayenta_contact_noise = hash21_smooth(world_xz * 0.020 + vec2(19.0, 6.0));
		float kayenta_contact_step = floor(kayenta_contact_noise * 5.0) - 2.0;
		kayenta_contact_y = kayenta_effective_end
		                  + kayenta_contact_step * zion_kayenta_contact_step_m
		                  + (hash21_smooth(world_xz * 0.047 + vec2(1.7, 15.0)) - 0.5) * 2.4;
		float kayenta_height_mask = smoothstep(zion_kayenta_height_start, zion_kayenta_height_start + 8.0, world_y)
		                          * (1.0 - smoothstep(kayenta_contact_y - 5.5, kayenta_contact_y + 1.5, world_y));
		float kayenta_wall_mask = max(sandstone_mask, high_wall_mask * 0.42);
		kayenta_mask = clamp(kayenta_height_mask, 0.0, 1.0) * kayenta_wall_mask;
		kayenta_contact_line = (1.0 - smoothstep(0.0, 5.5, abs(world_y - kayenta_contact_y))) * kayenta_wall_mask * cliff_face_mask;
		float navajo_height_span = max(zion_navajo_height_end - zion_navajo_height_start, 1.0);
		float navajo_height_t = clamp((world_y - zion_navajo_height_start) / navajo_height_span + cliff_face_mask * 0.035, 0.0, 1.0);
		navajo_height_t_out = navajo_height_t;
		navajo_color = zion_navajo_palette(navajo_height_t);
		// Cross-bed SET modeling: quantize the wall into stacked bedding packages, give each set
		// its own azimuth dip and tangent (set_hash / tangent_hash), and read the laminae within.
		// Set boundaries become truncation surfaces (truncation_line) -- the signature angular
		// unconformities of Navajo cross-bedding -- which darken rather than just shade.
		vec2 base_dip_dir = zion_crossbed_dip_dir / max(length(zion_crossbed_dip_dir), 0.001);
		vec2 bed_cross_dir = vec2(-base_dip_dir.y, base_dip_dir.x);
		float package_period = max(zion_crossbed_major_period_m, 1.0);
		float legacy_dip_nudge = dot(world_xz, zion_strata_dip) * 0.05;
		float package_seed_coord = world_y + dot(world_xz, base_dip_dir) * zion_crossbed_dip_tangent + legacy_dip_nudge;
		float package_index = floor(package_seed_coord / package_period);
		float azimuth_band = floor(dot(world_xz, bed_cross_dir) * 0.018);
		float set_hash = hash21(vec2(package_index, azimuth_band));
		float tangent_hash = hash21(vec2(package_index + 17.0, azimuth_band - 11.0));
		float dip_turn = (set_hash - 0.5) * zion_crossbed_set_turn;
		float dip_cos = cos(dip_turn);
		float dip_sin = sin(dip_turn);
		vec2 dip_dir = vec2(base_dip_dir.x * dip_cos - base_dip_dir.y * dip_sin, base_dip_dir.x * dip_sin + base_dip_dir.y * dip_cos);
		float set_tangent = zion_crossbed_dip_tangent * mix(0.88, 1.18, tangent_hash);
		float bed_warp = (hash21_smooth(world_xz * 0.010 + vec2(9.3, 4.4)) * 2.0 - 1.0) * zion_crossbed_warp_m;
		float bed_coord = world_y + dot(world_xz, dip_dir) * set_tangent + bed_warp + legacy_dip_nudge;
		float major_phase = bed_coord / package_period;
		float major_frac = fract(major_phase);
		float boundary_jitter = hash21_smooth(vec2(floor(dot(world_xz, bed_cross_dir) * 0.025), package_index) + vec2(5.0, 3.0)) * 0.04;
		major_line = wrapped_line(major_phase + boundary_jitter, 0.044);
		float sweep_t = smoothstep(0.05, 0.86, major_frac);
		major_sweep = sin(sweep_t * (ZION_TAU * 0.5));
		float lamina_coord = world_y + dot(world_xz, dip_dir) * set_tangent * mix(1.03, 1.12, set_hash) + bed_warp * 0.25 + set_hash * package_period * 0.12;
		float lamina_phase = lamina_coord / max(zion_crossbed_lamina_period_m, 0.25);
		float lamina_frac = fract(lamina_phase);
		float lamina_edge = min(lamina_frac, 1.0 - lamina_frac);
		lamina_wave = (1.0 - lamina_frac) * 2.0 - 1.0;
		lamina_line = 1.0 - smoothstep(0.018, 0.115, lamina_edge);
		lamina_dark = 1.0 - smoothstep(0.035, 0.160, lamina_frac);
		truncation_line = major_line * zion_crossbed_truncation_strength;
		strata_wave = clamp(major_sweep * 0.50 + (1.0 - lamina_frac) * 0.50, 0.0, 1.0) * 2.0 - 1.0;
		// Kayenta ledge banding: a coarse ledge-and-recess period plus a thin parting set, summed
		// with the contact line into a recessed-shadow term that darkens the basal skirt.
		float kayenta_phase = world_y / max(zion_kayenta_ledge_period_m, 0.5) + hash21_smooth(world_xz * 0.035 + vec2(5.0, 1.0)) * 0.16;
		float kayenta_frac = fract(kayenta_phase);
		float kayenta_line = wrapped_line(kayenta_phase, 0.11);
		float kayenta_thin_phase = world_y / 1.65 + hash21_smooth(world_xz * 0.045) * 0.12;
		float kayenta_thin_line = wrapped_line(kayenta_thin_phase, 0.050);
		float kayenta_lamina = smoothstep(0.12, 0.58, kayenta_frac) * (1.0 - smoothstep(0.58, 0.96, kayenta_frac));
		float kayenta_ledge_shadow = clamp(kayenta_line * 0.72 + kayenta_thin_line * 0.28 + kayenta_contact_line * 0.85, 0.0, 1.0);
		vec3 kayenta_base_color = mix(zion_kayenta_color.rgb, zion_kayenta_basal_color.rgb, 0.68);
		kayenta_base = mix(kayenta_base_color, zion_kayenta_lavender_color.rgb, smoothstep(0.48, 0.86, hash21_smooth(world_xz * 0.022 + vec2(12.0, 3.0))) * 0.34);
		kayenta_base *= 0.82 + kayenta_lamina * 0.18;
		kayenta_base = mix(kayenta_base, zion_kayenta_ledge_shadow_color.rgb, kayenta_ledge_shadow * 0.58);
		float kayenta_vegetation = smoothstep(0.68, 0.92, hash21_smooth(world_xz * 0.068 + vec2(8.0, 18.0))) * (0.35 + kayenta_ledge_shadow * 0.65);
		kayenta_base = mix(kayenta_base, zion_kayenta_vegetation_shadow_color.rgb, kayenta_vegetation * 0.18);
	}
	float detile_a = hash21_smooth(world_xz * 0.055) * 2.0 - 1.0;
	float detile_b = hash21_smooth(world_xz * 0.031 + vec2(7.3, 2.1)) * 2.0 - 1.0;
	float detile = detile_a * 0.5 + detile_b * 0.5;
	vec3 zion_albedo = ALBEDO;
	float river_distance_m = zion_river_distance(world_xz);
	float river_corridor_mask = 1.0 - smoothstep(zion_riparian_inner_m, zion_riparian_outer_m, river_distance_m);
	float low_river_floor_mask = (1.0 - sandstone_mask) * (1.0 - smoothstep(zion_sand_height_end - 1.0, zion_sand_height_end + 7.0, world_y));
	float riparian_tint_mask = river_corridor_mask * max(low_flat_mask, low_river_floor_mask * river_corridor_mask);
	float bank_wet_mask = smoothstep(6.0, 9.0, river_distance_m) * (1.0 - smoothstep(9.0, zion_bank_wet_width_m, river_distance_m)) * low_river_floor_mask;
	zion_albedo = mix(zion_albedo, zion_sand_color.rgb, low_flat_mask * 0.30);
	zion_albedo = mix(zion_albedo, zion_floor_cool_sand_color.rgb, low_flat_mask * zion_floor_deorange_strength);
	float floor_macro = hash21_smooth(world_xz * 0.010 + vec2(8.0, 2.0));
	float floor_mid = hash21_smooth(world_xz * 0.026 + vec2(3.1, 8.7));
	float floor_fine = hash21_smooth(world_xz * 0.083 + vec2(14.4, 6.2));
	// FLOOR-TONAL-DRIFT: broad warm/cool hue drift across the drivable floor. Two low
	// frequencies (~200 m + ~100 m, the latter reusing floor_macro) sum into a smooth
	// signed drift; positive pulls the floor base toward the redder iron-rich slickrock
	// bench, negative toward the paler bleached sandy wash. Gated to the low flat floor
	// (low_flat_mask), so the canyon floor reads as a mosaic of redder benches and paler
	// washes instead of one flat de-oranged tint. The small-scale wash/slickrock/sand
	// patch masks below break up ON TOP of this broad base.
	float floor_drift_broad = hash21_smooth(world_xz * 0.0052 + vec2(21.0, 9.0));
	float floor_drift = clamp((floor_drift_broad * 0.62 + floor_macro * 0.38) * 2.0 - 1.0 + zion_floor_tonal_drift_bias, -1.0, 1.0);
	vec3 floor_drift_color = mix(zion_floor_pale_wash_color.rgb, zion_floor_warm_bench_color.rgb, floor_drift * 0.5 + 0.5);
	zion_albedo = mix(zion_albedo, floor_drift_color, low_flat_mask * zion_floor_tonal_drift_strength);
	float floor_wash_mask = low_flat_mask * (1.0 - river_corridor_mask * 0.35) * smoothstep(0.46, 0.82, floor_mid);
	float floor_slickrock_mask = low_flat_mask * smoothstep(0.60, 0.90, floor_macro) * (1.0 - floor_wash_mask * 0.45);
	float floor_sand_patch_mask = low_flat_mask * smoothstep(0.48, 0.86, floor_fine) * (1.0 - floor_slickrock_mask * 0.30);
	zion_albedo = mix(zion_albedo, zion_floor_wash_color.rgb, floor_wash_mask * zion_floor_patch_strength);
	zion_albedo = mix(zion_albedo, zion_floor_slickrock_color.rgb, floor_slickrock_mask * zion_floor_patch_strength);
	zion_albedo = mix(zion_albedo, zion_floor_sand_patch_color.rgb, floor_sand_patch_mask * zion_floor_patch_strength * 0.8);
	float floor_scatter = floor_mid * 0.55 + floor_fine * 0.45;
	zion_albedo = mix(zion_albedo, zion_floor_sediment_color.rgb, low_flat_mask * (0.36 + floor_mid * 0.18));
	zion_albedo = mix(zion_albedo, zion_floor_dark_color.rgb, low_flat_mask * floor_scatter * zion_floor_scatter_strength * 0.95);
	float detile_floor = (floor_macro * 0.45 + floor_mid * 0.35 + floor_fine * 0.20) * 2.0 - 1.0;
	zion_albedo *= 1.0 + detile_floor * low_flat_mask * zion_floor_detile_strength * 0.72;
	// FLOOR-FIDELITY: fine (~0.5 m) albedo grain so the floor breaks up at sand-grain
	// scale under raking light, instead of reading as a smooth matte plane. Subtle.
	float floor_albedo_grain = hash21_smooth(world_xz * 2.1 + vec2(2.7, 8.3)) * 2.0 - 1.0;
	zion_albedo *= 1.0 + floor_albedo_grain * low_flat_mask * micro_albedo_grain_strength;
	zion_albedo = mix(zion_albedo, zion_riparian_tint_color.rgb, riparian_tint_mask * zion_riparian_tint_strength);
	float navajo_mask = clamp(cliff_mask * (1.0 - kayenta_mask * 0.80), 0.0, 1.0);
	vec3 navajo_modulated = zion_navajo_modulated_albedo(zion_albedo, navajo_color);
	zion_albedo = mix(zion_albedo, navajo_modulated, navajo_mask * zion_navajo_palette_strength);
	zion_albedo = mix(zion_albedo, kayenta_base, kayenta_mask * min(zion_kayenta_strength + 0.30, 1.0));
	float strata_shade = major_sweep * 0.11 + lamina_wave * 0.070 - truncation_line * 0.50 - lamina_dark * 0.12;
	vec3 strata_tint = navajo_modulated * (1.0 + strata_shade);
	// Truncation/bounding-surface shadow: warm red-brown low on the wall (iron-rich Navajo),
	// cooling toward a neutral grey-dark high up so the bleached cream/white tops don't read as
	// warm-red in their cross-bed shadows (preserves the warm-bottom / cool-top complement).
	vec3 strata_dark_tint = mix(zion_strata_dark_color.rgb, vec3(0.20, 0.17, 0.15), smoothstep(0.55, 0.92, navajo_height_t_out));
	strata_tint = mix(strata_tint, strata_dark_tint, clamp(truncation_line * 0.58 + major_line * 0.10, 0.0, 0.42));
	// Cross-bed lighter laminae are a tonal LIFT of the LOCAL height facies, not a single
	// warm-orange constant. The legacy constant (zion_strata_light_color, a warm orange) was
	// mixed into every lamina at all heights, which re-warmed the cream/white upper Navajo and
	// bleached tops -- fighting the vertical de-orange gradient (bible 1.3/4.3 rule 1, the
	// load-bearing "too orange on the upper walls" defect). Derive the lamina-light tint from
	// the local navajo_color brightened toward its own value, and fade the warm-orange constant
	// out with height so it only warms the lower/mid wall where warm laminae are correct.
	vec3 strata_local_light = clamp(navajo_color * 1.18 + vec3(0.045), vec3(0.0), vec3(1.0));
	float strata_warm_keep = 1.0 - smoothstep(0.42, 0.78, navajo_height_t_out);
	vec3 strata_light_tint = mix(strata_local_light, zion_strata_light_color.rgb, strata_warm_keep * 0.5);
	strata_tint = mix(strata_tint, strata_light_tint, lamina_line * 0.055 * (1.0 - major_line * 0.45));
	float strata_cliff_mask = navajo_mask * cliff_face_mask;
	zion_albedo = mix(zion_albedo, strata_tint, strata_cliff_mask * zion_strata_strength);
	zion_albedo = mix(zion_albedo, kayenta_base, kayenta_mask * cliff_face_mask * min(zion_kayenta_strength + 0.15, 1.0) * 0.45);
	zion_albedo = mix(zion_albedo, zion_kayenta_ledge_shadow_color.rgb, kayenta_contact_line * 0.42);
	zion_albedo *= 1.0 + detile * zion_detile_strength * max(cliff_mask, low_flat_mask * 0.5);
	// FAR-WALL WARM GRADIENT: height-driven warm Navajo-red tint + mild contrast boost.
	// Gated to cliff_mask (walls only) so the drivable floor is fully unaffected.
	// Blends toward zion_far_wall_warm_color as world_y rises through the canyon-wall range,
	// so sub-pixel strata bands that flatten to a mid-tone at distance still read warm+stratified.
	if (zion_far_wall_warm_strength > 0.0 && cliff_mask > 0.0) {
		float far_wall_height_t = smoothstep(zion_far_wall_height_start, zion_far_wall_height_end, world_y);
		float far_wall_gate = far_wall_height_t * cliff_mask;
		// Warm tint: lerp albedo toward the warm anchor color
		zion_albedo = mix(zion_albedo, zion_far_wall_warm_color.rgb, far_wall_gate * zion_far_wall_warm_strength);
		// Contrast lift: push luma away from 0.5 (darks darker, lights lighter) to counter post-stack flattening
		if (zion_far_wall_contrast > 0.0) {
			float lum = luminance(zion_albedo);
			float contrast_lum = clamp((lum - 0.5) * (1.0 + zion_far_wall_contrast * far_wall_gate) + 0.5, 0.0, 1.0);
			float lum_safe = max(lum, 0.001);
			zion_albedo = clamp(zion_albedo * (contrast_lum / lum_safe), vec3(0.0), vec3(1.0));
		}
	}
	ALBEDO = clamp(zion_albedo, vec3(0.0), vec3(1.0));
	// FLOOR-PBR inject: detail-blend the real CC0 PBR triplanar albedo into the floor. The
	// procedural tints above (de-orange, wash/slickrock/sand patches) keep supplying the Zion
	// COLOR; this adds the real close-up grain/structure the flat floor was missing. Gate is
	// ~= 0 off the low drivable surface, so wetrock/varnish/macro/bleach below run unaltered.
	if (floor_pbr_gate > 0.001) {
		vec3 floor_pbr_albedo = vec3(0.5);
		sample_floor_pbr_triplanar(world_geo_normal_now, world_xz, world_y, surface_id_value, floor_pbr_uv, floor_pbr_triplanar_blend, floor_pbr_albedo, floor_pbr_normal_w, floor_pbr_bump);
		ALBEDO = mix(ALBEDO, floor_pbr_albedo, floor_pbr_blend * floor_pbr_gate);
		ALBEDO = clamp(ALBEDO, vec3(0.0), vec3(1.0));
	}
	float flow_x = dot(world_xz, vec2(0.73, -0.68));
	float flow_y = dot(world_xz, vec2(0.68, 0.73));
	if (zion_wetrock_enabled) {
		float wetrock_wall = step(local_normal_y, 0.25);
		float wetrock_height = smoothstep(zion_wetrock_height_start, zion_wetrock_height_start + 15.0, world_y)
		                     * (1.0 - smoothstep(zion_wetrock_height_end - 15.0, zion_wetrock_height_end, world_y));
		float wetrock_scatter = step(0.72, hash21(floor(world_xz * 0.018)));
		float wetrock_mask = wetrock_wall * wetrock_height * wetrock_scatter;
		ALBEDO = mix(ALBEDO, ALBEDO * (1.0 - zion_wetrock_darkness) + zion_wetrock_moss_color.rgb * 0.08, wetrock_mask);
		// Hanging gardens: lush green seep lines hung just below the Kayenta/Navajo contact on
		// shaded (north/east-aspect) walls, dripping down and breaking up patchily. Gated to the
		// same vertical walls as wetrock so floors/strata are untouched.
		vec2 wall_aspect = world_geo_normal_now.xz / max(length(world_geo_normal_now.xz), 0.001);
		float garden_shade_aspect = smoothstep(0.08, 0.62, dot(wall_aspect, vec2(-0.62, -0.78)));
		float garden_contact_y = kayenta_contact_y - 5.0;
		float garden_down_from_contact_m = garden_contact_y - world_y;
		float garden_contact_band = (1.0 - smoothstep(1.5, 12.0, abs(world_y - garden_contact_y))) * wetrock_height;
		float garden_drip_band = smoothstep(0.0, 5.0, garden_down_from_contact_m)
		                       * (1.0 - smoothstep(10.0, 36.0, garden_down_from_contact_m))
		                       * wetrock_height;
		float garden_macro_patch = smoothstep(0.76, 0.94, hash21_smooth(world_xz * 0.022 + vec2(31.0, 12.0)));
		float garden_breakup = smoothstep(0.48, 0.80, hash21_smooth(vec2(flow_x * 0.075, world_y * 0.18) + vec2(22.0, 5.0)));
		float hanging_garden_mask = wetrock_wall * cliff_face_mask * garden_shade_aspect * garden_macro_patch * garden_breakup * max(garden_contact_band, garden_drip_band * 0.55);
		vec3 garden_color = mix(zion_wetrock_moss_color.rgb, zion_hanging_garden_color.rgb, 0.74);
		ALBEDO = mix(ALBEDO, garden_color, clamp(hanging_garden_mask * zion_hanging_garden_strength, 0.0, 0.40));
	}
	float varnish_wall_mask = 1.0 - smoothstep(zion_varnish_wall_threshold - 0.08, zion_varnish_wall_threshold + 0.08, local_normal_y);
	float seep_noise = hash21_smooth(world_xz * 0.016 + vec2(2.0, 17.0));
	float seep_y = mix(zion_wetrock_height_start + 35.0, max(zion_wetrock_height_end, zion_varnish_height_start) + 170.0, seep_noise);
	float down_from_seep_m = seep_y - world_y;
	float below_seep_mask = smoothstep(0.0, 18.0, down_from_seep_m)
	                       * (1.0 - smoothstep(zion_varnish_drop_m * 0.48, zion_varnish_drop_m, down_from_seep_m));
	// Cliff-LIP varnish drapes: periodic dark streaks hanging from the rim of the wall (where
	// runoff concentrates over the lip), in addition to the seep-fed columns. flow_x/flow_y are
	// hoisted above the wetrock block.
	float lip_period_m = mix(24.0, 42.0, hash21_smooth(vec2(floor(flow_y * 0.013), 4.0)));
	float lip_phase = (world_y + hash21_smooth(world_xz * 0.011 + vec2(9.0, 21.0)) * 12.0) / lip_period_m;
	float lip_drop_m = (1.0 - fract(lip_phase)) * lip_period_m;
	float lip_region = smoothstep(0.70, 0.92, hash21_smooth(vec2(floor(flow_x * 0.018), floor(lip_phase)) + vec2(13.0, 27.0)));
	float below_lip_mask = smoothstep(1.0, 7.5, lip_drop_m)
	                     * (1.0 - smoothstep(zion_varnish_drop_m * 0.32, zion_varnish_drop_m * 0.86, lip_drop_m))
	                     * lip_region;
	float varnish_phase = flow_x * zion_varnish_streak_scale + hash21_smooth(vec2(floor(flow_y * 0.025), floor(seep_y * 0.018))) * ZION_TAU;
	float varnish_column = pow(max(0.0, 1.0 - abs(sin(varnish_phase))), 3.6);
	float varnish_thread = pow(max(0.0, 1.0 - abs(sin(varnish_phase * 2.35))), 5.2);
	float varnish_breaks = smoothstep(0.22, 0.78, hash21_smooth(vec2(flow_x * 0.045 + sin(world_y * 0.025) * 0.42, world_y * 0.036) + vec2(11.0, 6.0)));
	float varnish_region = smoothstep(0.50, 0.86, hash21_smooth(world_xz * 0.021 + vec2(17.0, 3.0)));
	float varnish_lip_gate = max(below_seep_mask, below_lip_mask * zion_varnish_lip_strength);
	float varnish_streak = max(varnish_column, varnish_thread * 0.44) * varnish_breaks * varnish_region * mix(0.62, 1.0, strata_wave * 0.5 + 0.5);
	float varnish_height_mask = smoothstep(zion_varnish_height_start - 65.0, zion_varnish_height_start + 25.0, world_y);
	float varnish_amount = varnish_wall_mask * varnish_height_mask * varnish_lip_gate * varnish_streak * zion_varnish_strength;
	vec3 varnish_oxide = mix(zion_varnish_fe_color.rgb, zion_varnish_mn_color.rgb, smoothstep(0.50, 0.92, hash21_smooth(world_xz * 0.033 + vec2(4.0, 19.0))));
	vec3 varnish_brown = mix(zion_varnish_color.rgb, vec3(0.075, 0.038, 0.016), 0.65);
	varnish_oxide = mix(varnish_brown, varnish_oxide, 0.78);
	ALBEDO = mix(ALBEDO, varnish_oxide, clamp(varnish_amount, 0.0, 0.80));
	if (use_macro_albedo) {
		vec2 macro_uv = clamp((world_xz - macro_albedo_origin_xz) / macro_albedo_size_xz, vec2(0.0), vec2(1.0));
		vec3 macro_albedo = texture(macro_albedo_texture, macro_uv).rgb;
		float macro_luma = luminance(macro_albedo);
		float base_luma = max(luminance(ALBEDO), 0.035);
		float macro_luma_ratio = clamp(macro_luma / base_luma, 0.55, 1.45);
		ALBEDO = clamp(mix(ALBEDO, ALBEDO * macro_luma_ratio, macro_albedo_strength), vec3(0.0), vec3(1.0));
		vec3 macro_chroma_ratio = clamp(macro_albedo / vec3(max(macro_luma, 0.035)), vec3(0.72), vec3(1.28));
		vec3 macro_chroma_albedo = clamp(ALBEDO * macro_chroma_ratio, vec3(0.0), vec3(1.0));
		float chroma_luma = max(luminance(macro_chroma_albedo), 0.035);
		float post_luma = max(luminance(ALBEDO), 0.035);
		macro_chroma_albedo = clamp(macro_chroma_albedo * (post_luma / chroma_luma), vec3(0.0), vec3(1.0));
		ALBEDO = clamp(mix(ALBEDO, macro_chroma_albedo, clamp(macro_albedo_chroma_strength, 0.0, 1.0)), vec3(0.0), vec3(1.0));
	}
	float bleach_noise = hash21_smooth(world_xz * 0.018 + vec2(6.0, 14.0)) * 0.58
	                   + hash21_smooth(world_xz * 0.047 + vec2(1.0, 5.0)) * 0.42;
	float bleach_blob = smoothstep(0.50, 0.84, bleach_noise);
	float bleach_mask = smoothstep(zion_bleach_height_start, zion_bleach_height_start + 210.0, world_y) * cliff_mask * (0.42 + bleach_blob * 0.58);
	ALBEDO = mix(ALBEDO, zion_bleach_color.rgb, bleach_mask * zion_bleach_strength);
	vec3 bank_wet_albedo = clamp(ALBEDO * (1.0 - zion_bank_wet_darkness) + zion_wetrock_moss_color.rgb * 0.08, vec3(0.0), vec3(1.0));
	ALBEDO = mix(ALBEDO, bank_wet_albedo, bank_wet_mask);
	// W6-SURFACE-DETAIL: surface micro-relief so raking golden-hour light catches
	// real texture. A procedural micro-normal (hash only, no extra texture fetches)
	// perturbs the world-space geometric normal in the surface tangent plane, and a
	// gentle hashed ROUGHNESS wobble breaks up the uniformly matte floor. Strength
	// scales per surface -- more on packed_gravel/loose_rock, near-zero on paved_road,
	// with the normal array adding extra sandstone grain on cliff/strata bands.
	float micro_strength = surface_micro_strength_for_id(surface_id_value);
	vec3 world_detail_normal = world_geo_normal_now;
	float normal_mask = max(strata_cliff_mask, cliff_mask * 0.35);
	if (use_normal_array && normal_mask > 0.01) {
		float normal_layer = clamp(surface_id_value, 0.0, 7.0);
		vec2 normal_uv = world_xz * surface_uv_scale_for_id(surface_id_value);
		vec3 sampled_normal = texture(normal_array, vec3(normal_uv, normal_layer)).rgb * 2.0 - 1.0;
		world_detail_normal = apply_array_normal(world_detail_normal, sampled_normal, normal_array_strength * normal_mask);
	}
	// FLOOR-PBR normal: slope-safe triplanar world-space normal from the real PBR normal
	// map, gated to the drivable floor. Cliffs keep the strata/cliff normal above; the
	// floor finally gets real sand/rock grain that raking golden-hour light can catch.
	if (floor_pbr_gate > 0.001) {
		world_detail_normal = normalize(mix(world_detail_normal, floor_pbr_normal_w, floor_pbr_normal_strength * floor_pbr_gate));
	}
	// TILED-DETAIL-NORMAL: fine rock/sand grain across the whole terrain (the dominant surface),
	// summed two octaves, faded out with camera distance so far tiles do not shimmer/alias. Folds
	// strength * fade into amp; amp == 0 (strength 0 or beyond the fade end) is an exact no-op.
	// Applied on top of the strata/floor-pbr relief, before the procedural micro/fine octaves, so
	// the cavity-AO below naturally reads the added grain. Writes only NORMAL.
	vec3 detail_camera_pos = INV_VIEW_MATRIX[3].xyz;
	float detail_camera_dist = length(vec3(world_xz.x, world_y, world_xz.y) - detail_camera_pos);
	float detail_fade = 1.0 - smoothstep(terrain_detail_normal_fade_start_m, max(terrain_detail_normal_fade_end_m, terrain_detail_normal_fade_start_m + 1.0), detail_camera_dist);
	world_detail_normal = apply_detail_normal(world_detail_normal, world_xz, terrain_detail_normal_strength * detail_fade);
	vec3 world_micro_normal = apply_micro_normal(world_detail_normal, world_xz, micro_strength);
	world_micro_normal = apply_floor_fine_normal(world_micro_normal, world_xz, micro_strength, low_flat_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_micro_normal, 0.0)).xyz);
	// C2 CAVITY AO: darken ALBEDO in crevices using the relief signal the detail normal
	// already carries -- how far the final micro/detail normal leans off the geometric
	// normal (0 = flat plate, ~1 = deep grain/strata). No extra texture fetch. Weighted up
	// a touch on the drivable floor (where grain depth reads most) via surface_ao_floor_bias.
	// Conservative: a multiplicative darken only, so it deepens contact shadow without
	// shifting hue; surface_ao_strength = 0 restores the prior flat-lit albedo exactly.
	float surface_cavity = clamp(1.0 - dot(world_micro_normal, world_geo_normal_now), 0.0, 1.0);
	float surface_ao = 1.0 - surface_cavity * surface_ao_strength * (1.0 + surface_ao_floor_bias * low_flat_mask);
	ALBEDO = clamp(ALBEDO * clamp(surface_ao, 0.0, 1.0), vec3(0.0), vec3(1.0));
	float roughness_wobble = (hash21_smooth(world_xz * 0.31) * 2.0 - 1.0) * micro_roughness_variation * (0.5 + micro_strength);
	float floor_roughness_wobble = (hash21_smooth(world_xz * 0.9 + vec2(5.7, 2.4)) * 2.0 - 1.0) * micro_roughness_floor_variation * low_flat_mask;
	float floor_roughness_shift = floor_wash_mask * 0.035 + floor_sand_patch_mask * 0.055 - floor_slickrock_mask * 0.08 + low_flat_mask * detile_floor * 0.025;
	// C2: per-surface base roughness (catalog's own wet-adjusted value per surface-id layer)
	// replaces the single catalog-averaged terrain_roughness scalar, so wet/mossy stone reads
	// glossier and loose sand/scree matte. All the existing floor/relief/wet wobbles still
	// layer on top, and the wet-bank override is unchanged.
	float surface_base_roughness = surface_roughness_for_id(surface_id_value);
	ROUGHNESS = clamp(mix(surface_base_roughness + roughness_wobble + floor_roughness_shift + floor_roughness_wobble + floor_pbr_bump * floor_pbr_roughness_strength * floor_pbr_gate, zion_bank_wet_roughness, bank_wet_mask), 0.05, 1.0);
	SPECULAR = terrain_specular;
}
