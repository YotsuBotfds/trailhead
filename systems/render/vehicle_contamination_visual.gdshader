shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mud_mask : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dust_mask : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wetness_mask : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 mud_color : source_color = vec4(0.17, 0.10, 0.05, 1.0);
uniform vec4 dust_color : source_color = vec4(0.66, 0.55, 0.36, 1.0);
uniform vec4 wetness_color : source_color = vec4(0.52, 0.62, 0.66, 1.0);
uniform float mud_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.0;
uniform float mud_alpha_scale : hint_range(0.0, 1.0) = 0.58;
uniform float dust_alpha_scale : hint_range(0.0, 1.0) = 0.34;
uniform float wetness_alpha_scale : hint_range(0.0, 1.0) = 0.42;
uniform float normal_offset_meters : hint_range(0.0, 0.005) = 0.0015;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.88;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.12;
uniform float wet_specular : hint_range(0.0, 1.0) = 0.72;

void vertex() {
	VERTEX += NORMAL * normal_offset_meters;
}

void fragment() {
	float mud_mask_value = texture(mud_mask, UV).r;
	float dust_mask_value = texture(dust_mask, UV).r;
	float wetness_mask_value = texture(wetness_mask, UV).r;
	float mud_alpha = clamp(mud_amount * mud_alpha_scale * mud_mask_value, 0.0, 1.0);
	float dust_alpha = clamp(dust_amount * dust_alpha_scale * dust_mask_value, 0.0, 1.0);
	float wetness_alpha = clamp(wetness_amount * wetness_alpha_scale * wetness_mask_value, 0.0, 1.0);
	float combined_alpha = 1.0 - ((1.0 - mud_alpha) * (1.0 - dust_alpha) * (1.0 - wetness_alpha));
	vec3 weighted_color = mud_color.rgb * mud_alpha + dust_color.rgb * dust_alpha + wetness_color.rgb * wetness_alpha;
	ALBEDO = weighted_color / max(combined_alpha, 0.001);
	ALPHA = combined_alpha;
	METALLIC = 0.0;
	ROUGHNESS = mix(dry_roughness, wet_roughness, wetness_alpha);
	SPECULAR = mix(0.35, wet_specular, wetness_alpha);
}
