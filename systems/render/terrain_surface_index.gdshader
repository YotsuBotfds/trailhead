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
uniform float zion_navajo_palette_strength = 0.9;
uniform float zion_sandstone_slope_start = 0.08;
uniform float zion_sandstone_slope_end = 0.38;
uniform float zion_sand_height_start = 1193.0;
uniform float zion_sand_height_end = 1202.0;
uniform float zion_strata_scale = 2.0;
uniform float zion_strata_strength = 0.48;
uniform vec4 zion_strata_light_color : source_color = vec4(0.86, 0.62, 0.38, 1.0);  // lighter band tone (Navajo cross-bedding)
uniform vec2 zion_strata_dip = vec2(0.15, 0.15);                                    // xz phase per meter (diagonal cross-bedding dip)
uniform vec2 zion_crossbed_dip_dir = vec2(0.84, 0.54);
uniform float zion_crossbed_dip_tangent = 0.51;
uniform float zion_crossbed_major_period_m = 18.0;
uniform float zion_crossbed_lamina_period_m = 1.5;
uniform float zion_crossbed_warp_m = 3.5;
uniform float zion_detile_strength = 0.18;
uniform vec4 zion_floor_dark_color : source_color = vec4(0.20, 0.16, 0.13, 1.0);
uniform vec4 zion_floor_sediment_color : source_color = vec4(0.55, 0.34, 0.24, 1.0);  // reddish Kayenta sediment tint beneath the crust
uniform vec4 zion_floor_slickrock_color : source_color = vec4(0.60, 0.45, 0.32, 1.0);  // warm but desaturated (exposed Navajo, not glowing)
uniform vec4 zion_floor_wash_color : source_color = vec4(0.48, 0.42, 0.32, 1.0);
uniform vec4 zion_floor_sand_patch_color : source_color = vec4(0.74, 0.66, 0.52, 1.0);  // cooler tan patch (was saturated orange)
uniform float zion_floor_scatter_strength = 0.80;
uniform float zion_floor_detile_strength = 0.24;
uniform float zion_floor_patch_strength = 0.34;
uniform vec4 zion_riparian_tint_color : source_color = vec4(0.31, 0.44, 0.24, 1.0);
uniform float zion_riparian_tint_strength = 0.24;
uniform float zion_riparian_inner_m = 12.0;
uniform float zion_riparian_outer_m = 130.0;
uniform float zion_bank_wet_width_m = 14.0;
uniform float zion_bank_wet_darkness = 0.16;
uniform float zion_bank_wet_roughness = 0.36;
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
uniform float zion_varnish_wall_threshold = 0.30;   // local_normal_y below this = near-vertical face
uniform float zion_varnish_height_start = 1300.0;   // varnish mostly on walls above the floor
uniform float zion_varnish_streak_scale = 0.12;     // horizontal streak frequency
uniform float zion_varnish_drop_m = 145.0;
// Kayenta Formation: warm-dark band at cliff base (~1200-1250 m) below the Navajo mass.
uniform vec4 zion_kayenta_color : source_color = vec4(0.38, 0.10, 0.06, 1.0);  // deep brick-red
uniform vec4 zion_kayenta_lavender_color : source_color = vec4(0.20, 0.13, 0.14, 1.0);
uniform float zion_kayenta_height_start = 1200.0;
uniform float zion_kayenta_height_end = 1250.0;
uniform float zion_kayenta_skirt_height_m = 120.0;
uniform float zion_kayenta_strength = 0.55;
// Upper-wall bleach: pale buff cream tint driven by world height (Great White Throne reads near-white).
uniform vec4 zion_bleach_color : source_color = vec4(0.91, 0.84, 0.72, 1.0);  // pale buff cream
uniform float zion_bleach_height_start = 1550.0;   // lower edge of the bleached upper walls
uniform float zion_bleach_strength = 0.55;
uniform bool zion_wetrock_enabled = true;
uniform float zion_wetrock_height_start = 1230.0;
uniform float zion_wetrock_height_end = 1320.0;
uniform float zion_wetrock_darkness = 0.4;
uniform vec4 zion_wetrock_moss_color : source_color = vec4(0.164, 0.219, 0.125, 1.0);
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
	float cliff_mask = max(sandstone_mask, high_wall_mask * 0.58);
	float cliff_face_mask = smoothstep(0.32, 0.82, slope_mask);
	float kayenta_effective_end = max(zion_kayenta_height_end, zion_sand_height_start + zion_kayenta_skirt_height_m);
	float kayenta_height_mask = smoothstep(zion_kayenta_height_start, zion_kayenta_height_start + 12.0, world_y)
	                          * (1.0 - smoothstep(kayenta_effective_end - 20.0, kayenta_effective_end, world_y));
	float kayenta_mask = clamp(kayenta_height_mask, 0.0, 1.0) * max(sandstone_mask, high_wall_mask * 0.42);
	float navajo_height_span = max(zion_navajo_height_end - zion_navajo_height_start, 1.0);
	float navajo_height_t = clamp((world_y - zion_navajo_height_start) / navajo_height_span + cliff_face_mask * 0.035, 0.0, 1.0);
	vec3 navajo_color = zion_navajo_palette(navajo_height_t);
	vec2 base_dip_dir = zion_crossbed_dip_dir / max(length(zion_crossbed_dip_dir), 0.001);
	float dip_turn = (hash21_smooth(world_xz * 0.0025 + vec2(4.0, 9.0)) - 0.5) * 0.62;
	float dip_cos = cos(dip_turn);
	float dip_sin = sin(dip_turn);
	vec2 dip_dir = vec2(base_dip_dir.x * dip_cos - base_dip_dir.y * dip_sin, base_dip_dir.x * dip_sin + base_dip_dir.y * dip_cos);
	float bed_warp = (hash21_smooth(world_xz * 0.014 + vec2(9.3, 4.4)) * 2.0 - 1.0) * zion_crossbed_warp_m;
	float bed_coord = world_y + dot(world_xz, dip_dir) * zion_crossbed_dip_tangent + bed_warp + dot(world_xz, zion_strata_dip) * 0.2;
	float major_phase = bed_coord / max(zion_crossbed_major_period_m, 1.0);
	float lamina_phase = bed_coord / max(zion_crossbed_lamina_period_m, 0.25);
	float major_sweep = sin(major_phase * ZION_TAU + hash21_smooth(world_xz * 0.011) * ZION_TAU) * 0.5 + 0.5;
	float major_line = wrapped_line(major_phase, 0.052);
	float lamina_wave = sin(lamina_phase * ZION_TAU + hash21_smooth(world_xz * 0.065 + vec2(2.0, 13.0)) * 1.45);
	float lamina_line = pow(max(0.0, lamina_wave * 0.5 + 0.5), 2.2);
	float lamina_dark = wrapped_line(lamina_phase + 0.18, 0.055);
	float strata_wave = clamp(major_sweep * 0.42 + (lamina_wave * 0.5 + 0.5) * 0.58, 0.0, 1.0) * 2.0 - 1.0;
	float kayenta_phase = world_y / 4.25 + hash21_smooth(world_xz * 0.035 + vec2(5.0, 1.0)) * 0.25;
	float kayenta_line = wrapped_line(kayenta_phase, 0.13);
	float kayenta_lamina = sin(world_y * (ZION_TAU / 2.1) + hash21_smooth(world_xz * 0.045) * ZION_TAU) * 0.5 + 0.5;
	vec3 kayenta_base = mix(zion_kayenta_color.rgb, zion_kayenta_lavender_color.rgb, smoothstep(0.48, 0.86, hash21_smooth(world_xz * 0.022 + vec2(12.0, 3.0))) * 0.42);
	kayenta_base *= 0.88 + kayenta_lamina * 0.16;
	kayenta_base = mix(kayenta_base, zion_kayenta_color.rgb * 0.55, kayenta_line * 0.35);
	float detile_a = hash21_smooth(world_xz * 0.055) * 2.0 - 1.0;
	float detile_b = hash21_smooth(world_xz * 0.031 + vec2(7.3, 2.1)) * 2.0 - 1.0;
	float detile = detile_a * 0.5 + detile_b * 0.5;
	vec3 zion_albedo = ALBEDO;
	float river_distance_m = zion_river_distance(world_xz);
	float river_corridor_mask = 1.0 - smoothstep(zion_riparian_inner_m, zion_riparian_outer_m, river_distance_m);
	float low_river_floor_mask = (1.0 - sandstone_mask) * (1.0 - smoothstep(zion_sand_height_end - 1.0, zion_sand_height_end + 7.0, world_y));
	float riparian_tint_mask = river_corridor_mask * max(low_flat_mask, low_river_floor_mask * river_corridor_mask);
	float bank_wet_mask = smoothstep(3.5, 7.0, river_distance_m) * (1.0 - smoothstep(7.0, zion_bank_wet_width_m, river_distance_m)) * low_river_floor_mask;
	zion_albedo = mix(zion_albedo, zion_sand_color.rgb, low_flat_mask * 0.30);
	zion_albedo = mix(zion_albedo, zion_floor_cool_sand_color.rgb, low_flat_mask * zion_floor_deorange_strength);
	float floor_macro = hash21_smooth(world_xz * 0.010 + vec2(8.0, 2.0));
	float floor_mid = hash21_smooth(world_xz * 0.026 + vec2(3.1, 8.7));
	float floor_fine = hash21_smooth(world_xz * 0.083 + vec2(14.4, 6.2));
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
	zion_albedo = mix(zion_albedo, navajo_color, navajo_mask * zion_navajo_palette_strength);
	zion_albedo = mix(zion_albedo, kayenta_base, kayenta_mask * min(zion_kayenta_strength + 0.18, 1.0));
	float strata_shade = major_sweep * 0.10 + lamina_wave * 0.075 - major_line * 0.30 - lamina_dark * 0.11;
	vec3 strata_tint = navajo_color * (1.0 + strata_shade);
	strata_tint = mix(strata_tint, zion_strata_dark_color.rgb, major_line * 0.28);
	strata_tint = mix(strata_tint, zion_strata_light_color.rgb, lamina_line * 0.045);
	float strata_cliff_mask = navajo_mask * cliff_face_mask;
	zion_albedo = mix(zion_albedo, strata_tint, strata_cliff_mask * zion_strata_strength);
	zion_albedo = mix(zion_albedo, kayenta_base, kayenta_mask * cliff_face_mask * zion_kayenta_strength * 0.35);
	zion_albedo *= 1.0 + detile * zion_detile_strength * max(cliff_mask, low_flat_mask * 0.5);
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
	if (zion_wetrock_enabled) {
		float wetrock_wall = step(local_normal_y, 0.25);
		float wetrock_height = smoothstep(zion_wetrock_height_start, zion_wetrock_height_start + 15.0, world_y)
		                     * (1.0 - smoothstep(zion_wetrock_height_end - 15.0, zion_wetrock_height_end, world_y));
		float wetrock_scatter = step(0.72, hash21(floor(world_xz * 0.018)));
		float wetrock_mask = wetrock_wall * wetrock_height * wetrock_scatter;
		ALBEDO = mix(ALBEDO, ALBEDO * (1.0 - zion_wetrock_darkness) + zion_wetrock_moss_color.rgb * 0.08, wetrock_mask);
	}
	float varnish_wall_mask = 1.0 - smoothstep(zion_varnish_wall_threshold - 0.08, zion_varnish_wall_threshold + 0.08, local_normal_y);
	float seep_noise = hash21_smooth(world_xz * 0.016 + vec2(2.0, 17.0));
	float seep_y = mix(zion_wetrock_height_start + 35.0, max(zion_wetrock_height_end, zion_varnish_height_start) + 170.0, seep_noise);
	float down_from_seep_m = seep_y - world_y;
	float below_seep_mask = smoothstep(0.0, 18.0, down_from_seep_m)
	                       * (1.0 - smoothstep(zion_varnish_drop_m * 0.48, zion_varnish_drop_m, down_from_seep_m));
	float flow_x = dot(world_xz, vec2(0.73, -0.68));
	float flow_y = dot(world_xz, vec2(0.68, 0.73));
	float varnish_phase = flow_x * zion_varnish_streak_scale + hash21_smooth(vec2(floor(flow_y * 0.025), floor(seep_y * 0.018))) * ZION_TAU;
	float varnish_column = pow(max(0.0, 1.0 - abs(sin(varnish_phase))), 3.6);
	float varnish_breaks = smoothstep(0.22, 0.78, hash21_smooth(vec2(flow_x * 0.045, world_y * 0.036) + vec2(11.0, 6.0)));
	float varnish_region = smoothstep(0.54, 0.88, hash21_smooth(world_xz * 0.021 + vec2(17.0, 3.0)));
	float varnish_streak = varnish_column * varnish_breaks * varnish_region * mix(0.62, 1.0, strata_wave * 0.5 + 0.5);
	float varnish_height_mask = smoothstep(zion_varnish_height_start - 65.0, zion_varnish_height_start + 25.0, world_y);
	float varnish_amount = varnish_wall_mask * varnish_height_mask * below_seep_mask * varnish_streak * zion_varnish_strength;
	vec3 varnish_oxide = mix(zion_varnish_fe_color.rgb, zion_varnish_mn_color.rgb, smoothstep(0.50, 0.92, hash21_smooth(world_xz * 0.033 + vec2(4.0, 19.0))));
	varnish_oxide = mix(zion_varnish_color.rgb, varnish_oxide, 0.72);
	ALBEDO = mix(ALBEDO, varnish_oxide, clamp(varnish_amount, 0.0, 0.72));
	if (use_macro_albedo) {
		vec2 macro_uv = clamp((world_xz - macro_albedo_origin_xz) / macro_albedo_size_xz, vec2(0.0), vec2(1.0));
		vec3 macro_albedo = texture(macro_albedo_texture, macro_uv).rgb;
		float macro_luma = luminance(macro_albedo);
		float base_luma = max(luminance(ALBEDO), 0.035);
		float macro_luma_ratio = clamp(macro_luma / base_luma, 0.55, 1.45);
		ALBEDO = clamp(mix(ALBEDO, ALBEDO * macro_luma_ratio, macro_albedo_strength), vec3(0.0), vec3(1.0));
	}
	float bleach_noise = hash21_smooth(world_xz * 0.018 + vec2(6.0, 14.0)) * 0.58
	                   + hash21_smooth(world_xz * 0.047 + vec2(1.0, 5.0)) * 0.42;
	float bleach_blob = smoothstep(0.50, 0.84, bleach_noise);
	float bleach_mask = smoothstep(zion_bleach_height_start, zion_bleach_height_start + 210.0, world_y) * cliff_mask * (0.42 + bleach_blob * 0.58);
	ALBEDO = mix(ALBEDO, zion_navajo_bleached_white_color.rgb, bleach_mask * zion_bleach_strength);
	ALBEDO = mix(ALBEDO, ALBEDO * (1.0 - zion_bank_wet_darkness), bank_wet_mask);
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
	vec3 world_micro_normal = apply_micro_normal(world_detail_normal, world_xz, micro_strength);
	world_micro_normal = apply_floor_fine_normal(world_micro_normal, world_xz, micro_strength, low_flat_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_micro_normal, 0.0)).xyz);
	float roughness_wobble = (hash21_smooth(world_xz * 0.31) * 2.0 - 1.0) * micro_roughness_variation * (0.5 + micro_strength);
	float floor_roughness_wobble = (hash21_smooth(world_xz * 0.9 + vec2(5.7, 2.4)) * 2.0 - 1.0) * micro_roughness_floor_variation * low_flat_mask;
	float floor_roughness_shift = floor_wash_mask * 0.035 + floor_sand_patch_mask * 0.055 - floor_slickrock_mask * 0.08 + low_flat_mask * detile_floor * 0.025;
	ROUGHNESS = clamp(mix(terrain_roughness + roughness_wobble + floor_roughness_shift + floor_roughness_wobble + floor_pbr_bump * floor_pbr_roughness_strength * floor_pbr_gate, zion_bank_wet_roughness, bank_wet_mask), 0.05, 1.0);
	SPECULAR = terrain_specular;
}
