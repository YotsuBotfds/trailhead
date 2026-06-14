shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 shallow_color : source_color = vec4(0.45, 0.68, 0.70, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.22, 0.25, 1.0);
uniform float water_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float depth_fade_distance : hint_range(0.001, 2.0) = 0.45;
uniform float foam_edge_width : hint_range(0.001, 0.5) = 0.08;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.08;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.015;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y += sin((world_xz.x + TIME * flow_speed) * 18.0) * wave_amplitude;
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position.xyz /= view_position.w;
	float scene_depth = -view_position.z;
	float fragment_depth = -VERTEX.z;
	float depth_delta = max(scene_depth - fragment_depth, 0.0);
	float depth_mix = clamp(depth_delta / depth_fade_distance, 0.0, 1.0);
	float foam = 1.0 - smoothstep(0.0, foam_edge_width, depth_delta);
	float ripple = sin((world_xz.x * 11.0) + (world_xz.y * 7.0) + TIME * flow_speed * 9.0) * 0.5 + 0.5;
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
	water_color = mix(water_color, vec3(0.86, 0.92, 0.86), foam * (0.45 + ripple * 0.25));
	ALBEDO = water_color;
	ALPHA = water_alpha;
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
}
