shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform vec4 blade_base_color : source_color = vec4(0.07, 0.18, 0.055, 1.0);
uniform vec4 blade_tip_color : source_color = vec4(0.48, 0.66, 0.23, 1.0);
uniform float blade_height_reference = 0.42;
uniform float wind_strength = 0.012;
uniform float wind_speed = 0.65;
uniform float wind_time_factor = 1.0;
uniform vec4 backlight_color : source_color = vec4(1.0, 0.62, 0.30, 1.0);
uniform float backlight_energy = 0.32;
uniform vec3 vehicle_world_pos = vec3(0.0, 0.0, 0.0);
uniform float crush_radius = 1.2;
uniform float crush_strength = 0.75;
varying float blade_height;
varying float tip_mix_shift;
void vertex() {
	blade_height = smoothstep(0.0, blade_height_reference, VERTEX.y);
	tip_mix_shift = INSTANCE_CUSTOM.w;
	float wind_phase = INSTANCE_CUSTOM.y * TAU;
	float wind_time = TIME * wind_speed * wind_time_factor;
	float sway = sin(wind_phase + wind_time);
	float flutter = sin(wind_phase * 1.73 + wind_time * 1.47 + INSTANCE_CUSTOM.z * 2.91);
	float gust = 0.88 + sin(wind_time * 0.37 + INSTANCE_CUSTOM.w * TAU) * 0.12;
	float bend = (sway * 0.72 + flutter * 0.28) * gust * wind_strength * blade_height * blade_height * INSTANCE_CUSTOM.x;
	VERTEX.x += bend;
	VERTEX.z += bend * (INSTANCE_CUSTOM.z * 0.7 - 0.35);
	vec3 vehicle_local_pos = (inverse(MODEL_MATRIX) * vec4(vehicle_world_pos, 1.0)).xyz;
	vec2 crush_delta = VERTEX.xz - vehicle_local_pos.xz;
	float crush_distance = length(crush_delta);
	float crush_falloff = 1.0 - smoothstep(0.0, max(crush_radius, 0.001), crush_distance);
	float crush_tip_weight = blade_height * blade_height;
	vec2 crush_dir = crush_distance > 0.001 ? crush_delta / crush_distance : vec2(1.0, 0.0);
	float crush_amount = crush_falloff * crush_tip_weight * max(crush_strength, 0.0);
	VERTEX.xz += crush_dir * crush_amount * 0.18;
	VERTEX.y -= crush_amount * 0.20;
}
void fragment() {
	float tip_mix = smoothstep(0.0, 1.0, blade_height + (tip_mix_shift - 0.5) * 0.22);
	vec3 blade_color = mix(blade_base_color.rgb, blade_tip_color.rgb, tip_mix);
	blade_color = mix(blade_color, blade_base_color.rgb * 0.72, (1.0 - blade_height) * 0.24);
	ALBEDO = blade_color * COLOR.rgb;
	ROUGHNESS = 0.86;
	SPECULAR = 0.16;
	BACKLIGHT = backlight_color.rgb * backlight_energy * (0.35 + blade_height * 0.65) * COLOR.rgb;
}
