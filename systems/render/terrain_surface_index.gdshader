shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D surface_id_texture : filter_nearest, repeat_disable;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_albedo_texture : source_color, filter_linear, repeat_disable;
uniform vec2 control_origin_xz = vec2(0.0, 0.0);
uniform vec2 control_size_xz = vec2(100.0, 100.0);
uniform vec2 macro_albedo_origin_xz = vec2(0.0, 0.0);
uniform vec2 macro_albedo_size_xz = vec2(5500.0, 5700.0);
uniform bool use_albedo_array = false;
uniform bool use_macro_albedo = false;
uniform float macro_albedo_strength = 0.18;
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
uniform vec4 zion_sand_color : source_color = vec4(0.86, 0.74, 0.54, 1.0);
uniform vec4 zion_strata_dark_color : source_color = vec4(0.36, 0.14, 0.08, 1.0);
uniform float zion_sandstone_slope_start = 0.08;
uniform float zion_sandstone_slope_end = 0.38;
uniform float zion_sand_height_start = 1193.0;
uniform float zion_sand_height_end = 1202.0;
uniform float zion_strata_scale = 0.58;
uniform float zion_strata_strength = 0.48;
uniform vec4 zion_strata_light_color : source_color = vec4(0.86, 0.62, 0.38, 1.0);  // lighter band tone (Navajo cross-bedding)
uniform vec2 zion_strata_dip = vec2(0.15, 0.15);                                    // xz phase per meter (diagonal cross-bedding dip)
uniform float zion_detile_strength = 0.18;
uniform vec4 zion_varnish_color : source_color = vec4(0.13, 0.08, 0.06, 1.0);  // warm charcoal
uniform float zion_varnish_strength = 0.5;
uniform float zion_varnish_wall_threshold = 0.30;   // local_normal_y below this = near-vertical face
uniform float zion_varnish_height_start = 1300.0;   // varnish mostly on walls above the floor
uniform float zion_varnish_streak_scale = 0.12;     // horizontal streak frequency
// Kayenta Formation: warm-dark band at cliff base (~1200-1250 m) below the Navajo mass.
uniform vec4 zion_kayenta_color : source_color = vec4(0.38, 0.10, 0.06, 1.0);  // deep brick-red
uniform float zion_kayenta_height_start = 1200.0;
uniform float zion_kayenta_height_end = 1250.0;
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

varying vec2 world_xz;
varying float world_y;
varying float local_normal_y;

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
// for the surface-micro normal gradient below.
float micro_height(vec2 world_xz_pos) {
	vec2 q1 = world_xz_pos * micro_normal_scale;
	vec2 q2 = world_xz_pos * (micro_normal_scale * 2.17) + vec2(11.7, 4.3);
	return (hash21_smooth(q1) * 2.0 - 1.0) * 0.68 + (hash21_smooth(q2) * 2.0 - 1.0) * 0.32;
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

void vertex() {
	vec4 world_position = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = world_position.xz;
	world_y = world_position.y;
	local_normal_y = abs(normalize(NORMAL).y);
}

void fragment() {
	vec2 control_uv = clamp((world_xz - control_origin_xz) / control_size_xz, vec2(0.0), vec2(1.0));
	float surface_id_value = floor(texture(surface_id_texture, control_uv).r * 255.0 + 0.5);
	vec4 surface_color = surface_color_for_id(surface_id_value);
	if (use_albedo_array) {
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
	float strata_dip_phase = dot(world_xz, zion_strata_dip);
	float strata_wave = sin(world_y * zion_strata_scale + strata_dip_phase + hash21(floor(world_xz * 0.08)) * 6.283185);
	float kayenta_height_mask = smoothstep(zion_kayenta_height_start, zion_kayenta_height_start + 12.0, world_y) - smoothstep(zion_kayenta_height_end - 18.0, zion_kayenta_height_end, world_y);
	float kayenta_mask = clamp(kayenta_height_mask, 0.0, 1.0) * sandstone_mask;
	float detile_a = hash21_smooth(world_xz * 0.055) * 2.0 - 1.0;
	float detile_b = hash21_smooth(world_xz * 0.031 + vec2(7.3, 2.1)) * 2.0 - 1.0;
	float detile = detile_a * 0.5 + detile_b * 0.5;
	vec3 zion_albedo = ALBEDO;
	zion_albedo = mix(zion_albedo, zion_sand_color.rgb, low_flat_mask * 0.68);
	zion_albedo = mix(zion_albedo, zion_sandstone_color.rgb, cliff_mask * 0.74);
	zion_albedo = mix(zion_albedo, zion_kayenta_color.rgb, kayenta_mask * zion_kayenta_strength);
	float strata_tone = strata_wave * 0.5 + 0.5;
	vec3 strata_tint = mix(zion_strata_dark_color.rgb, zion_strata_light_color.rgb, strata_tone);
	zion_albedo = mix(zion_albedo, strata_tint, cliff_mask * zion_strata_strength);
	zion_albedo *= 1.0 + detile * zion_detile_strength;
	ALBEDO = clamp(zion_albedo, vec3(0.0), vec3(1.0));
	if (zion_wetrock_enabled) {
		float wetrock_wall = step(local_normal_y, 0.25);
		float wetrock_height = smoothstep(zion_wetrock_height_start, zion_wetrock_height_start + 15.0, world_y)
		                     * (1.0 - smoothstep(zion_wetrock_height_end - 15.0, zion_wetrock_height_end, world_y));
		float wetrock_scatter = step(0.72, hash21(floor(world_xz * 0.018)));
		float wetrock_mask = wetrock_wall * wetrock_height * wetrock_scatter;
		ALBEDO = mix(ALBEDO, ALBEDO * (1.0 - zion_wetrock_darkness) + zion_wetrock_moss_color.rgb * 0.08, wetrock_mask);
	}
	float varnish_wall_mask = 1.0 - smoothstep(zion_varnish_wall_threshold - 0.08, zion_varnish_wall_threshold + 0.08, local_normal_y);
	float varnish_height_mask = smoothstep(zion_varnish_height_start, zion_varnish_height_start + 80.0, world_y);
	float varnish_phase = hash21(floor(world_xz * 0.11)) * 6.283185;
	float varnish_region = hash21(floor(world_xz * 0.045) + vec2(17.0, 3.0));
	float varnish_s = sin(world_xz.x * zion_varnish_streak_scale + varnish_phase) + sin(world_xz.y * (zion_varnish_streak_scale * 0.87) + varnish_phase * 1.4);
	float varnish_streak = pow(max(0.0, 1.0 - abs(varnish_s) * 0.5), 2.0);
	varnish_streak *= smoothstep(0.25, 0.85, varnish_region);
	varnish_streak *= mix(0.55, 1.0, strata_wave * 0.5 + 0.5);
	float varnish_amount = varnish_wall_mask * varnish_height_mask * varnish_streak * zion_varnish_strength;
	ALBEDO = mix(ALBEDO, zion_varnish_color.rgb, clamp(varnish_amount, 0.0, 1.0));
	if (use_macro_albedo) {
		vec2 macro_uv = clamp((world_xz - macro_albedo_origin_xz) / macro_albedo_size_xz, vec2(0.0), vec2(1.0));
		vec3 macro_albedo = texture(macro_albedo_texture, macro_uv).rgb;
		ALBEDO = clamp(mix(ALBEDO, ALBEDO * (macro_albedo * 2.0), macro_albedo_strength), vec3(0.0), vec3(1.0));
	}
	float bleach_mask = smoothstep(zion_bleach_height_start, zion_bleach_height_start + 200.0, world_y) * cliff_mask;
	ALBEDO = mix(ALBEDO, zion_bleach_color.rgb, bleach_mask * zion_bleach_strength);
	// W6-SURFACE-DETAIL: surface micro-relief so raking golden-hour light catches
	// real texture. A procedural micro-normal (hash only, no extra texture fetches)
	// perturbs the world-space geometric normal in the surface tangent plane, and a
	// gentle hashed ROUGHNESS wobble breaks up the uniformly matte floor. Strength
	// scales per surface -- more on packed_gravel/loose_rock, near-zero on paved_road.
	// Strata/varnish/bleach/macro-albedo color logic above is untouched.
	float micro_strength = surface_micro_strength_for_id(surface_id_value);
	vec3 world_geo_normal_now = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_micro_normal = apply_micro_normal(world_geo_normal_now, world_xz, micro_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_micro_normal, 0.0)).xyz);
	float roughness_wobble = (hash21_smooth(world_xz * 0.31) * 2.0 - 1.0) * micro_roughness_variation * (0.5 + micro_strength);
	ROUGHNESS = clamp(terrain_roughness + roughness_wobble, 0.05, 1.0);
	SPECULAR = terrain_specular;
}
