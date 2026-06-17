shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D surface_id_texture : filter_nearest, repeat_disable;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 control_origin_xz = vec2(0.0, 0.0);
uniform vec2 control_size_xz = vec2(100.0, 100.0);
uniform bool use_albedo_array = false;
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
uniform float zion_detile_strength = 0.18;

varying vec2 world_xz;
varying float world_y;
varying float local_normal_y;

float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
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
	float strata_wave = sin(world_y * zion_strata_scale + hash21(floor(world_xz * 0.08)) * 6.283185);
	float strata_mask = smoothstep(0.64, 0.92, strata_wave) * cliff_mask;
	float detile = hash21(floor(world_xz * 0.055)) * 2.0 - 1.0;
	vec3 zion_albedo = ALBEDO;
	zion_albedo = mix(zion_albedo, zion_sand_color.rgb, low_flat_mask * 0.68);
	zion_albedo = mix(zion_albedo, zion_sandstone_color.rgb, cliff_mask * 0.74);
	zion_albedo = mix(zion_albedo, zion_strata_dark_color.rgb, strata_mask * zion_strata_strength);
	zion_albedo *= 1.0 + detile * zion_detile_strength;
	ALBEDO = clamp(zion_albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = terrain_roughness;
	SPECULAR = terrain_specular;
}
