shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D surface_id_texture : filter_nearest, repeat_disable;
uniform vec2 control_origin_xz = vec2(0.0, 0.0);
uniform vec2 control_size_xz = vec2(100.0, 100.0);
uniform vec4 surface_color_0 : source_color = vec4(0.50, 0.47, 0.38, 1.0);
uniform vec4 surface_color_1 : source_color = vec4(0.86, 0.86, 0.82, 1.0);
uniform vec4 surface_color_2 : source_color = vec4(0.92, 0.84, 0.72, 1.0);
uniform vec4 surface_color_3 : source_color = vec4(0.78, 0.96, 0.72, 1.0);
uniform vec4 surface_color_4 : source_color = vec4(0.72, 0.62, 0.50, 1.0);
uniform vec4 surface_color_5 : source_color = vec4(0.90, 0.86, 0.78, 1.0);
uniform vec4 surface_color_6 : source_color = vec4(0.62, 0.68, 0.64, 1.0);
uniform vec4 surface_color_7 : source_color = vec4(0.88, 0.78, 0.64, 1.0);
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

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 control_uv = clamp((world_xz - control_origin_xz) / control_size_xz, vec2(0.0), vec2(1.0));
	float surface_id_value = floor(texture(surface_id_texture, control_uv).r * 255.0 + 0.5);
	vec4 surface_color = surface_color_for_id(surface_id_value);
	ALBEDO = surface_color.rgb;
	ROUGHNESS = terrain_roughness;
	SPECULAR = terrain_specular;
}
