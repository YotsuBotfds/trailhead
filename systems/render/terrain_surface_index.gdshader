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
uniform vec2 surface_uv_scale_0 = vec2(68.0, 68.0);
uniform vec2 surface_uv_scale_1 = vec2(72.0, 72.0);
uniform vec2 surface_uv_scale_2 = vec2(68.0, 68.0);
uniform vec2 surface_uv_scale_3 = vec2(64.0, 64.0);
uniform vec2 surface_uv_scale_4 = vec2(62.0, 62.0);
uniform vec2 surface_uv_scale_5 = vec2(60.0, 60.0);
uniform vec2 surface_uv_scale_6 = vec2(58.0, 58.0);
uniform vec2 surface_uv_scale_7 = vec2(42.0, 42.0);
uniform float terrain_roughness = 0.88;
uniform float terrain_specular = 0.18;

varying vec2 world_xz;

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
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
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
	ROUGHNESS = terrain_roughness;
	SPECULAR = terrain_specular;
}
